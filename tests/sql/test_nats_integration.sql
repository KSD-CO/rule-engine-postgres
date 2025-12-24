-- =============================================================================
-- NATS Integration Test Suite
-- =============================================================================
-- This test suite validates NATS integration functionality
--
-- Prerequisites:
-- - PostgreSQL with Rule Engine extension installed
-- - Migration 007 applied
-- - pgTAP extension installed (optional but recommended)
--
-- Run with:
--   psql -U postgres -d your_database -f tests/sql/test_nats_integration.sql

\set ON_ERROR_STOP on
\set ECHO all

-- =============================================================================
-- Test Setup
-- =============================================================================

BEGIN;

-- Create test schema
CREATE SCHEMA IF NOT EXISTS nats_test;
SET search_path TO nats_test, public;

-- Test counter
CREATE TABLE IF NOT EXISTS test_results (
    test_number SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('PASS', 'FAIL', 'SKIP')),
    message TEXT,
    executed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Helper function to record test results
CREATE OR REPLACE FUNCTION assert_equals(
    p_test_name TEXT,
    p_expected ANYELEMENT,
    p_actual ANYELEMENT
) RETURNS VOID AS $$
BEGIN
    IF p_expected = p_actual OR (p_expected IS NULL AND p_actual IS NULL) THEN
        INSERT INTO nats_test.test_results (test_name, status, message)
        VALUES (p_test_name, 'PASS', format('Expected: %s, Got: %s', p_expected, p_actual));
        RAISE NOTICE 'PASS: %', p_test_name;
    ELSE
        INSERT INTO nats_test.test_results (test_name, status, message)
        VALUES (p_test_name, 'FAIL', format('Expected: %s, Got: %s', p_expected, p_actual));
        RAISE EXCEPTION 'FAIL: % - Expected: %, Got: %', p_test_name, p_expected, p_actual;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assert_true(
    p_test_name TEXT,
    p_condition BOOLEAN
) RETURNS VOID AS $$
BEGIN
    IF p_condition THEN
        INSERT INTO nats_test.test_results (test_name, status, message)
        VALUES (p_test_name, 'PASS', 'Condition is true');
        RAISE NOTICE 'PASS: %', p_test_name;
    ELSE
        INSERT INTO nats_test.test_results (test_name, status, message)
        VALUES (p_test_name, 'FAIL', 'Condition is false');
        RAISE EXCEPTION 'FAIL: % - Condition is false', p_test_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assert_not_null(
    p_test_name TEXT,
    p_value ANYELEMENT
) RETURNS VOID AS $$
BEGIN
    IF p_value IS NOT NULL THEN
        INSERT INTO nats_test.test_results (test_name, status, message)
        VALUES (p_test_name, 'PASS', 'Value is not null');
        RAISE NOTICE 'PASS: %', p_test_name;
    ELSE
        INSERT INTO nats_test.test_results (test_name, status, message)
        VALUES (p_test_name, 'FAIL', 'Value is null');
        RAISE EXCEPTION 'FAIL: % - Value is null', p_test_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Test 1: Schema Validation
-- =============================================================================

DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '=== Test 1: Schema Validation ===';
END $$;

-- Test 1.1: rule_nats_config table exists
DO $$
BEGIN
    PERFORM assert_true(
        '1.1 - rule_nats_config table exists',
        EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_name = 'rule_nats_config'
        )
    );
END $$;

-- Test 1.2: rule_nats_streams table exists
DO $$
BEGIN
    PERFORM assert_true(
        '1.2 - rule_nats_streams table exists',
        EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_name = 'rule_nats_streams'
        )
    );
END $$;

-- Test 1.3: rule_nats_publish_history table exists
DO $$
BEGIN
    PERFORM assert_true(
        '1.3 - rule_nats_publish_history table exists',
        EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_name = 'rule_nats_publish_history'
        )
    );
END $$;

-- Test 1.4: rule_nats_consumer_stats table exists
DO $$
BEGIN
    PERFORM assert_true(
        '1.4 - rule_nats_consumer_stats table exists',
        EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_name = 'rule_nats_consumer_stats'
        )
    );
END $$;

-- Test 1.5: rule_webhooks has NATS columns
DO $$
BEGIN
    PERFORM assert_true(
        '1.5 - rule_webhooks.nats_enabled column exists',
        EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'rule_webhooks'
            AND column_name = 'nats_enabled'
        )
    );
END $$;

DO $$
BEGIN
    PERFORM assert_true(
        '1.6 - rule_webhooks.nats_subject column exists',
        EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'rule_webhooks'
            AND column_name = 'nats_subject'
        )
    );
END $$;

DO $$
BEGIN
    PERFORM assert_true(
        '1.7 - rule_webhooks.publish_mode column exists',
        EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'rule_webhooks'
            AND column_name = 'publish_mode'
        )
    );
END $$;

-- =============================================================================
-- Test 2: Default Configuration
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 2: Default Configuration ===';
END $$;

-- Test 2.1: Default config exists
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM rule_nats_config
    WHERE config_name = 'default';

    PERFORM assert_equals(
        '2.1 - Default NATS config exists',
        1,
        v_count
    );
END $$;

-- Test 2.2: Default config has correct URL
DO $$
DECLARE
    v_url TEXT;
BEGIN
    SELECT nats_url INTO v_url
    FROM rule_nats_config
    WHERE config_name = 'default';

    PERFORM assert_equals(
        '2.2 - Default NATS URL is correct',
        'nats://localhost:4222',
        v_url
    );
END $$;

-- Test 2.3: Default config has JetStream enabled
DO $$
DECLARE
    v_enabled BOOLEAN;
BEGIN
    SELECT jetstream_enabled INTO v_enabled
    FROM rule_nats_config
    WHERE config_name = 'default';

    PERFORM assert_true(
        '2.3 - Default JetStream is enabled',
        v_enabled
    );
END $$;

-- =============================================================================
-- Test 3: Configuration Management
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 3: Configuration Management ===';
END $$;

-- Test 3.1: Insert custom NATS config
DO $$
DECLARE
    v_config_id INTEGER;
BEGIN
    INSERT INTO rule_nats_config (
        config_name,
        nats_url,
        jetstream_enabled,
        stream_name,
        max_connections
    ) VALUES (
        'test_config',
        'nats://test-server:4222',
        true,
        'TEST_STREAM',
        20
    ) RETURNING config_id INTO v_config_id;

    PERFORM assert_not_null(
        '3.1 - Insert custom NATS config',
        v_config_id
    );
END $$;

-- Test 3.2: Verify custom config values
DO $$
DECLARE
    v_max_conn INTEGER;
BEGIN
    SELECT max_connections INTO v_max_conn
    FROM rule_nats_config
    WHERE config_name = 'test_config';

    PERFORM assert_equals(
        '3.2 - Custom config max_connections',
        20,
        v_max_conn
    );
END $$;

-- Test 3.3: Update config
DO $$
BEGIN
    UPDATE rule_nats_config
    SET max_connections = 30
    WHERE config_name = 'test_config';

    PERFORM assert_equals(
        '3.3 - Update config max_connections',
        30,
        (SELECT max_connections FROM rule_nats_config WHERE config_name = 'test_config')
    );
END $$;

-- =============================================================================
-- Test 4: Webhook NATS Configuration
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 4: Webhook NATS Configuration ===';
END $$;

-- Test 4.1: Create NATS-enabled webhook
DO $$
DECLARE
    v_webhook_id INTEGER;
BEGIN
    INSERT INTO rule_webhooks (
        webhook_name,
        url,
        method,
        publish_mode,
        nats_enabled,
        nats_subject,
        nats_config_id,
        enabled
    ) VALUES (
        'test_nats_webhook',
        'https://example.com/webhook',
        'POST',
        'nats',
        true,
        'webhooks.test',
        (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
        true
    ) RETURNING webhook_id INTO v_webhook_id;

    PERFORM assert_not_null(
        '4.1 - Create NATS-enabled webhook',
        v_webhook_id
    );
END $$;

-- Test 4.2: Verify webhook NATS settings
DO $$
DECLARE
    v_nats_enabled BOOLEAN;
    v_publish_mode TEXT;
BEGIN
    SELECT nats_enabled, publish_mode INTO v_nats_enabled, v_publish_mode
    FROM rule_webhooks
    WHERE webhook_name = 'test_nats_webhook';

    PERFORM assert_true(
        '4.2a - Webhook nats_enabled is true',
        v_nats_enabled
    );

    PERFORM assert_equals(
        '4.2b - Webhook publish_mode is nats',
        'nats',
        v_publish_mode
    );
END $$;

-- Test 4.3: Create hybrid mode webhook
DO $$
DECLARE
    v_webhook_id INTEGER;
BEGIN
    INSERT INTO rule_webhooks (
        webhook_name,
        url,
        publish_mode,
        nats_enabled,
        nats_subject,
        enabled
    ) VALUES (
        'test_hybrid_webhook',
        'https://example.com/hybrid',
        'both',
        true,
        'webhooks.hybrid',
        true
    ) RETURNING webhook_id INTO v_webhook_id;

    PERFORM assert_not_null(
        '4.3 - Create hybrid mode webhook',
        v_webhook_id
    );
END $$;

-- Test 4.4: Test publish_mode constraint
DO $$
DECLARE
    v_error_occurred BOOLEAN := false;
BEGIN
    BEGIN
        INSERT INTO rule_webhooks (
            webhook_name,
            url,
            publish_mode
        ) VALUES (
            'test_invalid_mode',
            'https://example.com/invalid',
            'invalid_mode'
        );
    EXCEPTION WHEN check_violation THEN
        v_error_occurred := true;
    END;

    PERFORM assert_true(
        '4.4 - publish_mode constraint prevents invalid values',
        v_error_occurred
    );
END $$;

-- =============================================================================
-- Test 5: Consumer Statistics
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 5: Consumer Statistics ===';
END $$;

-- Test 5.1: Insert consumer stats
DO $$
DECLARE
    v_consumer_id INTEGER;
BEGIN
    INSERT INTO rule_nats_consumer_stats (
        stream_name,
        consumer_name,
        queue_group,
        ack_policy,
        max_deliver,
        active
    ) VALUES (
        'WEBHOOKS',
        'test-worker-1',
        'webhook-workers',
        'explicit',
        3,
        true
    ) RETURNING consumer_id INTO v_consumer_id;

    PERFORM assert_not_null(
        '5.1 - Insert consumer stats',
        v_consumer_id
    );
END $$;

-- Test 5.2: Update consumer stats
DO $$
BEGIN
    -- Simulate worker reporting stats
    UPDATE rule_nats_consumer_stats
    SET messages_delivered = 100,
        messages_acknowledged = 95,
        messages_pending = 5,
        avg_processing_time_ms = 45.5,
        last_active_at = NOW(),
        updated_at = NOW()
    WHERE consumer_name = 'test-worker-1';

    PERFORM assert_equals(
        '5.2 - Update consumer messages_acknowledged',
        95::BIGINT,
        (SELECT messages_acknowledged FROM rule_nats_consumer_stats WHERE consumer_name = 'test-worker-1')
    );
END $$;

-- Test 5.3: Test unique constraint (stream + consumer)
DO $$
DECLARE
    v_error_occurred BOOLEAN := false;
BEGIN
    BEGIN
        INSERT INTO rule_nats_consumer_stats (
            stream_name,
            consumer_name
        ) VALUES (
            'WEBHOOKS',
            'test-worker-1'
        );
    EXCEPTION WHEN unique_violation THEN
        v_error_occurred := true;
    END;

    PERFORM assert_true(
        '5.3 - Unique constraint on stream_name + consumer_name',
        v_error_occurred
    );
END $$;

-- =============================================================================
-- Test 6: Monitoring Views
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 6: Monitoring Views ===';
END $$;

-- Test 6.1: nats_publish_summary view exists
DO $$
BEGIN
    PERFORM assert_true(
        '6.1 - nats_publish_summary view exists',
        EXISTS (
            SELECT 1 FROM information_schema.views
            WHERE table_name = 'nats_publish_summary'
        )
    );
END $$;

-- Test 6.2: nats_recent_failures view exists
DO $$
BEGIN
    PERFORM assert_true(
        '6.2 - nats_recent_failures view exists',
        EXISTS (
            SELECT 1 FROM information_schema.views
            WHERE table_name = 'nats_recent_failures'
        )
    );
END $$;

-- Test 6.3: nats_performance_stats view exists
DO $$
BEGIN
    PERFORM assert_true(
        '6.3 - nats_performance_stats view exists',
        EXISTS (
            SELECT 1 FROM information_schema.views
            WHERE table_name = 'nats_performance_stats'
        )
    );
END $$;

-- Test 6.4: Query nats_publish_summary view
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM nats_publish_summary;

    PERFORM assert_not_null(
        '6.4 - Query nats_publish_summary view',
        v_count
    );
END $$;

-- =============================================================================
-- Test 7: Cleanup Functions
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 7: Cleanup Functions ===';
END $$;

-- Test 7.1: rule_nats_cleanup_old_history function exists
DO $$
BEGIN
    PERFORM assert_true(
        '7.1 - rule_nats_cleanup_old_history function exists',
        EXISTS (
            SELECT 1 FROM pg_proc
            WHERE proname = 'rule_nats_cleanup_old_history'
        )
    );
END $$;

-- Test 7.2: Test cleanup function (no old data yet)
DO $$
DECLARE
    v_deleted BIGINT;
BEGIN
    SELECT rule_nats_cleanup_old_history('1 day', true) INTO v_deleted;

    PERFORM assert_not_null(
        '7.2 - Cleanup function returns count',
        v_deleted
    );
END $$;

-- =============================================================================
-- Test 8: Data Integrity
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test 8: Data Integrity ===';
END $$;

-- Test 8.1: Foreign key from webhooks to nats_config
DO $$
DECLARE
    v_error_occurred BOOLEAN := false;
BEGIN
    BEGIN
        INSERT INTO rule_webhooks (
            webhook_name,
            url,
            nats_enabled,
            nats_config_id
        ) VALUES (
            'test_fk_webhook',
            'https://example.com',
            true,
            99999  -- Non-existent config_id
        );
    EXCEPTION WHEN foreign_key_violation THEN
        v_error_occurred := true;
    END;

    PERFORM assert_true(
        '8.1 - Foreign key constraint from webhooks to nats_config',
        v_error_occurred
    );
END $$;

-- Test 8.2: Cascade delete from nats_config
DO $$
DECLARE
    v_stream_count INTEGER;
    v_config_id INTEGER;
BEGIN
    -- Create config and stream
    INSERT INTO rule_nats_config (config_name, nats_url)
    VALUES ('test_cascade', 'nats://test:4222')
    RETURNING config_id INTO v_config_id;

    INSERT INTO rule_nats_streams (config_id, stream_name, subjects)
    VALUES (v_config_id, 'TEST_CASCADE', ARRAY['test.*']);

    -- Delete config
    DELETE FROM rule_nats_config WHERE config_id = v_config_id;

    -- Check stream was deleted
    SELECT COUNT(*) INTO v_stream_count
    FROM rule_nats_streams
    WHERE stream_name = 'TEST_CASCADE';

    PERFORM assert_equals(
        '8.2 - Cascade delete from nats_config to streams',
        0,
        v_stream_count
    );
END $$;

-- =============================================================================
-- Test Summary
-- =============================================================================

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test Summary ===';
END $$;

DO $$
DECLARE
    v_total INTEGER;
    v_passed INTEGER;
    v_failed INTEGER;
    v_success_rate NUMERIC;
BEGIN
    SELECT COUNT(*) INTO v_total FROM nats_test.test_results;
    SELECT COUNT(*) INTO v_passed FROM nats_test.test_results WHERE status = 'PASS';
    SELECT COUNT(*) INTO v_failed FROM nats_test.test_results WHERE status = 'FAIL';

    IF v_total > 0 THEN
        v_success_rate := ROUND((v_passed::NUMERIC / v_total::NUMERIC) * 100, 2);
    ELSE
        v_success_rate := 0;
    END IF;

    RAISE NOTICE 'Total Tests: %', v_total;
    RAISE NOTICE 'Passed: % (%.2f%%)', v_passed, v_success_rate;
    RAISE NOTICE 'Failed: %', v_failed;
    RAISE NOTICE '';

    IF v_failed > 0 THEN
        RAISE NOTICE 'Failed Tests:';
        FOR rec IN (SELECT test_name, message FROM nats_test.test_results WHERE status = 'FAIL') LOOP
            RAISE NOTICE '  - %: %', rec.test_name, rec.message;
        END LOOP;
    ELSE
        RAISE NOTICE '✅ ALL TESTS PASSED!';
    END IF;
END $$;

-- Display detailed results
SELECT
    test_number,
    test_name,
    status,
    message,
    executed_at
FROM nats_test.test_results
ORDER BY test_number;

-- Cleanup
DROP SCHEMA IF EXISTS nats_test CASCADE;

ROLLBACK;  -- Rollback all test changes

DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '=== Test Cleanup Complete ===';
END $$;
RAISE NOTICE 'All test changes have been rolled back.';
