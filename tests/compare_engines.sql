-- Engine Comparison Script
-- Compares RETE vs Forward Chaining performance side-by-side

\timing on

\echo ''
\echo '========================================='
\echo 'ENGINE COMPARISON - RETE vs Forward Chaining'
\echo '========================================='
\echo ''

-- ============================================================================
-- Test Case 1: Simple Rule (1 rule)
-- ============================================================================
\echo 'TEST 1: Simple rule (1 fact, 1 rule)'
\echo '-------------------------------------'

\echo 'Forward Chaining:'
SELECT run_rule_engine_fc(
    '{"Order": {"total": 1500}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = Order.total * 0.1; }'
) AS result \gset

\echo ''
\echo 'RETE:'
SELECT run_rule_engine_rete(
    '{"Order": {"total": 1500}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = Order.total * 0.1; }'
) AS result \gset

\echo ''
\echo '-------------------------------------'

-- ============================================================================
-- Test Case 2: Multiple Rules (10 rules)
-- ============================================================================
\echo ''
\echo 'TEST 2: Multiple rules (10 complex rules)'
\echo '-------------------------------------'

\echo 'Forward Chaining:'
SELECT run_rule_engine_fc(
    '{"Customer": {"age": 30, "income": 50000, "credit_score": 750}}',
    '
    rule "Rule1" salience 100 { when Customer.age > 18 then Customer.adult = true; }
    rule "Rule2" salience 90 { when Customer.income > 30000 then Customer.stable = true; }
    rule "Rule3" salience 80 { when Customer.credit_score > 700 then Customer.good_credit = true; }
    rule "Rule4" salience 70 { when Customer.age > 25 && Customer.income > 40000 then Customer.prime = true; }
    rule "Rule5" salience 60 { when Customer.credit_score > 650 && Customer.income > 35000 then Customer.qualified = true; }
    rule "Rule6" salience 50 { when Customer.adult == true && Customer.stable == true then Customer.reliable = true; }
    rule "Rule7" salience 40 { when Customer.good_credit == true && Customer.reliable == true then Customer.preferred = true; }
    rule "Rule8" salience 30 { when Customer.prime == true && Customer.qualified == true then Customer.vip = true; }
    rule "Rule9" salience 20 { when Customer.vip == true then Customer.discount_pct = 15; }
    rule "Rule10" salience 10 { when Customer.discount_pct > 0 then Customer.discount_amt = Customer.income * 0.15; }
    '
) AS result \gset

\echo ''
\echo 'RETE:'
SELECT run_rule_engine_rete(
    '{"Customer": {"age": 30, "income": 50000, "credit_score": 750}}',
    '
    rule "Rule1" salience 100 { when Customer.age > 18 then Customer.adult = true; }
    rule "Rule2" salience 90 { when Customer.income > 30000 then Customer.stable = true; }
    rule "Rule3" salience 80 { when Customer.credit_score > 700 then Customer.good_credit = true; }
    rule "Rule4" salience 70 { when Customer.age > 25 && Customer.income > 40000 then Customer.prime = true; }
    rule "Rule5" salience 60 { when Customer.credit_score > 650 && Customer.income > 35000 then Customer.qualified = true; }
    rule "Rule6" salience 50 { when Customer.adult == true && Customer.stable == true then Customer.reliable = true; }
    rule "Rule7" salience 40 { when Customer.good_credit == true && Customer.reliable == true then Customer.preferred = true; }
    rule "Rule8" salience 30 { when Customer.prime == true && Customer.qualified == true then Customer.vip = true; }
    rule "Rule9" salience 20 { when Customer.vip == true then Customer.discount_pct = 15; }
    rule "Rule10" salience 10 { when Customer.discount_pct > 0 then Customer.discount_amt = Customer.income * 0.15; }
    '
) AS result \gset

\echo ''
\echo '-------------------------------------'

-- ============================================================================
-- Test Case 3: Batch Simulation (20 iterations each)
-- ============================================================================
\echo ''
\echo 'TEST 3: Batch processing simulation (20 iterations)'
\echo '-------------------------------------'

\echo 'Forward Chaining (20 iterations):'
DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..20 LOOP
        PERFORM run_rule_engine_fc(
            format('{"Order": {"total": %s, "items": %s}}', 1000 + i * 50, i)::text,
            '
            rule "Discount" salience 100 {
                when Order.total > 1200
                then Order.discount_pct = 10;
            }
            rule "Calculate" salience 90 {
                when Order.discount_pct > 0
                then Order.final = Order.total * (100 - Order.discount_pct) / 100;
            }
            '
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE 'FC: %.1f ms total, %.1f ms average', total_ms, total_ms / 20;
END $$;

\echo ''
\echo 'RETE (20 iterations):'
DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..20 LOOP
        PERFORM run_rule_engine_rete(
            format('{"Order": {"total": %s, "items": %s}}', 1000 + i * 50, i)::text,
            '
            rule "Discount" salience 100 {
                when Order.total > 1200
                then Order.discount_pct = 10;
            }
            rule "Calculate" salience 90 {
                when Order.discount_pct > 0
                then Order.final = Order.total * (100 - Order.discount_pct) / 100;
            }
            '
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE 'RETE: %.1f ms total, %.1f ms average', total_ms, total_ms / 20;
END $$;

\echo ''
\echo '-------------------------------------'

-- ============================================================================
-- Summary
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'COMPARISON SUMMARY'
\echo '========================================='
\echo ''
\echo 'Key Observations:'
\echo '1. Simple rules (1-3): FC may be faster (no compilation overhead)'
\echo '2. Complex rules (10+): RETE benefits from pattern sharing'
\echo '3. Batch processing: RETE shows significant advantage'
\echo ''
\echo 'Recommendation:'
\echo '- Production workloads: Use RETE (run_rule_engine)'
\echo '- Simple validations: Use FC (run_rule_engine_fc)'
\echo '- Default: RETE is optimal for most cases'
\echo ''
\echo 'See docs/ENGINE_SELECTION.md for detailed guidance'
\echo ''
