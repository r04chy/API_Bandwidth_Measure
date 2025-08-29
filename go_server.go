package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"sync/atomic"
	"time"
)

// Statistics tracking
var (
	requestCount    int64
	totalBytes      int64
	startTime       time.Time
	requestTimes    = make(map[string]time.Time)
)

// Response structures
type BandwidthResponse struct {
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	Size      int       `json:"size"`
	Data      string    `json:"data"`
}

type StatsResponse struct {
	TotalRequests    int64   `json:"total_requests"`
	TotalBytes       int64   `json:"total_bytes"`
	UptimeSeconds    float64 `json:"uptime_seconds"`
	RequestsPerSec   float64 `json:"requests_per_second"`
	BytesPerSec      float64 `json:"bytes_per_second"`
	MBPerSec         float64 `json:"mb_per_second"`
}

func main() {
	startTime = time.Now()
	
	// Endpoint for bandwidth testing with configurable payload size
	http.HandleFunc("/api/bandwidth", bandwidthHandler)
	
	// Endpoint for getting server statistics
	http.HandleFunc("/api/stats", statsHandler)
	
	// Endpoint for resetting statistics
	http.HandleFunc("/api/reset", resetHandler)
	
	// Health check endpoint
	http.HandleFunc("/api/health", healthHandler)
	
	fmt.Println("🚀 Bandwidth Load Test Server starting...")
	fmt.Println("📊 Endpoints:")
	fmt.Println("   GET  /api/bandwidth?size=<bytes>  - Bandwidth test (default: 1KB)")
	fmt.Println("   GET  /api/stats                   - Get server statistics")
	fmt.Println("   POST /api/reset                   - Reset statistics")
	fmt.Println("   GET  /api/health                  - Health check")
	fmt.Println("🌐 Server running on :8080")
	
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func bandwidthHandler(w http.ResponseWriter, r *http.Request) {
	// Only accept GET requests
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	// Get size parameter (default to 1KB)
	sizeParam := r.URL.Query().Get("size")
	size := 1024 // Default 1KB
	
	if sizeParam != "" {
		if parsedSize, err := strconv.Atoi(sizeParam); err == nil && parsedSize > 0 {
			size = parsedSize
		}
	}
	
	// Generate data of specified size
	data := generateData(size)
	
	response := BandwidthResponse{
		Message:   fmt.Sprintf("Bandwidth test payload (%d bytes)", len(data)),
		Timestamp: time.Now(),
		Size:      len(data),
		Data:      data,
	}
	
	// Set headers for bandwidth testing
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Content-Size", strconv.Itoa(size))
	
	// Encode response
	responseBytes, err := json.Marshal(response)
	if err != nil {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	
	// Update statistics
	atomic.AddInt64(&requestCount, 1)
	atomic.AddInt64(&totalBytes, int64(len(responseBytes)))
	
	// Write response
	w.WriteHeader(http.StatusOK)
	w.Write(responseBytes)
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	uptime := time.Since(startTime).Seconds()
	requests := atomic.LoadInt64(&requestCount)
	bytes := atomic.LoadInt64(&totalBytes)
	
	stats := StatsResponse{
		TotalRequests:  requests,
		TotalBytes:     bytes,
		UptimeSeconds:  uptime,
		RequestsPerSec: float64(requests) / uptime,
		BytesPerSec:    float64(bytes) / uptime,
		MBPerSec:       (float64(bytes) / uptime) / (1024 * 1024),
	}
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}

func resetHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	
	atomic.StoreInt64(&requestCount, 0)
	atomic.StoreInt64(&totalBytes, 0)
	startTime = time.Now()
	
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Statistics reset successfully",
		"time":    time.Now().Format(time.RFC3339),
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "healthy",
		"uptime":  time.Since(startTime).Seconds(),
		"version": "1.0.0",
	})
}

// Generate test data of specified size
func generateData(size int) string {
	if size <= 0 {
		return ""
	}
	
	// Create repeating pattern for bandwidth testing
	pattern := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	data := make([]byte, size)
	
	for i := 0; i < size; i++ {
		data[i] = pattern[i%len(pattern)]
	}
	
	return string(data)
}