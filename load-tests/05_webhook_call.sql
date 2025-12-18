-- pgbench script: Webhook calls
-- This tests HTTP callout performance and queue processing
-- NOTE: Requires webhook to be registered first (see setup.sql)

\set severity_id random(1, 3)
\set client_id random(1, 10000)

SELECT rule_webhook_call(
    1,  -- webhook_id (created in setup)
    format('{"message": "Load test alert #%s", "severity": "%s", "timestamp": "%s"}',
        :client_id,
        CASE :severity_id
            WHEN 1 THEN 'info'
            WHEN 2 THEN 'warning'
            ELSE 'error'
        END,
        now()
    )::JSONB
);
