-- Migration 006: External Data Sources (Phase 4.3)
-- Created: 2025-12-12
-- Description: Fetch data from REST APIs in rules, connection pooling, caching strategies

-- ============================================================================
-- DATA SOURCE REGISTRY & CONFIGURATION
-- ============================================================================

-- Table: rule_datasources
-- Stores external data source configurations
CREATE TABLE IF NOT EXISTS rule_datasources (
    datasource_id SERIAL PRIMARY KEY,
    datasource_name TEXT NOT NULL UNIQUE,
    description TEXT,
    base_url TEXT NOT NULL,
    auth_type TEXT DEFAULT 'none' CHECK (auth_type IN ('none', 'basic', 'bearer', 'api_key', 'oauth2')),
    default_headers JSONB DEFAULT '{}'::JSONB, -- {"Content-Type": "application/json", "X-API-Version": "v2"}
    timeout_ms INTEGER DEFAULT 5000 CHECK (timeout_ms > 0 AND timeout_ms <= 60000),
    retry_enabled BOOLEAN DEFAULT true,
    max_retries INTEGER DEFAULT 3 CHECK (max_retries >= 0 AND max_retries <= 10),
    retry_delay_ms INTEGER DEFAULT 1000 CHECK (retry_delay_ms >= 0),
    cache_enabled BOOLEAN DEFAULT true,
    cache_ttl_seconds INTEGER DEFAULT 300 CHECK (cache_ttl_seconds >= 0), -- 5 minutes default
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}',
    CONSTRAINT valid_url CHECK (base_url ~* '^https?://')
);

-- Table: rule_datasource_auth
-- Stores authentication credentials for datasources
CREATE TABLE IF NOT EXISTS rule_datasource_auth (
    auth_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id) ON DELETE CASCADE,
    auth_key TEXT NOT NULL, -- e.g., 'username', 'password', 'token', 'api_key'
    auth_value TEXT NOT NULL, -- Should be encrypted in production
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    UNIQUE(datasource_id, auth_key)
);

-- Table: rule_datasource_cache
-- Cache for external API responses
CREATE TABLE IF NOT EXISTS rule_datasource_cache (
    cache_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id) ON DELETE CASCADE,
    cache_key TEXT NOT NULL, -- Hash of URL + params + headers
    cache_value JSONB NOT NULL,
    response_status INTEGER,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    hit_count INTEGER DEFAULT 0,
    last_hit_at TIMESTAMPTZ,
    UNIQUE(datasource_id, cache_key)
);

-- Table: rule_datasource_requests
-- History and monitoring of data source requests
CREATE TABLE IF NOT EXISTS rule_datasource_requests (
    request_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id) ON DELETE CASCADE,
    endpoint TEXT NOT NULL, -- Relative path (e.g., '/users/123')
    method TEXT DEFAULT 'GET' CHECK (method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')),
    params JSONB DEFAULT '{}'::JSONB,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed', 'cached')),
    cache_hit BOOLEAN DEFAULT false,
    rule_name TEXT, -- Which rule made this request
    rule_execution_id BIGINT,
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    retry_count INTEGER DEFAULT 0,
    response_status INTEGER,
    response_body JSONB,
    response_headers JSONB,
    error_message TEXT,
    execution_time_ms NUMERIC,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Table: rule_datasource_rate_limits
-- Track rate limiting for data sources
CREATE TABLE IF NOT EXISTS rule_datasource_rate_limits (
    rate_limit_id SERIAL PRIMARY KEY,
    datasource_id INTEGER REFERENCES rule_datasources(datasource_id) ON DELETE CASCADE UNIQUE,
    max_requests_per_minute INTEGER DEFAULT 60,
    max_requests_per_hour INTEGER DEFAULT 1000,
    current_minute_count INTEGER DEFAULT 0,
    current_hour_count INTEGER DEFAULT 0,
    minute_window_start TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    hour_window_start TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    last_request_at TIMESTAMPTZ
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_datasources_enabled ON rule_datasources(enabled) WHERE enabled = true;
CREATE INDEX IF NOT EXISTS idx_datasource_requests_status ON rule_datasource_requests(status, started_at);
CREATE INDEX IF NOT EXISTS idx_datasource_requests_datasource ON rule_datasource_requests(datasource_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_datasource_cache_expires ON rule_datasource_cache(expires_at) WHERE expires_at > CURRENT_TIMESTAMP;
CREATE INDEX IF NOT EXISTS idx_datasource_cache_key ON rule_datasource_cache(datasource_id, cache_key);

-- ============================================================================
-- DATA SOURCE MANAGEMENT FUNCTIONS
-- ============================================================================

-- Function: rule_datasource_register
-- Registers a new external data source
CREATE OR REPLACE FUNCTION rule_datasource_register(
    p_name TEXT,
    p_base_url TEXT,
    p_auth_type TEXT DEFAULT 'none',
    p_default_headers JSONB DEFAULT '{}'::JSONB,
    p_description TEXT DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT 5000,
    p_cache_ttl_seconds INTEGER DEFAULT 300
) RETURNS INTEGER AS $$
DECLARE
    v_datasource_id INTEGER;
BEGIN
    -- Validate URL format
    IF p_base_url !~ '^https?://' THEN
        RAISE EXCEPTION 'Invalid URL format. Must start with http:// or https://';
    END IF;

    -- Validate auth type
    IF p_auth_type NOT IN ('none', 'basic', 'bearer', 'api_key', 'oauth2') THEN
        RAISE EXCEPTION 'Invalid auth_type. Must be one of: none, basic, bearer, api_key, oauth2';
    END IF;

    INSERT INTO rule_datasources (
        datasource_name, base_url, auth_type, default_headers, description,
        timeout_ms, cache_ttl_seconds
    ) VALUES (
        p_name, p_base_url, p_auth_type, p_default_headers, p_description,
        p_timeout_ms, p_cache_ttl_seconds
    ) RETURNING datasource_id INTO v_datasource_id;

    -- Initialize rate limit tracking
    INSERT INTO rule_datasource_rate_limits (datasource_id)
    VALUES (v_datasource_id);

    RETURN v_datasource_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_update
-- Updates data source configuration
CREATE OR REPLACE FUNCTION rule_datasource_update(
    p_datasource_id INTEGER,
    p_base_url TEXT DEFAULT NULL,
    p_default_headers JSONB DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT NULL,
    p_cache_ttl_seconds INTEGER DEFAULT NULL,
    p_enabled BOOLEAN DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE rule_datasources SET
        base_url = COALESCE(p_base_url, base_url),
        default_headers = COALESCE(p_default_headers, default_headers),
        timeout_ms = COALESCE(p_timeout_ms, timeout_ms),
        cache_ttl_seconds = COALESCE(p_cache_ttl_seconds, cache_ttl_seconds),
        enabled = COALESCE(p_enabled, enabled),
        updated_at = CURRENT_TIMESTAMP
    WHERE datasource_id = p_datasource_id;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_delete
-- Deletes a data source (cascade deletes auth, cache, requests)
CREATE OR REPLACE FUNCTION rule_datasource_delete(p_datasource_id INTEGER)
RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM rule_datasources WHERE datasource_id = p_datasource_id;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_list
-- Lists all data sources with statistics
CREATE OR REPLACE FUNCTION rule_datasource_list(p_enabled_only BOOLEAN DEFAULT false)
RETURNS TABLE (
    datasource_id INTEGER,
    datasource_name TEXT,
    base_url TEXT,
    auth_type TEXT,
    enabled BOOLEAN,
    cache_enabled BOOLEAN,
    total_requests BIGINT,
    cache_hit_rate NUMERIC,
    avg_response_time_ms NUMERIC,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ds.datasource_id,
        ds.datasource_name,
        ds.base_url,
        ds.auth_type,
        ds.enabled,
        ds.cache_enabled,
        COUNT(r.request_id) as total_requests,
        ROUND(
            CASE
                WHEN COUNT(r.request_id) > 0 THEN
                    (COUNT(*) FILTER (WHERE r.cache_hit = true)::NUMERIC / COUNT(*) * 100)
                ELSE 0
            END, 2
        ) as cache_hit_rate,
        ROUND(AVG(r.execution_time_ms), 2) as avg_response_time_ms,
        ds.created_at
    FROM rule_datasources ds
    LEFT JOIN rule_datasource_requests r ON ds.datasource_id = r.datasource_id
    WHERE (NOT p_enabled_only OR ds.enabled = true)
    GROUP BY ds.datasource_id
    ORDER BY ds.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_get
-- Gets data source configuration by ID or name
CREATE OR REPLACE FUNCTION rule_datasource_get(p_identifier TEXT)
RETURNS JSON AS $$
DECLARE
    v_datasource rule_datasources%ROWTYPE;
BEGIN
    BEGIN
        SELECT * INTO v_datasource FROM rule_datasources
        WHERE datasource_id = p_identifier::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        SELECT * INTO v_datasource FROM rule_datasources
        WHERE datasource_name = p_identifier;
    END;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Data source not found');
    END IF;

    RETURN row_to_json(v_datasource);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- AUTHENTICATION MANAGEMENT
-- ============================================================================

-- Function: rule_datasource_auth_set
-- Sets authentication credentials for a data source
CREATE OR REPLACE FUNCTION rule_datasource_auth_set(
    p_datasource_id INTEGER,
    p_auth_key TEXT,
    p_auth_value TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    -- In production, encrypt p_auth_value before storing
    -- For now, storing as-is (WARNING: not secure for production)
    INSERT INTO rule_datasource_auth (datasource_id, auth_key, auth_value)
    VALUES (p_datasource_id, p_auth_key, p_auth_value)
    ON CONFLICT (datasource_id, auth_key) DO UPDATE
    SET auth_value = EXCLUDED.auth_value,
        created_at = CURRENT_TIMESTAMP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_auth_get
-- Gets authentication credential (use carefully!)
CREATE OR REPLACE FUNCTION rule_datasource_auth_get(
    p_datasource_id INTEGER,
    p_auth_key TEXT
) RETURNS TEXT AS $$
DECLARE
    v_auth_value TEXT;
BEGIN
    SELECT auth_value INTO v_auth_value
    FROM rule_datasource_auth
    WHERE datasource_id = p_datasource_id AND auth_key = p_auth_key;

    RETURN v_auth_value;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: rule_datasource_auth_delete
-- Removes authentication credential
CREATE OR REPLACE FUNCTION rule_datasource_auth_delete(
    p_datasource_id INTEGER,
    p_auth_key TEXT
) RETURNS BOOLEAN AS $$
BEGIN
    DELETE FROM rule_datasource_auth
    WHERE datasource_id = p_datasource_id AND auth_key = p_auth_key;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

-- Function: rule_datasource_cache_get
-- Retrieves cached response if valid
CREATE OR REPLACE FUNCTION rule_datasource_cache_get(
    p_datasource_id INTEGER,
    p_cache_key TEXT
) RETURNS JSONB AS $$
DECLARE
    v_cache_value JSONB;
BEGIN
    -- Update hit count and last hit timestamp
    UPDATE rule_datasource_cache
    SET hit_count = hit_count + 1,
        last_hit_at = CURRENT_TIMESTAMP
    WHERE datasource_id = p_datasource_id
      AND cache_key = p_cache_key
      AND expires_at > CURRENT_TIMESTAMP
    RETURNING cache_value INTO v_cache_value;

    RETURN v_cache_value;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_cache_set
-- Stores response in cache
CREATE OR REPLACE FUNCTION rule_datasource_cache_set(
    p_datasource_id INTEGER,
    p_cache_key TEXT,
    p_cache_value JSONB,
    p_response_status INTEGER,
    p_ttl_seconds INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    INSERT INTO rule_datasource_cache (
        datasource_id, cache_key, cache_value, response_status,
        expires_at
    ) VALUES (
        p_datasource_id, p_cache_key, p_cache_value, p_response_status,
        CURRENT_TIMESTAMP + (p_ttl_seconds || ' seconds')::INTERVAL
    )
    ON CONFLICT (datasource_id, cache_key) DO UPDATE
    SET cache_value = EXCLUDED.cache_value,
        response_status = EXCLUDED.response_status,
        created_at = CURRENT_TIMESTAMP,
        expires_at = CURRENT_TIMESTAMP + (p_ttl_seconds || ' seconds')::INTERVAL,
        hit_count = 0,
        last_hit_at = NULL;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_cache_clear
-- Clears cache for a specific data source or all
CREATE OR REPLACE FUNCTION rule_datasource_cache_clear(
    p_datasource_id INTEGER DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    IF p_datasource_id IS NULL THEN
        DELETE FROM rule_datasource_cache;
    ELSE
        DELETE FROM rule_datasource_cache WHERE datasource_id = p_datasource_id;
    END IF;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_datasource_cache_cleanup
-- Removes expired cache entries
CREATE OR REPLACE FUNCTION rule_datasource_cache_cleanup()
RETURNS BIGINT AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    DELETE FROM rule_datasource_cache WHERE expires_at <= CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- DATA FETCHING FUNCTIONS (Placeholder - Rust implementation required)
-- ============================================================================

-- Function: rule_datasource_fetch
-- Fetches data from external API (implemented in Rust)
-- This is a placeholder that will be implemented in Rust code
CREATE OR REPLACE FUNCTION rule_datasource_fetch(
    p_datasource_id INTEGER,
    p_endpoint TEXT,
    p_params JSONB DEFAULT '{}'::JSONB
) RETURNS JSON AS $$
BEGIN
    -- This function will be implemented in Rust
    -- For now, return error message
    RETURN json_build_object(
        'error', 'This function must be implemented in Rust',
        'message', 'Use the Rust implementation of rule_datasource_fetch'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- MONITORING VIEWS
-- ============================================================================

-- View: datasource_status_summary
-- Summary of data source request statistics
CREATE OR REPLACE VIEW datasource_status_summary AS
SELECT
    ds.datasource_id,
    ds.datasource_name,
    ds.base_url,
    ds.enabled,
    ds.cache_enabled,
    COUNT(r.request_id) as total_requests,
    COUNT(*) FILTER (WHERE r.status = 'success') as successful_requests,
    COUNT(*) FILTER (WHERE r.status = 'failed') as failed_requests,
    COUNT(*) FILTER (WHERE r.cache_hit = true) as cached_requests,
    ROUND(AVG(r.execution_time_ms), 2) as avg_execution_time_ms,
    MAX(r.created_at) as last_request_at,
    ROUND(
        CASE
            WHEN COUNT(r.request_id) > 0 THEN
                (COUNT(*) FILTER (WHERE r.status = 'success')::NUMERIC / COUNT(*) * 100)
            ELSE 0
        END, 2
    ) as success_rate_pct,
    ROUND(
        CASE
            WHEN COUNT(r.request_id) > 0 THEN
                (COUNT(*) FILTER (WHERE r.cache_hit = true)::NUMERIC / COUNT(*) * 100)
            ELSE 0
        END, 2
    ) as cache_hit_rate_pct
FROM rule_datasources ds
LEFT JOIN rule_datasource_requests r ON ds.datasource_id = r.datasource_id
GROUP BY ds.datasource_id;

-- View: datasource_recent_failures
-- Recent failed requests for debugging
CREATE OR REPLACE VIEW datasource_recent_failures AS
SELECT
    r.request_id,
    ds.datasource_name,
    ds.base_url,
    r.endpoint,
    r.method,
    r.status,
    r.retry_count,
    r.error_message,
    r.response_status,
    r.params,
    r.created_at,
    r.completed_at
FROM rule_datasource_requests r
JOIN rule_datasources ds ON r.datasource_id = ds.datasource_id
WHERE r.status = 'failed'
ORDER BY r.created_at DESC
LIMIT 100;

-- View: datasource_performance_stats
-- Performance statistics per data source
CREATE OR REPLACE VIEW datasource_performance_stats AS
SELECT
    ds.datasource_id,
    ds.datasource_name,
    COUNT(r.request_id) as total_requests,
    ROUND(AVG(r.execution_time_ms), 2) as avg_time_ms,
    ROUND(MIN(r.execution_time_ms), 2) as min_time_ms,
    ROUND(MAX(r.execution_time_ms), 2) as max_time_ms,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.execution_time_ms), 2) as p50_time_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY r.execution_time_ms), 2) as p95_time_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY r.execution_time_ms), 2) as p99_time_ms
FROM rule_datasources ds
LEFT JOIN rule_datasource_requests r ON ds.datasource_id = r.datasource_id
WHERE r.execution_time_ms IS NOT NULL
GROUP BY ds.datasource_id
HAVING COUNT(r.request_id) > 0
ORDER BY total_requests DESC;

-- View: datasource_cache_stats
-- Cache statistics per data source
CREATE OR REPLACE VIEW datasource_cache_stats AS
SELECT
    ds.datasource_id,
    ds.datasource_name,
    ds.cache_enabled,
    COUNT(c.cache_id) as total_cache_entries,
    COUNT(*) FILTER (WHERE c.expires_at > CURRENT_TIMESTAMP) as valid_cache_entries,
    COUNT(*) FILTER (WHERE c.expires_at <= CURRENT_TIMESTAMP) as expired_cache_entries,
    ROUND(AVG(c.hit_count), 2) as avg_hit_count,
    SUM(c.hit_count) as total_hits,
    MAX(c.last_hit_at) as last_cache_hit_at
FROM rule_datasources ds
LEFT JOIN rule_datasource_cache c ON ds.datasource_id = c.datasource_id
GROUP BY ds.datasource_id;

-- ============================================================================
-- MAINTENANCE FUNCTIONS
-- ============================================================================

-- Function: rule_datasource_cleanup_old_requests
-- Removes old request records
CREATE OR REPLACE FUNCTION rule_datasource_cleanup_old_requests(
    p_older_than INTERVAL DEFAULT '30 days',
    p_keep_failed BOOLEAN DEFAULT true
) RETURNS BIGINT AS $$
DECLARE
    v_deleted_count BIGINT;
BEGIN
    IF p_keep_failed THEN
        DELETE FROM rule_datasource_requests
        WHERE created_at < (CURRENT_TIMESTAMP - p_older_than)
          AND status != 'failed';
    ELSE
        DELETE FROM rule_datasource_requests
        WHERE created_at < (CURRENT_TIMESTAMP - p_older_than);
    END IF;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE rule_datasources IS 'External data source configurations for fetching data from REST APIs';
COMMENT ON TABLE rule_datasource_auth IS 'Authentication credentials for data sources';
COMMENT ON TABLE rule_datasource_cache IS 'Cache storage for API responses';
COMMENT ON TABLE rule_datasource_requests IS 'History and monitoring of data source requests';
COMMENT ON TABLE rule_datasource_rate_limits IS 'Rate limiting tracking per data source';

COMMENT ON FUNCTION rule_datasource_register IS 'Registers a new external data source';
COMMENT ON FUNCTION rule_datasource_fetch IS 'Fetches data from external API (Rust implementation)';
COMMENT ON FUNCTION rule_datasource_cache_get IS 'Retrieves cached response if still valid';
COMMENT ON FUNCTION rule_datasource_cache_cleanup IS 'Removes expired cache entries';
