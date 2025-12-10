-- Migration 005: Webhook Support (Phase 4.2)
-- Created: 2025-12-09
-- Description: HTTP callouts from rules, webhook management, retry logic

-- ============================================================================
-- WEBHOOK REGISTRY & CONFIGURATION
-- ============================================================================

-- Table: rule_webhooks
-- Stores webhook endpoint configurations
CREATE TABLE IF NOT EXISTS rule_webhooks (
    webhook_id SERIAL PRIMARY KEY,
    webhook_name TEXT NOT NULL UNIQUE,
    description TEXT,
    url TEXT NOT NULL,
    method TEXT DEFAULT 'POST' CHECK (method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')),
    headers JSONB DEFAULT '{}'::JSONB, -- {"Content-Type": "application/json", "Authorization": "Bearer ..."}
    timeout_ms INTEGER DEFAULT 5000 CHECK (timeout_ms > 0 AND timeout_ms <= 60000),
    retry_enabled BOOLEAN DEFAULT true,
    max_retries INTEGER DEFAULT 3 CHECK (max_retries >= 0 AND max_retries <= 10),
    retry_delay_ms INTEGER DEFAULT 1000 CHECK (retry_delay_ms >= 0),
    retry_backoff_multiplier NUMERIC DEFAULT 2.0 CHECK (retry_backoff_multiplier >= 1.0),
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}'
);

-- Table: rule_webhook_secrets
-- Stores encrypted secrets for webhooks (API keys, tokens)
CREATE TABLE IF NOT EXISTS rule_webhook_secrets (
    secret_id SERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,
    secret_name TEXT NOT NULL, -- e.g., 'api_key', 'signing_secret'
    secret_value TEXT NOT NULL, -- Should be encrypted in production
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    UNIQUE(webhook_id, secret_name)
);

-- Table: rule_webhook_calls
-- Queue and history of webhook calls
CREATE TABLE IF NOT EXISTS rule_webhook_calls (
    call_id SERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'success', 'failed', 'retrying')),
    payload JSONB NOT NULL,
    rule_name TEXT, -- Which rule triggered this
    rule_execution_id BIGINT, -- Link to rule execution if tracked
    scheduled_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMPTZ,
    response_status INTEGER, -- HTTP status code
    response_body TEXT,
    response_headers JSONB,
    error_message TEXT,
    execution_time_ms NUMERIC,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Table: rule_webhook_call_history
-- Detailed history of all attempts including retries
CREATE TABLE IF NOT EXISTS rule_webhook_call_history (
    history_id SERIAL PRIMARY KEY,
    call_id INTEGER REFERENCES rule_webhook_calls(call_id) ON DELETE CASCADE,
    attempt_number INTEGER NOT NULL,
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    response_status INTEGER,
    response_body TEXT,
    error_message TEXT,
    execution_time_ms NUMERIC
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_webhooks_enabled ON rule_webhooks(enabled) WHERE enabled = true;
CREATE INDEX IF NOT EXISTS idx_webhook_calls_status ON rule_webhook_calls(status, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_webhook_calls_webhook ON rule_webhook_calls(webhook_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_webhook_calls_retry ON rule_webhook_calls(next_retry_at) WHERE status = 'retrying';

-- ============================================================================
-- WEBHOOK MANAGEMENT FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_register
-- Registers a new webhook endpoint
CREATE OR REPLACE FUNCTION rule_webhook_register(
    p_name TEXT,
    p_url TEXT,
    p_method TEXT DEFAULT 'POST',
    p_headers JSONB DEFAULT '{}'::JSONB,
    p_description TEXT DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT 5000,
    p_max_retries INTEGER DEFAULT 3
) RETURNS INTEGER AS $$
DECLARE
    v_webhook_id INTEGER;
BEGIN
    -- Validate URL format
    IF p_url !~ '^https?://' THEN
        RAISE EXCEPTION 'Invalid URL format. Must start with http:// or https://';
    END IF;

    INSERT INTO rule_webhooks (
        webhook_name, url, method, headers, description,
        timeout_ms, max_retries
    ) VALUES (
        p_name, p_url, UPPER(p_method), p_headers, p_description,
        p_timeout_ms, p_max_retries
    ) RETURNING webhook_id INTO v_webhook_id;

    RETURN v_webhook_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_update
-- Updates webhook configuration
CREATE OR REPLACE FUNCTION rule_webhook_update(
    p_webhook_id INTEGER,
    p_url TEXT DEFAULT NULL,
    p_method TEXT DEFAULT NULL,
    p_headers JSONB DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT NULL,
    p_enabled BOOLEAN DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE rule_webhooks SET
        url = COALESCE(p_url, url),
        method = COALESCE(UPPER(p_method), method),
        headers = COALESCE(p_headers, headers),
        timeout_ms = COALESCE(p_timeout_ms, timeout_ms),
        enabled = COALESCE(p_enabled, enabled),
        updated_at = CURRENT_TIMESTAMP
    WHERE webhook_id = p_webhook_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_delete
-- Deletes a webhook (cascade deletes calls and secrets)
CREATE OR REPLACE FUNCTION rule_webhook_delete(p_webhook_id INTEGER)
RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM rule_webhooks WHERE webhook_id = p_webhook_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_list
-- Lists all webhooks
CREATE OR REPLACE FUNCTION rule_webhook_list(p_enabled_only BOOLEAN DEFAULT false)
RETURNS TABLE (
    webhook_id INTEGER,
    webhook_name TEXT,
    url TEXT,
    method TEXT,
    enabled BOOLEAN,
    total_calls BIGINT,
    success_rate NUMERIC,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        w.webhook_id,
        w.webhook_name,
        w.url,
        w.method,
        w.enabled,
        COUNT(c.call_id) as total_calls,
        ROUND(
            CASE
                WHEN COUNT(c.call_id) > 0 THEN
                    (COUNT(*) FILTER (WHERE c.status = 'success')::NUMERIC / COUNT(*) * 100)
                ELSE 0
            END, 2
        ) as success_rate,
        w.created_at
    FROM rule_webhooks w
    LEFT JOIN rule_webhook_calls c ON w.webhook_id = c.webhook_id
    WHERE (NOT p_enabled_only OR w.enabled = true)
    GROUP BY w.webhook_id
    ORDER BY w.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_get
-- Gets webhook configuration by ID or name
CREATE OR REPLACE FUNCTION rule_webhook_get(p_identifier TEXT)
RETURNS JSON AS $$
DECLARE
    v_webhook rule_webhooks%ROWTYPE;
BEGIN
    BEGIN
        SELECT * INTO v_webhook FROM rule_webhooks
        WHERE webhook_id = p_identifier::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        SELECT * INTO v_webhook FROM rule_webhooks
        WHERE webhook_name = p_identifier;
    END;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Webhook not found');
    END IF;

    RETURN row_to_json(v_webhook);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- WEBHOOK SECRET MANAGEMENT
-- ============================================================================

-- Function: rule_webhook_secret_set
-- Sets a secret for a webhook
CREATE OR REPLACE FUNCTION rule_webhook_secret_set(
    p_webhook_id INTEGER,
    p_secret_name TEXT,
    p_secret_value TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    -- In production, encrypt p_secret_value before storing
    -- For now, storing as-is (WARNING: not secure for production)
    INSERT INTO rule_webhook_secrets (webhook_id, secret_name, secret_value)
    VALUES (p_webhook_id, p_secret_name, p_secret_value)
    ON CONFLICT (webhook_id, secret_name) DO UPDATE
    SET secret_value = EXCLUDED.secret_value,
        created_at = CURRENT_TIMESTAMP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_secret_get
-- Gets a secret value (use carefully!)
CREATE OR REPLACE FUNCTION rule_webhook_secret_get(
    p_webhook_id INTEGER,
    p_secret_name TEXT
) RETURNS TEXT AS $$
DECLARE
    v_secret_value TEXT;
BEGIN
    SELECT secret_value INTO v_secret_value
    FROM rule_webhook_secrets
    WHERE webhook_id = p_webhook_id AND secret_name = p_secret_name;

    RETURN v_secret_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: rule_webhook_secret_delete
-- Removes a secret
CREATE OR REPLACE FUNCTION rule_webhook_secret_delete(
    p_webhook_id INTEGER,
    p_secret_name TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM rule_webhook_secrets
    WHERE webhook_id = p_webhook_id AND secret_name = p_secret_name;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- WEBHOOK EXECUTION FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_enqueue
-- Enqueues a webhook call for processing
CREATE OR REPLACE FUNCTION rule_webhook_enqueue(
    p_webhook_id INTEGER,
    p_payload JSONB,
    p_rule_name TEXT DEFAULT NULL,
    p_scheduled_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS INTEGER AS $$
DECLARE
    v_call_id INTEGER;
    v_webhook rule_webhooks%ROWTYPE;
BEGIN
    -- Check if webhook exists and is enabled
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Webhook not found: %', p_webhook_id;
    END IF;

    IF NOT v_webhook.enabled THEN
        RAISE EXCEPTION 'Webhook is disabled: %', v_webhook.webhook_name;
    END IF;

    -- Enqueue the call
    INSERT INTO rule_webhook_calls (
        webhook_id, payload, rule_name, scheduled_at, status
    ) VALUES (
        p_webhook_id, p_payload, p_rule_name, p_scheduled_at, 'pending'
    ) RETURNING call_id INTO v_call_id;

    RETURN v_call_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_call
-- Synchronous webhook call (requires http extension or external processor)
-- This is a placeholder that enqueues the call
-- In production, use with pgsql-http extension or external worker
CREATE OR REPLACE FUNCTION rule_webhook_call(
    p_webhook_id INTEGER,
    p_payload JSONB
) RETURNS JSON AS $$
DECLARE
    v_call_id INTEGER;
    v_webhook rule_webhooks%ROWTYPE;
    v_result JSON;
BEGIN
    -- Get webhook configuration
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Webhook not found'
        );
    END IF;

    IF NOT v_webhook.enabled THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Webhook is disabled'
        );
    END IF;

    -- Enqueue the call
    v_call_id := rule_webhook_enqueue(p_webhook_id, p_payload);

    -- Note: Actual HTTP call requires http extension or external worker
    -- This function returns the queued call info
    RETURN json_build_object(
        'success', true,
        'call_id', v_call_id,
        'status', 'enqueued',
        'webhook_name', v_webhook.webhook_name,
        'url', v_webhook.url,
        'message', 'Webhook call enqueued. Requires http extension or external worker to process.'
    );
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_call_with_http (if http extension is available)
-- This function uses pgsql-http extension if installed
CREATE OR REPLACE FUNCTION rule_webhook_call_with_http(
    p_webhook_id INTEGER,
    p_payload JSONB
) RETURNS JSON AS $$
DECLARE
    v_webhook rule_webhooks%ROWTYPE;
    v_call_id INTEGER;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_response RECORD;
    v_has_http BOOLEAN;
BEGIN
    -- Check if http extension is available
    SELECT EXISTS(
        SELECT 1 FROM pg_extension WHERE extname = 'http'
    ) INTO v_has_http;

    IF NOT v_has_http THEN
        RETURN json_build_object(
            'success', false,
            'error', 'HTTP extension not installed. Install with: CREATE EXTENSION http;'
        );
    END IF;

    -- Get webhook config
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = p_webhook_id;

    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Webhook not found');
    END IF;

    -- Create call record
    INSERT INTO rule_webhook_calls (webhook_id, payload, status, started_at)
    VALUES (p_webhook_id, p_payload, 'processing', CURRENT_TIMESTAMP)
    RETURNING call_id INTO v_call_id;

    v_start_time := clock_timestamp();

    BEGIN
        -- Make HTTP request using http extension
        -- Note: This requires http extension to be installed
        EXECUTE format(
            'SELECT status, content, headers FROM http((
                SELECT ROW(
                    %L,
                    %L,
                    %L,
                    %L,
                    %L
                )::http_request
            ))',
            v_webhook.method,
            v_webhook.url,
            v_webhook.headers,
            'application/json',
            p_payload::TEXT
        ) INTO v_response;

        v_end_time := clock_timestamp();

        -- Update call with success
        UPDATE rule_webhook_calls SET
            status = 'success',
            completed_at = v_end_time,
            response_status = v_response.status,
            response_body = v_response.content,
            response_headers = v_response.headers,
            execution_time_ms = EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        WHERE call_id = v_call_id;

        -- Log attempt
        INSERT INTO rule_webhook_call_history (
            call_id, attempt_number, started_at, completed_at,
            response_status, response_body, execution_time_ms
        ) VALUES (
            v_call_id, 1, v_start_time, v_end_time,
            v_response.status, v_response.content,
            EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        );

        RETURN json_build_object(
            'success', true,
            'call_id', v_call_id,
            'status', v_response.status,
            'response', v_response.content,
            'execution_time_ms', EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        );

    EXCEPTION WHEN OTHERS THEN
        v_end_time := clock_timestamp();

        -- Update call with error
        UPDATE rule_webhook_calls SET
            status = 'failed',
            completed_at = v_end_time,
            error_message = SQLERRM,
            execution_time_ms = EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        WHERE call_id = v_call_id;

        -- Log failed attempt
        INSERT INTO rule_webhook_call_history (
            call_id, attempt_number, started_at, completed_at,
            error_message, execution_time_ms
        ) VALUES (
            v_call_id, 1, v_start_time, v_end_time,
            SQLERRM, EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000
        );

        RETURN json_build_object(
            'success', false,
            'call_id', v_call_id,
            'error', SQLERRM
        );
    END;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- RETRY & RECOVERY FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_retry
-- Marks a failed call for retry
CREATE OR REPLACE FUNCTION rule_webhook_retry(p_call_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_call rule_webhook_calls%ROWTYPE;
    v_webhook rule_webhooks%ROWTYPE;
    v_next_delay_ms INTEGER;
BEGIN
    SELECT * INTO v_call FROM rule_webhook_calls WHERE call_id = p_call_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Call not found: %', p_call_id;
    END IF;

    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = v_call.webhook_id;

    -- Check if retry is enabled and not exceeded max retries
    IF NOT v_webhook.retry_enabled THEN
        RETURN false;
    END IF;

    IF v_call.retry_count >= v_webhook.max_retries THEN
        UPDATE rule_webhook_calls
        SET status = 'failed',
            error_message = 'Max retries exceeded'
        WHERE call_id = p_call_id;
        RETURN false;
    END IF;

    -- Calculate next retry delay with exponential backoff
    v_next_delay_ms := v_webhook.retry_delay_ms *
        (v_webhook.retry_backoff_multiplier ^ v_call.retry_count);

    -- Update call for retry
    UPDATE rule_webhook_calls SET
        status = 'retrying',
        retry_count = retry_count + 1,
        next_retry_at = CURRENT_TIMESTAMP + (v_next_delay_ms || ' milliseconds')::INTERVAL
    WHERE call_id = p_call_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_webhook_process_retries
-- Processes pending retries (called by scheduler/cron)
CREATE OR REPLACE FUNCTION rule_webhook_process_retries()
RETURNS TABLE (
    call_id INTEGER,
    webhook_name TEXT,
    retry_result JSON
) AS $$
DECLARE
    v_call RECORD;
BEGIN
    FOR v_call IN
        SELECT
            c.call_id,
            c.webhook_id,
            c.payload,
            w.webhook_name
        FROM rule_webhook_calls c
        JOIN rule_webhooks w ON c.webhook_id = w.webhook_id
        WHERE c.status = 'retrying'
          AND c.next_retry_at <= CURRENT_TIMESTAMP
        ORDER BY c.next_retry_at
        LIMIT 100
    LOOP
        -- Try to execute the webhook again
        -- In production, this would call the actual HTTP function
        RETURN QUERY SELECT
            v_call.call_id,
            v_call.webhook_name,
            json_build_object(
                'status', 'retry_enqueued',
                'message', 'Retry scheduled for processing'
            );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- MONITORING & ANALYTICS VIEWS
-- ============================================================================

-- View: webhook_status_summary
-- Summary of webhook call statuses
CREATE OR REPLACE VIEW webhook_status_summary AS
SELECT
    w.webhook_id,
    w.webhook_name,
    w.url,
    w.enabled,
    COUNT(c.call_id) as total_calls,
    COUNT(*) FILTER (WHERE c.status = 'success') as successful_calls,
    COUNT(*) FILTER (WHERE c.status = 'failed') as failed_calls,
    COUNT(*) FILTER (WHERE c.status = 'pending') as pending_calls,
    COUNT(*) FILTER (WHERE c.status = 'retrying') as retrying_calls,
    ROUND(AVG(c.execution_time_ms)::NUMERIC, 2) as avg_execution_time_ms,
    MAX(c.created_at) as last_call_at,
    ROUND(
        CASE
            WHEN COUNT(c.call_id) > 0 THEN
                (COUNT(*) FILTER (WHERE c.status = 'success')::NUMERIC / COUNT(*) * 100)
            ELSE 0
        END, 2
    ) as success_rate_pct
FROM rule_webhooks w
LEFT JOIN rule_webhook_calls c ON w.webhook_id = c.webhook_id
GROUP BY w.webhook_id, w.webhook_name, w.url, w.enabled;

-- View: webhook_recent_failures
-- Recent failed webhook calls for debugging
CREATE OR REPLACE VIEW webhook_recent_failures AS
SELECT
    c.call_id,
    w.webhook_name,
    w.url,
    c.status,
    c.retry_count,
    c.error_message,
    c.response_status,
    c.payload,
    c.created_at,
    c.completed_at
FROM rule_webhook_calls c
JOIN rule_webhooks w ON c.webhook_id = w.webhook_id
WHERE c.status IN ('failed', 'retrying')
ORDER BY c.created_at DESC
LIMIT 100;

-- View: webhook_performance_stats
-- Performance statistics per webhook
CREATE OR REPLACE VIEW webhook_performance_stats AS
SELECT
    w.webhook_id,
    w.webhook_name,
    COUNT(c.call_id) as total_calls,
    ROUND(AVG(c.execution_time_ms)::NUMERIC, 2) as avg_time_ms,
    ROUND(MIN(c.execution_time_ms)::NUMERIC, 2) as min_time_ms,
    ROUND(MAX(c.execution_time_ms)::NUMERIC, 2) as max_time_ms,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY c.execution_time_ms)::NUMERIC, 2) as p50_time_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY c.execution_time_ms)::NUMERIC, 2) as p95_time_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY c.execution_time_ms)::NUMERIC, 2) as p99_time_ms
FROM rule_webhooks w
LEFT JOIN rule_webhook_calls c ON w.webhook_id = c.webhook_id
WHERE c.status = 'success'
GROUP BY w.webhook_id, w.webhook_name
HAVING COUNT(c.call_id) > 0;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_call_status
-- Gets the status of a webhook call
CREATE OR REPLACE FUNCTION rule_webhook_call_status(p_call_id INTEGER)
RETURNS JSON AS $$
DECLARE
    v_call rule_webhook_calls%ROWTYPE;
    v_webhook rule_webhooks%ROWTYPE;
    v_attempts JSON;
BEGIN
    SELECT * INTO v_call FROM rule_webhook_calls WHERE call_id = p_call_id;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Call not found');
    END IF;

    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = v_call.webhook_id;

    -- Get all attempts
    SELECT json_agg(row_to_json(h)) INTO v_attempts
    FROM rule_webhook_call_history h
    WHERE h.call_id = p_call_id
    ORDER BY h.attempt_number;

    RETURN json_build_object(
        'call_id', v_call.call_id,
        'webhook_name', v_webhook.webhook_name,
        'url', v_webhook.url,
        'status', v_call.status,
        'retry_count', v_call.retry_count,
        'payload', v_call.payload,
        'response_status', v_call.response_status,
        'response_body', v_call.response_body,
        'error_message', v_call.error_message,
        'execution_time_ms', v_call.execution_time_ms,
        'scheduled_at', v_call.scheduled_at,
        'started_at', v_call.started_at,
        'completed_at', v_call.completed_at,
        'next_retry_at', v_call.next_retry_at,
        'attempts', COALESCE(v_attempts, '[]'::JSON)
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CLEANUP FUNCTIONS
-- ============================================================================

-- Function: rule_webhook_cleanup_old_calls
-- Removes old webhook call records
CREATE OR REPLACE FUNCTION rule_webhook_cleanup_old_calls(
    p_older_than INTERVAL DEFAULT '30 days',
    p_keep_failed BOOLEAN DEFAULT true
) RETURNS BIGINT AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    DELETE FROM rule_webhook_calls
    WHERE created_at < (CURRENT_TIMESTAMP - p_older_than)
      AND (NOT p_keep_failed OR status = 'success')
    ;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- SCHEMA MIGRATIONS TABLE UPDATE
-- ============================================================================

