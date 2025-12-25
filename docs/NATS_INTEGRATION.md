# NATS Integration for PostgreSQL Rule Engine

Complete guide to using NATS message queue with the PostgreSQL Rule Engine for scalable, event-driven webhook processing.

## Table of Contents

- [Overview](#overview)
- [Why NATS?](#why-nats)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Publishing Messages](#publishing-messages)
- [Workers](#workers)
- [Monitoring](#monitoring)
- [Production Deployment](#production-deployment)
- [Performance Tuning](#performance-tuning)
- [Migration Guide](#migration-guide)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)
- [FAQ](#faq)

## Overview

The NATS integration enables asynchronous, distributed webhook processing using NATS JetStream as a message queue. This provides:

- **Horizontal Scalability** - Add workers to handle more load
- **High Throughput** - Process 100K+ messages/second
- **Reliability** - Persistent messages with acknowledgments
- **Load Balancing** - Automatic distribution across workers
- **Fault Tolerance** - Survive worker and network failures
- **Deduplication** - Prevent duplicate processing

### Key Features

✅ **JetStream Integration** - Persistent, acknowledged messaging
✅ **Connection Pooling** - Efficient connection reuse
✅ **Multiple Publish Modes** - Queue, NATS, or hybrid
✅ **Worker Support** - Node.js and Go workers included
✅ **Monitoring** - Built-in views and statistics
✅ **Zero Downtime** - Add/remove workers without interruption

## Why NATS?

| Feature | PostgreSQL Queue | NATS JetStream | Improvement |
|---------|-----------------|----------------|-------------|
| Throughput | ~1K msg/sec | ~100K msg/sec | **100x** |
| Horizontal Scaling | Limited | Unlimited | **∞** |
| Worker Addition | Requires config | Automatic | **Instant** |
| Network Overhead | High | Low | **10x less** |
| Message Persistence | Database | Stream | **Dedicated** |
| Load Balancing | Manual | Automatic | **Built-in** |

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     PostgreSQL Database                      │
│                  (Rule Engine Extension)                     │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Triggers/Rules → rule_webhook_call_unified()        │  │
│  │                        ↓                              │  │
│  │           publish_mode: queue | nats | both          │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────┬────────────────┬───────────────────────┘
                     │                │
         publish_mode='nats'   publish_mode='queue'
                     │                │
                     ▼                ▼
          ┌─────────────────┐  ┌──────────────┐
          │ NATS JetStream  │  │  PG Queue    │
          │ Stream: WEBHOOKS│  │              │
          └────────┬────────┘  └──────┬───────┘
                   │                  │
       Queue Group Distribution   Polling
                   │                  │
    ┌──────────────┼──────────────┐   │
    ▼              ▼              ▼   ▼
┌────────┐   ┌────────┐   ┌────────┐
│Worker 1│   │Worker 2│   │Worker 3│
└────┬───┘   └────┬───┘   └────┬───┘
     └────────────┴────────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │  External Webhooks   │
       │  (HTTP Endpoints)    │
       └──────────────────────┘
```

### Message Flow

1. **PostgreSQL** publishes event to NATS JetStream
2. **NATS** persists message and assigns sequence number
3. **Workers** (queue group) receive messages round-robin
4. **Worker** makes HTTP request to webhook endpoint
5. **Worker** acknowledges (Ack) or rejects (Nak) message
6. **Worker** reports statistics back to PostgreSQL

### Publishing Modes

**Queue Mode** (`publish_mode = 'queue'`)
- Uses PostgreSQL queue only
- Legacy mode for backward compatibility
- Good for: Low volume, simple setups

**NATS Mode** (`publish_mode = 'nats'`)
- Uses NATS JetStream only
- Best performance and scalability
- Good for: High volume, distributed systems

**Hybrid Mode** (`publish_mode = 'both'`)
- Publishes to both queue AND NATS
- Maximum reliability
- Good for: Critical webhooks, migration period

## Quick Start

### 1. Prerequisites

```bash
# Install NATS server
docker run -d --name nats-server \
  -p 4222:4222 \
  -p 8222:8222 \
  nats:latest -js

# Verify NATS is running
nats server check
```

### 2. Apply Migration

```sql
-- Apply NATS integration migration
\i migrations/007_nats_integration.sql
```

### 3. Initialize NATS Connection

```sql
-- Initialize NATS connection pool
SELECT rule_nats_init('default');

-- Returns:
-- {
--   "success": true,
--   "config": "default",
--   "nats_url": "nats://localhost:4222",
--   "jetstream_enabled": true,
--   "stream_name": "WEBHOOKS"
-- }
```

### 4. Create NATS-Enabled Webhook

```sql
INSERT INTO rule_webhooks (
    webhook_name,
    webhook_url,
    http_method,
    publish_mode,
    nats_enabled,
    nats_subject,
    nats_config_id
) VALUES (
    'slack_notifications',
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    'POST',
    'nats',  -- Use NATS
    true,
    'webhooks.slack',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
);
```

### 5. Start a Worker

**Node.js:**
```bash
cd examples/nats-workers/nodejs
npm install
npm start
```

**Go:**
```bash
cd examples/nats-workers/go
go build
./webhook-worker
```

### 6. Publish a Message

```sql
-- Publish to NATS
SELECT rule_webhook_call_unified(
    webhook_id,
    '{"text": "Hello from PostgreSQL!", "channel": "#general"}'::jsonb
);

-- Worker will receive and execute the webhook
```

## Configuration

### NATS Server Configuration

Edit `rule_nats_config` table:

```sql
-- View current config
SELECT * FROM rule_nats_config WHERE config_name = 'default';

-- Update NATS URL
UPDATE rule_nats_config
SET nats_url = 'nats://production-server:4222'
WHERE config_name = 'default';

-- Update connection pool size
UPDATE rule_nats_config
SET max_connections = 50
WHERE config_name = 'default';

-- Re-initialize after changes
SELECT rule_nats_init('default');
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `nats_url` | `nats://localhost:4222` | Primary NATS server URL |
| `nats_cluster_urls` | `NULL` | Array of cluster URLs for failover |
| `auth_type` | `none` | Authentication: none, token, credentials, nkey |
| `jetstream_enabled` | `true` | Enable JetStream persistent messaging |
| `stream_name` | `WEBHOOKS` | JetStream stream name |
| `subject_prefix` | `webhooks` | Subject prefix for all messages |
| `max_connections` | `10` | Connection pool size |
| `connection_timeout_ms` | `5000` | Connection timeout (milliseconds) |
| `reconnect_delay_ms` | `2000` | Delay between reconnect attempts |
| `max_reconnect_attempts` | `-1` | Max reconnects (-1 = infinite) |

### Multiple Configurations

Create separate configurations for different environments:

```sql
-- Production config
INSERT INTO rule_nats_config (
    config_name,
    nats_url,
    max_connections,
    tls_enabled
) VALUES (
    'production',
    'nats://prod-nats-1:4222,prod-nats-2:4222,prod-nats-3:4222',
    100,
    true
);

-- Development config
INSERT INTO rule_nats_config (
    config_name,
    nats_url,
    max_connections
) VALUES (
    'development',
    'nats://localhost:4222',
    5
);
```

## Publishing Messages

### Direct NATS Publish

```sql
-- Publish with automatic message ID
SELECT rule_webhook_publish_nats(
    webhook_id,
    '{"event": "user.created", "user_id": 123}'::jsonb,
    NULL  -- Auto-generate message ID
);

-- Publish with custom message ID (for deduplication)
SELECT rule_webhook_publish_nats(
    webhook_id,
    '{"event": "order.completed", "order_id": 456}'::jsonb,
    'order-456'  -- Custom message ID
);
```

### Unified API (Recommended)

```sql
-- Respects webhook's publish_mode setting
SELECT rule_webhook_call_unified(
    webhook_id,
    '{"data": "value"}'::jsonb
);
```

### From Triggers

```sql
CREATE OR REPLACE FUNCTION notify_user_created()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM rule_webhook_call_unified(
        (SELECT webhook_id FROM rule_webhooks WHERE webhook_name = 'user_notifications'),
        jsonb_build_object(
            'event', 'user.created',
            'user_id', NEW.user_id,
            'email', NEW.email,
            'created_at', NEW.created_at
        )
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_after_insert
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION notify_user_created();
```

### Batch Publishing

```sql
-- Publish multiple messages in a loop
DO $$
DECLARE
    v_webhook_id INTEGER;
    v_i INTEGER;
BEGIN
    SELECT webhook_id INTO v_webhook_id
    FROM rule_webhooks
    WHERE webhook_name = 'analytics_events';

    FOR v_i IN 1..1000 LOOP
        PERFORM rule_webhook_publish_nats(
            v_webhook_id,
            jsonb_build_object('event_id', v_i, 'timestamp', NOW()),
            format('event-%s', v_i)
        );
    END LOOP;
END $$;
```

## Workers

Workers consume messages from NATS and execute webhook HTTP requests.

### Node.js Worker

See [examples/nats-workers/nodejs/README.md](../examples/nats-workers/nodejs/README.md)

**Features:**
- Async/await pattern
- Automatic retries with Nak()
- Statistics reporting
- Graceful shutdown
- Environment-based configuration

**Start:**
```bash
cd examples/nats-workers/nodejs
npm install
npm start
```

### Go Worker

See [examples/nats-workers/go/README.md](../examples/nats-workers/go/README.md)

**Features:**
- High performance
- Low memory footprint
- Concurrent message processing
- Type-safe configuration
- Built-in health checks

**Start:**
```bash
cd examples/nats-workers/go
go build
./webhook-worker
```

### Load Balancing

Deploy multiple workers in the same queue group:

```bash
# Terminal 1
CONSUMER_NAME=worker-1 QUEUE_GROUP=webhook-workers npm start

# Terminal 2
CONSUMER_NAME=worker-2 QUEUE_GROUP=webhook-workers npm start

# Terminal 3
CONSUMER_NAME=worker-3 QUEUE_GROUP=webhook-workers npm start
```

NATS automatically distributes messages round-robin across all workers in the group.

### Scaling Workers

**Add workers:**
```bash
# Simply start more instances - no config needed!
docker run -d -e CONSUMER_NAME=worker-4 -e QUEUE_GROUP=webhook-workers worker:latest
```

**Remove workers:**
```bash
# Stop the process - NATS redistributes pending messages
docker stop worker-3
```

## Monitoring

### Health Check

```sql
-- Check NATS connection health
SELECT rule_nats_health_check('default');

-- Returns:
-- {
--   "success": true,
--   "config": "default",
--   "connected": true,
--   "pool_stats": {
--     "total_connections": 10,
--     "healthy_connections": 10,
--     "health_percentage": 100.0,
--     "requests_served": 12543
--   },
--   "jetstream_enabled": true
-- }
```

### Publishing Statistics

```sql
-- View publish summary by webhook
SELECT * FROM nats_publish_summary;

-- Example output:
-- webhook_name          | total_published | successful | failed | success_rate_pct | avg_latency_ms
-- ----------------------+-----------------+------------+--------+------------------+----------------
-- slack_notifications   | 10000           | 9987       | 13     | 99.87            | 12.45
-- email_notifications   | 5000            | 4999       | 1      | 99.98            | 8.23
```

### Performance Metrics

```sql
-- View performance with percentiles
SELECT * FROM nats_performance_stats;

-- Example output:
-- webhook_name        | message_count | avg_latency_ms | p50 | p95  | p99
-- --------------------+---------------+----------------+-----+------+-----
-- slack_notifications | 10000         | 12.45          | 10  | 25   | 50
-- payment_webhooks    | 5000          | 45.67          | 40  | 80   | 120
```

### Recent Failures

```sql
-- View recent failures for debugging
SELECT * FROM nats_recent_failures LIMIT 10;

-- Example output:
-- webhook_name | subject          | error_message              | published_at
-- -------------+------------------+----------------------------+-------------
-- slack        | webhooks.slack   | connection timeout         | 2024-01-15...
-- payment      | webhooks.payment | 500 Internal Server Error  | 2024-01-15...
```

### Worker Statistics

```sql
-- View worker performance
SELECT
    consumer_name,
    messages_acknowledged,
    avg_processing_time_ms,
    last_active_at
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND active = true
ORDER BY messages_acknowledged DESC;

-- Example output:
-- consumer_name  | messages_acknowledged | avg_processing_time_ms | last_active_at
-- ---------------+-----------------------+------------------------+----------------
-- worker-1       | 3542                  | 45.2                   | 2024-01-15 10:30:00
-- worker-2       | 3538                  | 46.1                   | 2024-01-15 10:30:01
-- worker-3       | 3520                  | 44.8                   | 2024-01-15 10:29:59
```

### Real-time Monitoring

```sql
-- Create monitoring query
CREATE OR REPLACE VIEW worker_realtime_stats AS
SELECT
    consumer_name,
    messages_acknowledged,
    avg_processing_time_ms,
    CASE
        WHEN avg_processing_time_ms > 0 THEN
            ROUND(1000.0 / avg_processing_time_ms, 2)
        ELSE NULL
    END as theoretical_msg_per_sec,
    EXTRACT(EPOCH FROM (NOW() - last_active_at)) as seconds_since_last_active,
    CASE
        WHEN last_active_at >= NOW() - INTERVAL '30 seconds' THEN 'ACTIVE'
        WHEN last_active_at >= NOW() - INTERVAL '5 minutes' THEN 'IDLE'
        ELSE 'STALE'
    END as status
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND active = true;

-- Query every 10 seconds
SELECT * FROM worker_realtime_stats;
```

## Production Deployment

### Docker Compose Setup

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"

  nats:
    image: nats:latest
    command: ["-js", "-m", "8222"]
    ports:
      - "4222:4222"  # Client connections
      - "8222:8222"  # Monitoring
    volumes:
      - nats_data:/data

  worker-1:
    build: ./examples/nats-workers/go
    environment:
      NATS_URL: nats://nats:4222
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      CONSUMER_NAME: worker-1
      QUEUE_GROUP: webhook-workers
    depends_on:
      - postgres
      - nats
    restart: unless-stopped

  worker-2:
    build: ./examples/nats-workers/go
    environment:
      NATS_URL: nats://nats:4222
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      CONSUMER_NAME: worker-2
      QUEUE_GROUP: webhook-workers
    depends_on:
      - postgres
      - nats
    restart: unless-stopped

  worker-3:
    build: ./examples/nats-workers/go
    environment:
      NATS_URL: nats://nats:4222
      DATABASE_URL: postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      CONSUMER_NAME: worker-3
      QUEUE_GROUP: webhook-workers
    depends_on:
      - postgres
      - nats
    restart: unless-stopped

volumes:
  postgres_data:
  nats_data:
```

### Kubernetes Deployment

See [docs/kubernetes/](kubernetes/) for complete manifests.

**Key points:**
- Deploy NATS cluster (3+ nodes)
- Deploy worker as Deployment with HPA
- Use ConfigMaps for configuration
- Use Secrets for credentials
- Monitor with Prometheus/Grafana

### High Availability

**NATS Cluster:**
```bash
# 3-node NATS cluster
docker run -d --name nats-1 -p 4222:4222 nats:latest -js -cluster nats://0.0.0.0:6222
docker run -d --name nats-2 -p 4223:4222 nats:latest -js -cluster nats://0.0.0.0:6222 -routes nats://nats-1:6222
docker run -d --name nats-3 -p 4224:4222 nats:latest -js -cluster nats://0.0.0.0:6222 -routes nats://nats-1:6222
```

**PostgreSQL:**
- Use replication (primary + standby)
- Or managed service (RDS, Cloud SQL, etc.)

**Workers:**
- Deploy 3-10 workers minimum
- Use auto-scaling based on queue depth
- Health checks on `/health` endpoint

## Performance Tuning

### NATS Configuration

```sql
-- Increase connection pool for high throughput
UPDATE rule_nats_config
SET max_connections = 100
WHERE config_name = 'default';

-- Reduce timeouts for faster failures
UPDATE rule_nats_config
SET connection_timeout_ms = 2000
WHERE config_name = 'default';

-- Re-initialize
SELECT rule_nats_init('default');
```

### JetStream Stream Tuning

```sql
-- Use memory storage for speed (less durability)
UPDATE rule_nats_streams
SET storage_type = 'memory',
    max_messages = 10000000
WHERE stream_name = 'WEBHOOKS';

-- Or file storage for durability
UPDATE rule_nats_streams
SET storage_type = 'file',
    max_messages = 100000000,
    max_bytes = 10737418240  -- 10GB
WHERE stream_name = 'WEBHOOKS';
```

### Worker Tuning

**Node.js:**
```bash
# Increase batch size
BATCH_SIZE=50 npm start

# Use cluster mode
node --max-old-space-size=4096 worker.js
```

**Go:**
```bash
# Increase concurrent processing
BATCH_SIZE=100 ./webhook-worker

# Tune Go runtime
GOMAXPROCS=8 ./webhook-worker
```

### Database Tuning

```sql
-- Create indexes for faster queries
CREATE INDEX CONCURRENTLY idx_nats_publish_webhook_time
ON rule_nats_publish_history(webhook_id, published_at DESC);

-- Partition history table by time
-- (See PostgreSQL partitioning docs)

-- Regular cleanup
SELECT rule_nats_cleanup_old_history('7 days', true);
```

## Migration Guide

See [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) for detailed migration instructions.

### Quick Migration Steps

1. **Install NATS** (doesn't affect existing queue)
2. **Apply migration 007** (adds NATS tables)
3. **Enable hybrid mode** for critical webhooks:
   ```sql
   UPDATE rule_webhooks
   SET publish_mode = 'both',
       nats_enabled = true,
       nats_subject = 'webhooks.' || LOWER(webhook_name)
   WHERE webhook_name IN ('critical_webhook_1', 'critical_webhook_2');
   ```
4. **Start workers**
5. **Monitor for 24-48 hours**
6. **Switch to NATS-only**:
   ```sql
   UPDATE rule_webhooks SET publish_mode = 'nats' WHERE publish_mode = 'both';
   ```

## Troubleshooting

### Workers Not Receiving Messages

**Check NATS stream:**
```bash
nats stream ls
nats stream info WEBHOOKS
```

**Check consumer:**
```bash
nats consumer ls WEBHOOKS
nats consumer info WEBHOOKS webhook-worker-1
```

**Check subject:**
```sql
SELECT webhook_name, nats_subject, enabled
FROM rule_webhooks
WHERE nats_enabled = true;
```

### High Latency

**Check worker count:**
```sql
SELECT COUNT(*) FROM rule_nats_consumer_stats WHERE active = true;
```

**Check message backlog:**
```bash
nats stream info WEBHOOKS
# Look at "Messages: X"
```

**Solution:** Add more workers

### Connection Errors

**Check NATS server:**
```bash
nats server check
nats server ping
```

**Check configuration:**
```sql
SELECT * FROM rule_nats_config WHERE config_name = 'default';
```

**Re-initialize:**
```sql
SELECT rule_nats_init('default');
```

### Message Duplicates

**Enable deduplication:**
```sql
-- Use consistent message IDs
SELECT rule_webhook_publish_nats(
    webhook_id,
    payload,
    format('order-%s', order_id)  -- Consistent ID
);
```

**Check duplicate window:**
```sql
SELECT duplicate_window_seconds
FROM rule_nats_streams
WHERE stream_name = 'WEBHOOKS';
```

## API Reference

### SQL Functions

#### `rule_nats_init(config_name TEXT)`

Initialize NATS connection pool.

**Parameters:**
- `config_name` - Configuration name (default: 'default')

**Returns:** JSON with connection status

**Example:**
```sql
SELECT rule_nats_init('default');
```

#### `rule_webhook_publish_nats(webhook_id INT, payload JSONB, message_id TEXT)`

Publish message to NATS.

**Parameters:**
- `webhook_id` - Webhook ID
- `payload` - JSON payload
- `message_id` - Optional message ID for deduplication

**Returns:** JSON with publish acknowledgment

**Example:**
```sql
SELECT rule_webhook_publish_nats(
    123,
    '{"data": "value"}'::jsonb,
    'msg-001'
);
```

#### `rule_webhook_call_unified(webhook_id INT, payload JSONB)`

Unified webhook call (respects publish_mode).

**Parameters:**
- `webhook_id` - Webhook ID
- `payload` - JSON payload

**Returns:** JSON with results from queue and/or NATS

**Example:**
```sql
SELECT rule_webhook_call_unified(123, '{"data": "value"}'::jsonb);
```

#### `rule_nats_health_check(config_name TEXT)`

Check NATS connection health.

**Parameters:**
- `config_name` - Configuration name

**Returns:** JSON with health status

**Example:**
```sql
SELECT rule_nats_health_check('default');
```

## FAQ

**Q: Can I use NATS without removing the existing queue?**
A: Yes! Use hybrid mode (`publish_mode = 'both'`) to publish to both systems simultaneously.

**Q: What happens if NATS server goes down?**
A: Messages are persisted in JetStream. Workers will reconnect automatically and continue processing.

**Q: How do I monitor message backlog?**
A: Use `nats stream info WEBHOOKS` or query `rule_nats_consumer_stats` table.

**Q: Can I prioritize certain messages?**
A: Use separate streams/subjects for different priorities and deploy dedicated workers.

**Q: What's the maximum message size?**
A: NATS supports up to 1MB per message by default. Configure `max_payload` if needed.

**Q: How do I handle webhook failures?**
A: Workers automatically retry with `Nak()`. Failed messages are redelivered up to `max_deliver` times.

**Q: Can I use multiple NATS servers?**
A: Yes! Configure `nats_cluster_urls` for automatic failover.

**Q: How do I test without NATS server?**
A: Use `publish_mode = 'queue'` for testing. Switch to NATS in production.

**Q: What about message ordering?**
A: Messages are processed in order per worker. For strict ordering, use single worker or subject-based partitioning.

**Q: How much does NATS cost?**
A: NATS is open-source and free. You only pay for infrastructure (servers/cloud).

## Support

- **GitHub Issues:** [rule-engine-postgre-extensions/issues](https://github.com/yourusername/rule-engine-postgre-extensions/issues)
- **NATS Community:** [Slack](https://slack.nats.io/)
- **Documentation:** [docs.nats.io](https://docs.nats.io/)

## License

MIT
