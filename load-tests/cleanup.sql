-- Load Test Cleanup Script
-- Run this after load tests to clean up test data

\echo '=== Cleaning up load test data ==='

-- Clean webhook data
-- Use webhook_name/webhook_id columns that exist in the schema
DELETE FROM rule_webhook_calls WHERE webhook_id IN (SELECT webhook_id FROM rule_webhooks WHERE webhook_name LIKE 'loadtest_%');
DELETE FROM rule_webhooks WHERE webhook_name LIKE 'loadtest_%';

\echo '✓ Cleaned webhook data'

-- Clean datasource data
-- Use datasource_name/datasource_id columns
DELETE FROM rule_datasource_cache WHERE datasource_id IN (SELECT datasource_id FROM rule_datasources WHERE datasource_name LIKE 'loadtest_%');
DELETE FROM rule_datasource_requests WHERE datasource_id IN (SELECT datasource_id FROM rule_datasources WHERE datasource_name LIKE 'loadtest_%');
DELETE FROM rule_datasources WHERE datasource_name LIKE 'loadtest_%';

\echo '✓ Cleaned datasource data'

-- Clean test rules
-- rule_execution_stats uses rule_name; other repository tables use rule_name for cleanup in tests
-- rule_execution_stats stores rule_name
DELETE FROM rule_execution_stats WHERE rule_name LIKE 'test_rule_%';
-- rule_audit_log and rule_versions reference rule_definitions.id via rule_id
DELETE FROM rule_audit_log WHERE rule_id IN (SELECT id FROM rule_definitions WHERE name LIKE 'test_rule_%');
DELETE FROM rule_versions WHERE rule_id IN (SELECT id FROM rule_definitions WHERE name LIKE 'test_rule_%');
DELETE FROM rule_definitions WHERE name LIKE 'test_rule_%';

\echo '✓ Cleaned rule repository data'

\echo ''
\echo '=== Cleanup complete! ==='
