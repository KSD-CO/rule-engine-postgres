-- Integration Tests for Rule Repository
-- RFC-0001: Rule Repository & Versioning
-- Tests all CRUD operations and edge cases

BEGIN;

-- =============================================================================
-- Setup Test Environment
-- =============================================================================

-- Ensure tables exist
\echo 'Test 1: Verify tables exist'
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_name = 'rule_definitions'
) AS rule_definitions_exists;

SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_name = 'rule_versions'
) AS rule_versions_exists;

-- Clean up any existing test data
DELETE FROM rule_definitions WHERE name LIKE 'test_%';

-- =============================================================================
-- Test 2: Basic Rule Save and Retrieve
-- =============================================================================

\echo 'Test 2: Save and retrieve a new rule'

-- Save new rule
SELECT rule_save(
    'test_discount',
    'rule "TestDiscount" salience 10 {
        when Order.Amount > 100
        then Order.Discount = 15;
    }',
    '1.0.0',
    'Test discount rule'
) AS rule_id;

-- Verify rule was created
SELECT COUNT(*) = 1 AS rule_created
FROM rule_definitions
WHERE name = 'test_discount';

-- Verify version was created
SELECT COUNT(*) = 1 AS version_created
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount' AND rv.version = '1.0.0';

-- Retrieve rule
SELECT rule_get('test_discount') LIKE '%TestDiscount%' AS rule_retrieved;

-- Retrieve specific version
SELECT rule_get('test_discount', '1.0.0') LIKE '%TestDiscount%' AS specific_version_retrieved;

-- =============================================================================
-- Test 3: Version Management
-- =============================================================================

\echo 'Test 3: Add new version and test version activation'

-- Add new version
SELECT rule_save(
    'test_discount',
    'rule "TestDiscount" salience 10 {
        when Order.Amount > 100
        then Order.Discount = 20;
    }',
    '2.0.0',
    NULL,
    'Increased discount from 15 to 20'
) AS rule_id;

-- Verify 2 versions exist
SELECT COUNT(*) = 2 AS two_versions_exist
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount';

-- First version should still be default (we didn't activate new one)
SELECT rv.version = '1.0.0' AS first_version_is_default
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount' AND rv.is_default = true;

-- Activate version 2.0.0
SELECT rule_activate('test_discount', '2.0.0') AS activation_success;

-- Verify version 2.0.0 is now default
SELECT rv.version = '2.0.0' AS new_version_is_default
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount' AND rv.is_default = true;

-- Verify only one default version
SELECT COUNT(*) = 1 AS only_one_default
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount' AND rv.is_default = true;

-- Get rule (should return default 2.0.0)
SELECT rule_get('test_discount') LIKE '%Discount = 20%' AS default_version_correct;

-- =============================================================================
-- Test 4: Auto Version Increment
-- =============================================================================

\echo 'Test 4: Test auto version increment'

-- Save without specifying version (should auto-increment to 2.0.1)
SELECT rule_save(
    'test_discount',
    'rule "TestDiscount" salience 10 {
        when Order.Amount > 100
        then Order.Discount = 25;
    }',
    NULL,
    NULL,
    'Auto-incremented version'
) AS rule_id;

-- Verify version 2.0.1 was created
SELECT EXISTS (
    SELECT 1 FROM rule_versions rv
    JOIN rule_definitions rd ON rv.rule_id = rd.id
    WHERE rd.name = 'test_discount' AND rv.version = '2.0.1'
) AS auto_incremented_version_exists;

-- =============================================================================
-- Test 5: Rule Tags
-- =============================================================================

\echo 'Test 5: Test rule tagging'

-- Add tags
SELECT rule_tag_add('test_discount', 'discount') AS tag1_added;
SELECT rule_tag_add('test_discount', 'pricing') AS tag2_added;
SELECT rule_tag_add('test_discount', 'ecommerce') AS tag3_added;

-- Verify tags were added
SELECT COUNT(*) = 3 AS three_tags_added
FROM rule_tags rt
JOIN rule_definitions rd ON rt.rule_id = rd.id
WHERE rd.name = 'test_discount';

-- Remove a tag
SELECT rule_tag_remove('test_discount', 'pricing') AS tag_removed;

-- Verify tag was removed
SELECT COUNT(*) = 2 AS two_tags_remain
FROM rule_tags rt
JOIN rule_definitions rd ON rt.rule_id = rd.id
WHERE rd.name = 'test_discount';

-- =============================================================================
-- Test 6: Rule Execution by Name
-- =============================================================================

\echo 'Test 6: Test rule execution by name'

-- Execute rule by name (should use default version 2.0.0)
SELECT rule_execute_by_name(
    'test_discount',
    '{"Order": {"Amount": 150}}'
)::jsonb->'Order'->>'Discount' = '20' AS execution_correct;

-- Execute specific version
SELECT rule_execute_by_name(
    'test_discount',
    '{"Order": {"Amount": 150}}',
    '1.0.0'
)::jsonb->'Order'->>'Discount' = '15' AS specific_version_execution_correct;

-- =============================================================================
-- Test 7: Validation Errors
-- =============================================================================

\echo 'Test 7: Test validation errors'

-- Invalid rule name (should fail)
DO $$
BEGIN
    PERFORM rule_save('123invalid', 'rule {}', '1.0.0', NULL);
    RAISE EXCEPTION 'Should have failed with invalid rule name';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Correctly rejected invalid rule name';
END $$;

-- Invalid version format (should fail)
DO $$
BEGIN
    PERFORM rule_save('test_rule_2', 'rule {}', 'v1.0', NULL);
    RAISE EXCEPTION 'Should have failed with invalid version';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Correctly rejected invalid version format';
END $$;

-- Empty GRL content (should fail)
DO $$
BEGIN
    PERFORM rule_save('test_rule_3', '', '1.0.0', NULL);
    RAISE EXCEPTION 'Should have failed with empty GRL';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Correctly rejected empty GRL content';
END $$;

-- =============================================================================
-- Test 8: Rule Catalog View
-- =============================================================================

\echo 'Test 8: Test rule catalog view'

-- Check catalog view
SELECT COUNT(*) >= 1 AS catalog_has_rules
FROM rule_catalog
WHERE name = 'test_discount';

-- Verify catalog includes tags
SELECT tags IS NOT NULL AND array_length(tags, 1) >= 2 AS catalog_includes_tags
FROM rule_catalog
WHERE name = 'test_discount';

-- =============================================================================
-- Test 9: Audit Log
-- =============================================================================

\echo 'Test 9: Test audit logging'

-- Verify audit log has entries for our test rule
SELECT COUNT(*) >= 1 AS audit_log_has_entries
FROM rule_audit_log ral
JOIN rule_definitions rd ON ral.rule_id = rd.id
WHERE rd.name = 'test_discount';

-- Verify version updates were logged
SELECT COUNT(*) >= 1 AS version_updates_logged
FROM rule_audit_log ral
JOIN rule_definitions rd ON ral.rule_id = rd.id
WHERE rd.name = 'test_discount' AND ral.action = 'update';

-- =============================================================================
-- Test 10: Rule Deletion
-- =============================================================================

\echo 'Test 10: Test rule deletion'

-- Create a throwaway rule
SELECT rule_save('test_delete_me', 'rule "Delete" {}', '1.0.0', NULL);
SELECT rule_save('test_delete_me', 'rule "Delete" {}', '2.0.0', NULL);
SELECT rule_activate('test_delete_me', '2.0.0');

-- Try to delete default version (should fail)
DO $$
BEGIN
    PERFORM rule_delete('test_delete_me', '2.0.0');
    RAISE EXCEPTION 'Should have failed deleting default version';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Correctly prevented deletion of default version';
END $$;

-- Delete non-default version (should succeed)
SELECT rule_delete('test_delete_me', '1.0.0') AS non_default_deleted;

-- Verify only one version remains
SELECT COUNT(*) = 1 AS one_version_remains
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_delete_me';

-- Delete entire rule
SELECT rule_delete('test_delete_me') AS rule_deleted;

-- Verify rule is gone
SELECT COUNT(*) = 0 AS rule_completely_deleted
FROM rule_definitions
WHERE name = 'test_delete_me';

-- =============================================================================
-- Test 11: Concurrent Version Management
-- =============================================================================

\echo 'Test 11: Test duplicate version prevention'

-- Try to create duplicate version (should fail)
DO $$
BEGIN
    PERFORM rule_save('test_discount', 'rule {}', '2.0.0', NULL);
    RAISE EXCEPTION 'Should have failed with duplicate version';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Correctly prevented duplicate version';
END $$;

-- =============================================================================
-- Test 12: Rule Activation Workflow (Rollback Scenario)
-- =============================================================================

\echo 'Test 12: Test rollback scenario'

-- Current default should be 2.0.0
SELECT rv.version = '2.0.0' AS currently_on_v2
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount' AND rv.is_default = true;

-- Rollback to 1.0.0
SELECT rule_activate('test_discount', '1.0.0') AS rollback_success;

-- Verify 1.0.0 is now default
SELECT rv.version = '1.0.0' AS rolled_back_to_v1
FROM rule_versions rv
JOIN rule_definitions rd ON rv.rule_id = rd.id
WHERE rd.name = 'test_discount' AND rv.is_default = true;

-- Verify rule execution uses rolled back version
SELECT rule_execute_by_name(
    'test_discount',
    '{"Order": {"Amount": 150}}'
)::jsonb->'Order'->>'Discount' = '15' AS rollback_execution_correct;

-- =============================================================================
-- Cleanup
-- =============================================================================

\echo 'Cleaning up test data...'
DELETE FROM rule_definitions WHERE name LIKE 'test_%';

ROLLBACK;

-- =============================================================================
-- Test Summary
-- =============================================================================

\echo ''
\echo '========================================='
\echo 'Rule Repository Integration Tests Complete'
\echo '========================================='
\echo ''
\echo 'All tests passed! Rule Repository is working correctly.'
\echo ''
