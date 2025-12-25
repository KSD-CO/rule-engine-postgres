# NATS Integration Examples

Comprehensive SQL examples demonstrating NATS JetStream integration with the PostgreSQL Rule Engine.

## Overview

These examples show real-world usage patterns for webhook publishing via NATS:

1. **Basic Setup** - Initial configuration and simple publishing
2. **Fan-Out Pattern** - Publish one event to multiple webhooks
3. **Load Balancing** - Horizontal scaling with queue groups
4. **Hybrid Mode** - Using both NATS and PostgreSQL queue

## Prerequisites

Before running these examples, ensure you have:

### 1. PostgreSQL with Rule Engine Extension

```bash
# Install extension
CREATE EXTENSION IF NOT EXISTS rule_engine;

# Run migrations
\i migrations/001_initial_schema.sql
\i migrations/002_builtin_functions.sql
# ... (all migrations up to 007)
\i migrations/007_nats_integration.sql
```

### 2. NATS Server Running

```bash
# Docker
docker run -d --name nats-server \
  -p 4222:4222 \
  -p 8222:8222 \
  nats:latest \
  -js

# Or native installation
nats-server -js
```

Verify NATS is running:
```bash
nats server check
```

### 3. NATS Workers Deployed

Choose Node.js or Go workers (or both):

**Node.js Worker:**
```bash
cd examples/nats-workers/nodejs
npm install
npm start
```

**Go Worker:**
```bash
cd examples/nats-workers/go
go build
./webhook-worker
```

## Quick Start

### 1. Connect to PostgreSQL

```bash
psql -U postgres -d your_database
```

### 2. Run Examples in Order

```sql
-- Example 1: Basic Setup
\i examples/nats-integration/01_basic_setup.sql

-- Example 2: Fan-Out Pattern
\i examples/nats-integration/02_fanout_pattern.sql

-- Example 3: Load Balancing
\i examples/nats-integration/03_load_balancing.sql

-- Example 4: Hybrid Mode
\i examples/nats-integration/04_hybrid_mode.sql
```

## Example Summaries

### 01_basic_setup.sql

**What it demonstrates:**
- Initialize NATS connection pool
- Create a simple NATS-enabled webhook
- Publish messages to NATS JetStream
- Verify publishing with history and statistics
- Health checks and monitoring

**Key functions:**
- `rule_nats_init()` - Initialize NATS connection
- `rule_webhook_publish_nats()` - Publish to NATS
- `rule_webhook_call_unified()` - Unified API (respects publish_mode)
- `rule_nats_health_check()` - Connection health status

**Views used:**
- `nats_publish_summary` - Aggregate statistics per webhook
- `nats_performance_stats` - Performance metrics with percentiles
- `nats_recent_failures` - Recent errors for debugging

**Learning outcomes:**
- Understand NATS configuration options
- Learn message publishing flow
- Monitor NATS integration health
- Verify message delivery

---

### 02_fanout_pattern.sql

**What it demonstrates:**
- Publish one event to multiple webhooks using NATS subjects
- Create subject hierarchies (e.g., `webhooks.user.registered.*`)
- Implement database triggers for automatic fan-out
- Conditional fan-out based on business logic

**Use cases:**
- User registration triggers multiple services (Slack, Email, Analytics, CRM)
- Order creation notifies warehouse, shipping, accounting
- Content publication updates CDN, search index, social media

**Key concepts:**
- Subject patterns with wildcards (`*`, `>`)
- Subject hierarchy design
- Parallel webhook execution
- Independent failure handling

**Functions created:**
- `notify_user_registered()` - Fan-out to all user.registered webhooks
- `trigger_user_registered()` - Database trigger function
- `notify_user_registered_conditional()` - Conditional fan-out logic

**Learning outcomes:**
- Design effective subject hierarchies
- Implement database-driven event fan-out
- Handle partial failures gracefully
- Monitor per-webhook performance

---

### 03_load_balancing.sql

**What it demonstrates:**
- Horizontal scaling with NATS queue groups
- Multiple workers processing messages in parallel
- Load distribution across workers
- Dynamic scaling (add/remove workers at runtime)
- Worker health monitoring

**Key concepts:**
- Queue groups for load balancing
- Round-robin message distribution
- Worker registration and statistics
- Throughput calculation

**Functions created:**
- `generate_order_events()` - Generate test load
- `monitor_worker_health()` - Worker health check
- `compare_publish_modes()` - Performance comparison (NATS vs Queue)

**Views created:**
- `worker_throughput` - Real-time worker throughput metrics

**Performance insights:**
- Linear scaling: N workers = N× throughput
- Automatic failover when workers die
- No configuration needed for scaling
- Real-world example: ~400 msg/sec with 3 workers

**Learning outcomes:**
- Configure queue groups for load balancing
- Monitor worker distribution
- Scale horizontally based on load
- Handle worker failures gracefully

---

### 04_hybrid_mode.sql

**What it demonstrates:**
- Using both NATS and PostgreSQL queue simultaneously
- Maximum reliability for critical webhooks
- Failover scenarios and recovery
- Cost-benefit analysis
- Migration strategy from queue-only to hybrid/NATS

**When to use hybrid mode:**
- Critical financial transactions (payments, refunds)
- Compliance/legal notifications
- High-value customer events
- When maximum reliability is required

**Key concepts:**
- Dual publishing (queue + NATS)
- Independent retry mechanisms
- System health monitoring
- Gradual migration strategy

**Functions created:**
- `smart_webhook_publish()` - Conditional hybrid mode
- Views showing comparative statistics

**Views created:**
- `webhook_system_health` - Health status for NATS and Queue
- `hybrid_mode_costs` - Resource usage analysis

**Learning outcomes:**
- Understand trade-offs of each mode
- Implement multi-channel publishing
- Monitor dual systems effectively
- Plan migration from legacy queue

---

## Common Patterns

### Publishing a Message

```sql
-- Method 1: Direct NATS publish
SELECT rule_webhook_publish_nats(
    webhook_id,
    '{"data": "value"}'::jsonb,
    'optional-message-id'
);

-- Method 2: Unified API (recommended)
SELECT rule_webhook_call_unified(
    webhook_id,
    '{"data": "value"}'::jsonb
);
```

### Monitoring

```sql
-- Check NATS health
SELECT rule_nats_health_check('default');

-- View webhook statistics
SELECT * FROM nats_publish_summary;

-- Recent failures
SELECT * FROM nats_recent_failures LIMIT 10;

-- Performance metrics
SELECT * FROM nats_performance_stats;

-- Worker status
SELECT
    consumer_name,
    messages_acknowledged,
    avg_processing_time_ms,
    last_active_at
FROM rule_nats_consumer_stats
WHERE active = true;
```

### Troubleshooting

```sql
-- Find webhooks with high failure rate
SELECT
    webhook_name,
    total_published,
    failed,
    success_rate_pct
FROM nats_publish_summary
WHERE success_rate_pct < 95
ORDER BY failed DESC;

-- Check slow webhooks
SELECT
    webhook_name,
    subject,
    avg_latency_ms,
    p99_latency_ms
FROM nats_performance_stats
WHERE avg_latency_ms > 100
ORDER BY avg_latency_ms DESC;

-- Find inactive workers
SELECT
    consumer_name,
    last_active_at,
    EXTRACT(EPOCH FROM (NOW() - last_active_at)) as seconds_inactive
FROM rule_nats_consumer_stats
WHERE active = true
  AND last_active_at < NOW() - INTERVAL '5 minutes';
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     PostgreSQL Database                      │
│                  (Rule Engine Extension)                     │
│                                                              │
│  ┌──────────────┐    ┌───────────────┐   ┌──────────────┐ │
│  │   Triggers   │───▶│   Functions   │──▶│   Webhooks   │ │
│  │  (INSERT/    │    │ rule_webhook_ │   │   (NATS or   │ │
│  │   UPDATE)    │    │ call_unified()│   │    Queue)    │ │
│  └──────────────┘    └───────┬───────┘   └──────┬───────┘ │
│                              │                    │         │
└──────────────────────────────┼────────────────────┼─────────┘
                               │                    │
                    publish_mode='nats'   publish_mode='queue'
                               │                    │
                               ▼                    ▼
                    ┌─────────────────┐  ┌────────────────────┐
                    │ NATS JetStream  │  │ PostgreSQL Queue   │
                    │ Stream: WEBHOOKS│  │   (pgmq/native)    │
                    └────────┬────────┘  └─────────┬──────────┘
                             │                     │
                 Queue Group Distribution    Worker Polling
                             │                     │
        ┌────────────────────┼────────────────┐    │
        ▼                    ▼                ▼    ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ NATS Worker 1│  │ NATS Worker 2│  │ Queue Worker │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                  │
       └─────────────────┴──────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │  External Webhooks  │
              │   (HTTP Endpoints)  │
              └─────────────────────┘
```

## Configuration Reference

### NATS Config Table

```sql
SELECT * FROM rule_nats_config;
```

Key columns:
- `config_name` - Unique identifier (e.g., 'default', 'production')
- `nats_url` - NATS server URL
- `jetstream_enabled` - Enable JetStream (recommended: true)
- `stream_name` - JetStream stream name
- `max_connections` - Connection pool size

### Webhook Config

```sql
SELECT
    webhook_id,
    webhook_name,
    publish_mode,      -- 'queue', 'nats', or 'both'
    nats_enabled,      -- true for NATS publishing
    nats_subject       -- NATS subject (e.g., 'webhooks.orders')
FROM rule_webhooks;
```

## Performance Tuning

### 1. Connection Pool Size

```sql
-- Increase for higher throughput
UPDATE rule_nats_config
SET max_connections = 50
WHERE config_name = 'default';

-- Re-initialize
SELECT rule_nats_init('default');
```

### 2. Worker Scaling

```bash
# Add more workers for higher throughput
for i in {1..10}; do
  docker run -d \
    --name webhook-worker-$i \
    -e CONSUMER_NAME=webhook-worker-$i \
    -e QUEUE_GROUP=webhook-workers \
    nats-webhook-worker:latest
done
```

### 3. JetStream Storage

```sql
-- Use memory storage for high-throughput, non-critical events
UPDATE rule_nats_streams
SET storage_type = 'memory',
    max_messages = 10000000
WHERE stream_name = 'WEBHOOKS';
```

## Migration Guide

### From Queue-Only to NATS

**Step 1:** Start with hybrid mode
```sql
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(webhook_name)
WHERE webhook_id = <your_webhook_id>;
```

**Step 2:** Monitor for 24-48 hours
```sql
SELECT * FROM hybrid_mode_costs;
SELECT * FROM webhook_system_health;
```

**Step 3:** Switch to NATS-only if stable
```sql
UPDATE rule_webhooks
SET publish_mode = 'nats'
WHERE webhook_id = <your_webhook_id>;
```

## Troubleshooting

### Workers Not Receiving Messages

1. Check NATS connection:
```bash
nats server check
nats stream ls
nats stream info WEBHOOKS
```

2. Verify subject matches:
```sql
SELECT webhook_name, nats_subject FROM rule_webhooks WHERE nats_enabled = true;
```

3. Check worker logs

### High Latency

1. Check worker health:
```sql
SELECT * FROM monitor_worker_health();
```

2. Add more workers if needed

3. Check network latency to webhook endpoints

### Message Duplicates

- Ensure you're providing unique `message_id` when publishing
- Check duplicate window configuration

## Additional Resources

- [NATS Documentation](https://docs.nats.io/)
- [JetStream Guide](https://docs.nats.io/nats-concepts/jetstream)
- [Node.js Worker README](../nats-workers/nodejs/README.md)
- [Go Worker README](../nats-workers/go/README.md)
- [RFC-0007: NATS Integration](../../docs/rfcs/0007-nats-message-queue-integration.md)

## Support

For issues and questions:
- GitHub Issues: [rule-engine-postgre-extensions](https://github.com/yourusername/rule-engine-postgre-extensions/issues)
- NATS Community: [Slack](https://slack.nats.io/)

## License

MIT
