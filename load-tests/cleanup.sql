-- Load Test Cleanup Script
-- Run this after load tests to clean up test data

\echo '=== Cleaning up load test data ==='

-- Clean webhook data
DELETE FROM rule_webhook_calls WHERE webhook_id IN (SELECT id FROM rule_webhooks WHERE name LIKE 'loadtest_%');
DELETE FROM rule_webhooks WHERE name LIKE 'loadtest_%';

\echo '✓ Cleaned webhook data'

-- Clean datasource data
DELETE FROM rule_datasource_cache WHERE datasource_id IN (SELECT id FROM rule_datasources WHERE name LIKE 'loadtest_%');
DELETE FROM rule_datasource_requests WHERE datasource_id IN (SELECT id FROM rule_datasources WHERE name LIKE 'loadtest_%');
DELETE FROM rule_datasources WHERE name LIKE 'loadtest_%';

\echo '✓ Cleaned datasource data'

-- Clean test rules
DELETE FROM rule_execution_stats WHERE rule_name LIKE 'test_rule_%';
DELETE FROM rule_audit_log WHERE rule_name LIKE 'test_rule_%';
DELETE FROM rule_versions WHERE rule_name LIKE 'test_rule_%';
DELETE FROM rule_definitions WHERE name LIKE 'test_rule_%';

\echo '✓ Cleaned rule repository data'

\echo ''
\echo '=== Cleanup complete! ==='
