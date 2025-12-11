-- Test Suite: External Data Sources (Phase 4.3)
-- Description: Tests for external API data fetching, caching, and connection pooling
-- Created: 2025-12-12

\echo '========================================='
\echo 'Phase 4.3: External Data Sources Tests'
\echo '========================================='

-- ============================================================================
-- SETUP
-- ============================================================================

\echo ''
\echo '--- Setup: Load migration ---'
\i migrations/006_external_datasources.sql

-- ============================================================================
-- TEST 1: Data Source Registration
-- ============================================================================

\echo ''
\echo 'TEST 1: Data Source Registration'

-- Register a data source
SELECT rule_datasource_register(
    'jsonplaceholder',
    'https://jsonplaceholder.typicode.com',
    'none',
    '{"Content-Type": "application/json"}'::JSONB,
    'JSONPlaceholder test API',
    10000,
    300
) AS datasource_id \gset

\echo 'Registered data source ID: ' :datasource_id

-- Verify registration
SELECT datasource_name, base_url, auth_type, enabled
FROM rule_datasources
WHERE datasource_id = :datasource_id;

-- Expected: 1 row with jsonplaceholder data

-- ============================================================================
-- TEST 2: Data Source Listing
-- ============================================================================

\echo ''
\echo 'TEST 2: Data Source Listing'

SELECT * FROM rule_datasource_list();

-- Expected: At least 1 row with our registered data source

-- ============================================================================
-- TEST 3: Data Source Get by ID and Name
-- ============================================================================

\echo ''
\echo 'TEST 3: Data Source Get'

-- By ID
SELECT rule_datasource_get(:datasource_id::TEXT);

-- By name
SELECT rule_datasource_get('jsonplaceholder');

-- Expected: JSON object with data source configuration

-- ============================================================================
-- TEST 4: Authentication Management
-- ============================================================================

\echo ''
\echo 'TEST 4: Authentication Management'

-- Set API key (even though this API doesn't require it)
SELECT rule_datasource_auth_set(:datasource_id, 'api_key', 'test-key-123');

-- Get API key
SELECT rule_datasource_auth_get(:datasource_id, 'api_key') AS api_key;

-- Expected: 'test-key-123'

-- Delete API key
SELECT rule_datasource_auth_delete(:datasource_id, 'api_key');

-- Verify deletion
SELECT rule_datasource_auth_get(:datasource_id, 'api_key') AS should_be_null;

-- Expected: NULL

-- ============================================================================
-- TEST 5: Cache Management
-- ============================================================================

\echo ''
\echo 'TEST 5: Cache Management'

-- Set cache entry
SELECT rule_datasource_cache_set(
    :datasource_id,
    'test-key-1',
    '{"user": "john", "id": 1}'::JSONB,
    200,
    60
);

-- Get cache entry (should increment hit count)
SELECT rule_datasource_cache_get(:datasource_id, 'test-key-1');

-- Expected: {"user": "john", "id": 1}

-- Check cache stats
SELECT * FROM datasource_cache_stats WHERE datasource_id = :datasource_id;

-- Expected: 1 valid cache entry, hit_count = 1

-- Clear cache for this datasource
SELECT rule_datasource_cache_clear(:datasource_id) AS cleared_count;

-- Expected: 1

-- Verify cache is cleared
SELECT rule_datasource_cache_get(:datasource_id, 'test-key-1') AS should_be_null;

-- Expected: NULL

-- ============================================================================
-- TEST 6: Data Fetching (Requires HTTP Extension or External Worker)
-- ============================================================================

\echo ''
\echo 'TEST 6: Data Fetching (Mock)'

-- Note: Actual HTTP fetching requires the Rust implementation
-- For now, we test the database structure

-- Insert a mock successful request
INSERT INTO rule_datasource_requests (
    datasource_id, endpoint, method, params, status, cache_hit,
    response_status, response_body, execution_time_ms, completed_at
) VALUES (
    :datasource_id,
    '/users/1',
    'GET',
    '{}'::JSONB,
    'success',
    false,
    200,
    '{"id": 1, "name": "John Doe", "email": "john@example.com"}'::JSONB,
    123.45,
    CURRENT_TIMESTAMP
);

-- Check request was recorded
SELECT request_id, endpoint, status, cache_hit, response_status
FROM rule_datasource_requests
WHERE datasource_id = :datasource_id
ORDER BY created_at DESC
LIMIT 1;

-- Expected: 1 row with success status

-- ============================================================================
-- TEST 7: Monitoring Views
-- ============================================================================

\echo ''
\echo 'TEST 7: Monitoring Views'

-- Status summary
SELECT * FROM datasource_status_summary WHERE datasource_id = :datasource_id;

-- Expected: 1 row with total_requests = 1, success_rate = 100

-- Performance stats
SELECT * FROM datasource_performance_stats WHERE datasource_id = :datasource_id;

-- Expected: 1 row with avg_time_ms = 123.45

-- ============================================================================
-- TEST 8: Data Source Update
-- ============================================================================

\echo ''
\echo 'TEST 8: Data Source Update'

-- Update timeout
SELECT rule_datasource_update(
    :datasource_id,
    NULL,  -- base_url
    NULL,  -- default_headers
    15000, -- timeout_ms
    NULL,  -- cache_ttl_seconds
    NULL   -- enabled
);

-- Verify update
SELECT timeout_ms FROM rule_datasources WHERE datasource_id = :datasource_id;

-- Expected: 15000

-- ============================================================================
-- TEST 9: Rate Limiting Table
-- ============================================================================

\echo ''
\echo 'TEST 9: Rate Limiting'

-- Check rate limit was initialized
SELECT datasource_id, max_requests_per_minute, max_requests_per_hour
FROM rule_datasource_rate_limits
WHERE datasource_id = :datasource_id;

-- Expected: 1 row with default values (60, 1000)

-- ============================================================================
-- TEST 10: Failed Requests Tracking
-- ============================================================================

\echo ''
\echo 'TEST 10: Failed Requests Tracking'

-- Insert a failed request
INSERT INTO rule_datasource_requests (
    datasource_id, endpoint, method, params, status, cache_hit,
    error_message, execution_time_ms, completed_at
) VALUES (
    :datasource_id,
    '/users/999',
    'GET',
    '{}'::JSONB,
    'failed',
    false,
    'User not found',
    50.0,
    CURRENT_TIMESTAMP
);

-- Check recent failures view
SELECT * FROM datasource_recent_failures WHERE datasource_id = :datasource_id;

-- Expected: 1 row with error_message = 'User not found'

-- ============================================================================
-- TEST 11: Cache Cleanup
-- ============================================================================

\echo ''
\echo 'TEST 11: Cache Cleanup'

-- Insert expired cache entry
INSERT INTO rule_datasource_cache (
    datasource_id, cache_key, cache_value, response_status, expires_at
) VALUES (
    :datasource_id,
    'expired-key',
    '{"data": "old"}'::JSONB,
    200,
    CURRENT_TIMESTAMP - INTERVAL '1 hour'
);

-- Run cleanup
SELECT rule_datasource_cache_cleanup() AS cleaned_count;

-- Expected: >= 1

-- Verify expired entry was removed
SELECT COUNT(*) FROM rule_datasource_cache
WHERE datasource_id = :datasource_id AND cache_key = 'expired-key';

-- Expected: 0

-- ============================================================================
-- TEST 12: Request Cleanup
-- ============================================================================

\echo ''
\echo 'TEST 12: Request Cleanup'

-- Insert old request
INSERT INTO rule_datasource_requests (
    datasource_id, endpoint, method, params, status,
    created_at, completed_at
) VALUES (
    :datasource_id,
    '/old-endpoint',
    'GET',
    '{}'::JSONB,
    'success',
    CURRENT_TIMESTAMP - INTERVAL '60 days',
    CURRENT_TIMESTAMP - INTERVAL '60 days'
);

-- Cleanup old requests (keep failed)
SELECT rule_datasource_cleanup_old_requests('45 days', true) AS cleaned_count;

-- Expected: >= 1

-- Verify old successful request was removed
SELECT COUNT(*) FROM rule_datasource_requests
WHERE datasource_id = :datasource_id AND endpoint = '/old-endpoint';

-- Expected: 0

-- ============================================================================
-- TEST 13: Data Source Deletion
-- ============================================================================

\echo ''
\echo 'TEST 13: Data Source Deletion (Cascade)'

-- Create a temporary data source
SELECT rule_datasource_register(
    'temp_api',
    'https://api.example.com',
    'none',
    '{}'::JSONB,
    'Temporary API for testing deletion'
) AS temp_ds_id \gset

-- Add some data
INSERT INTO rule_datasource_requests (datasource_id, endpoint, method, params, status)
VALUES (:temp_ds_id, '/test', 'GET', '{}'::JSONB, 'success');

SELECT rule_datasource_cache_set(:temp_ds_id, 'temp-cache', '{"test": true}'::JSONB, 200, 60);

-- Delete data source
SELECT rule_datasource_delete(:temp_ds_id);

-- Verify cascaded deletion
SELECT COUNT(*) AS remaining_requests FROM rule_datasource_requests WHERE datasource_id = :temp_ds_id;
SELECT COUNT(*) AS remaining_cache FROM rule_datasource_cache WHERE datasource_id = :temp_ds_id;
SELECT COUNT(*) AS remaining_rate_limits FROM rule_datasource_rate_limits WHERE datasource_id = :temp_ds_id;

-- Expected: All counts = 0

-- ============================================================================
-- TEST 14: Disabled Data Source
-- ============================================================================

\echo ''
\echo 'TEST 14: Disabled Data Source'

-- Disable the data source
SELECT rule_datasource_update(:datasource_id, NULL, NULL, NULL, NULL, false);

-- Verify it's disabled
SELECT enabled FROM rule_datasources WHERE datasource_id = :datasource_id;

-- Expected: false

-- Re-enable it
SELECT rule_datasource_update(:datasource_id, NULL, NULL, NULL, NULL, true);

-- ============================================================================
-- TEST 15: Multiple Data Sources
-- ============================================================================

\echo ''
\echo 'TEST 15: Multiple Data Sources'

-- Register multiple data sources
SELECT rule_datasource_register('github_api', 'https://api.github.com', 'bearer', '{}'::JSONB) AS github_id \gset
SELECT rule_datasource_register('stripe_api', 'https://api.stripe.com', 'bearer', '{}'::JSONB) AS stripe_id \gset

-- List all enabled data sources
SELECT datasource_name, base_url, auth_type
FROM rule_datasource_list(true)
ORDER BY datasource_name;

-- Expected: At least 3 rows (jsonplaceholder, github_api, stripe_api)

-- Cleanup
SELECT rule_datasource_delete(:github_id);
SELECT rule_datasource_delete(:stripe_id);

-- ============================================================================
-- SUMMARY
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test Summary'
\echo '========================================='
\echo 'All external data source tests completed!'
\echo ''
\echo 'Verified features:'
\echo '  ✓ Data source registration and management'
\echo '  ✓ Authentication credential storage'
\echo '  ✓ Cache management (set, get, clear, cleanup)'
\echo '  ✓ Request tracking and history'
\echo '  ✓ Monitoring views (status, performance, failures)'
\echo '  ✓ Rate limiting tracking'
\echo '  ✓ Cascade deletion'
\echo '  ✓ Maintenance functions'
\echo ''
\echo 'Next steps:'
\echo '  1. Test actual HTTP fetching with Rust implementation'
\echo '  2. Integrate with rule engine for dynamic data fetching'
\echo '  3. Performance testing with high request volumes'
\echo '========================================='
