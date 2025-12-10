# Webhook Support (Phase 4.2, v1.5.0)

**Status:** ✅ Complete
**Version:** 1.5.0
**Released:** December 10, 2025

## Overview

Webhook support enables the rule engine to make HTTP callouts from rule actions, allowing integration with external systems, APIs, and services. This feature includes webhook registration, secret management, retry logic with exponential backoff, and comprehensive monitoring.

---

## Features

### ✅ Webhook Management
- Register webhooks with full configuration (URL, method, headers, timeout)
- Support for all HTTP methods (GET, POST, PUT, PATCH, DELETE)
- Custom headers and authentication
- Enable/disable webhooks without deletion
- Webhook categorization with tags

### ✅ Secret Management
- Secure storage of API keys and tokens
- Per-webhook secret management
- Easy secret rotation

### ✅ Retry Logic
- Automatic retry on failures
- Exponential backoff strategy
- Configurable max retries and delay
- Retry queue processing

### ✅ Monitoring & Analytics
- Real-time status tracking
- Success/failure rates
- Performance metrics (avg, min, max, percentiles)
- Recent failures view
- Call history with full audit trail

### ✅ Queue-Based Processing
- Asynchronous webhook execution
- Batch processing support
- External worker integration
- HTTP extension support

---

## Architecture

### Processing Options

#### Option 1: HTTP Extension (Recommended for simple use cases)
```sql
-- Install HTTP extension
CREATE EXTENSION http;

-- Use http-enabled function
SELECT rule_webhook_call_with_http(webhook_id, payload);
```

#### Option 2: Queue + External Worker (Recommended for production)
```
PostgreSQL → Queue (rule_webhook_calls table)
              ↓
         External Worker (Node.js, Python, Go, etc.)
              ↓
         External API/Service
              ↓
         Update call status in PostgreSQL
```

---

## Database Schema

### Tables

#### `rule_webhooks`
Webhook endpoint configurations
```sql
CREATE TABLE rule_webhooks (
    webhook_id SERIAL PRIMARY KEY,
    webhook_name TEXT NOT NULL UNIQUE,
    description TEXT,
    url TEXT NOT NULL,
    method TEXT DEFAULT 'POST',
    headers JSONB DEFAULT '{}',
    timeout_ms INTEGER DEFAULT 5000,
    retry_enabled BOOLEAN DEFAULT true,
    max_retries INTEGER DEFAULT 3,
    retry_delay_ms INTEGER DEFAULT 1000,
    retry_backoff_multiplier NUMERIC DEFAULT 2.0,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}'
);
```

#### `rule_webhook_secrets`
Encrypted secrets for webhooks
```sql
CREATE TABLE rule_webhook_secrets (
    secret_id SERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,
    secret_name TEXT NOT NULL,
    secret_value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    UNIQUE(webhook_id, secret_name)
);
```

#### `rule_webhook_calls`
Queue and history of webhook calls
```sql
CREATE TABLE rule_webhook_calls (
    call_id SERIAL PRIMARY KEY,
    webhook_id INTEGER REFERENCES rule_webhooks(webhook_id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending',
    payload JSONB NOT NULL,
    rule_name TEXT,
    rule_execution_id BIGINT,
    scheduled_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMPTZ,
    response_status INTEGER,
    response_body TEXT,
    response_headers JSONB,
    error_message TEXT,
    execution_time_ms NUMERIC,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### `rule_webhook_call_history`
Detailed history of all attempts including retries
```sql
CREATE TABLE rule_webhook_call_history (
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
```

---

## API Reference

### Webhook Registration

#### `rule_webhook_register()`
Registers a new webhook endpoint.

```sql
rule_webhook_register(
    p_name TEXT,
    p_url TEXT,
    p_method TEXT DEFAULT 'POST',
    p_headers JSONB DEFAULT '{}'::JSONB,
    p_description TEXT DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT 5000,
    p_max_retries INTEGER DEFAULT 3
) RETURNS INTEGER
```

**Example:**
```sql
-- Register Slack webhook
SELECT rule_webhook_register(
    'slack_notifications',
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB,
    'Send notifications to Slack #alerts channel',
    10000,  -- 10 second timeout
    5       -- max 5 retries
);

-- Register API webhook with authentication
SELECT rule_webhook_register(
    'crm_api',
    'https://api.crm.com/contacts',
    'POST',
    '{
        "Content-Type": "application/json",
        "Authorization": "Bearer YOUR_TOKEN",
        "X-API-Version": "v2"
    }'::JSONB,
    'Update CRM contacts'
);
```

**Returns:** `webhook_id` (INTEGER)

---

#### `rule_webhook_update()`
Updates webhook configuration.

```sql
rule_webhook_update(
    p_webhook_id INTEGER,
    p_url TEXT DEFAULT NULL,
    p_method TEXT DEFAULT NULL,
    p_headers JSONB DEFAULT NULL,
    p_timeout_ms INTEGER DEFAULT NULL,
    p_enabled BOOLEAN DEFAULT NULL
) RETURNS BOOLEAN
```

**Example:**
```sql
-- Update webhook URL
SELECT rule_webhook_update(
    1,
    'https://new-url.com/webhook',
    NULL, NULL, NULL, NULL
);

-- Disable webhook
SELECT rule_webhook_update(
    1, NULL, NULL, NULL, NULL, false
);
```

---

#### `rule_webhook_delete()`
Deletes a webhook (cascades to calls and secrets).

```sql
rule_webhook_delete(p_webhook_id INTEGER) RETURNS BOOLEAN
```

**Example:**
```sql
SELECT rule_webhook_delete(1);
```

---

#### `rule_webhook_list()`
Lists all webhooks with statistics.

```sql
rule_webhook_list(p_enabled_only BOOLEAN DEFAULT false)
RETURNS TABLE (
    webhook_id INTEGER,
    webhook_name TEXT,
    url TEXT,
    method TEXT,
    enabled BOOLEAN,
    total_calls BIGINT,
    success_rate NUMERIC,
    created_at TIMESTAMPTZ
)
```

**Example:**
```sql
-- List all webhooks
SELECT * FROM rule_webhook_list();

-- List only enabled webhooks
SELECT * FROM rule_webhook_list(true);
```

---

#### `rule_webhook_get()`
Gets webhook configuration by ID or name.

```sql
rule_webhook_get(p_identifier TEXT) RETURNS JSON
```

**Example:**
```sql
-- By name
SELECT rule_webhook_get('slack_notifications');

-- By ID
SELECT rule_webhook_get('1');
```

---

### Secret Management

#### `rule_webhook_secret_set()`
Sets a secret for a webhook.

```sql
rule_webhook_secret_set(
    p_webhook_id INTEGER,
    p_secret_name TEXT,
    p_secret_value TEXT
) RETURNS BOOLEAN
```

**Example:**
```sql
-- Set API key
SELECT rule_webhook_secret_set(1, 'api_key', 'your-secret-key-here');

-- Set signing secret
SELECT rule_webhook_secret_set(1, 'signing_secret', 'hmac-secret-123');
```

**Note:** In production, encrypt `secret_value` before storing!

---

#### `rule_webhook_secret_get()`
Gets a secret value (use carefully!).

```sql
rule_webhook_secret_get(
    p_webhook_id INTEGER,
    p_secret_name TEXT
) RETURNS TEXT
```

**Example:**
```sql
SELECT rule_webhook_secret_get(1, 'api_key');
```

**Warning:** This function is `SECURITY DEFINER`. Restrict access!

---

#### `rule_webhook_secret_delete()`
Removes a secret.

```sql
rule_webhook_secret_delete(
    p_webhook_id INTEGER,
    p_secret_name TEXT
) RETURNS BOOLEAN
```

**Example:**
```sql
SELECT rule_webhook_secret_delete(1, 'old_api_key');
```

---

### Webhook Execution

#### `rule_webhook_call()`
Enqueues a webhook call for processing.

```sql
rule_webhook_call(
    p_webhook_id INTEGER,
    p_payload JSONB
) RETURNS JSON
```

**Example:**
```sql
-- Send notification
SELECT rule_webhook_call(
    1,
    '{
        "text": "Alert: High CPU usage detected",
        "severity": "warning",
        "timestamp": "2025-12-10T10:00:00Z"
    }'::JSONB
);

-- Returns:
-- {
--   "success": true,
--   "call_id": 123,
--   "status": "enqueued",
--   "webhook_name": "slack_notifications",
--   "url": "https://hooks.slack.com/...",
--   "message": "Webhook call enqueued..."
-- }
```

---

#### `rule_webhook_enqueue()`
Enqueues a webhook call with scheduling.

```sql
rule_webhook_enqueue(
    p_webhook_id INTEGER,
    p_payload JSONB,
    p_rule_name TEXT DEFAULT NULL,
    p_scheduled_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
) RETURNS INTEGER
```

**Example:**
```sql
-- Schedule for immediate processing
SELECT rule_webhook_enqueue(
    1,
    '{"message": "Test"}'::JSONB,
    'my_rule_name'
);

-- Schedule for later (5 minutes from now)
SELECT rule_webhook_enqueue(
    1,
    '{"message": "Delayed notification"}'::JSONB,
    'scheduled_rule',
    CURRENT_TIMESTAMP + INTERVAL '5 minutes'
);
```

---

#### `rule_webhook_call_with_http()`
Makes actual HTTP call using `http` extension.

```sql
rule_webhook_call_with_http(
    p_webhook_id INTEGER,
    p_payload JSONB
) RETURNS JSON
```

**Requires:** `CREATE EXTENSION http;`

**Example:**
```sql
-- Make actual HTTP call
SELECT rule_webhook_call_with_http(
    1,
    '{"text": "Real HTTP call"}'::JSONB
);

-- Returns:
-- {
--   "success": true,
--   "call_id": 124,
--   "status": 200,
--   "response": "{\"ok\": true}",
--   "execution_time_ms": 123.45
-- }
```

---

### Retry & Recovery

#### `rule_webhook_retry()`
Marks a failed call for retry.

```sql
rule_webhook_retry(p_call_id INTEGER) RETURNS BOOLEAN
```

**Example:**
```sql
-- Retry failed call
SELECT rule_webhook_retry(123);
```

**Retry Logic:**
- Uses exponential backoff
- Respects `max_retries` setting
- Calculates delay: `retry_delay_ms * (backoff_multiplier ^ retry_count)`

---

#### `rule_webhook_process_retries()`
Processes pending retries (called by scheduler/cron).

```sql
rule_webhook_process_retries()
RETURNS TABLE (
    call_id INTEGER,
    webhook_name TEXT,
    retry_result JSON
)
```

**Example:**
```sql
-- Process all pending retries
SELECT * FROM rule_webhook_process_retries();
```

**Setup with pg_cron:**
```sql
-- Install pg_cron
CREATE EXTENSION pg_cron;

-- Schedule retry processor every minute
SELECT cron.schedule(
    'process-webhook-retries',
    '*/1 * * * *',  -- Every minute
    $$SELECT rule_webhook_process_retries()$$
);
```

---

### Monitoring

#### `rule_webhook_call_status()`
Gets the status of a webhook call.

```sql
rule_webhook_call_status(p_call_id INTEGER) RETURNS JSON
```

**Example:**
```sql
SELECT rule_webhook_call_status(123);

-- Returns:
-- {
--   "call_id": 123,
--   "webhook_name": "slack_notifications",
--   "url": "https://hooks.slack.com/...",
--   "status": "success",
--   "retry_count": 0,
--   "payload": {...},
--   "response_status": 200,
--   "response_body": "{\"ok\": true}",
--   "execution_time_ms": 123.45,
--   "scheduled_at": "2025-12-10T10:00:00Z",
--   "started_at": "2025-12-10T10:00:01Z",
--   "completed_at": "2025-12-10T10:00:01.123Z",
--   "attempts": [...]
-- }
```

---

### Views

#### `webhook_status_summary`
Summary of webhook call statuses.

```sql
SELECT * FROM webhook_status_summary;
```

**Columns:**
- `webhook_id`, `webhook_name`, `url`, `enabled`
- `total_calls`, `successful_calls`, `failed_calls`, `pending_calls`, `retrying_calls`
- `avg_execution_time_ms`, `last_call_at`, `success_rate_pct`

---

#### `webhook_recent_failures`
Recent failed webhook calls for debugging.

```sql
SELECT * FROM webhook_recent_failures LIMIT 10;
```

**Columns:**
- `call_id`, `webhook_name`, `url`, `status`, `retry_count`
- `error_message`, `response_status`, `payload`
- `created_at`, `completed_at`

---

#### `webhook_performance_stats`
Performance statistics per webhook.

```sql
SELECT * FROM webhook_performance_stats;
```

**Columns:**
- `webhook_id`, `webhook_name`, `total_calls`
- `avg_time_ms`, `min_time_ms`, `max_time_ms`
- `p50_time_ms`, `p95_time_ms`, `p99_time_ms`

---

### Maintenance

#### `rule_webhook_cleanup_old_calls()`
Removes old webhook call records.

```sql
rule_webhook_cleanup_old_calls(
    p_older_than INTERVAL DEFAULT '30 days',
    p_keep_failed BOOLEAN DEFAULT true
) RETURNS BIGINT
```

**Example:**
```sql
-- Cleanup calls older than 7 days (keep failed ones)
SELECT rule_webhook_cleanup_old_calls('7 days', true);

-- Cleanup all calls older than 30 days
SELECT rule_webhook_cleanup_old_calls('30 days', false);
```

---

## Usage Examples

### Example 1: Slack Notifications

```sql
-- 1. Register Slack webhook
SELECT rule_webhook_register(
    'slack_alerts',
    'https://hooks.slack.com/services/T00/B00/XXX',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB,
    'Send alerts to #engineering channel'
) AS webhook_id;

-- 2. Send notification
SELECT rule_webhook_call(
    1,  -- webhook_id
    '{
        "text": "🚨 High error rate detected!",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": "*Error Rate Alert*\nError rate exceeded 5% threshold"
                }
            }
        ]
    }'::JSONB
);

-- 3. Monitor status
SELECT * FROM webhook_status_summary WHERE webhook_name = 'slack_alerts';
```

---

### Example 2: CRM Integration with Retry

```sql
-- 1. Register CRM webhook with retry config
SELECT rule_webhook_register(
    'crm_contact_update',
    'https://api.crm.com/v2/contacts',
    'PUT',
    '{
        "Content-Type": "application/json",
        "Authorization": "Bearer YOUR_TOKEN"
    }'::JSONB,
    'Update CRM contact records',
    15000,  -- 15 second timeout
    5       -- max 5 retries
);

-- 2. Set secret
SELECT rule_webhook_secret_set(1, 'api_token', 'your-secret-token');

-- 3. Update contact
SELECT rule_webhook_call(
    1,
    '{
        "id": "contact_12345",
        "email": "john@example.com",
        "status": "qualified",
        "updated_by": "rule_engine"
    }'::JSONB
);

-- 4. Check if retry is needed
SELECT call_id, status, retry_count, error_message
FROM rule_webhook_calls
WHERE webhook_id = 1
ORDER BY created_at DESC
LIMIT 5;
```

---

### Example 3: Batch Processing

```sql
-- Enqueue multiple webhook calls
DO $$
DECLARE
    v_webhook_id INTEGER := 1;
    v_user RECORD;
BEGIN
    FOR v_user IN SELECT * FROM users WHERE created_at > NOW() - INTERVAL '1 day'
    LOOP
        PERFORM rule_webhook_enqueue(
            v_webhook_id,
            jsonb_build_object(
                'user_id', v_user.id,
                'email', v_user.email,
                'action', 'welcome_email'
            ),
            'user_onboarding'
        );
    END LOOP;
END $$;

-- Monitor batch progress
SELECT
    status,
    COUNT(*) as count,
    AVG(execution_time_ms) as avg_time
FROM rule_webhook_calls
WHERE rule_name = 'user_onboarding'
GROUP BY status;
```

---

### Example 4: Integration with Rules

Create a rule that calls a webhook:

```sql
-- 1. Register webhook
SELECT rule_webhook_register(
    'order_notification',
    'https://api.notifications.com/send',
    'POST',
    '{"Content-Type": "application/json"}'::JSONB
);

-- 2. Create rule that uses webhook
SELECT rule_save(
    'high_value_order',
    'rule HighValueOrder "Notify on high value orders" salience 10 {
        when
            Order.total > 10000
        then
            // This would be handled by external worker or custom function
            Notification.webhook_id = 1;
            Notification.payload = {
                "order_id": Order.id,
                "total": Order.total,
                "customer": Order.customer
            };
            Retract("HighValueOrder");
    }',
    '1.0.0',
    'Webhook notification for high-value orders'
);

-- 3. In your application, after rule execution:
-- Extract webhook calls from results and enqueue them
```

---

## External Worker Setup

### Node.js Worker Example

```javascript
const { Pool } = require('pg');
const axios = require('axios');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

async function processWebhookQueue() {
  const client = await pool.connect();

  try {
    // Get pending calls
    const { rows } = await client.query(`
      SELECT c.call_id, c.payload, w.url, w.method, w.headers, w.timeout_ms
      FROM rule_webhook_calls c
      JOIN rule_webhooks w ON c.webhook_id = w.webhook_id
      WHERE c.status = 'pending'
        AND c.scheduled_at <= NOW()
      LIMIT 10
      FOR UPDATE SKIP LOCKED
    `);

    for (const call of rows) {
      await processWebhookCall(client, call);
    }
  } finally {
    client.release();
  }
}

async function processWebhookCall(client, call) {
  const startTime = Date.now();

  try {
    // Update status to processing
    await client.query(
      'UPDATE rule_webhook_calls SET status = $1, started_at = NOW() WHERE call_id = $2',
      ['processing', call.call_id]
    );

    // Make HTTP request
    const response = await axios({
      method: call.method,
      url: call.url,
      data: call.payload,
      headers: call.headers,
      timeout: call.timeout_ms
    });

    const executionTime = Date.now() - startTime;

    // Update success
    await client.query(`
      UPDATE rule_webhook_calls SET
        status = 'success',
        completed_at = NOW(),
        response_status = $1,
        response_body = $2,
        response_headers = $3,
        execution_time_ms = $4
      WHERE call_id = $5
    `, [
      response.status,
      JSON.stringify(response.data),
      JSON.stringify(response.headers),
      executionTime,
      call.call_id
    ]);

  } catch (error) {
    const executionTime = Date.now() - startTime;

    // Update failure
    await client.query(`
      UPDATE rule_webhook_calls SET
        status = 'failed',
        completed_at = NOW(),
        error_message = $1,
        execution_time_ms = $2
      WHERE call_id = $3
    `, [
      error.message,
      executionTime,
      call.call_id
    ]);

    // Mark for retry
    await client.query('SELECT rule_webhook_retry($1)', [call.call_id]);
  }
}

// Run every 5 seconds
setInterval(processWebhookQueue, 5000);
```

---

## Best Practices

### 1. Security

✅ **DO:**
- Encrypt secrets before storing
- Use HTTPS URLs only
- Rotate secrets regularly
- Restrict access to `rule_webhook_secret_get()`
- Validate webhook URLs

❌ **DON'T:**
- Store secrets in plain text
- Use HTTP for sensitive data
- Share secrets across webhooks unnecessarily

### 2. Performance

✅ **DO:**
- Use queue-based processing for high volume
- Set appropriate timeouts
- Monitor performance metrics
- Clean up old call records regularly

❌ **DON'T:**
- Make synchronous HTTP calls in transactions
- Set timeouts too high
- Keep unlimited call history

### 3. Reliability

✅ **DO:**
- Enable retry logic
- Monitor failure rates
- Set up alerting for high failure rates
- Use exponential backoff

❌ **DON'T:**
- Retry indefinitely
- Ignore error messages
- Skip monitoring

### 4. Monitoring

✅ **DO:**
- Check `webhook_status_summary` regularly
- Monitor `webhook_recent_failures`
- Track performance with `webhook_performance_stats`
- Set up alerts for failed webhooks

❌ **DON'T:**
- Ignore pending calls piling up
- Skip cleanup of old records
- Forget to monitor retry queues

---

## Troubleshooting

### Problem: Webhooks not being processed

**Solution:**
1. Check if HTTP extension is installed: `SELECT * FROM pg_extension WHERE extname = 'http';`
2. If not, set up external worker
3. Check pending calls: `SELECT * FROM rule_webhook_calls WHERE status = 'pending';`

### Problem: High retry rate

**Solution:**
1. Check recent failures: `SELECT * FROM webhook_recent_failures LIMIT 20;`
2. Verify webhook URL is accessible
3. Check timeout settings
4. Review error messages

### Problem: Secrets not working

**Solution:**
1. Verify secret exists: `SELECT * FROM rule_webhook_secrets WHERE webhook_id = ?;`
2. Check secret name matches exactly
3. Ensure proper access permissions

---

## Migration

### From v1.4.0 to v1.5.0

```sql
-- Upgrade extension
ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';

-- Or run migration directly
\i migrations/005_webhooks.sql
```

### Verify Installation

```sql
-- Check tables
\dt rule_webhook*

-- Check functions
\df rule_webhook*

-- Check views
\dv webhook*
```

---

## References

- [PostgreSQL HTTP Extension](https://github.com/pramsey/pgsql-http)
- [pg_cron Extension](https://github.com/citusdata/pg_cron)
- [ROADMAP](ROADMAP.md) - Feature roadmap
- [CHANGELOG](../CHANGELOG.md) - Version history

---

**Version:** 1.5.0
**Status:** ✅ Production Ready
**Last Updated:** December 10, 2025
