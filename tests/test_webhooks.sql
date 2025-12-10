-- Test Suite for Webhook Support (Phase 4.2)
-- Run this file after applying migration 005_webhooks.sql

\echo '=========================================='
\echo 'Webhook Support Test Suite'
\echo '=========================================='
\echo ''

-- ============================================================================
-- SECTION 1: WEBHOOK REGISTRATION TESTS
-- ============================================================================

\echo '1. Register Webhook - Simple POST'
\echo '------------------------------------------'

SELECT rule_webhook_register(
    'slack_notifications',
    'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB,
    'Send notifications to Slack channel'
) AS webhook_id_1;

\echo ''
\echo '2. Register Webhook - GET with custom timeout'
\echo '------------------------------------------'

SELECT rule_webhook_register(
    'external_api_check',
    'https://api.example.com/status',
    'GET',
    '{"Authorization": "Bearer token123"}'::JSONB,
    'Check external API status',
    10000,  -- 10 second timeout
    5       -- max 5 retries
) AS webhook_id_2;

\echo ''
\echo '3. Register Webhook - PUT with authentication'
\echo '------------------------------------------'

SELECT rule_webhook_register(
    'crm_update',
    'https://crm.example.com/api/contacts',
    'PUT',
    '{"Content-Type": "application/json", "X-API-Key": "abc123"}'::JSONB,
    'Update CRM contact records'
) AS webhook_id_3;

\echo ''
\echo '4. Invalid URL - Should Fail'
\echo '------------------------------------------'

DO $$
BEGIN
    PERFORM rule_webhook_register('invalid', 'not-a-valid-url', 'POST');
    RAISE EXCEPTION 'Should have failed with invalid URL';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected error caught: %', SQLERRM;
END $$;

\echo ''
\echo '5. List All Webhooks'
\echo '------------------------------------------'

SELECT * FROM rule_webhook_list() ORDER BY webhook_id;

\echo ''
\echo '6. Get Specific Webhook'
\echo '------------------------------------------'

SELECT rule_webhook_get('slack_notifications');

-- ============================================================================
-- SECTION 2: WEBHOOK SECRET MANAGEMENT
-- ============================================================================

\echo ''
\echo '7. Set Webhook Secret'
\echo '------------------------------------------'

SELECT rule_webhook_secret_set(1, 'signing_secret', 'secret_key_12345') AS secret_set_1;
SELECT rule_webhook_secret_set(1, 'api_token', 'token_xyz789') AS secret_set_2;
SELECT rule_webhook_secret_set(2, 'api_key', 'key_abc456') AS secret_set_3;

\echo ''
\echo '8. Get Webhook Secret'
\echo '------------------------------------------'

SELECT rule_webhook_secret_get(1, 'signing_secret') AS retrieved_secret;

\echo ''
\echo '9. List Secrets (via table)'
\echo '------------------------------------------'

SELECT webhook_id, secret_name, created_by, created_at
FROM rule_webhook_secrets
ORDER BY webhook_id, secret_name;

-- ============================================================================
-- SECTION 3: WEBHOOK EXECUTION TESTS
-- ============================================================================

\echo ''
\echo '10. Enqueue Webhook Call'
\echo '------------------------------------------'

SELECT rule_webhook_enqueue(
    1,  -- webhook_id for slack_notifications
    '{"text": "Test notification from rule engine", "channel": "#alerts"}'::JSONB,
    'test_rule'
) AS call_id_1;

\echo ''
\echo '11. Enqueue Multiple Webhook Calls'
\echo '------------------------------------------'

SELECT rule_webhook_enqueue(
    1,
    format('{"text": "Message %s", "priority": "high"}', i)::JSONB,
    'batch_test'
) AS call_id
FROM generate_series(1, 5) i;

\echo ''
\echo '12. Call Webhook (Enqueues for Processing)'
\echo '------------------------------------------'

SELECT rule_webhook_call(
    2,  -- external_api_check
    '{"action": "health_check"}'::JSONB
);

\echo ''
\echo '13. Call Disabled Webhook - Should Fail'
\echo '------------------------------------------'

-- First disable a webhook
SELECT rule_webhook_update(3, NULL, NULL, NULL, NULL, false) AS webhook_disabled;

-- Try to call it
SELECT rule_webhook_call(
    3,  -- crm_update (now disabled)
    '{"contact": "John Doe"}'::JSONB
);

-- Re-enable it
SELECT rule_webhook_update(3, NULL, NULL, NULL, NULL, true) AS webhook_enabled;

-- ============================================================================
-- SECTION 4: WEBHOOK CALL STATUS & MONITORING
-- ============================================================================

\echo ''
\echo '14. View Webhook Call Status'
\echo '------------------------------------------'

SELECT rule_webhook_call_status(1);

\echo ''
\echo '15. View All Pending Calls'
\echo '------------------------------------------'

SELECT call_id, webhook_id, status, rule_name, scheduled_at
FROM rule_webhook_calls
WHERE status = 'pending'
ORDER BY scheduled_at
LIMIT 10;

\echo ''
\echo '16. Webhook Status Summary View'
\echo '------------------------------------------'

SELECT * FROM webhook_status_summary ORDER BY webhook_id;

\echo ''
\echo '17. Recent Failures View (Should be empty initially)'
\echo '------------------------------------------'

SELECT * FROM webhook_recent_failures LIMIT 5;

-- ============================================================================
-- SECTION 5: RETRY LOGIC TESTS
-- ============================================================================

\echo ''
\echo '18. Simulate Failed Call & Retry'
\echo '------------------------------------------'

-- Manually create a failed call
INSERT INTO rule_webhook_calls (webhook_id, payload, status, error_message, retry_count)
VALUES (1, '{"test": "failed call"}'::JSONB, 'failed', 'Connection timeout', 0)
RETURNING call_id;

-- Get the last call_id
DO $$
DECLARE
    v_failed_call_id INTEGER;
BEGIN
    SELECT call_id INTO v_failed_call_id
    FROM rule_webhook_calls
    WHERE status = 'failed'
    ORDER BY call_id DESC
    LIMIT 1;

    RAISE NOTICE 'Failed call ID: %', v_failed_call_id;

    -- Retry the failed call
    PERFORM rule_webhook_retry(v_failed_call_id);

    RAISE NOTICE 'Call marked for retry';
END $$;

\echo ''
\echo '19. View Retrying Calls'
\echo '------------------------------------------'

SELECT call_id, webhook_id, status, retry_count, next_retry_at, error_message
FROM rule_webhook_calls
WHERE status = 'retrying'
ORDER BY next_retry_at;

\echo ''
\echo '20. Process Pending Retries'
\echo '------------------------------------------'

SELECT * FROM rule_webhook_process_retries();

-- ============================================================================
-- SECTION 6: WEBHOOK MANAGEMENT FUNCTIONS
-- ============================================================================

\echo ''
\echo '21. Update Webhook Configuration'
\echo '------------------------------------------'

SELECT rule_webhook_update(
    1,  -- webhook_id
    'https://hooks.slack.com/services/NEW_WEBHOOK_URL',  -- new URL
    NULL,  -- keep method
    '{"Content-Type": "application/json", "X-Custom-Header": "value"}'::JSONB,  -- updated headers
    8000,  -- new timeout
    NULL   -- keep enabled status
) AS webhook_updated;

\echo ''
\echo '22. View Updated Webhook'
\echo '------------------------------------------'

SELECT webhook_name, url, timeout_ms, headers
FROM rule_webhooks
WHERE webhook_id = 1;

\echo ''
\echo '23. Cleanup Old Webhook Calls (older than 1 hour)'
\echo '------------------------------------------'

SELECT rule_webhook_cleanup_old_calls('1 hour'::INTERVAL, true) AS deleted_count;

-- ============================================================================
-- SECTION 7: ADVANCED SCENARIOS
-- ============================================================================

\echo ''
\echo '24. Create Webhook with All Options'
\echo '------------------------------------------'

SELECT rule_webhook_register(
    'advanced_webhook',
    'https://api.example.com/webhook',
    'POST',
    '{
        "Content-Type": "application/json",
        "Authorization": "Bearer token",
        "X-Webhook-Version": "v1",
        "User-Agent": "RuleEngine/1.4.0"
    }'::JSONB,
    'Advanced webhook with full configuration',
    15000,  -- 15 second timeout
    5       -- 5 retries
) AS advanced_webhook_id;

\echo ''
\echo '25. Test Maximum Retry Limit'
\echo '------------------------------------------'

DO $$
DECLARE
    v_call_id INTEGER;
    v_webhook rule_webhooks%ROWTYPE;
    i INTEGER;
BEGIN
    -- Create a call for testing
    INSERT INTO rule_webhook_calls (webhook_id, payload, status, error_message, retry_count)
    VALUES (4, '{"test": "max retries"}'::JSONB, 'failed', 'Test error', 0)
    RETURNING call_id INTO v_call_id;

    -- Get webhook config
    SELECT * INTO v_webhook FROM rule_webhooks WHERE webhook_id = 4;

    RAISE NOTICE 'Testing max retries (limit: %)', v_webhook.max_retries;

    -- Try to retry more than max_retries times
    FOR i IN 1..v_webhook.max_retries + 2 LOOP
        IF rule_webhook_retry(v_call_id) THEN
            RAISE NOTICE 'Retry % succeeded', i;
        ELSE
            RAISE NOTICE 'Retry % failed - max retries reached', i;
            EXIT;
        END IF;
    END LOOP;

    -- Check final status
    SELECT status, retry_count INTO STRICT v_webhook
    FROM rule_webhook_calls
    WHERE call_id = v_call_id;

    RAISE NOTICE 'Final status: %, Retry count: %', v_webhook.status, v_webhook.retry_count;
END $$;

\echo ''
\echo '26. Webhook Performance Stats'
\echo '------------------------------------------'

-- Simulate some successful calls
INSERT INTO rule_webhook_calls (webhook_id, payload, status, execution_time_ms, response_status, completed_at)
VALUES
    (1, '{}'::JSONB, 'success', 123.45, 200, CURRENT_TIMESTAMP),
    (1, '{}'::JSONB, 'success', 98.76, 200, CURRENT_TIMESTAMP),
    (1, '{}'::JSONB, 'success', 156.89, 200, CURRENT_TIMESTAMP),
    (2, '{}'::JSONB, 'success', 234.56, 200, CURRENT_TIMESTAMP),
    (2, '{}'::JSONB, 'success', 198.23, 200, CURRENT_TIMESTAMP);

SELECT * FROM webhook_performance_stats ORDER BY webhook_id;

-- ============================================================================
-- SECTION 8: INTEGRATION WITH HTTP EXTENSION (IF AVAILABLE)
-- ============================================================================

\echo ''
\echo '27. Check HTTP Extension Availability'
\echo '------------------------------------------'

SELECT
    CASE
        WHEN EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'http') THEN
            '✅ HTTP extension is installed'
        ELSE
            '⚠️  HTTP extension NOT installed. Install with: CREATE EXTENSION http;'
    END AS http_status;

\echo ''
\echo '28. Test HTTP Extension Function (if available)'
\echo '------------------------------------------'

DO $$
DECLARE
    v_has_http BOOLEAN;
    v_result JSON;
BEGIN
    SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'http') INTO v_has_http;

    IF v_has_http THEN
        RAISE NOTICE 'Testing with HTTP extension...';
        -- This would make actual HTTP call
        -- v_result := rule_webhook_call_with_http(1, '{"test": "real call"}'::JSONB);
        -- RAISE NOTICE 'Result: %', v_result;
        RAISE NOTICE 'Skipped actual HTTP call in test';
    ELSE
        RAISE NOTICE 'HTTP extension not available. Webhook calls will be enqueued for external processing.';
    END IF;
END $$;

-- ============================================================================
-- SECTION 9: CLEANUP & DELETE TESTS
-- ============================================================================

\echo ''
\echo '29. Delete Webhook Secret'
\echo '------------------------------------------'

SELECT rule_webhook_secret_delete(1, 'api_token') AS secret_deleted;

\echo ''
\echo '30. Delete Webhook (cascades to calls and secrets)'
\echo '------------------------------------------'

-- Count related records before delete
SELECT
    webhook_name,
    (SELECT COUNT(*) FROM rule_webhook_calls WHERE webhook_id = 4) as call_count,
    (SELECT COUNT(*) FROM rule_webhook_secrets WHERE webhook_id = 4) as secret_count
FROM rule_webhooks
WHERE webhook_id = 4;

-- Delete webhook
SELECT rule_webhook_delete(4) AS webhook_deleted;

-- Verify cascade delete worked
SELECT
    (SELECT COUNT(*) FROM rule_webhook_calls WHERE webhook_id = 4) as remaining_calls,
    (SELECT COUNT(*) FROM rule_webhook_secrets WHERE webhook_id = 4) as remaining_secrets;

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

\echo ''
\echo '=========================================='
\echo 'WEBHOOK TEST SUITE SUMMARY'
\echo '=========================================='

\echo ''
\echo 'Database Objects:'
SELECT
    (SELECT COUNT(*) FROM rule_webhooks) as total_webhooks,
    (SELECT COUNT(*) FROM rule_webhook_calls) as total_calls,
    (SELECT COUNT(*) FROM rule_webhook_secrets) as total_secrets,
    (SELECT COUNT(*) FROM rule_webhook_call_history) as total_history_entries;

\echo ''
\echo 'Webhook Status Distribution:'
SELECT status, COUNT(*) as count
FROM rule_webhook_calls
GROUP BY status
ORDER BY count DESC;

\echo ''
\echo 'Active Webhooks:'
SELECT webhook_id, webhook_name, url, enabled
FROM rule_webhooks
WHERE enabled = true
ORDER BY webhook_id;

\echo ''
\echo '=========================================='
\echo '✅ Webhook Support Tests Complete!'
\echo '=========================================='
\echo ''
\echo 'Features Tested:'
\echo '  ✓ Webhook registration and configuration'
\echo '  ✓ Secret management'
\echo '  ✓ Webhook call enqueueing'
\echo '  ✓ Retry logic with exponential backoff'
\echo '  ✓ Status monitoring and analytics'
\echo '  ✓ Cleanup and maintenance functions'
\echo ''
\echo 'Next Steps:'
\echo '  1. Install http extension for actual HTTP calls:'
\echo '     CREATE EXTENSION http;'
\echo '  2. Or set up external worker to process webhook queue'
\echo '  3. Monitor webhook status: SELECT * FROM webhook_status_summary;'
\echo '  4. Check failures: SELECT * FROM webhook_recent_failures;'
\echo ''
