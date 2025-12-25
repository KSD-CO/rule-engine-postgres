-- =============================================================================
-- NATS Integration Example 1: Basic Setup
-- =============================================================================
-- This example demonstrates basic NATS configuration and webhook publishing
--
-- Prerequisites:
-- - NATS server running at nats://localhost:4222
-- - Rule Engine extension installed
-- - Migration 007 applied

-- =============================================================================
-- Step 1: Configure NATS Connection
-- =============================================================================

-- Initialize NATS connection with default settings
SELECT rule_nats_init('default');

-- Expected output:
-- {
--   "success": true,
--   "config": "default",
--   "message": "NATS connection initialized for config 'default'",
--   "nats_url": "nats://localhost:4222",
--   "jetstream_enabled": true,
--   "stream_name": "WEBHOOKS"
-- }

-- =============================================================================
-- Step 2: Create a NATS-Enabled Webhook
-- =============================================================================

-- Insert webhook with NATS publishing
INSERT INTO rule_webhooks (
    webhook_name,
    webhook_url,
    http_method,
    publish_mode,
    nats_enabled,
    nats_subject,
    nats_config_id,
    headers,
    enabled
) VALUES (
    'slack_notifications',
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    'POST',
    'nats',  -- Use NATS only
    true,
    'webhooks.slack',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    '{"Content-Type": "application/json"}'::jsonb,
    true
) RETURNING webhook_id, webhook_name, nats_subject;

-- Save webhook_id for later use
\gset webhook_

-- =============================================================================
-- Step 3: Publish a Message to NATS
-- =============================================================================

-- Method 1: Direct NATS publish
SELECT rule_webhook_publish_nats(
    :webhook_webhook_id,
    '{"text": "Hello from PostgreSQL Rule Engine!", "channel": "#general"}'::jsonb,
    'msg-001'  -- Optional message ID for deduplication
);

-- Expected output:
-- {
--   "success": true,
--   "webhook_name": "slack_notifications",
--   "subject": "webhooks.slack",
--   "stream": "WEBHOOKS",
--   "sequence": 1,
--   "duplicate": false,
--   "latency_ms": 2.45
-- }

-- Method 2: Unified webhook call (respects publish_mode)
SELECT rule_webhook_call_unified(
    :webhook_webhook_id,
    '{"text": "Message via unified API", "channel": "#general"}'::jsonb
);

-- =============================================================================
-- Step 4: Verify Message Publishing
-- =============================================================================

-- Check publish history
SELECT
    publish_id,
    subject,
    payload,
    published_at,
    sequence_number,
    success,
    latency_ms
FROM rule_nats_publish_history
WHERE webhook_id = :webhook_webhook_id
ORDER BY published_at DESC
LIMIT 5;

-- Check summary statistics
SELECT * FROM nats_publish_summary
WHERE webhook_id = :webhook_webhook_id;

-- =============================================================================
-- Step 5: Health Check
-- =============================================================================

-- Verify NATS connection is healthy
SELECT rule_nats_health_check('default');

-- Expected output:
-- {
--   "success": true,
--   "config": "default",
--   "connected": true,
--   "pool_stats": {
--     "total_connections": 10,
--     "healthy_connections": 10,
--     "health_percentage": 100.0,
--     "requests_served": 2
--   },
--   "jetstream_enabled": true
-- }

-- =============================================================================
-- Step 6: Monitor with Views
-- =============================================================================

-- View all NATS-enabled webhooks
SELECT
    webhook_id,
    webhook_name,
    nats_subject,
    publish_mode,
    enabled
FROM rule_webhooks
WHERE nats_enabled = true;

-- View recent performance
SELECT * FROM nats_performance_stats;

-- View recent failures (if any)
SELECT * FROM nats_recent_failures LIMIT 10;

-- =============================================================================
-- Notes:
-- =============================================================================
--
-- 1. Message Flow:
--    PostgreSQL → NATS JetStream → Worker → Webhook URL
--
-- 2. Message Durability:
--    - Messages are persisted in JetStream stream
--    - Survive NATS server restarts
--    - Configurable retention (default: 7 days)
--
-- 3. Deduplication:
--    - Provide message_id to prevent duplicates
--    - Duplicate window: 120 seconds (configurable)
--
-- 4. Next Steps:
--    - Start a worker to consume messages (see workers/nodejs or workers/go)
--    - Monitor statistics in rule_nats_consumer_stats
--    - Configure additional webhooks
--
-- =============================================================================
