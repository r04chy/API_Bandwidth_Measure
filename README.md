# API_Bandwidth_Measure

<H2>Go Server (Bandwidth Load Test Server)</H1>
Features:

* Configurable payload sizes via ?size= parameter
* Real-time statistics tracking requests, bandwidth, throughput
* Multiple endpoints: /api/bandwidth, /api/stats, /api/reset, /api/health
* Concurrent request handling with atomic counters
* JSON responses with timing and size information

Key endpoints:

`GET /api/bandwidth?size=1024 - Returns test payload of specified size`

`GET /api/stats - Shows real-time server statistics (requests/sec, MB/sec, etc.)`

`POST /api/reset - Resets all statistics`

`GET /api/health - Health check`

<H2> Bash Client (Load Test Script)</H1>
Features:

* Concurrent request testing with configurable parallelism
* Flexible test modes: by request count or duration
* Real-time progress tracking and statistics
* Comprehensive result analysis including bandwidth calculations
* Output options: console display and file export
* Server health checking before tests

# Basic test (10 concurrent, 100 requests, 1KB payload)
`./load_test.sh`

# Heavy load test
`./load_test.sh -c 50 -n 1000 -z 4096`

# Duration-based test (20 concurrent for 30 seconds)
`./load_test.sh -c 20 -d 30 -z 8192 -v`

# Save results to file
`./load_test.sh -c 10 -n 100 -o results.txt`

<H2>Setup Instructions:</H2>

Start the Go server:

```go run server.go```

Make the bash script executable:

```chmod +x load_test.sh```

Run load tests:

```bash./load_test.sh --help  # See all options```
```./load_test.sh         # Run with defaults```
