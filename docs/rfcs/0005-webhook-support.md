# RFC-0005: Webhook Support - HTTP Callouts from Rules

- **Status:** Draft
- **Author:** Rule Engine Team
- **Created:** 2025-12-06
- **Updated:** 2025-12-06
- **Phase:** 4.2 (Integration & Interoperability)
- **Priority:** P2 - Medium

---

## Summary

Enable rules to make HTTP requests to external APIs and webhooks, allowing integration with third-party services (Slack, email, payment gateways, etc.) directly from rule actions.

---

## Motivation

Currently, rules can only modify facts within PostgreSQL. To integrate with external systems, developers must:
- Poll database for changes
- Write custom application code
- Maintain separate integration services

### Use Cases

1. **Notifications:** Send Slack/Email when high-value order placed
2. **Payment Processing:** Call Stripe API when order confirmed
3. **CRM Integration:** Update Salesforce when customer status changes
4. **Inventory Management:** Notify warehouse system when stock low
5. **Third-party APIs:** Call any REST API from rule actions

---

## Detailed Design

### Database Schema

```sql
-- Webhook configurations
CREATE TABLE rule_webhooks (
    id SERIAL PRIMARY KEY,
    webhook_name TEXT NOT NULL UNIQUE,
    url TEXT NOT NULL,
    method TEXT NOT NULL DEFAULT 'POST', -- GET, POST, PUT, PATCH, DELETE
    
    -- Authentication
    auth_type TEXT, -- 'none', 'basic', 'bearer', 'api_key', 'oauth2'
    auth_config JSONB, -- Stores credentials securely
    
    -- Headers
    headers JSONB, -- Custom HTTP headers
    
    -- Request/Response config
    timeout_ms INTEGER NOT NULL DEFAULT 5000,
    retry_count INTEGER NOT NULL DEFAULT 3,
    retry_backoff_ms INTEGER NOT NULL DEFAULT 1000,
    
    -- Rate limiting
    rate_limit_per_minute INTEGER,
    
    -- Status
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT,
    
    CONSTRAINT valid_method CHECK (method IN ('GET', 'POST', 'PUT', 'PATCH', 'DELETE')),
    CONSTRAINT valid_auth_type CHECK (auth_type IN ('none', 'basic', 'bearer', 'api_key', 'oauth2'))
);

CREATE INDEX idx_webhooks_enabled ON rule_webhooks(is_enabled);

-- Webhook execution history
CREATE TABLE rule_webhook_executions (
    id BIGSERIAL PRIMARY KEY,
    webhook_id INTEGER NOT NULL REFERENCES rule_webhooks(id) ON DELETE CASCADE,
    
    -- Request
    request_payload JSONB,
    request_headers JSONB,
    executed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Response
    response_status INTEGER,
    response_body TEXT,
    response_headers JSONB,
    duration_ms NUMERIC(10, 2),
    
    -- Status
    success BOOLEAN NOT NULL,
    error_message TEXT,
    retry_attempt INTEGER NOT NULL DEFAULT 0,
    
    -- Context
    triggered_by TEXT, -- Rule name or trigger that called webhook
    
    -- Cleanup
    expires_at TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '7 days'
);

CREATE INDEX idx_webhook_exec_webhook ON rule_webhook_executions(webhook_id);
CREATE INDEX idx_webhook_exec_time ON rule_webhook_executions(executed_at DESC);
CREATE INDEX idx_webhook_exec_expires ON rule_webhook_executions(expires_at);

-- Webhook queue (for async/retry)
CREATE TABLE rule_webhook_queue (
    id BIGSERIAL PRIMARY KEY,
    webhook_id INTEGER NOT NULL REFERENCES rule_webhooks(id) ON DELETE CASCADE,
    
    -- Payload
    payload JSONB NOT NULL,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'processing', 'completed', 'failed'
    
    -- Scheduling
    queued_at TIMESTAMP NOT NULL DEFAULT NOW(),
    scheduled_for TIMESTAMP NOT NULL DEFAULT NOW(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    
    -- Retry
    retry_count INTEGER NOT NULL DEFAULT 0,
    max_retries INTEGER NOT NULL DEFAULT 3,
    error_message TEXT,
    
    -- Context
    triggered_by TEXT,
    
    CONSTRAINT valid_status CHECK (status IN ('pending', 'processing', 'completed', 'failed'))
);

CREATE INDEX idx_webhook_queue_status ON rule_webhook_queue(status, scheduled_for);
CREATE INDEX idx_webhook_queue_webhook ON rule_webhook_queue(webhook_id);
```

### Core Functions

```sql
-- HTTP client function (requires http extension or plpython)
-- Option 1: Using pg_net extension (recommended)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Option 2: Using plpython3u with requests library
CREATE OR REPLACE FUNCTION http_request(
    method TEXT,
    url TEXT,
    headers JSONB DEFAULT '{}',
    body TEXT DEFAULT NULL,
    timeout_ms INTEGER DEFAULT 5000
) RETURNS JSONB AS $$
import json
import urllib.request
import urllib.error

try:
    # Build request
    headers_dict = json.loads(headers) if headers else {}
    req = urllib.request.Request(
        url,
        data=body.encode('utf-8') if body else None,
        headers=headers_dict,
        method=method
    )
    
    # Make request with timeout
    with urllib.request.urlopen(req, timeout=timeout_ms/1000) as response:
        return json.dumps({
            'status': response.status,
            'body': response.read().decode('utf-8'),
            'headers': dict(response.headers)
        })
        
except urllib.error.HTTPError as e:
    return json.dumps({
        'status': e.code,
        'body': e.read().decode('utf-8'),
        'error': str(e)
    })
    
except Exception as e:
    return json.dumps({
        'status': 0,
        'error': str(e)
    })

$$ LANGUAGE plpython3u;

-- Webhook caller function
CREATE OR REPLACE FUNCTION rule_webhook_call(
    webhook_name TEXT,
    payload JSONB,
    triggered_by TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    webhook RECORD;
    headers JSONB;
    request_url TEXT;
    response JSONB;
    start_time TIMESTAMP;
    duration_ms NUMERIC;
    success BOOLEAN;
BEGIN
    start_time := clock_timestamp();
    
    -- Get webhook configuration
    SELECT * INTO webhook
    FROM rule_webhooks
    WHERE webhook_name = $1 AND is_enabled = true;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Webhook % not found or disabled', webhook_name;
    END IF;
    
    -- Build headers
    headers := COALESCE(webhook.headers, '{}'::JSONB);
    headers := jsonb_set(headers, '{Content-Type}', '"application/json"');
    
    -- Add authentication
    IF webhook.auth_type = 'bearer' THEN
        headers := jsonb_set(headers, '{Authorization}',
            to_jsonb('Bearer ' || (webhook.auth_config->>'token')));
    ELSIF webhook.auth_type = 'api_key' THEN
        headers := jsonb_set(headers, 
            ARRAY[webhook.auth_config->>'header_name'],
            to_jsonb(webhook.auth_config->>'api_key'));
    ELSIF webhook.auth_type = 'basic' THEN
        headers := jsonb_set(headers, '{Authorization}',
            to_jsonb('Basic ' || encode(
                (webhook.auth_config->>'username' || ':' || webhook.auth_config->>'password')::bytea,
                'base64'
            )));
    END IF;
    
    -- Build URL with query params for GET
    request_url := webhook.url;
    IF webhook.method = 'GET' AND payload IS NOT NULL THEN
        request_url := request_url || '?' || 
            (SELECT string_agg(key || '=' || value, '&')
             FROM jsonb_each_text(payload));
    END IF;
    
    -- Make HTTP request
    BEGIN
        response := http_request(
            webhook.method,
            request_url,
            headers,
            CASE WHEN webhook.method != 'GET' THEN payload::TEXT ELSE NULL END,
            webhook.timeout_ms
        );
        
        duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        success := (response->>'status')::INTEGER BETWEEN 200 AND 299;
        
        -- Log execution
        INSERT INTO rule_webhook_executions (
            webhook_id, request_payload, request_headers,
            response_status, response_body, response_headers,
            duration_ms, success, triggered_by
        ) VALUES (
            webhook.id, payload, headers,
            (response->>'status')::INTEGER,
            response->>'body',
            response->'headers',
            duration_ms, success, triggered_by
        );
        
        -- Handle rate limiting
        IF webhook.rate_limit_per_minute IS NOT NULL THEN
            PERFORM pg_sleep(60.0 / webhook.rate_limit_per_minute);
        END IF;
        
        RETURN response;
        
    EXCEPTION WHEN OTHERS THEN
        duration_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
        
        -- Log failure
        INSERT INTO rule_webhook_executions (
            webhook_id, request_payload, request_headers,
            duration_ms, success, error_message, triggered_by
        ) VALUES (
            webhook.id, payload, headers,
            duration_ms, false, SQLERRM, triggered_by
        );
        
        -- Queue for retry
        IF webhook.retry_count > 0 THEN
            INSERT INTO rule_webhook_queue (
                webhook_id, payload, max_retries, triggered_by
            ) VALUES (
                webhook.id, payload, webhook.retry_count, triggered_by
            );
        END IF;
        
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Async webhook processor
CREATE OR REPLACE FUNCTION rule_webhook_process_queue(batch_size INTEGER DEFAULT 10)
RETURNS TABLE (processed INTEGER, succeeded INTEGER, failed INTEGER) AS $$
DECLARE
    queue_item RECORD;
    response JSONB;
    success_count INTEGER := 0;
    fail_count INTEGER := 0;
    total_count INTEGER := 0;
BEGIN
    FOR queue_item IN
        SELECT *
        FROM rule_webhook_queue
        WHERE status = 'pending'
          AND scheduled_for <= NOW()
        ORDER BY queued_at
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED
    LOOP
        total_count := total_count + 1;
        
        UPDATE rule_webhook_queue
        SET status = 'processing', started_at = NOW()
        WHERE id = queue_item.id;
        
        BEGIN
            response := rule_webhook_call(
                (SELECT webhook_name FROM rule_webhooks WHERE id = queue_item.webhook_id),
                queue_item.payload,
                queue_item.triggered_by
            );
            
            UPDATE rule_webhook_queue
            SET status = 'completed', completed_at = NOW()
            WHERE id = queue_item.id;
            
            success_count := success_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            IF queue_item.retry_count < queue_item.max_retries THEN
                UPDATE rule_webhook_queue
                SET status = 'pending',
                    retry_count = retry_count + 1,
                    scheduled_for = NOW() + (POWER(2, retry_count + 1) || ' seconds')::INTERVAL,
                    error_message = SQLERRM
                WHERE id = queue_item.id;
            ELSE
                UPDATE rule_webhook_queue
                SET status = 'failed', completed_at = NOW(), error_message = SQLERRM
                WHERE id = queue_item.id;
                
                fail_count := fail_count + 1;
            END IF;
        END;
    END LOOP;
    
    RETURN QUERY SELECT total_count, success_count, fail_count;
END;
$$ LANGUAGE plpgsql;
```

### Integration with GRL Rules

```sql
-- Extend GRL to support webhook calls in actions
-- Example GRL with webhook:
'rule "HighValueOrderAlert" salience 10 {
    when Order.Amount > 1000
    then Order.Priority = "HIGH";
         WEBHOOK("slack_alerts", {
             "text": "High value order: $" + Order.Amount,
             "order_id": Order.Id
         });
}'

-- Implementation: Parse WEBHOOK() calls in rule engine
-- and translate to rule_webhook_call() function calls
```

### API Functions

#### Function 1: `rule_webhook_register(name TEXT, url TEXT, method TEXT DEFAULT 'POST', auth_config JSONB DEFAULT '{}', options JSONB DEFAULT '{}') → INTEGER`

**Example:**
```sql
-- Register Slack webhook
SELECT rule_webhook_register(
    'slack_alerts',
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    'POST',
    '{"auth_type": "none"}',
    '{"headers": {"Content-Type": "application/json"}, "timeout_ms": 3000}'
);

-- Register API with Bearer token
SELECT rule_webhook_register(
    'payment_api',
    'https://api.stripe.com/v1/charges',
    'POST',
    '{"auth_type": "bearer", "token": "sk_test_..."}',
    '{"retry_count": 3, "rate_limit_per_minute": 100}'
);
```

#### Function 2: `rule_webhook_call(webhook_name TEXT, payload JSONB) → JSONB`

**Example:**
```sql
-- Send notification
SELECT rule_webhook_call(
    'slack_alerts',
    '{"text": "Order #123 shipped", "channel": "#orders"}'
);
```

#### Function 3: `rule_webhook_stats(webhook_name TEXT) → JSON`

**Example:**
```sql
SELECT rule_webhook_stats('slack_alerts');

-- Returns:
{
  "total_calls": 1523,
  "success_rate": 99.2,
  "avg_duration_ms": 245,
  "last_called": "2025-12-06T10:30:00Z",
  "errors": 12
}
```

---

## Examples

### Example 1: Slack Notifications

```sql
-- Register Slack webhook
SELECT rule_webhook_register(
    'slack_orders',
    'https://hooks.slack.com/services/T00/B00/XXX',
    'POST'
);

-- Create rule with webhook call
SELECT rule_save(
    'order_notification',
    'rule "NotifyHighValue" {
        when Order.Amount > 5000
        then WEBHOOK("slack_orders", {
            "text": "🚨 High value order!",
            "attachments": [{
                "fields": [
                    {"title": "Amount", "value": Order.Amount},
                    {"title": "Customer", "value": Order.CustomerId}
                ]
            }]
        });
    }',
    '1.0.0'
);

-- Trigger automatically sends to Slack
SELECT rule_execute_by_name(
    'order_notification',
    '{"Order": {"Amount": 10000, "CustomerId": 456}}'
);
```

### Example 2: Email via SendGrid

```sql
-- Register SendGrid API
SELECT rule_webhook_register(
    'sendgrid_email',
    'https://api.sendgrid.com/v3/mail/send',
    'POST',
    '{"auth_type": "bearer", "token": "SG.xxx"}',
    '{"headers": {"Content-Type": "application/json"}}'
);

-- Send email from rule
SELECT rule_webhook_call(
    'sendgrid_email',
    '{
        "personalizations": [{"to": [{"email": "customer@example.com"}]}],
        "from": {"email": "noreply@myapp.com"},
        "subject": "Order Confirmation",
        "content": [{"type": "text/plain", "value": "Your order has been confirmed!"}]
    }'
);
```

### Example 3: Payment Processing

```sql
-- Register Stripe API
SELECT rule_webhook_register(
    'stripe_charge',
    'https://api.stripe.com/v1/charges',
    'POST',
    '{"auth_type": "basic", "username": "sk_test_...", "password": ""}',
    '{"retry_count": 5}'
);

-- Charge customer from rule
SELECT rule_webhook_call(
    'stripe_charge',
    '{
        "amount": 2000,
        "currency": "usd",
        "source": "tok_visa",
        "description": "Order #123"
    }'
);
```

---

## Security Considerations

- **Credential Encryption:** Auth configs encrypted at rest
- **HTTPS Only:** Enforce HTTPS for all webhooks
- **Rate Limiting:** Prevent abuse with rate limits
- **Timeout:** Prevent hanging requests
- **Audit Log:** Complete history of all webhook calls
- **Permission Model:** Only admins can register webhooks

---

## Performance Considerations

- **Async Mode:** Don't block rule execution
- **Retry Logic:** Exponential backoff
- **Connection Pooling:** Reuse HTTP connections
- **Timeout:** Default 5s timeout
- **Queue Processing:** Background workers

---

## Success Metrics

- **Adoption:** 50% of production deployments use webhooks
- **Reliability:** 99.5% success rate
- **Performance:** < 500ms average webhook duration
- **Integration:** 10+ common services documented

---

## Changelog

- **2025-12-06:** Initial draft
