# Migration Guide: PostgreSQL Queue → NATS

Step-by-step guide to migrate from PostgreSQL queue-based webhooks to NATS message queue.

## Table of Contents

- [Overview](#overview)
- [Migration Strategy](#migration-strategy)
- [Prerequisites](#prerequisites)
- [Phase 1: Preparation](#phase-1-preparation)
- [Phase 2: Pilot Migration](#phase-2-pilot-migration)
- [Phase 3: Gradual Rollout](#phase-3-gradual-rollout)
- [Phase 4: Full Migration](#phase-4-full-migration)
- [Phase 5: Cleanup](#phase-5-cleanup)
- [Rollback Plan](#rollback-plan)
- [Validation](#validation)
- [Best Practices](#best-practices)

## Overview

This guide helps you migrate from the traditional PostgreSQL queue to NATS JetStream while maintaining **zero downtime** and **zero data loss**.

### Migration Timeline

| Phase | Duration | Downtime | Risk |
|-------|----------|----------|------|
| 1. Preparation | 1-2 hours | None | Low |
| 2. Pilot | 24-48 hours | None | Low |
| 3. Gradual Rollout | 1-2 weeks | None | Medium |
| 4. Full Migration | 1-2 days | None | Low |
| 5. Cleanup | 1 hour | None | Low |

**Total Time:** 2-3 weeks (can be faster for smaller deployments)

### Why Hybrid Mode?

During migration, we use **hybrid mode** (`publish_mode = 'both'`) which:
- Publishes to BOTH queue and NATS simultaneously
- Provides safety net during migration
- Allows gradual worker transition
- Enables easy rollback if issues occur
- Validates NATS behavior against known queue behavior

## Migration Strategy

```
Current State          Hybrid State           Target State
─────────────         ──────────────         ─────────────

   Queue                Queue + NATS              NATS
     │                     │     │                  │
     ▼                     ▼     ▼                  ▼
   Worker              Old   New               Worker
                      Worker Worker
```

### Three-Phase Approach

1. **Hybrid Mode** - Publish to both systems
2. **Dual Workers** - Run both old and new workers
3. **NATS Only** - Switch to NATS after validation

## Prerequisites

### Infrastructure

- [ ] NATS server installed and running
- [ ] NATS accessible from PostgreSQL server
- [ ] NATS accessible from worker servers
- [ ] Sufficient network bandwidth
- [ ] Monitoring tools ready

### Database

- [ ] PostgreSQL 12+ with Rule Engine extension
- [ ] Migration 007 applied
- [ ] Sufficient disk space for logs
- [ ] Database backups current

### Testing

- [ ] Staging environment available
- [ ] Test webhooks configured
- [ ] Monitoring alerts configured

## Phase 1: Preparation

**Duration:** 1-2 hours
**Risk:** Low

### Step 1.1: Install NATS Server

```bash
# Using Docker (recommended for testing)
docker run -d --name nats-server \
  -p 4222:4222 \
  -p 8222:8222 \
  -v $(pwd)/nats-data:/data \
  nats:latest -js -sd /data

# Verify installation
nats server check
nats server ping
```

For production, see [NATS deployment guide](https://docs.nats.io/running-a-nats-service/introduction/installation).

### Step 1.2: Apply Migration

```bash
# Backup database first!
pg_dump -U postgres -d your_database > backup_pre_nats.sql

# Apply migration
psql -U postgres -d your_database -f migrations/007_nats_integration.sql
```

**Verify migration:**
```sql
-- Check new tables exist
SELECT table_name FROM information_schema.tables
WHERE table_name LIKE 'rule_nats%';

-- Should return:
-- rule_nats_config
-- rule_nats_streams
-- rule_nats_publish_history
-- rule_nats_consumer_stats
```

### Step 1.3: Configure NATS Connection

```sql
-- Update default config (if needed)
UPDATE rule_nats_config
SET nats_url = 'nats://your-nats-server:4222',
    max_connections = 20
WHERE config_name = 'default';

-- Initialize connection pool
SELECT rule_nats_init('default');

-- Verify health
SELECT rule_nats_health_check('default');
```

### Step 1.4: Identify Migration Candidates

```sql
-- Find high-volume webhooks (good candidates)
SELECT
    w.webhook_id,
    w.webhook_name,
    COUNT(q.queue_id) as total_calls,
    COUNT(*) FILTER (WHERE q.status = 'success') as successful,
    COUNT(*) FILTER (WHERE q.status = 'failed') as failed,
    ROUND(AVG(EXTRACT(EPOCH FROM (q.completed_at - q.created_at)) * 1000), 2) as avg_latency_ms
FROM rule_webhooks w
LEFT JOIN rule_webhook_queue q ON w.webhook_id = q.webhook_id
WHERE q.created_at >= NOW() - INTERVAL '7 days'
GROUP BY w.webhook_id, w.webhook_name
ORDER BY total_calls DESC;

-- Identify critical webhooks (migrate carefully)
SELECT webhook_id, webhook_name
FROM rule_webhooks
WHERE webhook_name LIKE '%payment%'
   OR webhook_name LIKE '%critical%'
   OR webhook_name LIKE '%alert%';
```

## Phase 2: Pilot Migration

**Duration:** 24-48 hours
**Risk:** Low

### Step 2.1: Select Pilot Webhook

Choose a **non-critical, high-volume** webhook for pilot:

```sql
-- Example: Select analytics webhook
SELECT webhook_id, webhook_name
FROM rule_webhooks
WHERE webhook_name = 'analytics_events'
  AND enabled = true;
```

### Step 2.2: Enable Hybrid Mode

```sql
-- Enable hybrid mode for pilot webhook
UPDATE rule_webhooks
SET publish_mode = 'both',           -- Publish to queue AND NATS
    nats_enabled = true,
    nats_subject = 'webhooks.analytics',  -- Choose appropriate subject
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_name = 'analytics_events';

-- Verify configuration
SELECT
    webhook_id,
    webhook_name,
    publish_mode,
    nats_enabled,
    nats_subject
FROM rule_webhooks
WHERE webhook_name = 'analytics_events';
```

### Step 2.3: Deploy NATS Worker

**Option A: Node.js Worker**
```bash
cd examples/nats-workers/nodejs
npm install

# Configure environment
export NATS_URL="nats://your-nats-server:4222"
export DATABASE_URL="postgresql://user:pass@host:5432/dbname"
export STREAM_NAME="WEBHOOKS"
export CONSUMER_NAME="pilot-worker-1"
export QUEUE_GROUP="webhook-workers"
export SUBJECT="webhooks.analytics"

# Start worker
npm start
```

**Option B: Go Worker**
```bash
cd examples/nats-workers/go
go build -o webhook-worker

# Start with environment variables
NATS_URL="nats://your-nats-server:4222" \
DATABASE_URL="postgresql://user:pass@host:5432/dbname" \
CONSUMER_NAME="pilot-worker-1" \
QUEUE_GROUP="webhook-workers" \
SUBJECT="webhooks.analytics" \
./webhook-worker
```

### Step 2.4: Monitor Pilot

**Monitor for 24-48 hours:**

```sql
-- Compare queue vs NATS performance
WITH queue_stats AS (
    SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'success') as successful,
        AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) * 1000) as avg_ms
    FROM rule_webhook_queue
    WHERE webhook_id = (SELECT webhook_id FROM rule_webhooks WHERE webhook_name = 'analytics_events')
      AND created_at >= NOW() - INTERVAL '24 hours'
),
nats_stats AS (
    SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE success = true) as successful,
        AVG(latency_ms) as avg_ms
    FROM rule_nats_publish_history
    WHERE webhook_id = (SELECT webhook_id FROM rule_webhooks WHERE webhook_name = 'analytics_events')
      AND published_at >= NOW() - INTERVAL '24 hours'
)
SELECT
    'Queue' as system,
    q.total,
    q.successful,
    ROUND(q.avg_ms::numeric, 2) as avg_latency_ms
FROM queue_stats q
UNION ALL
SELECT
    'NATS' as system,
    n.total,
    n.successful,
    ROUND(n.avg_ms::numeric, 2) as avg_latency_ms
FROM nats_stats n;
```

**Check worker health:**
```sql
SELECT
    consumer_name,
    messages_delivered,
    messages_acknowledged,
    avg_processing_time_ms,
    last_active_at
FROM rule_nats_consumer_stats
WHERE consumer_name = 'pilot-worker-1';
```

**Expected Results:**
- ✅ Both systems receiving same number of messages
- ✅ Similar success rates (±1%)
- ✅ NATS latency lower than queue
- ✅ No errors in worker logs

### Step 2.5: Pilot Validation Checklist

- [ ] Messages published to both queue and NATS
- [ ] Both queue and NATS workers processing successfully
- [ ] No increase in error rate
- [ ] NATS latency acceptable
- [ ] Worker stable for 24+ hours
- [ ] No memory leaks in worker
- [ ] Alerts not triggered

**If pilot fails:** See [Rollback Plan](#rollback-plan)

## Phase 3: Gradual Rollout

**Duration:** 1-2 weeks
**Risk:** Medium

### Step 3.1: Categorize Webhooks

```sql
-- Create migration plan
CREATE TEMP TABLE migration_plan AS
SELECT
    webhook_id,
    webhook_name,
    CASE
        WHEN webhook_name LIKE '%test%' OR webhook_name LIKE '%dev%' THEN 1
        WHEN webhook_name LIKE '%analytics%' OR webhook_name LIKE '%log%' THEN 2
        WHEN webhook_name LIKE '%notification%' OR webhook_name LIKE '%email%' THEN 3
        WHEN webhook_name LIKE '%payment%' OR webhook_name LIKE '%critical%' THEN 5
        ELSE 4
    END as migration_wave,
    (SELECT COUNT(*) FROM rule_webhook_queue WHERE webhook_id = w.webhook_id) as call_volume
FROM rule_webhooks w
WHERE enabled = true
ORDER BY migration_wave, call_volume DESC;

-- View migration plan
SELECT * FROM migration_plan;
```

### Step 3.2: Wave 1 - Test/Dev Webhooks

```sql
-- Enable hybrid mode for Wave 1
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(REPLACE(webhook_name, ' ', '.')),
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_id IN (SELECT webhook_id FROM migration_plan WHERE migration_wave = 1);

-- Deploy workers
-- Start 2-3 workers for Wave 1
```

**Wait 48 hours, monitor, validate**

### Step 3.3: Wave 2 - Non-Critical, High-Volume

```sql
-- Enable hybrid mode for Wave 2
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(REPLACE(webhook_name, ' ', '.')),
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_id IN (SELECT webhook_id FROM migration_plan WHERE migration_wave = 2);

-- Scale workers (add 3-5 more)
```

**Wait 3-5 days, monitor, validate**

### Step 3.4: Wave 3 - Standard Webhooks

```sql
-- Enable hybrid mode for Wave 3
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(REPLACE(webhook_name, ' ', '.')),
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_id IN (SELECT webhook_id FROM migration_plan WHERE migration_wave = 3);

-- Scale workers as needed
```

**Wait 3-5 days, monitor, validate**

### Step 3.5: Wave 4 - Remaining Non-Critical

```sql
-- Enable hybrid mode for Wave 4
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(REPLACE(webhook_name, ' ', '.')),
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_id IN (SELECT webhook_id FROM migration_plan WHERE migration_wave = 4);
```

**Wait 5-7 days, monitor, validate**

### Step 3.6: Wave 5 - Critical Webhooks (Final)

```sql
-- Enable hybrid mode for critical webhooks
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(REPLACE(webhook_name, ' ', '.')),
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_id IN (SELECT webhook_id FROM migration_plan WHERE migration_wave = 5);

-- Deploy dedicated workers for critical webhooks (optional)
```

**Wait 7-10 days, monitor very carefully, validate thoroughly**

### Step 3.7: Monitoring During Rollout

Create monitoring dashboard:

```sql
-- Daily migration status
CREATE OR REPLACE VIEW migration_status AS
SELECT
    publish_mode,
    COUNT(*) as webhook_count,
    SUM((SELECT COUNT(*) FROM rule_nats_publish_history h
        WHERE h.webhook_id = w.webhook_id
          AND h.published_at >= NOW() - INTERVAL '24 hours')) as nats_messages_24h,
    SUM((SELECT COUNT(*) FROM rule_webhook_queue q
        WHERE q.webhook_id = w.webhook_id
          AND q.created_at >= NOW() - INTERVAL '24 hours')) as queue_messages_24h
FROM rule_webhooks w
WHERE enabled = true
GROUP BY publish_mode;

-- Check daily
SELECT * FROM migration_status;
```

## Phase 4: Full Migration

**Duration:** 1-2 days
**Risk:** Low (after successful hybrid period)

### Step 4.1: Final Validation

**Before switching to NATS-only:**

```sql
-- Validate all webhooks in hybrid mode
SELECT
    webhook_id,
    webhook_name,
    publish_mode,
    nats_enabled
FROM rule_webhooks
WHERE enabled = true
  AND (publish_mode != 'both' OR nats_enabled != true);

-- Should return 0 rows (all should be in hybrid mode)
```

**Compare metrics:**
```sql
-- Success rate comparison (last 7 days)
WITH metrics AS (
    SELECT
        w.webhook_name,
        COUNT(DISTINCT q.queue_id) as queue_total,
        COUNT(DISTINCT h.publish_id) as nats_total,
        COUNT(DISTINCT q.queue_id) FILTER (WHERE q.status = 'success') as queue_success,
        COUNT(DISTINCT h.publish_id) FILTER (WHERE h.success = true) as nats_success
    FROM rule_webhooks w
    LEFT JOIN rule_webhook_queue q ON w.webhook_id = q.webhook_id
        AND q.created_at >= NOW() - INTERVAL '7 days'
    LEFT JOIN rule_nats_publish_history h ON w.webhook_id = h.webhook_id
        AND h.published_at >= NOW() - INTERVAL '7 days'
    WHERE w.publish_mode = 'both'
    GROUP BY w.webhook_name
)
SELECT
    webhook_name,
    queue_total,
    nats_total,
    ROUND(100.0 * queue_success / NULLIF(queue_total, 0), 2) as queue_success_rate,
    ROUND(100.0 * nats_success / NULLIF(nats_total, 0), 2) as nats_success_rate,
    ABS(ROUND(100.0 * queue_success / NULLIF(queue_total, 0), 2) -
        ROUND(100.0 * nats_success / NULLIF(nats_total, 0), 2)) as rate_diff
FROM metrics
WHERE queue_total > 100  -- Only webhooks with significant volume
ORDER BY rate_diff DESC;

-- Success rates should be within 1-2%
```

### Step 4.2: Switch to NATS-Only

**Perform during low-traffic period:**

```sql
-- Switch all webhooks to NATS-only
BEGIN;

-- Update all webhooks
UPDATE rule_webhooks
SET publish_mode = 'nats'
WHERE publish_mode = 'both'
  AND enabled = true;

-- Verify
SELECT COUNT(*) as nats_only_count
FROM rule_webhooks
WHERE publish_mode = 'nats';

COMMIT;
```

### Step 4.3: Monitor Post-Migration

**Monitor for 24-48 hours:**

```sql
-- Check message flow
SELECT
    COUNT(*) as messages_published,
    COUNT(*) FILTER (WHERE success = true) as successful,
    COUNT(*) FILTER (WHERE success = false) as failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE success = true) / COUNT(*), 2) as success_rate
FROM rule_nats_publish_history
WHERE published_at >= NOW() - INTERVAL '1 hour';

-- Check worker health
SELECT
    consumer_name,
    messages_acknowledged,
    avg_processing_time_ms,
    active,
    last_active_at
FROM rule_nats_consumer_stats
WHERE active = true
ORDER BY consumer_name;

-- Check for errors
SELECT * FROM nats_recent_failures LIMIT 20;
```

### Step 4.4: Decommission Queue Workers

**After 48 hours of stable NATS-only operation:**

```bash
# Stop old queue workers gracefully
# Let them finish processing existing messages

# Stop worker 1
kill -SIGTERM <pid_of_queue_worker_1>

# Wait for it to finish
# Repeat for other queue workers
```

## Phase 5: Cleanup

**Duration:** 1 hour
**Risk:** Low

### Step 5.1: Archive Old Queue Data

```sql
-- Optional: Archive old queue data before cleanup
CREATE TABLE rule_webhook_queue_archive AS
SELECT * FROM rule_webhook_queue
WHERE created_at < NOW() - INTERVAL '30 days';

-- Cleanup old queue entries
DELETE FROM rule_webhook_queue
WHERE created_at < NOW() - INTERVAL '30 days'
  AND status IN ('success', 'failed');
```

### Step 5.2: Update Monitoring

```sql
-- Remove queue-specific monitoring
-- Update dashboards to focus on NATS
-- Update alerts to use NATS metrics
```

### Step 5.3: Documentation

- [ ] Update runbooks
- [ ] Update architecture diagrams
- [ ] Update team documentation
- [ ] Train team on NATS operations

## Rollback Plan

### Scenario 1: Pilot Failure

**Symptoms:** High error rate, worker crashes, performance issues

**Action:**
```sql
-- Revert pilot webhook to queue-only
UPDATE rule_webhooks
SET publish_mode = 'queue',
    nats_enabled = false
WHERE webhook_name = 'analytics_events';

-- Stop NATS worker
kill -SIGTERM <worker_pid>
```

### Scenario 2: Wave Failure

**Symptoms:** Multiple webhooks experiencing issues

**Action:**
```sql
-- Revert specific wave
UPDATE rule_webhooks
SET publish_mode = 'queue',
    nats_enabled = false
WHERE webhook_id IN (SELECT webhook_id FROM migration_plan WHERE migration_wave = X);

-- Or revert all
UPDATE rule_webhooks
SET publish_mode = 'queue',
    nats_enabled = false
WHERE publish_mode IN ('both', 'nats');
```

### Scenario 3: Post-Migration Issue

**Symptoms:** Issues discovered after full migration

**Action:**
```sql
-- Emergency rollback to queue
UPDATE rule_webhooks
SET publish_mode = 'queue'
WHERE publish_mode = 'nats';

-- Restart queue workers immediately
```

**Hybrid mode provides safety:** Even in worst case, you can roll back without data loss because messages were going to queue as well.

## Validation

### Success Criteria

Migration is successful when:

- [ ] All webhooks publishing to NATS
- [ ] Success rate maintained (within 1%)
- [ ] Latency improved (>2x faster)
- [ ] Workers stable for 1 week+
- [ ] No increase in error rate
- [ ] Team comfortable with NATS operations
- [ ] Monitoring and alerts working
- [ ] Runbooks updated

### Performance Validation

```sql
-- Compare before/after metrics
SELECT
    'Before NATS' as period,
    COUNT(*) as total_messages,
    ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) * 1000), 2) as avg_latency_ms
FROM rule_webhook_queue
WHERE created_at BETWEEN '2024-01-01' AND '2024-01-07'  -- Pre-migration week
UNION ALL
SELECT
    'After NATS' as period,
    COUNT(*) as total_messages,
    ROUND(AVG(latency_ms), 2) as avg_latency_ms
FROM rule_nats_publish_history
WHERE published_at BETWEEN '2024-02-01' AND '2024-02-07';  -- Post-migration week
```

## Best Practices

### DO

✅ Test in staging first
✅ Use hybrid mode during migration
✅ Monitor continuously
✅ Migrate gradually (waves)
✅ Keep hybrid mode for critical webhooks longer
✅ Document everything
✅ Train team before migration
✅ Have rollback plan ready
✅ Validate each wave before proceeding

### DON'T

❌ Migrate all webhooks at once
❌ Skip pilot phase
❌ Ignore monitoring data
❌ Rush critical webhooks
❌ Disable queue workers too early
❌ Skip validation steps
❌ Migrate during peak traffic
❌ Skip backups

## Support

If you encounter issues:

1. Check [Troubleshooting](NATS_INTEGRATION.md#troubleshooting)
2. Review worker logs
3. Check NATS server logs: `nats server ls`
4. Review monitoring dashboards
5. Create GitHub issue with details

## Conclusion

Following this guide ensures:
- ✅ Zero downtime migration
- ✅ Zero data loss
- ✅ Easy rollback if needed
- ✅ Gradual, controlled process
- ✅ Team confidence in NATS

**Estimated total time:** 2-3 weeks for safe, validated migration

Good luck! 🚀
