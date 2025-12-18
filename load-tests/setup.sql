-- Load Test Setup Script
-- Run this ONCE before running load tests

\echo '=== Setting up load test environment ==='

-- 1. Create extension if not exists
CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;

\echo '✓ Extension created'

-- 2. Clean up old test data (ignore errors if tables don't exist yet)
DO $$
BEGIN
    -- Clean webhook data if tables exist
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'rule_webhooks') THEN
        DELETE FROM rule_webhook_calls WHERE webhook_id IN (SELECT webhook_id FROM rule_webhooks WHERE name LIKE 'loadtest_%');
        DELETE FROM rule_webhooks WHERE name LIKE 'loadtest_%';
    END IF;

    -- Clean datasource data if tables exist
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'rule_datasources') THEN
        DELETE FROM rule_datasource_requests WHERE datasource_id IN (SELECT datasource_id FROM rule_datasources WHERE name LIKE 'loadtest_%');
        DELETE FROM rule_datasources WHERE name LIKE 'loadtest_%';
    END IF;

    -- Clean rule repository data if tables exist
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'rule_definitions') THEN
        DELETE FROM rule_definitions WHERE name LIKE 'test_rule_%';
    END IF;
END $$;

\echo '✓ Cleaned old test data'

-- 3. Register test webhook (using httpbin.org for testing)
-- httpbin.org is a free HTTP testing service
DO $$
DECLARE
    webhook_id INTEGER;
BEGIN
    SELECT rule_webhook_register(
        'loadtest_webhook',
        'https://httpbin.org/post',  -- Free test endpoint
        'POST',
        '{"Content-Type": "application/json"}'::JSONB,
        'Load test webhook',
        10000,  -- 10s timeout
        3       -- max 3 retries
    ) INTO webhook_id;

    RAISE NOTICE '✓ Created webhook with ID: %', webhook_id;
END $$;

-- 4. Register test datasource (using JSONPlaceholder for testing)
-- JSONPlaceholder is a free fake REST API
DO $$
DECLARE
    datasource_id INTEGER;
BEGIN
    SELECT rule_datasource_register(
        'loadtest_datasource',
        'https://jsonplaceholder.typicode.com',  -- Free test API
        'none',                                   -- auth_type
        '{"Content-Type": "application/json"}'::JSONB,  -- default_headers
        'Load test datasource',                   -- description
        5000,                                     -- timeout_ms
        300                                       -- cache_ttl_seconds (no max_retries param)
    ) INTO datasource_id;

    RAISE NOTICE '✓ Created datasource with ID: %', datasource_id;
END $$;

-- 5. Note: Rule repository functions will be available after full install
-- For now, tests 01-02 (forward chaining) will work without rule repository

\echo ''
\echo '=== Load test environment ready! ==='
\echo ''
\echo 'Available tests:'
\echo '  01_simple_rule.sql       - Simple forward chaining (1 condition)'
\echo '  02_complex_rule.sql      - Complex rules (multiple conditions)'
\echo '  03_repository_save.sql   - Concurrent rule saves'
\echo '  04_repository_execute.sql - Execute saved rules'
\echo '  05_webhook_call.sql      - Webhook HTTP callouts'
\echo '  06_datasource_fetch.sql  - External API fetching with cache'
\echo ''
\echo 'Use run_loadtest.sh to execute tests'
\echo ''
