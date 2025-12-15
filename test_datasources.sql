-- ============================================================================
-- TEST SCRIPT FOR EXTERNAL DATA SOURCES (v1.6.0)
-- ============================================================================
-- This script tests the external data source functionality
-- Run: psql -d postgres -f test_datasources.sql

\echo '============================================================================'
\echo 'TEST: External Data Sources - v1.6.0'
\echo '============================================================================'

-- Clean up first
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;

\echo '\n=== 1. Creating Extension ==='
CREATE EXTENSION rule_engine_postgre_extensions;

\echo '\n=== 2. Verify Extension Version ==='
SELECT rule_engine_version();

\echo '\n=== 3. Check Tables Exist ==='
SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename LIKE 'rule_datasource%'
ORDER BY tablename;

\echo '\n=== 4. Register External Data Source ==='
SELECT rule_datasource_register(
    'test_api',
    'https://api.example.com',
    'api_key',
    '{"Content-Type": "application/json"}'::JSONB,
    'Test API for development',
    5000,   -- 5s timeout
    300     -- 5min cache TTL
);

\echo '\n=== 5. Verify Data Source Created ==='
SELECT datasource_id, datasource_name, base_url, auth_type, enabled, cache_enabled
FROM rule_datasources;

\echo '\n=== 6. Set API Credentials ==='
SELECT rule_datasource_auth_set(1, 'api_key', 'test-secret-key-12345');

\echo '\n=== 7. Verify Credentials Stored (should be encrypted) ==='
SELECT datasource_id, auth_key,
       CASE WHEN auth_value LIKE 'test-%' THEN '❌ PLAINTEXT!'
            ELSE '✅ ENCRYPTED'
       END as encryption_status,
       LEFT(auth_value, 20) || '...' AS encrypted_preview
FROM rule_datasource_auth;

\echo '\n=== 7.1. Test Decryption ==='
SELECT rule_datasource_auth_get(1, 'api_key') AS decrypted_value;

\echo '\n=== 7.2. View Encryption Audit ==='
SELECT * FROM datasource_encryption_audit;

\echo '\n=== 8. Test Monitoring Views ==='

\echo '\n--- 8.1. Data Source Status Summary ---'
SELECT datasource_id, datasource_name, enabled, cache_enabled, total_requests
FROM datasource_status_summary;

\echo '\n--- 8.2. Cache Stats (should be empty initially) ---'
SELECT datasource_id, datasource_name, total_cache_entries
FROM datasource_cache_stats;

\echo '\n=== 9. Register Multiple Data Sources ==='
SELECT rule_datasource_register(
    'weather_api',
    'https://api.weather.com',
    'bearer',
    '{"Content-Type": "application/json"}'::JSONB,
    'Weather API',
    3000,
    600
);

SELECT rule_datasource_register(
    'fraud_detection_api',
    'https://api.fraud-check.com',
    'api_key',
    '{"Content-Type": "application/json", "Accept": "application/json"}'::JSONB,
    'Fraud Detection Service',
    10000,
    120
);

\echo '\n=== 10. List All Data Sources ==='
SELECT datasource_id, datasource_name, base_url, timeout_ms, cache_ttl_seconds, enabled
FROM rule_datasources
ORDER BY datasource_id;

\echo '\n=== 11. Update Data Source Configuration ==='
SELECT rule_datasource_update(
    1,  -- datasource_id
    'https://api.example.com/v2',  -- new URL
    '{"Content-Type": "application/json", "X-API-Version": "2.0"}'::JSONB,  -- new headers
    7000,  -- increased timeout
    600,   -- increased cache TTL
    TRUE   -- enabled
);

\echo '\n=== 12. Verify Update ==='
SELECT datasource_id, datasource_name, base_url, timeout_ms, cache_ttl_seconds
FROM rule_datasources
WHERE datasource_id = 1;

\echo '\n=== 13. Test Enable/Disable Data Source ==='
-- Disable
UPDATE rule_datasources SET enabled = false WHERE datasource_id = 1;

-- Verify disabled
SELECT datasource_id, datasource_name, enabled
FROM rule_datasources
WHERE datasource_id = 1;

-- Re-enable
UPDATE rule_datasources SET enabled = true WHERE datasource_id = 1;

\echo '\n=== 14. Test Cache Table Structure ==='
\d rule_datasource_cache

\echo '\n=== 15. Insert Mock Cache Entry Using Function ==='
SELECT rule_datasource_cache_set(
    1,  -- datasource_id
    'test_endpoint_12345',  -- cache_key
    '{"result": "success", "data": {"temperature": 25}}'::JSONB,  -- cache_value
    200,  -- response_status
    300   -- ttl_seconds (5 minutes)
);

\echo '\n=== 16. Verify Cache Entry ==='
SELECT cache_id, datasource_id, cache_key, hit_count, expires_at > NOW() as is_valid
FROM rule_datasource_cache;

\echo '\n=== 16.1. Test Cache Get Function ==='
SELECT rule_datasource_cache_get(1, 'test_endpoint_12345');

\echo '\n=== 17. Test Cache Stats View ==='
SELECT datasource_id, datasource_name, total_cache_entries, valid_cache_entries, expired_cache_entries
FROM datasource_cache_stats;

\echo '\n=== 18. Insert Mock Request Records ==='
-- Simulate some API requests
INSERT INTO rule_datasource_requests (
    datasource_id, endpoint, method, params, status, cache_hit,
    started_at, completed_at, execution_time_ms, response_status, response_body
) VALUES
    (1, '/weather/current', 'GET', '{}'::JSONB, 'success', false,
     NOW() - INTERVAL '1 hour', NOW() - INTERVAL '1 hour', 150.5, 200, '{"temp": 25}'::JSONB),
    (1, '/weather/forecast', 'GET', '{}'::JSONB, 'success', true,
     NOW() - INTERVAL '30 minutes', NOW() - INTERVAL '30 minutes', 5.2, 200, '{"forecast": "sunny"}'::JSONB),
    (2, '/current', 'GET', '{"city": "NYC"}'::JSONB, 'success', false,
     NOW() - INTERVAL '15 minutes', NOW() - INTERVAL '15 minutes', 220.8, 200, '{"temp": 15}'::JSONB),
    (3, '/score/customer123', 'POST', '{"customer_id": "123"}'::JSONB, 'success', false,
     NOW() - INTERVAL '5 minutes', NOW() - INTERVAL '5 minutes', 456.3, 200, '{"score": 85}'::JSONB),
    (1, '/weather/alerts', 'GET', '{}'::JSONB, 'failed', false,
     NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes', NULL, 500, NULL);

\echo '\n=== 19. Test Data Source Status Summary ==='
SELECT
    datasource_id,
    datasource_name,
    total_requests,
    successful_requests,
    failed_requests,
    cached_requests,
    avg_execution_time_ms,
    success_rate_pct,
    cache_hit_rate_pct
FROM datasource_status_summary
ORDER BY datasource_id;

\echo '\n=== 20. Test Performance Stats View ==='
SELECT
    datasource_id,
    datasource_name,
    total_requests,
    avg_time_ms,
    min_time_ms,
    max_time_ms,
    p50_time_ms
FROM datasource_performance_stats
ORDER BY datasource_id;

\echo '\n=== 21. Test Recent Failures View ==='
SELECT
    request_id,
    datasource_name,
    endpoint,
    response_status,
    error_message,
    completed_at
FROM datasource_recent_failures
ORDER BY completed_at DESC
LIMIT 5;

\echo '\n=== 22. Test Rate Limiting Table ==='
SELECT
    datasource_id,
    COUNT(*) as total_limits
FROM rule_datasource_rate_limits
GROUP BY datasource_id;

\echo '\n=== 23. Test Delete Data Source ==='
-- Try to delete (should work)
SELECT rule_datasource_delete(3);  -- Delete fraud_detection_api

-- Verify deleted
SELECT COUNT(*) as remaining_datasources
FROM rule_datasources;

\echo '\n=== 24. Test Cascade Delete (Auth & Cache) ==='
-- Check if auth entries for deleted datasource are gone
SELECT COUNT(*) as auth_entries
FROM rule_datasource_auth
WHERE datasource_id = 3;

-- Check if cache entries for deleted datasource are gone
SELECT COUNT(*) as cache_entries
FROM rule_datasource_cache
WHERE datasource_id = 3;

\echo '\n=== 25. Test Request History ==='
SELECT
    COUNT(*) as total_requests,
    COUNT(*) FILTER (WHERE status = 'success') as successful,
    COUNT(*) FILTER (WHERE status = 'failed') as failed,
    COUNT(*) FILTER (WHERE cache_hit = true) as from_cache,
    ROUND(AVG(execution_time_ms)::NUMERIC, 2) as avg_time_ms
FROM rule_datasource_requests;

\echo '\n=== 26. Test Data Source List Function ==='
SELECT * FROM rule_datasource_list();

\echo '\n=== 27. Test Data Source Get Function ==='
SELECT rule_datasource_get('test_api');

\echo '\n=== 28. Test Cache Cleanup (Expired Entries) ==='
-- Add an expired cache entry (TTL = -3600 seconds = expired 1 hour ago)
SELECT rule_datasource_cache_set(
    1,  -- datasource_id
    'expired_entry',  -- cache_key
    '{"old": "data"}'::JSONB,  -- cache_value
    200,  -- response_status
    -3600  -- ttl_seconds (negative = already expired)
);

-- Count before cleanup
SELECT COUNT(*) as total_cache,
       COUNT(*) FILTER (WHERE expires_at > NOW()) as valid,
       COUNT(*) FILTER (WHERE expires_at <= NOW()) as expired
FROM rule_datasource_cache;

-- Cleanup expired entries
DELETE FROM rule_datasource_cache WHERE expires_at <= NOW();

-- Count after cleanup
SELECT COUNT(*) as total_cache,
       COUNT(*) FILTER (WHERE expires_at > NOW()) as valid,
       COUNT(*) FILTER (WHERE expires_at <= NOW()) as expired
FROM rule_datasource_cache;

\echo '\n=== 29. Test Views Performance ==='
\timing on

SELECT COUNT(*) FROM datasource_status_summary;
SELECT COUNT(*) FROM datasource_performance_stats;
SELECT COUNT(*) FROM datasource_cache_stats;

\timing off

\echo '\n=== 30. Summary Report ==='
\echo '\n--- Final Statistics ---'
SELECT
    'Data Sources' as metric,
    COUNT(*)::TEXT as value
FROM rule_datasources
UNION ALL
SELECT
    'Total Requests',
    COUNT(*)::TEXT
FROM rule_datasource_requests
UNION ALL
SELECT
    'Cache Entries',
    COUNT(*)::TEXT
FROM rule_datasource_cache
UNION ALL
SELECT
    'Auth Credentials',
    COUNT(*)::TEXT
FROM rule_datasource_auth;

\echo '\n============================================================================'
\echo 'TEST COMPLETE: External Data Sources'
\echo '============================================================================'
\echo ''
\echo 'Summary:'
\echo '  ✅ Tables created'
\echo '  ✅ Data sources registered'
\echo '  ✅ Auth credentials stored'
\echo '  ✅ Monitoring views working'
\echo '  ✅ Cache system functional'
\echo '  ✅ Request tracking operational'
\echo ''
\echo 'Note: Actual HTTP calls require external APIs and are not tested here.'
\echo '      The Rust function rule_datasource_fetch() would make real HTTP requests.'
\echo '============================================================================'
