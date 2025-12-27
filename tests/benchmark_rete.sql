-- RETE Engine Benchmark - Multiple Iterations
-- Measures performance for batch processing scenarios

\timing on

-- ============================================================================
-- Warm-up: Compile RETE network first time
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'WARM-UP: First execution (includes compilation)'
\echo '========================================='

SELECT run_rule_engine(
    '{"Order": {"total": 1250, "customer_type": "gold"}}',
    'rule "Discount" { when Order.total > 1000 then Order.discount = 125; }'
) AS result \gset

-- ============================================================================
-- Benchmark 1: Single fact processing (10 iterations)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'BENCHMARK 1: Single fact - 10 iterations'
\echo '========================================='

DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..10 LOOP
        PERFORM run_rule_engine(
            format('{"Order": {"total": %s, "customer_type": "gold"}}', 1000 + i * 100)::text,
            'rule "Discount" { when Order.total > 1000 then Order.discount = Order.total * 0.1; }'
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE '10 iterations: %.3f ms total, %.3f ms average', total_ms, total_ms / 10;
END $$;

-- ============================================================================
-- Benchmark 2: Complex rules (10 iterations)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'BENCHMARK 2: Complex rules - 10 iterations'
\echo '========================================='

DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..10 LOOP
        PERFORM run_rule_engine(
            format('{"Customer": {"age": %s, "income": %s, "credit_score": 750}}',
                   20 + i, 30000 + i * 5000)::text,
            '
            rule "Adult" salience 100 { when Customer.age > 18 then Customer.adult = true; }
            rule "Stable" salience 90 { when Customer.income > 30000 then Customer.stable = true; }
            rule "GoodCredit" salience 80 { when Customer.credit_score > 700 then Customer.good_credit = true; }
            rule "Prime" salience 70 { when Customer.age > 25 && Customer.income > 40000 then Customer.prime = true; }
            rule "Qualified" salience 60 { when Customer.credit_score > 650 && Customer.income > 35000 then Customer.qualified = true; }
            '
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE '10 iterations: %.3f ms total, %.3f ms average', total_ms, total_ms / 10;
END $$;

-- ============================================================================
-- Benchmark 3: Batch processing simulation (50 iterations)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'BENCHMARK 3: Batch processing - 50 orders'
\echo '========================================='

DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..50 LOOP
        PERFORM run_rule_engine(
            format('{"Order": {"total": %s, "items": %s, "customer_type": "%s"}}',
                   500 + i * 50, i, CASE WHEN i % 3 = 0 THEN 'gold' ELSE 'silver' END)::text,
            '
            rule "BaseDiscount" salience 100 {
                when Order.customer_type == "gold"
                then Order.discount_pct = 10;
            }
            rule "VolumeDiscount" salience 90 {
                when Order.total > 1000
                then Order.discount_pct = Order.discount_pct + 5;
            }
            rule "Calculate" salience 80 {
                when Order.discount_pct > 0
                then Order.final_total = Order.total * (100 - Order.discount_pct) / 100;
            }
            '
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE '50 orders: %.3f ms total, %.3f ms average, %.1f orders/sec',
                 total_ms, total_ms / 50, 50000 / total_ms;
END $$;

-- ============================================================================
-- Benchmark 4: High-throughput test (100 iterations)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'BENCHMARK 4: High-throughput - 100 evaluations'
\echo '========================================='

DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..100 LOOP
        PERFORM run_rule_engine(
            format('{"Data": {"value": %s, "flag": %s}}', i, i % 2 = 0)::text,
            'rule "Check" { when Data.value > 50 then Data.result = true; }'
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE '100 iterations: %.3f ms total, %.3f ms average, %.1f evals/sec',
                 total_ms, total_ms / 100, 100000 / total_ms;
END $$;

-- ============================================================================
-- Benchmark 5: E-commerce real-world (25 iterations)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'BENCHMARK 5: E-commerce scenario - 25 orders'
\echo '========================================='

DO $$
DECLARE
    i INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_ms NUMERIC;
BEGIN
    start_time := clock_timestamp();

    FOR i IN 1..25 LOOP
        PERFORM run_rule_engine(
            format('{
                "Order": {"total": %s, "customer_type": "%s", "has_coupon": %s},
                "Customer": {"lifetime_value": %s, "vip": false}
            }',
            1000 + i * 100,
            CASE WHEN i % 2 = 0 THEN 'gold' ELSE 'silver' END,
            i % 3 = 0,
            i * 500)::text,
            '
            rule "VIP" salience 100 { when Customer.lifetime_value > 5000 then Customer.vip = true; }
            rule "BaseDiscount" salience 90 { when Order.customer_type == "gold" then Order.discount_pct = 10; }
            rule "VIPBonus" salience 80 { when Customer.vip == true then Order.discount_pct = 15; }
            rule "Coupon" salience 70 { when Order.has_coupon == true then Order.discount_pct = Order.discount_pct + 5; }
            rule "Calculate" salience 60 { when Order.discount_pct > 0 then Order.final = Order.total * (100 - Order.discount_pct) / 100; }
            '
        );
    END LOOP;

    end_time := clock_timestamp();
    total_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;

    RAISE NOTICE '25 orders: %.3f ms total, %.3f ms average, %.1f orders/sec',
                 total_ms, total_ms / 25, 25000 / total_ms;
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'BENCHMARK SUMMARY'
\echo '========================================='
\echo 'RETE Engine throughput metrics:'
\echo '- Simple rules: Target >100 evals/sec'
\echo '- Complex rules: Target >20 evals/sec'
\echo '- E-commerce: Target >50 orders/sec'
\echo ''
\echo 'Note: First execution includes RETE compilation overhead'
\echo 'Subsequent executions benefit from incremental evaluation'
