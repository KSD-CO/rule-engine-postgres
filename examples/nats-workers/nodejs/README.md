# NATS Webhook Worker (Node.js)

A production-ready NATS JetStream worker for processing webhook events from PostgreSQL rule engine.

## Features

- ✅ JetStream consumer with durable storage
- ✅ Queue group for load balancing across multiple workers
- ✅ Automatic retry with exponential backoff
- ✅ HTTP webhook execution with axios
- ✅ Statistics reporting back to PostgreSQL
- ✅ Graceful shutdown handling
- ✅ Error handling and logging

## Installation

```bash
npm install
```

## Configuration

Configure via environment variables:

```bash
# NATS connection
export NATS_URL="nats://localhost:4222"
export NATS_USER=""  # Optional
export NATS_PASS=""  # Optional

# PostgreSQL connection
export DATABASE_URL="postgresql://user:pass@localhost/dbname"

# Worker settings
export STREAM_NAME="WEBHOOKS"
export CONSUMER_NAME="webhook-worker-1"
export QUEUE_GROUP="webhook-workers"
export SUBJECT="webhooks.*"
export BATCH_SIZE="10"
```

Or create a `.env` file:

```env
NATS_URL=nats://localhost:4222
DATABASE_URL=postgresql://localhost/postgres
STREAM_NAME=WEBHOOKS
CONSUMER_NAME=webhook-worker-1
QUEUE_GROUP=webhook-workers
SUBJECT=webhooks.*
BATCH_SIZE=10
```

## Usage

### Start Worker

```bash
npm start
```

### Development Mode (with auto-reload)

```bash
npm run dev
```

### Docker

```bash
docker build -t nats-webhook-worker .
docker run -e NATS_URL=nats://nats:4222 \
           -e DATABASE_URL=postgresql://postgres:5432/mydb \
           nats-webhook-worker
```

## Message Format

The worker expects messages with the following format:

```json
{
  "webhook_url": "https://hooks.example.com/webhook",
  "data": {
    "event": "order.created",
    "order_id": 12345,
    "amount": 99.99
  },
  "headers": {
    "Content-Type": "application/json",
    "Authorization": "Bearer token123"
  }
}
```

Or simplified format (webhook URL in PostgreSQL):

```json
{
  "event": "order.created",
  "order_id": 12345,
  "amount": 99.99
}
```

## Load Balancing

Multiple workers can share the workload by joining the same queue group:

```bash
# Terminal 1
CONSUMER_NAME=worker-1 npm start

# Terminal 2
CONSUMER_NAME=worker-2 npm start

# Terminal 3
CONSUMER_NAME=worker-3 npm start
```

All workers in the same `QUEUE_GROUP` will receive messages in round-robin fashion.

## Monitoring

The worker reports statistics to PostgreSQL every 100 messages:

```sql
-- View consumer statistics
SELECT * FROM rule_nats_consumer_stats
WHERE consumer_name = 'webhook-worker-1';

-- View recent activity
SELECT
  consumer_name,
  messages_delivered,
  messages_acknowledged,
  avg_processing_time_ms,
  last_active_at
FROM rule_nats_consumer_stats
WHERE active = true;
```

## Error Handling

- **HTTP 2xx-3xx:** Message acknowledged (success)
- **HTTP 4xx-5xx:** Message NAK'd (will retry)
- **Network errors:** Message NAK'd (will retry)
- **Max retries (3):** Message moved to dead letter queue

## Graceful Shutdown

The worker handles `SIGINT` and `SIGTERM` signals:

```bash
# Ctrl+C or kill command
kill <pid>
```

On shutdown:
1. Stops consuming new messages
2. Reports final statistics to PostgreSQL
3. Closes database connections
4. Exits cleanly

## Logging

Worker logs include:
- Message processing (subject, payload preview)
- HTTP response status and duration
- Statistics every 100 messages
- Errors with stack traces

Example output:

```
🚀 Starting NATS Webhook Worker
✅ Connected to NATS at nats://localhost:4222
✅ Stream "WEBHOOKS" found
✅ Consumer "webhook-worker-1" ready
📥 Listening for messages on "webhooks.*"...

📨 [1] Processing: webhooks.slack
   Payload: {"webhook_url":"https://hooks.slack.com/...","data":{"text":"Hello"}...
   ✅ Success: 200 (123ms)

📊 Statistics: {
  processed: 100,
  succeeded: 98,
  failed: 2,
  avgTime: '145.23ms',
  uptime: '45s'
}
✅ Statistics reported to PostgreSQL
```

## Troubleshooting

### Worker can't connect to NATS

```bash
# Check NATS is running
nats server ping

# Check URL is correct
echo $NATS_URL
```

### Consumer not receiving messages

```bash
# Check stream exists
nats stream info WEBHOOKS

# Check messages in stream
nats stream view WEBHOOKS

# Check consumer status
nats consumer info WEBHOOKS webhook-worker-1
```

### PostgreSQL connection fails

```bash
# Test connection
psql $DATABASE_URL -c "SELECT 1"

# Check if function exists
psql $DATABASE_URL -c "\df rule_nats_consumer_update_stats"
```

## Production Deployment

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nats-webhook-worker
spec:
  replicas: 3  # Scale horizontally
  selector:
    matchLabels:
      app: nats-webhook-worker
  template:
    metadata:
      labels:
        app: nats-webhook-worker
    spec:
      containers:
      - name: worker
        image: nats-webhook-worker:latest
        env:
        - name: NATS_URL
          value: "nats://nats:4222"
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: url
        - name: CONSUMER_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
```

### Docker Compose

```yaml
version: '3.8'
services:
  nats:
    image: nats:latest
    command: ["-js"]
    ports:
      - "4222:4222"

  postgres:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"

  worker:
    build: .
    depends_on:
      - nats
      - postgres
    environment:
      NATS_URL: nats://nats:4222
      DATABASE_URL: postgresql://postgres:postgres@postgres:5432/postgres
    deploy:
      replicas: 3
```

## Performance Tuning

- **BATCH_SIZE:** Increase for higher throughput (default: 10)
- **Replicas:** Add more workers for horizontal scaling
- **Queue Groups:** Use different groups for different webhook types
- **Connection Pool:** Adjust PostgreSQL pool size in code

## License

MIT
