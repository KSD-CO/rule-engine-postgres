# NATS Webhook Worker (Go)

High-performance NATS JetStream consumer for processing webhook events from the PostgreSQL Rule Engine.

## Features

- ✅ **NATS JetStream Consumer** - Durable consumer with acknowledgment
- ✅ **Queue Groups** - Load balancing across multiple workers
- ✅ **HTTP Webhook Execution** - POST requests with custom headers
- ✅ **Retry Logic** - Automatic retries with `Nak()` for failed requests
- ✅ **Statistics Tracking** - Real-time metrics and PostgreSQL reporting
- ✅ **Graceful Shutdown** - Clean termination with final stats report
- ✅ **Configurable** - Environment variable-based configuration

## Prerequisites

- Go 1.21+
- NATS Server with JetStream enabled
- PostgreSQL with Rule Engine extension
- Access to NATS server and PostgreSQL database

## Installation

### 1. Clone and Build

```bash
cd examples/nats-workers/go
go mod download
go build -o webhook-worker .
```

### 2. Configuration

Set environment variables:

```bash
# NATS Configuration
export NATS_URL="nats://localhost:4222"
export NATS_USER=""                    # Optional
export NATS_PASS=""                    # Optional

# PostgreSQL Configuration
export DATABASE_URL="postgresql://postgres:password@localhost:5432/postgres?sslmode=disable"

# Worker Configuration
export STREAM_NAME="WEBHOOKS"
export CONSUMER_NAME="webhook-worker-1"
export QUEUE_GROUP="webhook-workers"
export SUBJECT="webhooks.*"
export BATCH_SIZE="10"
```

Or create a `.env` file:

```env
NATS_URL=nats://localhost:4222
DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres?sslmode=disable
STREAM_NAME=WEBHOOKS
CONSUMER_NAME=webhook-worker-1
QUEUE_GROUP=webhook-workers
SUBJECT=webhooks.*
BATCH_SIZE=10
```

### 3. Run Worker

```bash
./webhook-worker
```

## Docker Deployment

### Build Image

```bash
docker build -t nats-webhook-worker:latest .
```

### Run Container

```bash
docker run -d \
  --name webhook-worker-1 \
  -e NATS_URL=nats://nats-server:4222 \
  -e DATABASE_URL=postgresql://postgres:password@postgres:5432/postgres \
  -e CONSUMER_NAME=webhook-worker-1 \
  -e QUEUE_GROUP=webhook-workers \
  --restart unless-stopped \
  nats-webhook-worker:latest
```

## Load Balancing Setup

Deploy multiple workers in the same queue group for horizontal scaling:

```bash
# Worker 1
docker run -d \
  --name webhook-worker-1 \
  -e CONSUMER_NAME=webhook-worker-1 \
  -e QUEUE_GROUP=webhook-workers \
  nats-webhook-worker:latest

# Worker 2
docker run -d \
  --name webhook-worker-2 \
  -e CONSUMER_NAME=webhook-worker-2 \
  -e QUEUE_GROUP=webhook-workers \
  nats-webhook-worker:latest

# Worker 3
docker run -d \
  --name webhook-worker-3 \
  -e CONSUMER_NAME=webhook-worker-3 \
  -e QUEUE_GROUP=webhook-workers \
  nats-webhook-worker:latest
```

All workers in the same `QUEUE_GROUP` will share the message load automatically.

## Message Format

The worker expects messages with the following JSON structure:

```json
{
  "webhook_url": "https://example.com/webhook",
  "data": {
    "event": "user.created",
    "user_id": 123,
    "timestamp": "2024-01-15T10:30:00Z"
  },
  "headers": {
    "X-Event-Type": "user.created",
    "Authorization": "Bearer token123"
  }
}
```

**Fields:**
- `webhook_url` (required) - Target HTTP endpoint
- `data` (optional) - JSON payload to send
- `headers` (optional) - Custom HTTP headers

## Statistics

The worker reports statistics every 100 messages and on shutdown:

```
📊 Statistics:
   Processed: 1000
   Succeeded: 985
   Failed: 15
   Avg Time: 45.23ms
   Uptime: 3600s
```

Statistics are automatically saved to PostgreSQL:

```sql
SELECT * FROM rule_nats_consumer_stats
WHERE consumer_name = 'webhook-worker-1';
```

## Monitoring

### Check Worker Status

```sql
-- View consumer statistics
SELECT
    consumer_name,
    messages_delivered,
    messages_acknowledged,
    avg_processing_time_ms,
    last_active_at
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND active = true;
```

### View Recent Failures

```sql
SELECT * FROM nats_recent_failures LIMIT 10;
```

### Performance Metrics

```sql
SELECT * FROM nats_performance_stats;
```

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `NATS_URL` | `nats://localhost:4222` | NATS server URL |
| `NATS_USER` | `` | NATS username (optional) |
| `NATS_PASS` | `` | NATS password (optional) |
| `DATABASE_URL` | `postgresql://localhost/postgres` | PostgreSQL connection string |
| `STREAM_NAME` | `WEBHOOKS` | JetStream stream name |
| `CONSUMER_NAME` | `webhook-worker-1` | Unique consumer identifier |
| `QUEUE_GROUP` | `webhook-workers` | Queue group for load balancing |
| `SUBJECT` | `webhooks.*` | Subject filter pattern |
| `BATCH_SIZE` | `10` | Messages to process concurrently |

## Architecture

```
┌─────────────────────┐
│   PostgreSQL DB     │
│  Rule Engine Ext    │
└──────────┬──────────┘
           │ Publishes
           ▼
┌─────────────────────┐
│   NATS JetStream    │
│  Stream: WEBHOOKS   │
└──────────┬──────────┘
           │ Distributes
           ▼
┌─────────────────────────────────────┐
│      Queue Group: webhook-workers    │
├──────────┬──────────┬───────────────┤
│ Worker 1 │ Worker 2 │   Worker 3    │
└──────────┴──────────┴───────────────┘
           │
           ▼
┌─────────────────────┐
│  External Webhooks  │
│   (HTTP Endpoints)  │
└─────────────────────┘
```

## Error Handling

The worker uses NATS acknowledgment policies:

- **Ack()** - Message processed successfully (2xx HTTP response)
- **Nak()** - Message failed, should be redelivered (non-2xx HTTP response or errors)

Failed messages are automatically redelivered up to `MaxDeliver: 3` times before being moved to a dead letter queue.

## Graceful Shutdown

The worker handles `SIGINT` and `SIGTERM` signals:

```bash
# Stop gracefully
kill -SIGTERM <pid>

# Or with Docker
docker stop webhook-worker-1
```

On shutdown:
1. Stops accepting new messages
2. Completes in-flight message processing
3. Reports final statistics to PostgreSQL
4. Closes NATS connection cleanly

## Troubleshooting

### Worker Not Receiving Messages

1. Check stream exists:
```bash
nats stream ls
nats stream info WEBHOOKS
```

2. Check consumer exists:
```bash
nats consumer ls WEBHOOKS
nats consumer info WEBHOOKS webhook-worker-1
```

3. Verify subject matches:
```bash
# Should match SUBJECT env var
nats stream info WEBHOOKS
```

### Connection Issues

```bash
# Test NATS connection
nats server check connection

# Test PostgreSQL connection
psql $DATABASE_URL -c "SELECT 1"
```

### High Error Rate

Check recent failures:
```sql
SELECT
    error_message,
    COUNT(*) as occurrences
FROM rule_nats_publish_history
WHERE success = false
  AND published_at >= NOW() - INTERVAL '1 hour'
GROUP BY error_message
ORDER BY occurrences DESC;
```

## Performance Tuning

### Increase Concurrency

```bash
# Process more messages in parallel
export BATCH_SIZE=50
```

### Horizontal Scaling

Add more workers to the queue group:

```bash
# Scale to 5 workers
for i in {1..5}; do
  docker run -d \
    --name webhook-worker-$i \
    -e CONSUMER_NAME=webhook-worker-$i \
    -e QUEUE_GROUP=webhook-workers \
    nats-webhook-worker:latest
done
```

### Tune JetStream

For high throughput, configure stream for memory storage:

```sql
UPDATE rule_nats_streams
SET storage_type = 'memory',
    max_messages = 10000000
WHERE stream_name = 'WEBHOOKS';
```

## Development

### Run Tests

```bash
go test ./...
```

### Build for Production

```bash
# With optimizations
go build -ldflags="-s -w" -o webhook-worker .

# Check binary size
ls -lh webhook-worker
```

### Cross-Compile

```bash
# Linux AMD64
GOOS=linux GOARCH=amd64 go build -o webhook-worker-linux-amd64 .

# Linux ARM64
GOOS=linux GOARCH=arm64 go build -o webhook-worker-linux-arm64 .

# macOS AMD64
GOOS=darwin GOARCH=amd64 go build -o webhook-worker-darwin-amd64 .
```

## License

MIT

## Support

For issues and questions:
- GitHub Issues: [rule-engine-postgre-extensions](https://github.com/yourusername/rule-engine-postgre-extensions/issues)
- Documentation: [docs/NATS_INTEGRATION.md](../../../docs/NATS_INTEGRATION.md)
