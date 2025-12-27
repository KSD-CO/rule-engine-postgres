-- Simple Debug Test
-- Test existing debug functionality

\timing on

\echo ''
\echo '========================================='
\echo 'SIMPLE DEBUG TEST (v1.x functions)'
\echo '========================================='
\echo ''

-- ============================================================================
-- TEST 1: Basic Debug Execution
-- ============================================================================
\echo 'TEST 1: Basic debug execution with rule_debug_execute'
\echo '-------------------------------------'

SELECT rule_debug_execute(
    '{"Order": {"total": 1500}}'::jsonb,
    'rule "Discount" { when Order.total > 1000 then Order.discount = Order.total * 0.1; }'
) AS result;

\echo ''

-- ============================================================================
-- TEST 2: Complex Rules Debug
-- ============================================================================
\echo 'TEST 2: Complex rules debug'
\echo '-------------------------------------'

SELECT rule_debug_execute(
    '{"Customer": {"age": 30, "income": 50000, "credit_score": 750}}'::jsonb,
    '
    rule "Adult" salience 100 { when Customer.age > 18 then Customer.adult = true; }
    rule "Stable" salience 90 { when Customer.income > 30000 then Customer.stable = true; }
    rule "GoodCredit" salience 80 { when Customer.credit_score > 700 then Customer.good_credit = true; }
    rule "Prime" salience 70 { when Customer.age > 25 && Customer.income > 40000 then Customer.prime = true; }
    rule "VIP" salience 60 { when Customer.prime == true then Customer.vip = true; }
    '
) AS result;

\echo ''

-- ============================================================================
-- TEST 3: Performance Comparison
-- ============================================================================
\echo 'TEST 3: Debug vs Normal Performance'
\echo '-------------------------------------'

\echo 'Normal RETE execution:'
SELECT run_rule_engine(
    '{"Order": {"total": 1500}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = Order.total * 0.1; }'
) AS result \gset

\echo ''
\echo 'Debug execution:'
SELECT rule_debug_execute(
    '{"Order": {"total": 1500}}'::jsonb,
    'rule "Discount" { when Order.total > 1000 then Order.discount = Order.total * 0.1; }'
) AS result \gset

-- ============================================================================
-- TEST 4: Batch Debug Test (10 iterations)
-- ============================================================================
\echo ''
\echo 'TEST 4: Batch debug test (10 iterations)'
\echo '-------------------------------------'

DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
    result JSON;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..10 LOOP
        SELECT rule_debug_execute(
            format('{"Order": {"id": %s, "total": %s}}', i, 1000 + i * 100)::jsonb,
            'rule "VIP" { when Order.total > 1500 then Order.vip = true; }'
        ) INTO result;
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE 'Debug mode (10 iterations): %.1f ms total, %.1f ms average',
                 total_ms, total_ms / 10;
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'DEBUG TEST SUMMARY'
\echo '========================================='
\echo ''
\echo 'Available debug functions:'
\df *debug*

\echo ''
\echo 'Note: v2.0.0 debug functions (run_rule_engine_debug, debug_get_events, etc.)'
\echo '      will be available after SQL schema generation is fixed.'
\echo ''
\echo 'Current debug function (rule_debug_execute) works but uses v1.x architecture.'
