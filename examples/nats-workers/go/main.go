package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/nats-io/nats.go"
	_ "github.com/lib/pq"
)

// Configuration loaded from environment variables
type Config struct {
	NATS struct {
		URL        string
		User       string
		Pass       string
	}
	Postgres struct {
		URL string
	}
	Worker struct {
		StreamName   string
		ConsumerName string
		QueueGroup   string
		Subject      string
		BatchSize    int
	}
}

// WebhookPayload represents the expected message format
type WebhookPayload struct {
	WebhookURL string                 `json:"webhook_url"`
	Data       map[string]interface{} `json:"data"`
	Headers    map[string]string      `json:"headers"`
}

// Statistics tracker
type Stats struct {
	MessagesProcessed uint64
	MessagesSucceeded uint64
	MessagesFailed    uint64
	TotalProcessingTimeMs uint64
	StartTime         time.Time
}

var (
	config Config
	stats  Stats
	db     *sql.DB
)

func main() {
	log.Println("🚀 Starting NATS Webhook Worker (Go)")

	// Load configuration
	loadConfig()
	printConfig()

	// Initialize PostgreSQL connection
	var err error
	db, err = sql.Open("postgres", config.Postgres.URL)
	if err != nil {
		log.Fatalf("❌ Failed to connect to PostgreSQL: %v", err)
	}
	defer db.Close()

	// Test PostgreSQL connection
	if err = db.Ping(); err != nil {
		log.Fatalf("❌ PostgreSQL ping failed: %v", err)
	}
	log.Println("✅ Connected to PostgreSQL")

	// Start worker
	stats.StartTime = time.Now()
	if err := startWorker(); err != nil {
		log.Fatalf("❌ Worker failed: %v", err)
	}
}

func loadConfig() {
	config = Config{}

	// NATS configuration
	config.NATS.URL = getEnv("NATS_URL", "nats://localhost:4222")
	config.NATS.User = getEnv("NATS_USER", "")
	config.NATS.Pass = getEnv("NATS_PASS", "")

	// PostgreSQL configuration
	config.Postgres.URL = getEnv("DATABASE_URL", "postgresql://localhost/postgres?sslmode=disable")

	// Worker configuration
	config.Worker.StreamName = getEnv("STREAM_NAME", "WEBHOOKS")
	config.Worker.ConsumerName = getEnv("CONSUMER_NAME", "webhook-worker-1")
	config.Worker.QueueGroup = getEnv("QUEUE_GROUP", "webhook-workers")
	config.Worker.Subject = getEnv("SUBJECT", "webhooks.*")
	config.Worker.BatchSize = getEnvInt("BATCH_SIZE", 10)
}

func printConfig() {
	log.Printf("Configuration:")
	log.Printf("  NATS URL: %s", config.NATS.URL)
	log.Printf("  Stream: %s", config.Worker.StreamName)
	log.Printf("  Consumer: %s", config.Worker.ConsumerName)
	log.Printf("  Queue Group: %s", config.Worker.QueueGroup)
	log.Printf("  Subject: %s", config.Worker.Subject)
	log.Printf("  Batch Size: %d", config.Worker.BatchSize)
}

func startWorker() error {
	// Connect to NATS
	opts := []nats.Option{
		nats.Name("Rule Engine Webhook Worker"),
	}

	if config.NATS.User != "" && config.NATS.Pass != "" {
		opts = append(opts, nats.UserInfo(config.NATS.User, config.NATS.Pass))
	}

	nc, err := nats.Connect(config.NATS.URL, opts...)
	if err != nil {
		return fmt.Errorf("failed to connect to NATS: %w", err)
	}
	defer nc.Close()

	log.Printf("✅ Connected to NATS at %s", nc.ConnectedUrl())

	// Get JetStream context
	js, err := nc.JetStream()
	if err != nil {
		return fmt.Errorf("failed to get JetStream context: %w", err)
	}

	// Check if stream exists
	_, err = js.StreamInfo(config.Worker.StreamName)
	if err != nil {
		log.Printf("⚠️  Stream '%s' not found - will be created by first publish", config.Worker.StreamName)
	} else {
		log.Printf("✅ Stream '%s' found", config.Worker.StreamName)
	}

	// Create or get durable consumer
	consumerConfig := &nats.ConsumerConfig{
		Durable:       config.Worker.ConsumerName,
		AckPolicy:     nats.AckExplicitPolicy,
		FilterSubject: config.Worker.Subject,
		DeliverGroup:  config.Worker.QueueGroup,
		MaxDeliver:    3,           // Max 3 delivery attempts
		AckWait:       30 * time.Second,
	}

	_, err = js.AddConsumer(config.Worker.StreamName, consumerConfig)
	if err != nil {
		// Consumer might already exist
		log.Printf("⚠️  Consumer may already exist: %v", err)
	}

	log.Printf("✅ Consumer '%s' ready", config.Worker.ConsumerName)

	// Subscribe to messages
	log.Printf("📥 Listening for messages on '%s'...\n", config.Worker.Subject)

	sub, err := js.QueueSubscribe(
		config.Worker.Subject,
		config.Worker.QueueGroup,
		processMessage,
		nats.Durable(config.Worker.ConsumerName),
		nats.ManualAck(),
		nats.MaxDeliver(3),
		nats.AckWait(30*time.Second),
	)
	if err != nil {
		return fmt.Errorf("failed to subscribe: %w", err)
	}
	defer sub.Unsubscribe()

	// Setup graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	<-sigChan
	log.Println("\n🛑 Received shutdown signal, stopping gracefully...")

	// Report final statistics
	reportStatistics()

	log.Println("👋 Worker stopped")
	return nil
}

func processMessage(msg *nats.Msg) {
	startTime := time.Now()
	messageNum := atomic.AddUint64(&stats.MessagesProcessed, 1)

	// Parse payload
	var payload WebhookPayload
	if err := json.Unmarshal(msg.Data, &payload); err != nil {
		log.Printf("❌ [%d] Failed to parse payload: %v", messageNum, err)
		atomic.AddUint64(&stats.MessagesFailed, 1)
		msg.Nak()
		return
	}

	log.Printf("📨 [%d] Processing: %s", messageNum, msg.Subject)

	// Extract webhook URL
	webhookURL := payload.WebhookURL
	if webhookURL == "" {
		log.Printf("❌ [%d] Missing webhook_url in payload", messageNum)
		atomic.AddUint64(&stats.MessagesFailed, 1)
		msg.Nak()
		return
	}

	// Prepare request body
	var requestBody []byte
	var err error
	if payload.Data != nil {
		requestBody, err = json.Marshal(payload.Data)
	} else {
		requestBody = msg.Data
	}

	if err != nil {
		log.Printf("❌ [%d] Failed to marshal request body: %v", messageNum, err)
		atomic.AddUint64(&stats.MessagesFailed, 1)
		msg.Nak()
		return
	}

	// Make HTTP request
	req, err := http.NewRequestWithContext(
		context.Background(),
		"POST",
		webhookURL,
		bytes.NewBuffer(requestBody),
	)
	if err != nil {
		log.Printf("❌ [%d] Failed to create request: %v", messageNum, err)
		atomic.AddUint64(&stats.MessagesFailed, 1)
		msg.Nak()
		return
	}

	// Set headers
	if payload.Headers != nil {
		for key, value := range payload.Headers {
			req.Header.Set(key, value)
		}
	} else {
		req.Header.Set("Content-Type", "application/json")
	}

	// Execute request
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)

	duration := time.Since(startTime)
	durationMs := duration.Milliseconds()

	if err != nil {
		log.Printf("   ❌ Request failed: %v (%dms)", err, durationMs)
		atomic.AddUint64(&stats.MessagesFailed, 1)
		msg.Nak()
		return
	}
	defer resp.Body.Close()

	// Check response status
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		log.Printf("   ✅ Success: %d (%dms)", resp.StatusCode, durationMs)
		atomic.AddUint64(&stats.MessagesSucceeded, 1)
		atomic.AddUint64(&stats.TotalProcessingTimeMs, uint64(durationMs))
		msg.Ack()
	} else {
		log.Printf("   ⚠️  HTTP Error: %d (%dms)", resp.StatusCode, durationMs)
		atomic.AddUint64(&stats.MessagesFailed, 1)
		msg.Nak()
	}

	// Report statistics periodically
	if messageNum%100 == 0 {
		reportStatistics()
	}
}

func reportStatistics() {
	processed := atomic.LoadUint64(&stats.MessagesProcessed)
	succeeded := atomic.LoadUint64(&stats.MessagesSucceeded)
	failed := atomic.LoadUint64(&stats.MessagesFailed)
	totalTime := atomic.LoadUint64(&stats.TotalProcessingTimeMs)

	var avgTime float64
	if succeeded > 0 {
		avgTime = float64(totalTime) / float64(succeeded)
	}

	uptime := time.Since(stats.StartTime).Seconds()

	log.Printf("\n📊 Statistics:")
	log.Printf("   Processed: %d", processed)
	log.Printf("   Succeeded: %d", succeeded)
	log.Printf("   Failed: %d", failed)
	log.Printf("   Avg Time: %.2fms", avgTime)
	log.Printf("   Uptime: %.0fs\n", uptime)

	// Update PostgreSQL consumer stats
	_, err := db.Exec(
		"SELECT rule_nats_consumer_update_stats($1, $2, $3, $4, $5, $6)",
		config.Worker.StreamName,
		config.Worker.ConsumerName,
		processed,
		succeeded,
		failed,
		avgTime,
	)

	if err != nil {
		log.Printf("⚠️  Failed to report statistics to PostgreSQL: %v", err)
	} else {
		log.Println("✅ Statistics reported to PostgreSQL\n")
	}
}

// Utility functions

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		var intValue int
		fmt.Sscanf(value, "%d", &intValue)
		return intValue
	}
	return defaultValue
}
