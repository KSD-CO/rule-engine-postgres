-- =============================================================================
-- NATS Integration Example 4: Hybrid Mode (Queue + NATS)
-- =============================================================================
-- This example demonstrates using both PostgreSQL queue and NATS simultaneously
-- for maximum reliability and flexibility
--
-- Use Case: Critical webhooks that need both:
-- - Immediate delivery via NATS (fast)
-- - Database backup via PostgreSQL queue (reliable fallback)

-- =============================================================================
-- Step 1: Initialize NATS
-- =============================================================================

SELECT rule_nats_init('default');

-- =============================================================================
-- Step 2: Create Hybrid Webhook
-- =============================================================================

INSERT INTO rule_webhooks (
    webhook_name,
    webhook_url,
    http_method,
    publish_mode,      -- KEY: Set to 'both' for hybrid
    nats_enabled,
    nats_subject,
    nats_config_id,
    max_retries,       -- For PostgreSQL queue
    retry_delay_ms,
    timeout_ms,
    enabled
) VALUES (
    'critical_payment_notification',
    'https://api.payment-gateway.com/webhooks/transaction',
    'POST',
    'both',  -- Hybrid mode: NATS + Queue
    true,
    'webhooks.payments.critical',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    5,       -- Queue will retry 5 times if needed
    2000,    -- 2 second delay between retries
    30000,   -- 30 second timeout
    true
) RETURNING webhook_id, webhook_name, publish_mode;

-- Save webhook_id
\gset payment_webhook_

-- =============================================================================
-- Step 3: Publish to Hybrid Webhook
-- =============================================================================

-- Single API call publishes to BOTH queue and NATS
SELECT rule_webhook_call_unified(
    :payment_webhook_webhook_id,
    jsonb_build_object(
        'transaction_id', 'TXN-12345',
        'amount', 299.99,
        'currency', 'USD',
        'customer_id', 'CUST-67890',
        'timestamp', NOW()
    )
);

-- Expected output:
-- {
--   "queue": {
--     "success": true,
--     "queue_id": 42,
--     "status": "pending"
--   },
--   "nats": {
--     "success": true,
--     "subject": "webhooks.payments.critical",
--     "stream": "WEBHOOKS",
--     "sequence": 123,
--     "duplicate": false,
--     "latency_ms": 2.34
--   }
-- }

-- =============================================================================
-- Step 4: Verify Dual Publishing
-- =============================================================================

-- Check NATS publish history
SELECT
    publish_id,
    subject,
    sequence_number,
    success,
    latency_ms,
    published_at
FROM rule_nats_publish_history
WHERE webhook_id = :payment_webhook_webhook_id
ORDER BY published_at DESC
LIMIT 5;

-- Check PostgreSQL queue
SELECT
    queue_id,
    status,
    retry_count,
    created_at,
    next_retry_at
FROM rule_webhook_queue
WHERE webhook_id = :payment_webhook_webhook_id
ORDER BY created_at DESC
LIMIT 5;

-- =============================================================================
-- Step 5: Hybrid Mode Benefits
-- =============================================================================

-- Benefit 1: Fast primary delivery via NATS
-- - NATS delivers within milliseconds
-- - Scales horizontally with workers
-- - No database overhead

-- Benefit 2: Reliable fallback via Queue
-- - If NATS workers are down, queue workers still process
-- - Database ensures message durability
-- - Built-in retry mechanism

-- Benefit 3: Audit trail in both systems
-- - NATS history for performance metrics
-- - Queue history for detailed retry information

-- =============================================================================
-- Step 6: Monitoring Hybrid Webhooks
-- =============================================================================

-- View comprehensive statistics
SELECT
    w.webhook_name,
    w.publish_mode,

    -- NATS stats
    (SELECT COUNT(*) FROM rule_nats_publish_history
     WHERE webhook_id = w.webhook_id AND success = true) as nats_successful,
    (SELECT COUNT(*) FROM rule_nats_publish_history
     WHERE webhook_id = w.webhook_id AND success = false) as nats_failed,
    (SELECT ROUND(AVG(latency_ms), 2) FROM rule_nats_publish_history
     WHERE webhook_id = w.webhook_id) as nats_avg_latency_ms,

    -- Queue stats
    (SELECT COUNT(*) FROM rule_webhook_queue
     WHERE webhook_id = w.webhook_id AND status = 'success') as queue_successful,
    (SELECT COUNT(*) FROM rule_webhook_queue
     WHERE webhook_id = w.webhook_id AND status = 'failed') as queue_failed,
    (SELECT COUNT(*) FROM rule_webhook_queue
     WHERE webhook_id = w.webhook_id AND status = 'pending') as queue_pending,

    w.enabled
FROM rule_webhooks w
WHERE w.publish_mode = 'both'
  AND w.webhook_id = :payment_webhook_webhook_id;

-- =============================================================================
-- Step 7: Advanced - Conditional Hybrid Mode
-- =============================================================================

-- Use hybrid mode for critical events, NATS-only for non-critical
CREATE OR REPLACE FUNCTION smart_webhook_publish(
    p_webhook_id INTEGER,
    p_payload jsonb,
    p_is_critical BOOLEAN DEFAULT false
)
RETURNS jsonb AS $$
DECLARE
    v_result jsonb;
    v_original_mode TEXT;
BEGIN
    -- Get current publish mode
    SELECT publish_mode INTO v_original_mode
    FROM rule_webhooks
    WHERE webhook_id = p_webhook_id;

    -- Temporarily switch to 'both' for critical events
    IF p_is_critical AND v_original_mode != 'both' THEN
        UPDATE rule_webhooks
        SET publish_mode = 'both'
        WHERE webhook_id = p_webhook_id;
    END IF;

    -- Publish
    SELECT rule_webhook_call_unified(p_webhook_id, p_payload)
    INTO v_result;

    -- Restore original mode
    IF p_is_critical AND v_original_mode != 'both' THEN
        UPDATE rule_webhooks
        SET publish_mode = v_original_mode
        WHERE webhook_id = p_webhook_id;
    END IF;

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Test: Critical transaction (uses hybrid)
SELECT smart_webhook_publish(
    :payment_webhook_webhook_id,
    '{"transaction_id": "TXN-CRITICAL-001", "amount": 10000}'::jsonb,
    true  -- Critical
);

-- Test: Non-critical transaction (uses NATS only)
SELECT smart_webhook_publish(
    :payment_webhook_webhook_id,
    '{"transaction_id": "TXN-NORMAL-002", "amount": 50}'::jsonb,
    false  -- Non-critical
);

-- =============================================================================
-- Step 8: Failover Scenarios
-- =============================================================================

-- Scenario 1: NATS workers down, Queue workers active
-- Result: Messages still delivered via queue, but slower

-- Scenario 2: Database queue workers down, NATS active
-- Result: Messages delivered quickly via NATS
-- Queue messages accumulate and will be processed when workers return

-- Scenario 3: Both systems down
-- Result: Messages persist in both NATS JetStream and PostgreSQL
-- Will be delivered when any worker comes back online

-- Test failover awareness
CREATE OR REPLACE VIEW webhook_system_health AS
SELECT
    'NATS' as system,
    config_name,
    (SELECT COUNT(*) > 0 FROM rule_nats_consumer_stats
     WHERE active = true AND last_active_at >= NOW() - INTERVAL '1 minute') as workers_active,
    (SELECT health_percentage FROM (
        SELECT jsonb_extract_path_text(
            rule_nats_health_check(config_name)::jsonb,
            'pool_stats',
            'health_percentage'
        )::NUMERIC as health_percentage
    ) sub) as health_percentage
FROM rule_nats_config
WHERE enabled = true

UNION ALL

SELECT
    'Queue' as system,
    'default' as config_name,
    (SELECT COUNT(*) > 0 FROM rule_webhook_queue
     WHERE status = 'processing'
     AND created_at >= NOW() - INTERVAL '1 minute') as workers_active,
    100.0 as health_percentage  -- Queue is always available if DB is up
;

SELECT * FROM webhook_system_health;

-- =============================================================================
-- Step 9: Cost-Benefit Analysis
-- =============================================================================

-- Calculate resource usage for hybrid mode
CREATE OR REPLACE VIEW hybrid_mode_costs AS
SELECT
    w.webhook_name,

    -- Message counts
    (SELECT COUNT(*) FROM rule_nats_publish_history
     WHERE webhook_id = w.webhook_id) as nats_messages,
    (SELECT COUNT(*) FROM rule_webhook_queue
     WHERE webhook_id = w.webhook_id) as queue_messages,

    -- Storage costs (approximate)
    (SELECT pg_size_pretty(SUM(pg_column_size(payload)))
     FROM rule_nats_publish_history
     WHERE webhook_id = w.webhook_id) as nats_storage,
    (SELECT pg_size_pretty(SUM(pg_column_size(payload)))
     FROM rule_webhook_queue
     WHERE webhook_id = w.webhook_id) as queue_storage,

    -- Performance benefits
    (SELECT ROUND(AVG(latency_ms), 2) FROM rule_nats_publish_history
     WHERE webhook_id = w.webhook_id AND success = true) as nats_avg_latency,
    (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (completed_at - created_at)) * 1000), 2)
     FROM rule_webhook_queue
     WHERE webhook_id = w.webhook_id AND status = 'success') as queue_avg_latency

FROM rule_webhooks w
WHERE publish_mode = 'both';

SELECT * FROM hybrid_mode_costs;

-- =============================================================================
-- Step 10: Migration Strategy
-- =============================================================================

-- Gradually migrate from queue-only to hybrid mode

-- Step 1: Identify critical webhooks
SELECT
    webhook_id,
    webhook_name,
    (SELECT COUNT(*) FROM rule_webhook_queue WHERE webhook_id = w.webhook_id) as total_calls,
    publish_mode
FROM rule_webhooks w
WHERE publish_mode = 'queue'
  AND (SELECT COUNT(*) FROM rule_webhook_queue WHERE webhook_id = w.webhook_id) > 1000
ORDER BY total_calls DESC;

-- Step 2: Enable NATS for top webhooks
UPDATE rule_webhooks
SET publish_mode = 'both',
    nats_enabled = true,
    nats_subject = 'webhooks.' || LOWER(REPLACE(webhook_name, ' ', '.')),
    nats_config_id = (SELECT config_id FROM rule_nats_config WHERE config_name = 'default')
WHERE webhook_name IN (
    SELECT webhook_name
    FROM rule_webhooks w
    WHERE publish_mode = 'queue'
    ORDER BY (SELECT COUNT(*) FROM rule_webhook_queue WHERE webhook_id = w.webhook_id) DESC
    LIMIT 10
);

-- Step 3: Monitor for 24 hours

-- Step 4: If stable, switch to NATS-only
-- UPDATE rule_webhooks
-- SET publish_mode = 'nats'
-- WHERE publish_mode = 'both'
--   AND webhook_name IN (...);

-- =============================================================================
-- Cleanup
-- =============================================================================

-- DROP FUNCTION IF EXISTS smart_webhook_publish(INTEGER, jsonb, BOOLEAN);
-- DROP VIEW IF EXISTS webhook_system_health;
-- DROP VIEW IF EXISTS hybrid_mode_costs;

-- =============================================================================
-- Notes:
-- =============================================================================
--
-- 1. When to Use Hybrid Mode:
--    - Financial transactions (payments, refunds)
--    - Legal/compliance notifications
--    - Critical system alerts
--    - High-value customer events
--
-- 2. When to Use NATS-Only:
--    - High-volume analytics events
--    - Real-time notifications (non-critical)
--    - Logging/telemetry
--    - Social media updates
--
-- 3. When to Use Queue-Only:
--    - Legacy integrations (during migration)
--    - Low-volume webhooks (<100/day)
--    - Testing/development
--
-- 4. Trade-offs:
--    - Hybrid uses 2x storage (both systems)
--    - Hybrid provides maximum reliability
--    - Hybrid requires monitoring both systems
--    - Worth it for critical workloads
--
-- 5. Best Practices:
--    - Start with hybrid for critical webhooks
--    - Monitor both systems
--    - Gradually migrate to NATS-only if confidence is high
--    - Keep queue as fallback for mission-critical
--
-- =============================================================================
