-- =============================================================================
-- NATS Integration Example 2: Fan-Out Pattern
-- =============================================================================
-- This example demonstrates publishing one event to multiple webhooks
-- using NATS subject patterns
--
-- Use Case: User registration triggers notifications to multiple services
-- - Slack notification
-- - Email service
-- - Analytics tracking
-- - CRM update

-- =============================================================================
-- Step 1: Initialize NATS
-- =============================================================================

SELECT rule_nats_init('default');

-- =============================================================================
-- Step 2: Create Multiple Webhooks with Subject Hierarchy
-- =============================================================================

-- Webhook 1: Slack notification
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
    'slack_user_registration',
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    'POST',
    'nats',
    true,
    'webhooks.user.registered.slack',  -- Specific subject
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    true
);

-- Webhook 2: Email service
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
    'email_welcome',
    'https://api.sendgrid.com/v3/mail/send',
    'POST',
    'nats',
    true,
    'webhooks.user.registered.email',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    true
);

-- Webhook 3: Analytics tracking
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
    'analytics_user_event',
    'https://analytics.example.com/track',
    'POST',
    'nats',
    true,
    'webhooks.user.registered.analytics',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    true
);

-- Webhook 4: CRM update
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
    'crm_contact_create',
    'https://api.salesforce.com/services/data/v58.0/sobjects/Contact',
    'POST',
    'nats',
    true,
    'webhooks.user.registered.crm',
    (SELECT config_id FROM rule_nats_config WHERE config_name = 'default'),
    true
);

-- =============================================================================
-- Step 3: Configure Workers to Subscribe to Patterns
-- =============================================================================

-- Worker configuration examples:
--
-- Worker 1 - Subscribe to ALL user.registered events:
--   SUBJECT=webhooks.user.registered.*
--
-- Worker 2 - Subscribe to ALL webhooks:
--   SUBJECT=webhooks.>
--
-- Worker 3 - Subscribe only to slack and email:
--   Use two separate workers or filter in code

-- =============================================================================
-- Step 4: Create Helper Function to Publish to All
-- =============================================================================

CREATE OR REPLACE FUNCTION notify_user_registered(
    p_user_id INTEGER,
    p_email TEXT,
    p_name TEXT,
    p_signup_date TIMESTAMPTZ DEFAULT NOW()
)
RETURNS jsonb AS $$
DECLARE
    v_payload jsonb;
    v_webhook RECORD;
    v_results jsonb := '[]'::jsonb;
    v_result jsonb;
BEGIN
    -- Build common payload
    v_payload := jsonb_build_object(
        'event', 'user.registered',
        'user_id', p_user_id,
        'email', p_email,
        'name', p_name,
        'signup_date', p_signup_date,
        'timestamp', NOW()
    );

    -- Publish to all user.registered webhooks
    FOR v_webhook IN
        SELECT webhook_id, webhook_name, nats_subject
        FROM rule_webhooks
        WHERE nats_enabled = true
          AND nats_subject LIKE 'webhooks.user.registered.%'
          AND enabled = true
    LOOP
        -- Publish to NATS
        SELECT rule_webhook_publish_nats(
            v_webhook.webhook_id,
            v_payload,
            format('user-reg-%s-%s', p_user_id, v_webhook.webhook_name)
        ) INTO v_result;

        -- Collect results
        v_results := v_results || jsonb_build_object(
            'webhook', v_webhook.webhook_name,
            'subject', v_webhook.nats_subject,
            'result', v_result
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'webhooks_triggered', jsonb_array_length(v_results),
        'results', v_results
    );
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Step 5: Trigger Fan-Out
-- =============================================================================

-- Simulate user registration
SELECT notify_user_registered(
    123,                              -- user_id
    'john.doe@example.com',           -- email
    'John Doe',                       -- name
    NOW()                             -- signup_date
);

-- Expected output:
-- {
--   "success": true,
--   "webhooks_triggered": 4,
--   "results": [
--     {
--       "webhook": "slack_user_registration",
--       "subject": "webhooks.user.registered.slack",
--       "result": { "success": true, "sequence": 1, ... }
--     },
--     {
--       "webhook": "email_welcome",
--       "subject": "webhooks.user.registered.email",
--       "result": { "success": true, "sequence": 2, ... }
--     },
--     ...
--   ]
-- }

-- =============================================================================
-- Step 6: Integrate with Triggers
-- =============================================================================

-- Create users table (example)
CREATE TABLE IF NOT EXISTS users (
    user_id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create trigger function
CREATE OR REPLACE FUNCTION trigger_user_registered()
RETURNS TRIGGER AS $$
BEGIN
    -- Asynchronously notify via NATS
    PERFORM notify_user_registered(
        NEW.user_id,
        NEW.email,
        NEW.name,
        NEW.created_at
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger
CREATE TRIGGER user_after_insert
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION trigger_user_registered();

-- =============================================================================
-- Step 7: Test the Complete Flow
-- =============================================================================

-- Insert a new user (triggers fan-out automatically)
INSERT INTO users (email, name)
VALUES ('jane.smith@example.com', 'Jane Smith')
RETURNING *;

-- Check that all 4 webhooks were triggered
SELECT
    w.webhook_name,
    h.subject,
    h.sequence_number,
    h.success,
    h.latency_ms,
    h.published_at
FROM rule_nats_publish_history h
JOIN rule_webhooks w ON h.webhook_id = w.webhook_id
WHERE h.published_at >= NOW() - INTERVAL '1 minute'
ORDER BY h.published_at DESC;

-- =============================================================================
-- Step 8: Monitor Fan-Out Performance
-- =============================================================================

-- Summary across all webhooks
SELECT
    COUNT(DISTINCT webhook_id) as total_webhooks,
    COUNT(*) as total_messages,
    COUNT(*) FILTER (WHERE success = true) as successful,
    ROUND(AVG(latency_ms), 2) as avg_latency_ms,
    MAX(published_at) as last_published
FROM rule_nats_publish_history
WHERE subject LIKE 'webhooks.user.registered.%'
  AND published_at >= NOW() - INTERVAL '1 hour';

-- Performance by webhook
SELECT
    webhook_name,
    subject,
    total_published,
    successful,
    failed,
    success_rate_pct,
    avg_latency_ms
FROM nats_publish_summary
WHERE subject LIKE 'webhooks.user.registered.%'
ORDER BY avg_latency_ms ASC;

-- =============================================================================
-- Advanced: Conditional Fan-Out
-- =============================================================================

-- Only trigger certain webhooks based on conditions
CREATE OR REPLACE FUNCTION notify_user_registered_conditional(
    p_user_id INTEGER,
    p_email TEXT,
    p_name TEXT,
    p_user_type TEXT  -- 'premium', 'free', etc.
)
RETURNS jsonb AS $$
DECLARE
    v_payload jsonb;
    v_result jsonb;
    v_results jsonb := '[]'::jsonb;
BEGIN
    v_payload := jsonb_build_object(
        'event', 'user.registered',
        'user_id', p_user_id,
        'email', p_email,
        'name', p_name,
        'user_type', p_user_type
    );

    -- Always notify Slack
    SELECT rule_webhook_publish_nats(
        (SELECT webhook_id FROM rule_webhooks WHERE webhook_name = 'slack_user_registration'),
        v_payload,
        format('user-reg-%s-slack', p_user_id)
    ) INTO v_result;
    v_results := v_results || v_result;

    -- Only notify CRM for premium users
    IF p_user_type = 'premium' THEN
        SELECT rule_webhook_publish_nats(
            (SELECT webhook_id FROM rule_webhooks WHERE webhook_name = 'crm_contact_create'),
            v_payload,
            format('user-reg-%s-crm', p_user_id)
        ) INTO v_result;
        v_results := v_results || v_result;
    END IF;

    -- Always send welcome email
    SELECT rule_webhook_publish_nats(
        (SELECT webhook_id FROM rule_webhooks WHERE webhook_name = 'email_welcome'),
        v_payload,
        format('user-reg-%s-email', p_user_id)
    ) INTO v_result;
    v_results := v_results || v_result;

    RETURN jsonb_build_object('success', true, 'results', v_results);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Cleanup (Optional)
-- =============================================================================

-- DROP TRIGGER IF EXISTS user_after_insert ON users;
-- DROP FUNCTION IF EXISTS trigger_user_registered();
-- DROP FUNCTION IF EXISTS notify_user_registered(INTEGER, TEXT, TEXT, TIMESTAMPTZ);
-- DROP FUNCTION IF EXISTS notify_user_registered_conditional(INTEGER, TEXT, TEXT, TEXT);
-- DROP TABLE IF EXISTS users;

-- =============================================================================
-- Notes:
-- =============================================================================
--
-- 1. Subject Hierarchy:
--    webhooks.user.registered.*    - All user registration events
--    webhooks.user.*               - All user events
--    webhooks.>                    - All webhook events
--
-- 2. Performance:
--    - NATS delivers messages in parallel to all subscribers
--    - Much faster than sequential HTTP calls
--    - Workers can scale horizontally
--
-- 3. Reliability:
--    - If one webhook fails, others still succeed
--    - Failed messages are retried independently
--    - No cascading failures
--
-- 4. Best Practices:
--    - Use meaningful subject hierarchies
--    - Include message IDs for deduplication
--    - Monitor per-webhook statistics
--    - Use conditional logic for business rules
--
-- =============================================================================
