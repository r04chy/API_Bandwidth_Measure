#!/bin/bash

# Bandwidth Load Testing Client
# Usage: ./load_test.sh [OPTIONS]

set -e

# Default configuration
SERVER_URL="http://localhost:8080"
CONCURRENT_REQUESTS=10
TOTAL_REQUESTS=100
PAYLOAD_SIZE=1024
TEST_DURATION=""
OUTPUT_FILE=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print usage information
usage() {
    cat << EOF
🚀 Bandwidth Load Testing Client

Usage: $0 [OPTIONS]

OPTIONS:
    -s, --server URL        Server URL (default: $SERVER_URL)
    -c, --concurrent NUM    Number of concurrent requests (default: $CONCURRENT_REQUESTS)
    -n, --requests NUM      Total number of requests (default: $TOTAL_REQUESTS)
    -z, --size BYTES        Payload size in bytes (default: $PAYLOAD_SIZE)
    -d, --duration SEC      Test duration in seconds (overrides -n)
    -o, --output FILE       Output results to file
    -v, --verbose           Verbose output
    -h, --help             Show this help message

EXAMPLES:
    $0                                          # Basic test with defaults
    $0 -c 50 -n 1000 -z 4096                   # 50 concurrent, 1000 requests, 4KB payload
    $0 -c 20 -d 30 -z 8192 -v                  # 20 concurrent for 30 seconds, 8KB payload
    $0 -s http://example.com:8080 -c 100       # Test remote server
    $0 -c 10 -n 100 -o results.txt             # Save results to file

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                SERVER_URL="$2"
                shift 2
                ;;
            -c|--concurrent)
                CONCURRENT_REQUESTS="$2"
                shift 2
                ;;
            -n|--requests)
                TOTAL_REQUESTS="$2"
                shift 2
                ;;
            -z|--size)
                PAYLOAD_SIZE="$2"
                shift 2
                ;;
            -d|--duration)
                TEST_DURATION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Log message with timestamp
log() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $1"
}

# Log verbose message
log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${PURPLE}[VERBOSE]${NC} $1"
    fi
}

# Check server health
check_server() {
    log "🔍 Checking server health at $SERVER_URL"
    
    local response
    if response=$(curl -s --max-time 5 "$SERVER_URL/api/health" 2>/dev/null); then
        local status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        if [[ "$status" == "healthy" ]]; then
            log "${GREEN}✅ Server is healthy${NC}"
            return 0
        fi
    fi
    
    log "${RED}❌ Server health check failed${NC}"
    log "${YELLOW}💡 Make sure the Go server is running on $SERVER_URL${NC}"
    exit 1
}

# Reset server statistics
reset_stats() {
    log "🔄 Resetting server statistics"
    curl -s -X POST "$SERVER_URL/api/reset" > /dev/null || {
        log "${YELLOW}⚠️  Could not reset server stats (continuing anyway)${NC}"
    }
}

# Get server statistics
get_stats() {
    curl -s "$SERVER_URL/api/stats" 2>/dev/null || echo "{}"
}

# Make a single request and return timing info
make_request() {
    local request_id=$1
    local start_time=$(date +%s.%N)
    
    local response
    local http_code
    local total_time
    local size
    
    # Make the request with timing info
    response=$(curl -s -w "%{http_code}|%{time_total}|%{size_download}" \
                   "$SERVER_URL/api/bandwidth?size=$PAYLOAD_SIZE" 2>/dev/null)
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Parse curl output
    local body=$(echo "$response" | sed '$d')
    local metrics=$(echo "$response" | tail -n1)
    
    if [[ "$metrics" == *"|"* ]]; then
        http_code=$(echo "$metrics" | cut -d'|' -f1)
        total_time=$(echo "$metrics" | cut -d'|' -f2)
        size=$(echo "$metrics" | cut -d'|' -f3)
    else
        http_code="000"
        total_time="0"
        size="0"
    fi
    
    # Output timing info for aggregation
    echo "$request_id|$http_code|$total_time|$size|$duration"
    
    log_verbose "Request $request_id: HTTP $http_code, ${total_time}s, ${size} bytes"
}

# Run concurrent requests
run_load_test() {
    log "🚀 Starting load test"
    log "📊 Configuration:"
    log "   Server: $SERVER_URL"
    log "   Concurrent requests: $CONCURRENT_REQUESTS"
    if [[ -n "$TEST_DURATION" ]]; then
        log "   Duration: ${TEST_DURATION} seconds"
    else
        log "   Total requests: $TOTAL_REQUESTS"
    fi
    log "   Payload size: $PAYLOAD_SIZE bytes"
    echo
    
    local temp_dir=$(mktemp -d)
    local results_file="$temp_dir/results.txt"
    local pids=()
    
    # Start time
    local test_start=$(date +%s.%N)
    local end_time=""
    
    if [[ -n "$TEST_DURATION" ]]; then
        end_time=$(echo "$test_start + $TEST_DURATION" | bc -l)
        log "⏱️  Running test for $TEST_DURATION seconds..."
    else
        log "⏱️  Running $TOTAL_REQUESTS requests with $CONCURRENT_REQUESTS concurrent..."
    fi
    
    # Progress tracking
    local completed=0
    local request_id=0
    
    # Function to run requests in background
    run_request_batch() {
        local batch_start=$1
        local batch_size=$2
        
        for ((i=0; i<batch_size; i++)); do
            local current_id=$((batch_start + i))
            
            # Check if we should continue based on time or count
            if [[ -n "$TEST_DURATION" ]]; then
                local current_time=$(date +%s.%N)
                if (( $(echo "$current_time > $end_time" | bc -l) )); then
                    break
                fi
            fi
            
            make_request $current_id >> "$results_file" &
            pids+=($!)
            
            # Limit concurrent processes
            if (( ${#pids[@]} >= CONCURRENT_REQUESTS )); then
                wait ${pids[0]}
                pids=("${pids[@]:1}")
                ((completed++))
                
                # Show progress
                if [[ -z "$TEST_DURATION" ]] && (( completed % 10 == 0 )); then
                    local progress=$((completed * 100 / TOTAL_REQUESTS))
                    log "📈 Progress: $completed/$TOTAL_REQUESTS requests ($progress%)"
                fi
            fi
        done
    }
    
    # Run the test
    if [[ -n "$TEST_DURATION" ]]; then
        # Duration-based test
        local current_time=$(date +%s.%N)
        while (( $(echo "$current_time < $end_time" | bc -l) )); do
            run_request_batch $request_id $CONCURRENT_REQUESTS
            request_id=$((request_id + CONCURRENT_REQUESTS))
            current_time=$(date +%s.%N)
            sleep 0.01  # Small delay to prevent overwhelming
        done
    else
        # Count-based test
        local remaining=$TOTAL_REQUESTS
        while (( remaining > 0 )); do
            local batch_size=$((remaining < CONCURRENT_REQUESTS ? remaining : CONCURRENT_REQUESTS))
            run_request_batch $request_id $batch_size
            request_id=$((request_id + batch_size))
            remaining=$((remaining - batch_size))
        done
    fi
    
    # Wait for all remaining requests
    log "⏳ Waiting for remaining requests to complete..."
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    local test_end=$(date +%s.%N)
    local test_duration=$(echo "$test_end - $test_start" | bc -l)
    
    # Analyze results
    analyze_results "$results_file" "$test_duration"
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Analyze test results
analyze_results() {
    local results_file=$1
    local test_duration=$2
    
    if [[ ! -f "$results_file" || ! -s "$results_file" ]]; then
        log "${RED}❌ No results to analyze${NC}"
        return 1
    fi
    
    log "📊 Analyzing results..."
    
    # Parse results
    local total_requests=0
    local successful_requests=0
    local failed_requests=0
    local total_bytes=0
    local total_time=0
    local min_time=999999
    local max_time=0
    local times=()
    
    while IFS='|' read -r req_id http_code time_total size_download duration; do
        ((total_requests++))
        
        if [[ "$http_code" == "200" ]]; then
            ((successful_requests++))
            total_bytes=$((total_bytes + size_download))
            
            # Time analysis
            if (( $(echo "$time_total > 0" | bc -l) )); then
                total_time=$(echo "$total_time + $time_total" | bc -l)
                times+=("$time_total")
                
                if (( $(echo "$time_total < $min_time" | bc -l) )); then
                    min_time=$time_total
                fi
                if (( $(echo "$time_total > $max_time" | bc -l) )); then
                    max_time=$time_total
                fi
            fi
        else
            ((failed_requests++))
            log_verbose "Failed request $req_id: HTTP $http_code"
        fi
    done < "$results_file"
    
    # Calculate statistics
    local avg_time=0
    if (( successful_requests > 0 )); then
        avg_time=$(echo "scale=4; $total_time / $successful_requests" | bc -l)
    fi
    
    local requests_per_sec=0
    local bytes_per_sec=0
    local mbps=0
    
    if (( $(echo "$test_duration > 0" | bc -l) )); then
        requests_per_sec=$(echo "scale=2; $successful_requests / $test_duration" | bc -l)
        bytes_per_sec=$(echo "scale=0; $total_bytes / $test_duration" | bc -l)
        mbps=$(echo "scale=2; ($total_bytes * 8) / ($test_duration * 1024 * 1024)" | bc -l)
    fi
    
    # Get server stats
    local server_stats=$(get_stats)
    local server_requests=$(echo "$server_stats" | grep -o '"total_requests":[^,}]*' | cut -d':' -f2 || echo "0")
    local server_bytes=$(echo "$server_stats" | grep -o '"total_bytes":[^,}]*' | cut -d':' -f2 || echo "0")
    local server_mbps=$(echo "$server_stats" | grep -o '"mb_per_second":[^,}]*' | cut -d':' -f2 || echo "0")
    
    # Display results
    echo
    log "${GREEN}🎯 Load Test Results${NC}"
    echo "$(printf '%.0s=' {1..50})"
    
    echo -e "${BLUE}📈 Request Statistics:${NC}"
    echo "   Total Requests:      $total_requests"
    echo "   Successful:          $successful_requests"
    echo "   Failed:              $failed_requests"
    echo "   Success Rate:        $(echo "scale=1; $successful_requests * 100 / $total_requests" | bc -l)%"
    echo
    
    echo -e "${BLUE}⏱️  Timing Statistics:${NC}"
    printf "   Test Duration:       %.2fs\n" "$test_duration"
    printf "   Requests/sec:        %.2f\n" "$requests_per_sec"
    printf "   Avg Response Time:   %.4fs\n" "$avg_time"
    printf "   Min Response Time:   %.4fs\n" "$min_time"
    printf "   Max Response Time:   %.4fs\n" "$max_time"
    echo
    
    echo -e "${BLUE}📊 Bandwidth Statistics:${NC}"
    echo "   Total Data Transfer: $(numfmt --to=iec $total_bytes)"
    echo "   Bytes/sec:           $(numfmt --to=iec $bytes_per_sec)"
    printf "   Bandwidth (Mbps):    %.2f\n" "$mbps"
    echo
    
    echo -e "${BLUE}🖥️  Server Statistics:${NC}"
    echo "   Server Total Requests: $server_requests"
    echo "   Server Total Bytes:    $(numfmt --to=iec $server_bytes)"
    printf "   Server Bandwidth:      %.2f Mbps\n" "$server_mbps"
    
    # Save to file if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        {
            echo "# Load Test Results - $(date)"
            echo "# Configuration: $CONCURRENT_REQUESTS concurrent, $total_requests requests, $PAYLOAD_SIZE bytes payload"
            echo
            echo "total_requests=$total_requests"
            echo "successful_requests=$successful_requests"
            echo "failed_requests=$failed_requests"
            echo "test_duration=$test_duration"
            echo "requests_per_sec=$requests_per_sec"
            echo "avg_response_time=$avg_time"
            echo "min_response_time=$min_time"
            echo "max_response_time=$max_time"
            echo "total_bytes=$total_bytes"
            echo "bytes_per_sec=$bytes_per_sec"
            echo "bandwidth_mbps=$mbps"
        } > "$OUTPUT_FILE"
        log "💾 Results saved to $OUTPUT_FILE"
    fi
}

# Main function
main() {
    parse_args "$@"
    
    # Validate numeric inputs
    if ! [[ "$CONCURRENT_REQUESTS" =~ ^[0-9]+$ ]] || (( CONCURRENT_REQUESTS < 1 )); then
        echo "Error: Concurrent requests must be a positive integer"
        exit 1
    fi
    
    if ! [[ "$TOTAL_REQUESTS" =~ ^[0-9]+$ ]] || (( TOTAL_REQUESTS < 1 )); then
        echo "Error: Total requests must be a positive integer"
        exit 1
    fi
    
    if ! [[ "$PAYLOAD_SIZE" =~ ^[0-9]+$ ]] || (( PAYLOAD_SIZE < 1 )); then
        echo "Error: Payload size must be a positive integer"
        exit 1
    fi
    
    # Check dependencies
    command -v curl >/dev/null 2>&1 || {
        log "${RED}❌ curl is required but not installed${NC}"
        exit 1
    }
    
    command -v bc >/dev/null 2>&1 || {
        log "${RED}❌ bc is required but not installed${NC}"
        exit 1
    }
    
    # Run the test
    check_server
    reset_stats
    run_load_test
    
    log "${GREEN}✅ Load test completed successfully${NC}"
}

# Run main function
main "$@"