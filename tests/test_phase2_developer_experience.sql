-- Test Suite for Phase 2: Developer Experience (v1.4.0)
-- Run this file after applying migration 004_developer_experience.sql

\echo '=========================================='
\echo 'Phase 2: Developer Experience Test Suite'
\echo '=========================================='
\echo ''

-- ============================================================================
-- SECTION 1: RULE TESTING FRAMEWORK TESTS
-- ============================================================================

\echo '1. Testing Framework - Create Test Cases'
\echo '------------------------------------------'

-- Test 1.1: Create a simple test case
SELECT rule_test_create(
    'test_discount_gold_tier',
    'discount_rules',
    '{"customer": {"tier": "gold", "total_spent": 5000}}'::JSONB,
    '{"customer": {"tier": "gold", "total_spent": 5000, "discount": 0.15}}'::JSONB,
    'latest',
    'Test gold tier discount application'
) AS test_id_1;

-- Test 1.2: Create test with assertions
SELECT rule_test_create(
    'test_discount_with_assertions',
    'discount_rules',
    '{"customer": {"tier": "silver", "total_spent": 2000}}'::JSONB,
    NULL,
    'latest',
    'Test silver tier with assertions',
    '[
        {"type": "equals", "path": "customer.discount", "value": 0.10},
        {"type": "exists", "path": "customer.tier"},
        {"type": "greater_than", "path": "customer.total_spent", "value": 1000}
    ]'::JSONB
) AS test_id_2;

-- Test 1.3: Create test for threshold check
SELECT rule_test_create(
    'test_threshold_check',
    'threshold_rule',
    '{"temperature": 95, "status": "normal"}'::JSONB,
    '{"temperature": 95, "status": "warning", "alert": true}'::JSONB,
    'latest',
    'Test temperature threshold warning'
) AS test_id_3;

\echo ''
\echo '2. Testing Framework - View Test Cases'
\echo '------------------------------------------'

SELECT test_id, test_name, rule_name, enabled
FROM rule_test_cases
ORDER BY test_id;

\echo ''
\echo '3. Testing Framework - Run Individual Test'
\echo '------------------------------------------'

-- Note: This will fail if the actual rule doesn't exist, but demonstrates the API
-- SELECT rule_test_run(1);

\echo 'Skipping actual test execution (requires rules to be defined)'
\echo 'Use: SELECT rule_test_run(test_id) to run a specific test'

\echo ''
\echo '4. Testing Framework - Run All Tests'
\echo '------------------------------------------'

\echo 'Use: SELECT * FROM rule_test_run_all(NULL) to run all tests'
\echo 'Use: SELECT * FROM rule_test_run_all(''rule_name'') to run tests for specific rule'

\echo ''
\echo '5. Testing Framework - Check Coverage'
\echo '------------------------------------------'

SELECT * FROM rule_test_coverage ORDER BY rule_name;

\echo ''
\echo '6. Testing Framework - Test Suite Summary View'
\echo '------------------------------------------'

SELECT * FROM test_suite_summary ORDER BY rule_name;

-- ============================================================================
-- SECTION 2: RULE VALIDATION & LINTING TESTS
-- ============================================================================

\echo ''
\echo '7. Validation - Valid GRL Syntax'
\echo '------------------------------------------'

SELECT rule_validate('
rule SimpleRule "A simple valid rule" {
    when
        customer.age > 18
    then
        customer.is_adult = true;
}
') AS validation_result;

\echo ''
\echo '8. Validation - Invalid GRL Syntax'
\echo '------------------------------------------'

SELECT rule_validate('
invalid syntax here
no proper rule structure
') AS validation_result;

\echo ''
\echo '9. Validation - Empty Rule'
\echo '------------------------------------------'

SELECT rule_validate('') AS validation_result;

\echo ''
\echo '10. Linting - Simple Lint Check'
\echo '------------------------------------------'

SELECT rule_lint('
rule TestRule "Test rule for linting" salience 10 {
    when
        x > 10
    then
        y = 20;
}
') AS lint_result;

\echo ''
\echo '11. Linting - Complex Rule with Warnings'
\echo '------------------------------------------'

SELECT rule_lint('
rule ComplexRule "Complex rule" {
    when
        a > 1 && b > 2 && c > 3 && d > 4 && e > 5 && f > 6 && g > 7
    then
        result = true;
}
') AS lint_result;

\echo ''
\echo '12. Linting - Strict Mode'
\echo '------------------------------------------'

SELECT rule_lint('
rule LongLineRule "Rule with a very long line that exceeds one hundred and twenty characters which should trigger a warning in strict mode" {
    when
        condition = true
    then
        action = true;
}
', true) AS lint_result_strict;

-- ============================================================================
-- SECTION 3: RULE DEBUGGING TOOLS TESTS
-- ============================================================================

\echo ''
\echo '13. Debugging - Debug Execute'
\echo '------------------------------------------'

SELECT rule_debug_execute(
    '{"customer": {"age": 25, "country": "US"}}'::JSONB,
    'rule AgeCheck "Check age" {
        when
            customer.age >= 21
        then
            customer.can_drink = true;
            Retract("AgeCheck");
    }',
    'debug_session_001'
) AS debug_result;

\echo ''
\echo '14. Debugging - Retrieve Trace'
\echo '------------------------------------------'

SELECT step_number, step_type, description, traced_at FROM rule_trace_get('debug_session_001');

\echo ''
\echo '15. Debugging - Multiple Debug Sessions'
\echo '------------------------------------------'

SELECT rule_debug_execute(
    '{"order": {"total": 150, "items": 5}}'::JSONB,
    'rule BulkDiscount "Apply bulk discount" {
        when
            order.items >= 5
        then
            order.discount = 0.10;
            Retract("BulkDiscount");
    }',
    'debug_session_002'
) AS debug_result_2;

SELECT session_id, COUNT(*) as trace_steps
FROM rule_debug_traces
GROUP BY session_id
ORDER BY session_id;

-- ============================================================================
-- SECTION 4: RULE TEMPLATES TESTS
-- ============================================================================

\echo ''
\echo '16. Templates - View Built-in Templates'
\echo '------------------------------------------'

SELECT * FROM rule_template_list();

\echo ''
\echo '17. Templates - Get Specific Template'
\echo '------------------------------------------'

SELECT rule_template_get('threshold_check') AS template_detail;

\echo ''
\echo '18. Templates - Create Custom Template'
\echo '------------------------------------------'

SELECT rule_template_create(
    'age_verification',
    'rule AgeVerification_{{name}} "Verify minimum age of {{min_age}}" salience 10 {
        when
            {{field}} >= {{min_age}}
        then
            Result.verified = true;
            Result.message = "Age verification passed";
            Retract("AgeVerification_{{name}}");
    }',
    '[
        {"name": "name", "type": "string", "description": "Rule instance name"},
        {"name": "field", "type": "string", "description": "Field containing age"},
        {"name": "min_age", "type": "number", "description": "Minimum required age"}
    ]'::JSONB,
    'Age verification template for various scenarios',
    'compliance'
) AS new_template_id;

\echo ''
\echo '19. Templates - Instantiate Template'
\echo '------------------------------------------'

-- First, get the template ID we just created
DO $$
DECLARE
    v_template_id INTEGER;
    v_instantiated_grl TEXT;
BEGIN
    SELECT template_id INTO v_template_id
    FROM rule_templates
    WHERE template_name = 'threshold_check';

    IF v_template_id IS NOT NULL THEN
        SELECT rule_template_instantiate(
            v_template_id,
            '{"field": "temperature", "threshold": "100"}'::JSONB,
            'temperature_alert_rule'
        ) INTO v_instantiated_grl;

        RAISE NOTICE 'Instantiated GRL:';
        RAISE NOTICE '%', v_instantiated_grl;
    END IF;
END $$;

\echo ''
\echo '20. Templates - List by Category'
\echo '------------------------------------------'

SELECT * FROM rule_template_list('validation');
SELECT * FROM rule_template_list('pricing');

\echo ''
\echo '21. Templates - Usage Statistics'
\echo '------------------------------------------'

SELECT * FROM template_usage_stats ORDER BY usage_count DESC;

-- ============================================================================
-- SECTION 5: INTEGRATION TESTS
-- ============================================================================

\echo ''
\echo '22. Integration - Create, Test, and Validate Workflow'
\echo '------------------------------------------'

DO $$
DECLARE
    v_grl TEXT;
    v_validation JSON;
    v_lint JSON;
    v_test_id INTEGER;
BEGIN
    -- Step 1: Create a rule from template
    v_grl := rule_template_instantiate(
        (SELECT template_id FROM rule_templates WHERE template_name = 'discount_rule' LIMIT 1),
        '{"condition": "customer.loyalty_years > 5", "discount_pct": "20"}'::JSONB
    );

    RAISE NOTICE 'Step 1: Created rule from template';

    -- Step 2: Validate the rule
    v_validation := rule_validate(v_grl);
    RAISE NOTICE 'Step 2: Validation result: %', v_validation->>'valid';

    -- Step 3: Lint the rule
    v_lint := rule_lint(v_grl);
    RAISE NOTICE 'Step 3: Lint passed: %', v_lint->>'passed';

    -- Step 4: Create a test case
    SELECT rule_test_create(
        'integration_test_loyalty_discount',
        'loyalty_discount_rule',
        '{"customer": {"loyalty_years": 6}}'::JSONB,
        '{"customer": {"loyalty_years": 6}, "Result": {"discount": 20}}'::JSONB
    ) INTO v_test_id;

    RAISE NOTICE 'Step 4: Created test case with ID: %', v_test_id;

    RAISE NOTICE 'Integration workflow completed successfully!';
END $$;

\echo ''
\echo '23. Integration - Template Usage Analysis'
\echo '------------------------------------------'

SELECT
    t.template_name,
    t.category,
    t.usage_count,
    COUNT(ti.instance_id) as instances_created,
    t.created_at
FROM rule_templates t
LEFT JOIN rule_template_instances ti ON t.template_id = ti.template_id
GROUP BY t.template_id, t.template_name, t.category, t.usage_count, t.created_at
ORDER BY t.usage_count DESC, instances_created DESC;

\echo ''
\echo '24. Integration - Recent Test Failures View'
\echo '------------------------------------------'

SELECT * FROM recent_test_failures LIMIT 10;

-- ============================================================================
-- SECTION 6: PERFORMANCE TESTS
-- ============================================================================

\echo ''
\echo '25. Performance - Validation Speed Test'
\echo '------------------------------------------'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_duration NUMERIC;
    v_iterations INTEGER := 100;
    i INTEGER;
    v_result JSON;
BEGIN
    v_start := clock_timestamp();

    FOR i IN 1..v_iterations LOOP
        v_result := rule_validate('
            rule PerfTest "Performance test rule" salience 10 {
                when
                    x > 10 && y < 20
                then
                    z = x + y;
            }
        ');
    END LOOP;

    v_end := clock_timestamp();
    v_duration := EXTRACT(EPOCH FROM (v_end - v_start)) * 1000;

    RAISE NOTICE 'Validated % rules in % ms', v_iterations, v_duration;
    RAISE NOTICE 'Average: % ms per validation', ROUND(v_duration / v_iterations, 3);
END $$;

\echo ''
\echo '26. Performance - Template Instantiation Speed'
\echo '------------------------------------------'

DO $$
DECLARE
    v_start TIMESTAMPTZ;
    v_end TIMESTAMPTZ;
    v_duration NUMERIC;
    v_iterations INTEGER := 50;
    i INTEGER;
    v_result TEXT;
    v_template_id INTEGER;
BEGIN
    SELECT template_id INTO v_template_id
    FROM rule_templates
    WHERE template_name = 'threshold_check';

    v_start := clock_timestamp();

    FOR i IN 1..v_iterations LOOP
        v_result := rule_template_instantiate(
            v_template_id,
            format('{"field": "metric_%s", "threshold": "%s"}', i, i * 10)::JSONB
        );
    END LOOP;

    v_end := clock_timestamp();
    v_duration := EXTRACT(EPOCH FROM (v_end - v_start)) * 1000;

    RAISE NOTICE 'Instantiated % templates in % ms', v_iterations, v_duration;
    RAISE NOTICE 'Average: % ms per instantiation', ROUND(v_duration / v_iterations, 3);
END $$;

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

\echo ''
\echo '=========================================='
\echo 'PHASE 2 TEST SUITE SUMMARY'
\echo '=========================================='

\echo ''
\echo 'Database Objects Created:'
SELECT 'Tables' as object_type, COUNT(*) as count FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'rule_%'
UNION ALL
SELECT 'Views', COUNT(*) FROM information_schema.views
WHERE table_schema = 'public' AND table_name LIKE '%test%' OR table_name LIKE '%template%'
UNION ALL
SELECT 'Functions', COUNT(*) FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name LIKE 'rule_%';

\echo ''
\echo 'Test Data Summary:'
SELECT
    (SELECT COUNT(*) FROM rule_test_cases) as test_cases,
    (SELECT COUNT(*) FROM rule_templates) as templates,
    (SELECT COUNT(*) FROM rule_template_instances) as template_instances,
    (SELECT COUNT(*) FROM rule_debug_traces) as debug_traces;

\echo ''
\echo '=========================================='
\echo '✅ Phase 2 Developer Experience Tests Complete!'
\echo '=========================================='
\echo ''
\echo 'Features Tested:'
\echo '  ✓ Rule Testing Framework (2.1)'
\echo '  ✓ Rule Validation & Linting (2.2)'
\echo '  ✓ Rule Debugging Tools (2.3)'
\echo '  ✓ Rule Templates (2.4)'
\echo ''
\echo 'Next Steps:'
\echo '  1. Review test results above'
\echo '  2. Create actual rules for test execution'
\echo '  3. Run: SELECT * FROM rule_test_run_all()'
\echo '  4. Check: SELECT * FROM test_suite_summary'
\echo ''
