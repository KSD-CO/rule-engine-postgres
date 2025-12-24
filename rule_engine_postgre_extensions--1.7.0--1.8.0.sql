-- Migration from v1.7.0 to v1.8.0
-- Adds NATS JetStream integration for high-performance message streaming

-- This upgrade adds NATS integration with 100K+ msg/sec throughput
-- Includes: Connection pooling, JetStream persistence, webhook integration

-- Migration: NATS Integration (RFC-0007)
-- Version: 1.6.0
-- Description: Add NATS message queue integration for webhooks
--
-- This migration adds:
-- 1. NATS server configuration
-- 2. JetStream stream definitions
-- 3. NATS publish history tracking
-- 4. Consumer statistics
-- 5. Extended webhook table with NATS support
-- 6. Monitoring views

-- =============================================================================
-- 1. NATS Configuration
-- =============================================================================

-- NATS server configuration
CREATE TABLE IF NOT EXISTS rule_nats_config (
    config_id SERIAL PRIMARY KEY,
    config_name TEXT NOT NULL UNIQUE DEFAULT 'default',

    -- Connection
    nats_url TEXT NOT NULL DEFAULT 'nats://localhost:4222',
    nats_cluster_urls TEXT[], -- Optional cluster URLs for failover

    -- Authentication
    auth_type TEXT DEFAULT 'none', -- 'none', 'token', 'credentials', 'nkey'
    auth_token TEXT,
    auth_credentials_file TEXT, -- Path to .creds file
    auth_nkey_seed TEXT,

    -- TLS
    tls_enabled BOOLEAN DEFAULT false,
    tls_cert_file TEXT,
    tls_key_file TEXT,
    tls_ca_file TEXT,

    -- Connection Pool
    max_connections INTEGER DEFAULT 10,
    connection_timeout_ms INTEGER DEFAULT 5000,
    reconnect_delay_ms INTEGER DEFAULT 2000,
    max_reconnect_attempts INTEGER DEFAULT -1, -- -1 = infinite

    -- JetStream
    jetstream_enabled BOOLEAN DEFAULT true,
    stream_name TEXT DEFAULT 'WEBHOOKS',
    subject_prefix TEXT DEFAULT 'webhooks',

    -- Status
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT valid_auth_type CHECK (auth_type IN ('none', 'token', 'credentials', 'nkey'))
);

COMMENT ON TABLE rule_nats_config IS 'NATS server connection configuration';
COMMENT ON COLUMN rule_nats_config.config_name IS 'Unique configuration name (default: "default")';
COMMENT ON COLUMN rule_nats_config.nats_url IS 'Primary NATS server URL (e.g., nats://localhost:4222)';
COMMENT ON COLUMN rule_nats_config.auth_type IS 'Authentication method: none, token, credentials, or nkey';
COMMENT ON COLUMN rule_nats_config.jetstream_enabled IS 'Enable JetStream for persistent messaging';

-- Insert default configuration
INSERT INTO rule_nats_config (config_name, nats_url)
VALUES ('default', 'nats://localhost:4222')
ON CONFLICT (config_name) DO NOTHING;

-- =============================================================================
-- 2. JetStream Stream Configuration
-- =============================================================================

-- JetStream stream definitions
CREATE TABLE IF NOT EXISTS rule_nats_streams (
    stream_id SERIAL PRIMARY KEY,
    config_id INTEGER NOT NULL REFERENCES rule_nats_config(config_id) ON DELETE CASCADE,

    -- Stream Definition
    stream_name TEXT NOT NULL,
    subjects TEXT[] NOT NULL, -- e.g., ['webhooks.*', 'events.*']
    description TEXT,

    -- Storage
    storage_type TEXT DEFAULT 'file', -- 'memory', 'file'
    max_messages BIGINT DEFAULT 1000000,
    max_bytes BIGINT DEFAULT 1073741824, -- 1GB
    max_age_seconds BIGINT DEFAULT 604800, -- 7 days

    -- Retention Policy
    retention_policy TEXT DEFAULT 'limits', -- 'limits', 'interest', 'workqueue'
    discard_policy TEXT DEFAULT 'old', -- 'old', 'new'

    -- Replication (cluster)
    replicas INTEGER DEFAULT 1,

    -- Deduplication
    duplicate_window_seconds INTEGER DEFAULT 120,

    -- Status
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(config_id, stream_name),
    CONSTRAINT valid_storage CHECK (storage_type IN ('memory', 'file')),
    CONSTRAINT valid_retention CHECK (retention_policy IN ('limits', 'interest', 'workqueue')),
    CONSTRAINT valid_discard CHECK (discard_policy IN ('old', 'new'))
);

COMMENT ON TABLE rule_nats_streams IS 'JetStream stream configurations';
COMMENT ON COLUMN rule_nats_streams.subjects IS 'Array of subjects this stream listens to (supports wildcards)';
COMMENT ON COLUMN rule_nats_streams.storage_type IS 'Storage backend: memory (fast) or file (persistent)';
COMMENT ON COLUMN rule_nats_streams.retention_policy IS 'Message retention: limits, interest, or workqueue';

CREATE INDEX idx_nats_streams_config ON rule_nats_streams(config_id);
CREATE INDEX idx_nats_streams_enabled ON rule_nats_streams(enabled) WHERE enabled = true;

-- =============================================================================
-- 3. Extend Webhooks Table
-- =============================================================================

-- Add NATS support columns to existing rule_webhooks table
DO $$
BEGIN
    -- Check if columns don't exist before adding
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'rule_webhooks' AND column_name = 'nats_enabled') THEN

        ALTER TABLE rule_webhooks
        ADD COLUMN nats_enabled BOOLEAN DEFAULT false,
        ADD COLUMN nats_subject TEXT,
        ADD COLUMN nats_config_id INTEGER REFERENCES rule_nats_config(config_id),
        ADD COLUMN publish_mode TEXT DEFAULT 'queue';

        -- Add constraint
        ALTER TABLE rule_webhooks
        ADD CONSTRAINT valid_publish_mode
        CHECK (publish_mode IN ('queue', 'nats', 'both'));

    END IF;
END $$;

COMMENT ON COLUMN rule_webhooks.nats_enabled IS 'Enable NATS publishing for this webhook';
COMMENT ON COLUMN rule_webhooks.nats_subject IS 'NATS subject to publish to (e.g., webhooks.slack)';
COMMENT ON COLUMN rule_webhooks.publish_mode IS 'Publishing mode: queue (PG only), nats (NATS only), both (hybrid)';

CREATE INDEX IF NOT EXISTS idx_webhooks_nats_enabled ON rule_webhooks(nats_enabled) WHERE nats_enabled = true;

-- =============================================================================
-- 4. NATS Publishing History
-- =============================================================================

-- Track all NATS publish operations
CREATE TABLE IF NOT EXISTS rule_nats_publish_history (
    publish_id BIGSERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,

    -- NATS Message
    subject TEXT NOT NULL,
    payload JSONB NOT NULL,
    headers JSONB,

    -- Publishing
    published_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    message_id TEXT, -- NATS message ID for deduplication
    sequence_number BIGINT, -- JetStream sequence number

    -- Status
    success BOOLEAN NOT NULL,
    error_message TEXT,
    latency_ms NUMERIC(10,2),

    -- Context
    triggered_by TEXT,
    rule_execution_id BIGINT,

    -- Cleanup
    expires_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP + INTERVAL '7 days'
);

COMMENT ON TABLE rule_nats_publish_history IS 'Audit log of all NATS publish operations';
COMMENT ON COLUMN rule_nats_publish_history.sequence_number IS 'JetStream sequence number (if using JetStream)';
COMMENT ON COLUMN rule_nats_publish_history.latency_ms IS 'Time taken to publish message in milliseconds';

CREATE INDEX idx_nats_publish_webhook ON rule_nats_publish_history(webhook_id);
CREATE INDEX idx_nats_publish_time ON rule_nats_publish_history(published_at DESC);
CREATE INDEX idx_nats_publish_subject ON rule_nats_publish_history(subject);
CREATE INDEX idx_nats_publish_success ON rule_nats_publish_history(success);
CREATE INDEX idx_nats_publish_expires ON rule_nats_publish_history(expires_at);

-- =============================================================================
-- 5. Consumer Statistics
-- =============================================================================

-- Track NATS consumer statistics (external workers)
CREATE TABLE IF NOT EXISTS rule_nats_consumer_stats (
    consumer_id SERIAL PRIMARY KEY,
    stream_name TEXT NOT NULL,
    consumer_name TEXT NOT NULL,

    -- Consumer Info
    queue_group TEXT, -- For load balancing
    ack_policy TEXT, -- 'none', 'all', 'explicit'
    max_deliver INTEGER,

    -- Statistics (updated by workers or admin queries)
    messages_delivered BIGINT DEFAULT 0,
    messages_acknowledged BIGINT DEFAULT 0,
    messages_pending BIGINT DEFAULT 0,
    messages_redelivered BIGINT DEFAULT 0,

    -- Performance
    avg_processing_time_ms NUMERIC(10,2),
    last_active_at TIMESTAMPTZ,

    -- Status
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(stream_name, consumer_name)
);

COMMENT ON TABLE rule_nats_consumer_stats IS 'Statistics for NATS consumers (external workers)';
COMMENT ON COLUMN rule_nats_consumer_stats.queue_group IS 'Queue group name for load-balanced consumers';
COMMENT ON COLUMN rule_nats_consumer_stats.ack_policy IS 'Acknowledgment policy: none, all, or explicit';

CREATE INDEX idx_nats_consumer_stream ON rule_nats_consumer_stats(stream_name);
CREATE INDEX idx_nats_consumer_active ON rule_nats_consumer_stats(active) WHERE active = true;

-- =============================================================================
-- 6. Monitoring Views
-- =============================================================================

-- View: NATS Publish Summary
CREATE OR REPLACE VIEW nats_publish_summary AS
SELECT
    w.webhook_id,
    w.webhook_name,
    w.nats_subject as subject,
    w.publish_mode,
    COUNT(h.publish_id) as total_published,
    COUNT(*) FILTER (WHERE h.success = true) as successful,
    COUNT(*) FILTER (WHERE h.success = false) as failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE h.success = true) / NULLIF(COUNT(*), 0), 2) as success_rate_pct,
    ROUND(AVG(h.latency_ms), 2) as avg_latency_ms,
    MIN(h.latency_ms) as min_latency_ms,
    MAX(h.latency_ms) as max_latency_ms,
    MAX(h.published_at) as last_published_at
FROM rule_webhooks w
LEFT JOIN rule_nats_publish_history h ON w.webhook_id = h.webhook_id
WHERE w.nats_enabled = true
GROUP BY w.webhook_id, w.webhook_name, w.nats_subject, w.publish_mode;

COMMENT ON VIEW nats_publish_summary IS 'Summary statistics for NATS-enabled webhooks';

-- View: NATS Recent Failures
CREATE OR REPLACE VIEW nats_recent_failures AS
SELECT
    h.publish_id,
    w.webhook_name,
    h.subject,
    h.error_message,
    h.payload,
    h.published_at,
    h.latency_ms
FROM rule_nats_publish_history h
JOIN rule_webhooks w ON h.webhook_id = w.webhook_id
WHERE h.success = false
  AND h.published_at >= NOW() - INTERVAL '24 hours'
ORDER BY h.published_at DESC
LIMIT 100;

COMMENT ON VIEW nats_recent_failures IS 'Recent NATS publish failures for debugging (last 24 hours)';

-- View: NATS Performance Stats (with percentiles)
CREATE OR REPLACE VIEW nats_performance_stats AS
SELECT
    w.webhook_name,
    h.subject,
    COUNT(*) as message_count,
    ROUND(AVG(h.latency_ms), 2) as avg_latency_ms,
    MIN(h.latency_ms) as min_latency_ms,
    MAX(h.latency_ms) as max_latency_ms,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY h.latency_ms) as p50_latency_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY h.latency_ms) as p95_latency_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY h.latency_ms) as p99_latency_ms
FROM rule_nats_publish_history h
JOIN rule_webhooks w ON h.webhook_id = w.webhook_id
WHERE h.success = true
  AND h.published_at >= NOW() - INTERVAL '24 hours'
GROUP BY w.webhook_name, h.subject;

COMMENT ON VIEW nats_performance_stats IS 'NATS publishing performance metrics with percentiles (last 24 hours)';

-- =============================================================================
-- 7. Cleanup Functions
-- =============================================================================

-- Function: Cleanup old NATS publish history
CREATE OR REPLACE FUNCTION rule_nats_cleanup_old_history(
    p_older_than INTERVAL DEFAULT '30 days',
    p_keep_failed BOOLEAN DEFAULT true
) RETURNS BIGINT AS $$
DECLARE
    v_deleted BIGINT;
BEGIN
    DELETE FROM rule_nats_publish_history
    WHERE published_at < NOW() - p_older_than
      AND (NOT p_keep_failed OR success = true);

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_cleanup_old_history IS 'Delete old NATS publish history records';

-- =============================================================================
-- 8. Grants and Permissions
-- =============================================================================

-- Grant SELECT on views to PUBLIC
GRANT SELECT ON nats_publish_summary TO PUBLIC;
GRANT SELECT ON nats_recent_failures TO PUBLIC;
GRANT SELECT ON nats_performance_stats TO PUBLIC;

-- =============================================================================
-- Migration Complete
-- =============================================================================

-- Record migration
DO $$
BEGIN
    RAISE NOTICE 'NATS Integration migration completed successfully';
    RAISE NOTICE 'Tables created: rule_nats_config, rule_nats_streams, rule_nats_publish_history, rule_nats_consumer_stats';
    RAISE NOTICE 'Views created: nats_publish_summary, nats_recent_failures, nats_performance_stats';
    RAISE NOTICE 'Default NATS configuration inserted';
END $$;
-- NATS Integration SQL API Functions
-- Version: 1.6.0
-- Description: PL/pgSQL functions for NATS configuration and management
--
-- This file provides SQL-level API for NATS integration without requiring
-- the Rust extension to be loaded. These functions are used for configuration
-- and management only. Actual publishing requires the Rust extension.

-- =============================================================================
-- Configuration Management
-- =============================================================================

-- Function: Configure NATS connection
CREATE OR REPLACE FUNCTION rule_nats_configure(
    p_config_name TEXT DEFAULT 'default',
    p_nats_url TEXT DEFAULT 'nats://localhost:4222',
    p_auth_type TEXT DEFAULT 'none',
    p_jetstream_enabled BOOLEAN DEFAULT true,
    p_stream_name TEXT DEFAULT 'WEBHOOKS',
    p_subject_prefix TEXT DEFAULT 'webhooks'
) RETURNS BOOLEAN AS $$
BEGIN
    -- Validate inputs
    IF p_nats_url IS NULL OR p_nats_url = '' THEN
        RAISE EXCEPTION 'NATS URL cannot be empty';
    END IF;

    IF p_auth_type NOT IN ('none', 'token', 'credentials', 'nkey') THEN
        RAISE EXCEPTION 'Invalid auth_type: %. Must be: none, token, credentials, or nkey', p_auth_type;
    END IF;

    -- Insert or update configuration
    INSERT INTO rule_nats_config (
        config_name,
        nats_url,
        auth_type,
        jetstream_enabled,
        stream_name,
        subject_prefix,
        updated_at
    ) VALUES (
        p_config_name,
        p_nats_url,
        p_auth_type,
        p_jetstream_enabled,
        p_stream_name,
        p_subject_prefix,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (config_name)
    DO UPDATE SET
        nats_url = EXCLUDED.nats_url,
        auth_type = EXCLUDED.auth_type,
        jetstream_enabled = EXCLUDED.jetstream_enabled,
        stream_name = EXCLUDED.stream_name,
        subject_prefix = EXCLUDED.subject_prefix,
        updated_at = CURRENT_TIMESTAMP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_configure IS 'Configure NATS server connection settings';

-- Function: Create JetStream stream
CREATE OR REPLACE FUNCTION rule_nats_stream_create(
    p_stream_name TEXT,
    p_subjects TEXT[],
    p_config_name TEXT DEFAULT 'default',
    p_description TEXT DEFAULT NULL,
    p_retention_policy TEXT DEFAULT 'limits',
    p_max_age_seconds BIGINT DEFAULT 604800 -- 7 days
) RETURNS INTEGER AS $$
DECLARE
    v_config_id INTEGER;
    v_stream_id INTEGER;
BEGIN
    -- Validate inputs
    IF p_stream_name IS NULL OR p_stream_name = '' THEN
        RAISE EXCEPTION 'Stream name cannot be empty';
    END IF;

    IF p_subjects IS NULL OR array_length(p_subjects, 1) IS NULL THEN
        RAISE EXCEPTION 'Subjects array cannot be empty';
    END IF;

    IF p_retention_policy NOT IN ('limits', 'interest', 'workqueue') THEN
        RAISE EXCEPTION 'Invalid retention_policy: %. Must be: limits, interest, or workqueue', p_retention_policy;
    END IF;

    -- Get config ID
    SELECT config_id INTO v_config_id
    FROM rule_nats_config
    WHERE config_name = p_config_name;

    IF v_config_id IS NULL THEN
        RAISE EXCEPTION 'NATS config % not found', p_config_name;
    END IF;

    -- Create stream definition
    INSERT INTO rule_nats_streams (
        config_id,
        stream_name,
        subjects,
        description,
        retention_policy,
        max_age_seconds
    ) VALUES (
        v_config_id,
        p_stream_name,
        p_subjects,
        p_description,
        p_retention_policy,
        p_max_age_seconds
    )
    RETURNING stream_id INTO v_stream_id;

    RETURN v_stream_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_stream_create IS 'Create a JetStream stream definition';

-- =============================================================================
-- Webhook NATS Integration
-- =============================================================================

-- Function: Enable NATS for a webhook
CREATE OR REPLACE FUNCTION rule_webhook_enable_nats(
    p_webhook_id INTEGER,
    p_nats_subject TEXT DEFAULT NULL,
    p_publish_mode TEXT DEFAULT 'both',
    p_config_name TEXT DEFAULT 'default'
) RETURNS BOOLEAN AS $$
DECLARE
    v_config_id INTEGER;
    v_webhook_name TEXT;
    v_subject TEXT;
BEGIN
    -- Validate publish mode
    IF p_publish_mode NOT IN ('queue', 'nats', 'both') THEN
        RAISE EXCEPTION 'Invalid publish_mode: %. Must be: queue, nats, or both', p_publish_mode;
    END IF;

    -- Get config ID
    SELECT config_id INTO v_config_id
    FROM rule_nats_config
    WHERE config_name = p_config_name AND enabled = true;

    IF v_config_id IS NULL THEN
        RAISE EXCEPTION 'NATS config % not found or disabled', p_config_name;
    END IF;

    -- Get webhook name for default subject
    SELECT webhook_name INTO v_webhook_name
    FROM rule_webhooks
    WHERE webhook_id = p_webhook_id;

    IF v_webhook_name IS NULL THEN
        RAISE EXCEPTION 'Webhook % not found', p_webhook_id;
    END IF;

    -- Default subject: webhooks.<webhook_name>
    v_subject := COALESCE(p_nats_subject, 'webhooks.' || v_webhook_name);

    -- Enable NATS
    UPDATE rule_webhooks
    SET nats_enabled = true,
        nats_subject = v_subject,
        nats_config_id = v_config_id,
        publish_mode = p_publish_mode
    WHERE webhook_id = p_webhook_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_webhook_enable_nats IS 'Enable NATS publishing for a webhook';

-- Function: Disable NATS for a webhook
CREATE OR REPLACE FUNCTION rule_webhook_disable_nats(
    p_webhook_id INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE rule_webhooks
    SET nats_enabled = false,
        publish_mode = 'queue' -- Revert to queue-only mode
    WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Webhook % not found', p_webhook_id;
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_webhook_disable_nats IS 'Disable NATS publishing for a webhook';

-- =============================================================================
-- Statistics and Monitoring
-- =============================================================================

-- Function: Get NATS statistics for webhooks
CREATE OR REPLACE FUNCTION rule_nats_stats(
    p_webhook_id INTEGER DEFAULT NULL,
    p_hours INTEGER DEFAULT 24
) RETURNS JSON AS $$
DECLARE
    v_stats JSON;
BEGIN
    SELECT json_build_object(
        'total_published', COUNT(*),
        'successful', COUNT(*) FILTER (WHERE success = true),
        'failed', COUNT(*) FILTER (WHERE success = false),
        'success_rate_pct', ROUND(
            100.0 * COUNT(*) FILTER (WHERE success = true) / NULLIF(COUNT(*), 0),
            2
        ),
        'avg_latency_ms', ROUND(AVG(latency_ms), 2),
        'min_latency_ms', MIN(latency_ms),
        'max_latency_ms', MAX(latency_ms),
        'p50_latency_ms', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY latency_ms),
        'p95_latency_ms', PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms),
        'p99_latency_ms', PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms),
        'unique_subjects', COUNT(DISTINCT subject),
        'time_range_hours', p_hours,
        'period_start', MIN(published_at),
        'period_end', MAX(published_at)
    ) INTO v_stats
    FROM rule_nats_publish_history
    WHERE (p_webhook_id IS NULL OR webhook_id = p_webhook_id)
      AND published_at >= NOW() - (p_hours || ' hours')::INTERVAL;

    RETURN COALESCE(v_stats, '{}'::JSON);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_stats IS 'Get NATS publishing statistics for a webhook or all webhooks';

-- Function: Get NATS configuration info
CREATE OR REPLACE FUNCTION rule_nats_config_info(
    p_config_name TEXT DEFAULT 'default'
) RETURNS JSON AS $$
DECLARE
    v_config JSON;
BEGIN
    SELECT json_build_object(
        'config_id', config_id,
        'config_name', config_name,
        'nats_url', nats_url,
        'auth_type', auth_type,
        'jetstream_enabled', jetstream_enabled,
        'stream_name', stream_name,
        'subject_prefix', subject_prefix,
        'max_connections', max_connections,
        'connection_timeout_ms', connection_timeout_ms,
        'enabled', enabled,
        'created_at', created_at,
        'updated_at', updated_at
    ) INTO v_config
    FROM rule_nats_config
    WHERE config_name = p_config_name;

    IF v_config IS NULL THEN
        RAISE EXCEPTION 'NATS config % not found', p_config_name;
    END IF;

    RETURN v_config;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_config_info IS 'Get NATS configuration details';

-- Function: List all NATS-enabled webhooks
CREATE OR REPLACE FUNCTION rule_nats_webhooks_list()
RETURNS TABLE (
    webhook_id INTEGER,
    webhook_name TEXT,
    nats_subject TEXT,
    publish_mode TEXT,
    config_name TEXT,
    total_published BIGINT,
    success_rate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        w.webhook_id,
        w.webhook_name,
        w.nats_subject,
        w.publish_mode,
        c.config_name,
        COUNT(h.publish_id) as total_published,
        ROUND(100.0 * COUNT(*) FILTER (WHERE h.success = true) / NULLIF(COUNT(*), 0), 2) as success_rate
    FROM rule_webhooks w
    LEFT JOIN rule_nats_config c ON w.nats_config_id = c.config_id
    LEFT JOIN rule_nats_publish_history h ON w.webhook_id = h.webhook_id
    WHERE w.nats_enabled = true
    GROUP BY w.webhook_id, w.webhook_name, w.nats_subject, w.publish_mode, c.config_name
    ORDER BY w.webhook_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_webhooks_list IS 'List all NATS-enabled webhooks with statistics';

-- =============================================================================
-- Maintenance and Cleanup
-- =============================================================================

-- Function: Cleanup expired publish history
CREATE OR REPLACE FUNCTION rule_nats_cleanup_expired()
RETURNS BIGINT AS $$
DECLARE
    v_deleted BIGINT;
BEGIN
    DELETE FROM rule_nats_publish_history
    WHERE expires_at < CURRENT_TIMESTAMP;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RETURN v_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_cleanup_expired IS 'Delete expired NATS publish history records';

-- Function: Update consumer statistics
CREATE OR REPLACE FUNCTION rule_nats_consumer_update_stats(
    p_stream_name TEXT,
    p_consumer_name TEXT,
    p_messages_delivered BIGINT,
    p_messages_acknowledged BIGINT,
    p_messages_pending BIGINT,
    p_avg_processing_time_ms NUMERIC DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO rule_nats_consumer_stats (
        stream_name,
        consumer_name,
        messages_delivered,
        messages_acknowledged,
        messages_pending,
        avg_processing_time_ms,
        last_active_at,
        updated_at
    ) VALUES (
        p_stream_name,
        p_consumer_name,
        p_messages_delivered,
        p_messages_acknowledged,
        p_messages_pending,
        p_avg_processing_time_ms,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (stream_name, consumer_name)
    DO UPDATE SET
        messages_delivered = EXCLUDED.messages_delivered,
        messages_acknowledged = EXCLUDED.messages_acknowledged,
        messages_pending = EXCLUDED.messages_pending,
        avg_processing_time_ms = COALESCE(EXCLUDED.avg_processing_time_ms, rule_nats_consumer_stats.avg_processing_time_ms),
        last_active_at = EXCLUDED.last_active_at,
        updated_at = EXCLUDED.updated_at;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_consumer_update_stats IS 'Update consumer statistics (called by external workers)';

-- =============================================================================
-- Helper Functions
-- =============================================================================

-- Function: Test NATS configuration connectivity (placeholder)
CREATE OR REPLACE FUNCTION rule_nats_test_connection(
    p_config_name TEXT DEFAULT 'default'
) RETURNS JSON AS $$
DECLARE
    v_config RECORD;
BEGIN
    SELECT * INTO v_config
    FROM rule_nats_config
    WHERE config_name = p_config_name AND enabled = true;

    IF v_config IS NULL THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Configuration not found or disabled'
        );
    END IF;

    -- Note: Actual connection testing requires the Rust extension
    -- This is a placeholder that verifies configuration exists
    RETURN json_build_object(
        'success', true,
        'message', 'Configuration found. Use Rust function rule_nats_init() to test actual connection',
        'config', json_build_object(
            'name', v_config.config_name,
            'url', v_config.nats_url,
            'jetstream', v_config.jetstream_enabled
        )
    );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION rule_nats_test_connection IS 'Verify NATS configuration exists (actual test requires Rust extension)';

-- =============================================================================
-- Grants
-- =============================================================================

-- Grant EXECUTE on functions to PUBLIC (adjust as needed for your security requirements)
GRANT EXECUTE ON FUNCTION rule_nats_configure TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_stream_create TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_webhook_enable_nats TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_webhook_disable_nats TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_stats TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_config_info TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_webhooks_list TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_cleanup_expired TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_consumer_update_stats TO PUBLIC;
GRANT EXECUTE ON FUNCTION rule_nats_test_connection TO PUBLIC;
