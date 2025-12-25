-- =============================================================================
-- NATS Integration Example 3: Load Balancing with Queue Groups
-- =============================================================================
-- This example demonstrates horizontal scaling with multiple workers
-- using NATS queue groups for automatic load balancing
--
-- Use Case: High-throughput webhook processing with multiple workers

-- =============================================================================
-- Step 1: Initialize NATS
-- =============================================================================

SELECT rule_nats_init('default');

-- =============================================================================
-- Step 2: Create High-Volume Webhook
-- =============================================================================

INSERT INTO rule_webhooks (
    webhook_name,
    webhook_url,
    http_method,
    publish_mode,
    nats_enabled,
    nats_subject,
    nats_config_id,
    enabled
) VALUES (
    'order_processing',
    'https://api.example.com/orders/webhook',
    'POST',
    'nats',
    true,
    'webhooks.orders.created',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    true
) RETURNING webhook_id;

-- Save webhook_id
\gset order_webhook_

-- =============================================================================
-- Step 3: Register Multiple Workers
-- =============================================================================

-- Workers report their statistics to PostgreSQL
-- This helps track which workers are processing messages

-- Manually register workers (optional - workers auto-register on startup)
INSERT INTO rule_nats_consumer_stats (
    stream_name,
    consumer_name,
    queue_group,
    ack_policy,
    max_deliver,
    active
) VALUES
    ('WEBHOOKS', 'webhook-worker-1', 'webhook-workers', 'explicit', 3, true),
    ('WEBHOOKS', 'webhook-worker-2', 'webhook-workers', 'explicit', 3, true),
    ('WEBHOOKS', 'webhook-worker-3', 'webhook-workers', 'explicit', 3, true)
ON CONFLICT (stream_name, consumer_name) DO NOTHING;

-- =============================================================================
-- Step 4: Simulate High-Volume Publishing
-- =============================================================================

-- Function to generate test load
CREATE OR REPLACE FUNCTION generate_order_events(
    p_count INTEGER DEFAULT 100,
    p_batch_size INTEGER DEFAULT 10
)
RETURNS jsonb AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_webhook_id INTEGER;
    v_i INTEGER;
    v_payload jsonb;
    v_published INTEGER := 0;
    v_failed INTEGER := 0;
BEGIN
    v_start_time := clock_timestamp();

    -- Get webhook ID
    SELECT webhook_id INTO v_webhook_id
    FROM rule_webhooks
    WHERE webhook_name = 'order_processing';

    -- Publish messages
    FOR v_i IN 1..p_count LOOP
        BEGIN
            v_payload := jsonb_build_object(
                'order_id', v_i,
                'customer_id', (random() * 10000)::INTEGER,
                'amount', (random() * 1000)::NUMERIC(10,2),
                'items', (random() * 10 + 1)::INTEGER,
                'timestamp', clock_timestamp()
            );

            -- Publish to NATS
            PERFORM rule_webhook_publish_nats(
                v_webhook_id,
                v_payload,
                format('order-%s', v_i)
            );

            v_published := v_published + 1;

            -- Batch commit
            IF v_i % p_batch_size = 0 THEN
                COMMIT;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed + 1;
        END;
    END LOOP;

    v_end_time := clock_timestamp();

    RETURN jsonb_build_object(
        'published', v_published,
        'failed', v_failed,
        'duration_seconds', EXTRACT(EPOCH FROM (v_end_time - v_start_time)),
        'messages_per_second',
            v_published / GREATEST(EXTRACT(EPOCH FROM (v_end_time - v_start_time)), 0.001)
    );
END;
$$ LANGUAGE plpgsql;

-- Generate 1000 test events
SELECT generate_order_events(1000, 50);

-- Expected output:
-- {
--   "published": 1000,
--   "failed": 0,
--   "duration_seconds": 2.345,
--   "messages_per_second": 426.44
-- }

-- =============================================================================
-- Step 5: Monitor Worker Distribution
-- =============================================================================

-- Wait a few seconds for workers to process messages
SELECT pg_sleep(5);

-- View worker statistics
SELECT
    consumer_name,
    queue_group,
    messages_delivered,
    messages_acknowledged,
    messages_pending,
    messages_redelivered,
    avg_processing_time_ms,
    last_active_at,
    active
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND queue_group = 'webhook-workers'
ORDER BY consumer_name;

-- Expected output (example):
-- consumer_name     | messages_delivered | messages_acknowledged | avg_processing_time_ms
-- ------------------+-------------------+----------------------+----------------------
-- webhook-worker-1  | 334               | 334                  | 45.23
-- webhook-worker-2  | 333               | 333                  | 43.87
-- webhook-worker-3  | 333               | 333                  | 46.12

-- Calculate load distribution
SELECT
    consumer_name,
    messages_acknowledged,
    ROUND(100.0 * messages_acknowledged /
          SUM(messages_acknowledged) OVER (), 2) as percentage
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND queue_group = 'webhook-workers'
  AND active = true
ORDER BY messages_acknowledged DESC;

-- =============================================================================
-- Step 6: Dynamic Scaling - Add More Workers
-- =============================================================================

-- Start additional workers at runtime:
--
-- Terminal 1:
--   docker run -e CONSUMER_NAME=webhook-worker-4 \
--              -e QUEUE_GROUP=webhook-workers \
--              nats-webhook-worker:latest
--
-- Terminal 2:
--   docker run -e CONSUMER_NAME=webhook-worker-5 \
--              -e QUEUE_GROUP=webhook-workers \
--              nats-webhook-worker:latest

-- Generate more load with 5 workers
SELECT generate_order_events(5000, 100);

-- Check new distribution
SELECT
    consumer_name,
    messages_acknowledged,
    ROUND(100.0 * messages_acknowledged /
          SUM(messages_acknowledged) OVER (), 2) as percentage,
    avg_processing_time_ms,
    last_active_at
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND queue_group = 'webhook-workers'
  AND active = true
ORDER BY messages_acknowledged DESC;

-- =============================================================================
-- Step 7: Monitor Throughput Metrics
-- =============================================================================

-- Real-time throughput
CREATE OR REPLACE VIEW worker_throughput AS
SELECT
    consumer_name,
    messages_acknowledged,
    avg_processing_time_ms,
    -- Calculate theoretical max throughput
    CASE
        WHEN avg_processing_time_ms > 0 THEN
            ROUND(1000.0 / avg_processing_time_ms, 2)
        ELSE NULL
    END as max_msg_per_second,
    last_active_at,
    EXTRACT(EPOCH FROM (NOW() - last_active_at)) as seconds_since_active
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND active = true;

SELECT * FROM worker_throughput
ORDER BY max_msg_per_second DESC NULLS LAST;

-- Aggregate throughput
SELECT
    COUNT(*) as active_workers,
    SUM(messages_acknowledged) as total_processed,
    ROUND(AVG(avg_processing_time_ms), 2) as avg_processing_time,
    ROUND(SUM(1000.0 / NULLIF(avg_processing_time_ms, 0)), 2) as theoretical_max_throughput
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND queue_group = 'webhook-workers'
  AND active = true;

-- =============================================================================
-- Step 8: Handle Worker Failures
-- =============================================================================

-- Simulate worker failure (stop webhook-worker-2)
-- NATS will automatically redistribute its messages to other workers

-- Mark worker as inactive (simulated)
UPDATE rule_nats_consumer_stats
SET active = false,
    updated_at = NOW()
WHERE consumer_name = 'webhook-worker-2';

-- Generate more load
SELECT generate_order_events(1000, 50);

-- Check redistribution (worker-2 should get no new messages)
SELECT
    consumer_name,
    messages_acknowledged,
    active,
    last_active_at
FROM rule_nats_consumer_stats
WHERE stream_name = 'WEBHOOKS'
  AND queue_group = 'webhook-workers'
ORDER BY consumer_name;

-- =============================================================================
-- Step 9: Advanced Monitoring
-- =============================================================================

-- Create monitoring function
CREATE OR REPLACE FUNCTION monitor_worker_health()
RETURNS TABLE (
    consumer_name TEXT,
    status TEXT,
    messages_processed BIGINT,
    avg_latency_ms NUMERIC,
    health_score NUMERIC,
    recommendation TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.consumer_name,
        CASE
            WHEN NOT c.active THEN 'INACTIVE'
            WHEN c.last_active_at < NOW() - INTERVAL '1 minute' THEN 'STALE'
            WHEN c.avg_processing_time_ms > 1000 THEN 'SLOW'
            ELSE 'HEALTHY'
        END as status,
        c.messages_acknowledged as messages_processed,
        c.avg_processing_time_ms as avg_latency_ms,
        -- Health score (0-100)
        CASE
            WHEN NOT c.active THEN 0
            WHEN c.last_active_at < NOW() - INTERVAL '1 minute' THEN 25
            WHEN c.avg_processing_time_ms > 1000 THEN 50
            ELSE 100
        END as health_score,
        CASE
            WHEN NOT c.active THEN 'Restart worker'
            WHEN c.last_active_at < NOW() - INTERVAL '1 minute' THEN 'Check worker logs'
            WHEN c.avg_processing_time_ms > 1000 THEN 'Investigate slow performance'
            ELSE 'All good'
        END as recommendation
    FROM rule_nats_consumer_stats c
    WHERE c.stream_name = 'WEBHOOKS'
      AND c.queue_group = 'webhook-workers'
    ORDER BY health_score ASC;
END;
$$ LANGUAGE plpgsql;

-- Check worker health
SELECT * FROM monitor_worker_health();

-- =============================================================================
-- Step 10: Performance Comparison
-- =============================================================================

-- Compare NATS vs PostgreSQL queue performance
CREATE OR REPLACE FUNCTION compare_publish_modes()
RETURNS TABLE (
    mode TEXT,
    messages INTEGER,
    duration_seconds NUMERIC,
    messages_per_second NUMERIC
) AS $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_webhook_nats INTEGER;
    v_webhook_queue INTEGER;
    v_i INTEGER;
    v_payload jsonb;
BEGIN
    -- Create test webhooks if not exist
    INSERT INTO rule_webhooks (webhook_name, webhook_url, publish_mode, nats_enabled, nats_subject, enabled)
    VALUES ('test_nats', 'http://example.com', 'nats', true, 'test.nats', true)
    ON CONFLICT (webhook_name) DO UPDATE SET enabled = true
    RETURNING webhook_id INTO v_webhook_nats;

    INSERT INTO rule_webhooks (webhook_name, webhook_url, publish_mode, enabled)
    VALUES ('test_queue', 'http://example.com', 'queue', true)
    ON CONFLICT (webhook_name) DO UPDATE SET enabled = true
    RETURNING webhook_id INTO v_webhook_queue;

    v_payload := '{"test": true}'::jsonb;

    -- Test NATS
    v_start := clock_timestamp();
    FOR v_i IN 1..100 LOOP
        PERFORM rule_webhook_call_unified(v_webhook_nats, v_payload);
    END LOOP;
    v_end := clock_timestamp();

    mode := 'NATS';
    messages := 100;
    duration_seconds := EXTRACT(EPOCH FROM (v_end - v_start));
    messages_per_second := messages / GREATEST(duration_seconds, 0.001);
    RETURN NEXT;

    -- Test Queue
    v_start := clock_timestamp();
    FOR v_i IN 1..100 LOOP
        PERFORM rule_webhook_call_unified(v_webhook_queue, v_payload);
    END LOOP;
    v_end := clock_timestamp();

    mode := 'Queue';
    messages := 100;
    duration_seconds := EXTRACT(EPOCH FROM (v_end - v_start));
    messages_per_second := messages / GREATEST(duration_seconds, 0.001);
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- Run comparison
SELECT * FROM compare_publish_modes();

-- Expected output (example):
-- mode  | messages | duration_seconds | messages_per_second
-- ------+----------+------------------+--------------------
-- NATS  | 100      | 0.234            | 427.35
-- Queue | 100      | 1.567            | 63.81

-- =============================================================================
-- Cleanup
-- =============================================================================

-- DROP FUNCTION IF EXISTS generate_order_events(INTEGER, INTEGER);
-- DROP FUNCTION IF EXISTS monitor_worker_health();
-- DROP FUNCTION IF EXISTS compare_publish_modes();
-- DROP VIEW IF EXISTS worker_throughput;

-- =============================================================================
-- Notes:
-- =============================================================================
--
-- 1. Queue Groups:
--    - All workers in same queue group share message load
--    - NATS distributes messages evenly (round-robin)
--    - Each message delivered to exactly ONE worker in the group
--
-- 2. Scaling:
--    - Add workers: Start new instance with same QUEUE_GROUP
--    - Remove workers: Simply stop the process
--    - No configuration changes needed
--    - Automatic redistribution on failure
--
-- 3. Performance:
--    - 3 workers = 3x throughput (linear scaling)
--    - 10 workers = 10x throughput
--    - Limited only by NATS server and network
--
-- 4. Monitoring:
--    - Track per-worker statistics
--    - Calculate aggregate throughput
--    - Alert on stale/slow workers
--    - Monitor message distribution
--
-- 5. Best Practices:
--    - Use queue groups for all production workloads
--    - Monitor worker health regularly
--    - Set appropriate max_deliver for retries
--    - Scale workers based on load metrics
--
-- =============================================================================
