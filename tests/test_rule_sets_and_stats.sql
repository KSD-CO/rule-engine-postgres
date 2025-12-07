-- Test Suite for Rule Sets and Execution Statistics
-- Version: 1.3.0

-- ============================================================================
-- SETUP
-- ============================================================================

-- Clean up any existing test data
DELETE FROM rule_set_members WHERE ruleset_id IN (SELECT ruleset_id FROM rule_sets WHERE name LIKE 'test_%');
DELETE FROM rule_sets WHERE name LIKE 'test_%';
DELETE FROM rule_execution_stats WHERE rule_name LIKE 'test_%';

-- Create test rules for rule sets
SELECT rule_save(
    'test_credit_check',
    'rule CreditCheck "Check credit score" {
        when
            CreditScore >= 700
        then
            Approve = true;
            Log("Credit check passed");
    }',
    '1.0.0',
    'Test rule for credit checking',
    'Initial version'
);

SELECT rule_save(
    'test_income_verification',
    'rule IncomeVerification "Verify income" {
        when
            Income >= 50000
        then
            IncomeVerified = true;
            Log("Income verified");
    }',
    '1.0.0',
    'Test rule for income verification',
    'Initial version'
);

SELECT rule_save(
    'test_debt_ratio',
    'rule DebtRatio "Check debt ratio" {
        when
            DebtRatio < 0.4
        then
            DebtAcceptable = true;
            Log("Debt ratio acceptable");
    }',
    '1.0.0',
    'Test rule for debt ratio',
    'Initial version'
);

-- ============================================================================
-- TEST 1: Create Rule Set
-- ============================================================================
\echo ''
\echo '=== TEST 1: Create Rule Set ==='

SELECT ruleset_create('test_loan_approval', 'Test rule set for loan approval process') AS ruleset_id \gset

\echo 'Created rule set ID:' :ruleset_id

-- Verify creation
SELECT * FROM rule_sets WHERE name = 'test_loan_approval';

-- ============================================================================
-- TEST 2: Add Rules to Rule Set
-- ============================================================================
\echo ''
\echo '=== TEST 2: Add Rules to Rule Set ==='

-- Add rules in specific order
SELECT ruleset_add_rule(:ruleset_id, 'test_credit_check', '1.0.0', 0) AS credit_added;
SELECT ruleset_add_rule(:ruleset_id, 'test_income_verification', '1.0.0', 1) AS income_added;
SELECT ruleset_add_rule(:ruleset_id, 'test_debt_ratio', '1.0.0', 2) AS debt_added;

-- Verify rules added
SELECT * FROM ruleset_get_rules(:ruleset_id);

-- ============================================================================
-- TEST 3: List Rule Sets
-- ============================================================================
\echo ''
\echo '=== TEST 3: List Rule Sets ==='

SELECT * FROM ruleset_list() WHERE name LIKE 'test_%';

-- ============================================================================
-- TEST 4: Execute Rule Set
-- ============================================================================
\echo ''
\echo '=== TEST 4: Execute Rule Set ==='

-- Execute rule set with test data
SELECT ruleset_execute(
    :ruleset_id,
    '{"CreditScore": 750, "Income": 60000, "DebtRatio": 0.35}'
) AS execution_result;

-- ============================================================================
-- TEST 5: Remove Rule from Rule Set
-- ============================================================================
\echo ''
\echo '=== TEST 5: Remove Rule from Rule Set ==='

SELECT ruleset_remove_rule(:ruleset_id, 'test_debt_ratio', '1.0.0') AS removed;

-- Verify rule removed
SELECT * FROM ruleset_get_rules(:ruleset_id);

-- ============================================================================
-- TEST 6: Record Execution Statistics
-- ============================================================================
\echo ''
\echo '=== TEST 6: Record Execution Statistics ==='

-- Record successful executions
SELECT rule_record_execution('test_credit_check', '1.0.0', 45.5, true, NULL, 1, 1) AS stat1;
SELECT rule_record_execution('test_credit_check', '1.0.0', 42.3, true, NULL, 1, 1) AS stat2;
SELECT rule_record_execution('test_credit_check', '1.0.0', 48.7, true, NULL, 1, 1) AS stat3;

-- Record a failed execution
SELECT rule_record_execution('test_credit_check', '1.0.0', 15.2, false, 'Invalid input', 0, 0) AS stat4;

-- Record stats for another rule
SELECT rule_record_execution('test_income_verification', '1.0.0', 32.1, true, NULL, 1, 1) AS stat5;
SELECT rule_record_execution('test_income_verification', '1.0.0', 35.8, true, NULL, 1, 1) AS stat6;

-- ============================================================================
-- TEST 7: Get Rule Statistics
-- ============================================================================
\echo ''
\echo '=== TEST 7: Get Rule Statistics ==='

-- Get stats for credit check rule
SELECT rule_stats('test_credit_check', NOW() - INTERVAL '1 day', NOW());

-- Get stats for income verification rule
SELECT rule_stats('test_income_verification', NOW() - INTERVAL '1 day', NOW());

-- ============================================================================
-- TEST 8: Performance Summary View
-- ============================================================================
\echo ''
\echo '=== TEST 8: Performance Summary View ==='

SELECT * FROM rule_performance_summary 
WHERE rule_name LIKE 'test_%'
ORDER BY rule_name;

-- ============================================================================
-- TEST 9: Performance Report
-- ============================================================================
\echo ''
\echo '=== TEST 9: Performance Report ==='

-- Get top rules by execution count
SELECT * FROM rule_performance_report(10, 'total_executions')
WHERE rule_name LIKE 'test_%';

-- Get top rules by avg execution time
SELECT * FROM rule_performance_report(10, 'avg_execution_time_ms')
WHERE rule_name LIKE 'test_%';

-- ============================================================================
-- TEST 10: Update Rule Order in Rule Set
-- ============================================================================
\echo ''
\echo '=== TEST 10: Update Rule Order ==='

-- Add debt ratio back with different order
SELECT ruleset_add_rule(:ruleset_id, 'test_debt_ratio', '1.0.0', 0) AS re_added;

-- Verify new order (debt ratio should be first now)
SELECT * FROM ruleset_get_rules(:ruleset_id);

-- ============================================================================
-- TEST 11: Clear Statistics
-- ============================================================================
\echo ''
\echo '=== TEST 11: Clear Statistics ==='

-- Clear stats for credit check rule
SELECT rule_clear_stats('test_credit_check', NULL) AS cleared_count;

-- Verify stats cleared
SELECT COUNT(*) as remaining_stats FROM rule_execution_stats WHERE rule_name = 'test_credit_check';

-- ============================================================================
-- TEST 12: Delete Rule Set
-- ============================================================================
\echo ''
\echo '=== TEST 12: Delete Rule Set ==='

-- Create a temporary rule set for deletion test
SELECT ruleset_create('test_temp_ruleset', 'Temporary rule set') AS temp_ruleset_id \gset
SELECT ruleset_add_rule(:temp_ruleset_id, 'test_credit_check', '1.0.0', 0);

-- Delete the rule set
SELECT ruleset_delete(:temp_ruleset_id) AS deleted;

-- Verify deletion (should return 0 rows)
SELECT COUNT(*) as should_be_zero FROM rule_sets WHERE ruleset_id = :temp_ruleset_id;
SELECT COUNT(*) as should_be_zero FROM rule_set_members WHERE ruleset_id = :temp_ruleset_id;

-- ============================================================================
-- TEST 13: Error Handling
-- ============================================================================
\echo ''
\echo '=== TEST 13: Error Handling ==='

-- Try to create duplicate rule set (should fail)
\echo 'Attempting to create duplicate rule set (should fail):'
SELECT ruleset_create('test_loan_approval', 'Duplicate') AS should_fail;

-- Try to add non-existent rule (should fail)
\echo 'Attempting to add non-existent rule (should fail):'
SELECT ruleset_add_rule(:ruleset_id, 'nonexistent_rule', NULL, 0) AS should_fail;

-- Try to execute non-existent rule set (should fail)
\echo 'Attempting to execute non-existent rule set (should fail):'
SELECT ruleset_execute(99999, '{}') AS should_fail;

-- ============================================================================
-- TEST 14: Complex Rule Set Execution
-- ============================================================================
\echo ''
\echo '=== TEST 14: Complex Rule Set Execution ==='

-- Test with all conditions passing
\echo 'Test 1: All conditions pass'
SELECT ruleset_execute(
    :ruleset_id,
    '{"CreditScore": 800, "Income": 80000, "DebtRatio": 0.25}'
);

-- Test with some conditions failing
\echo 'Test 2: Some conditions fail'
SELECT ruleset_execute(
    :ruleset_id,
    '{"CreditScore": 650, "Income": 40000, "DebtRatio": 0.45}'
);

-- ============================================================================
-- TEST 15: Statistics Over Time
-- ============================================================================
\echo ''
\echo '=== TEST 15: Statistics Over Time ==='

-- Create more execution records for better statistics
DO $$
DECLARE
    i INTEGER;
BEGIN
    FOR i IN 1..10 LOOP
        PERFORM rule_record_execution(
            'test_income_verification',
            '1.0.0',
            30 + (random() * 20)::numeric,  -- Random execution time 30-50ms
            random() < 0.9,  -- 90% success rate
            CASE WHEN random() < 0.1 THEN 'Random error' ELSE NULL END,
            1,
            1
        );
    END LOOP;
END $$;

-- View comprehensive statistics
SELECT rule_stats('test_income_verification', NOW() - INTERVAL '1 hour', NOW());

-- ============================================================================
-- CLEANUP
-- ============================================================================
\echo ''
\echo '=== CLEANUP ==='

-- Clean up test data
DELETE FROM rule_set_members WHERE ruleset_id IN (SELECT ruleset_id FROM rule_sets WHERE name LIKE 'test_%');
DELETE FROM rule_sets WHERE name LIKE 'test_%';
DELETE FROM rule_execution_stats WHERE rule_name LIKE 'test_%';
DELETE FROM rule_definitions WHERE name LIKE 'test_%';

\echo 'All tests completed!'
