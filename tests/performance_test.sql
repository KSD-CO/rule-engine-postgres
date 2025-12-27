-- Performance Test Suite for RETE Engine
-- Compares RETE performance with various rule complexities

-- Setup: Create test table for results
CREATE TABLE IF NOT EXISTS perf_test_results (
    test_name TEXT,
    engine_type TEXT,
    facts_count INT,
    rules_count INT,
    execution_time_ms NUMERIC,
    result_size INT,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Clean previous results
TRUNCATE TABLE perf_test_results;

\timing on

-- ============================================================================
-- TEST 1: Simple Rule (Baseline)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 1: Simple Rule (1 fact, 1 rule)'
\echo '========================================='

-- RETE Engine
\echo 'Running with RETE engine...'
SELECT run_rule_engine(
    '{"Order": {"total": 150, "country": "US"}}',
    'rule "HighValue" { when Order.total > 100 then Order.approved = true; }'
) AS result \gset

\echo 'Result:' :result

-- ============================================================================
-- TEST 2: Multiple Rules (10 rules)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 2: Multiple Rules (1 fact, 10 rules)'
\echo '========================================='

SELECT run_rule_engine(
    '{"Customer": {"age": 30, "income": 50000, "credit_score": 750, "country": "US", "vip": false}}',
    '
    rule "Rule1" salience 100 { when Customer.age > 18 then Customer.adult = true; }
    rule "Rule2" salience 90 { when Customer.income > 30000 then Customer.stable = true; }
    rule "Rule3" salience 80 { when Customer.credit_score > 700 then Customer.good_credit = true; }
    rule "Rule4" salience 70 { when Customer.country == "US" then Customer.domestic = true; }
    rule "Rule5" salience 60 { when Customer.age > 25 && Customer.income > 40000 then Customer.prime = true; }
    rule "Rule6" salience 50 { when Customer.credit_score > 650 && Customer.income > 35000 then Customer.qualified = true; }
    rule "Rule7" salience 40 { when Customer.adult == true && Customer.stable == true then Customer.reliable = true; }
    rule "Rule8" salience 30 { when Customer.good_credit == true && Customer.domestic == true then Customer.preferred = true; }
    rule "Rule9" salience 20 { when Customer.prime == true && Customer.qualified == true then Customer.vip = true; }
    rule "Rule10" salience 10 { when Customer.vip == true then Customer.discount = 15; }
    '
) AS result \gset

\echo 'Result length:'
SELECT length(:'result');

-- ============================================================================
-- TEST 3: Complex Conditions (Chained Rules)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 3: Chained Rules (5 rules with dependencies)'
\echo '========================================='

SELECT run_rule_engine(
    '{"Application": {"income": 60000, "debt": 15000, "credit_score": 720, "employment_years": 5}}',
    '
    rule "CalculateDTI" salience 100 {
        when Application.income > 0
        then Application.dti = Application.debt / Application.income * 100;
    }
    rule "CheckDTI" salience 90 {
        when Application.dti < 40
        then Application.dti_ok = true;
    }
    rule "CheckCredit" salience 80 {
        when Application.credit_score > 680
        then Application.credit_ok = true;
    }
    rule "CheckEmployment" salience 70 {
        when Application.employment_years >= 2
        then Application.employment_ok = true;
    }
    rule "FinalApproval" salience 60 {
        when Application.dti_ok == true &&
             Application.credit_ok == true &&
             Application.employment_ok == true
        then Application.approved = true;
             Application.approval_amount = Application.income * 3;
    }
    '
) AS result \gset

\echo 'Result:' :result

-- ============================================================================
-- TEST 4: Built-in Functions (v1.7.0 features)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 4: Built-in Functions (String, Math, DateTime)'
\echo '========================================='

SELECT run_rule_engine(
    '{"User": {"email": "test@example.com", "signup_date": "2024-01-01", "score": 87.5}}',
    '
    rule "ValidateEmail" {
        when IsValidEmail(User.email) == true
        then User.email_valid = true;
    }
    rule "CalculateDays" {
        when User.signup_date != ""
        then User.days_since_signup = DaysSince(User.signup_date);
    }
    rule "RoundScore" {
        when User.score > 0
        then User.rounded_score = Round(User.score, 0);
    }
    rule "CheckLength" {
        when Length(User.email) > 5
        then User.email_ok = true;
    }
    '
) AS result \gset

\echo 'Result:' :result

-- ============================================================================
-- TEST 5: Stress Test (100 rules)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 5: Stress Test (Many rules)'
\echo '========================================='

-- Generate 50 simple rules dynamically
DO $$
DECLARE
    rules TEXT := '';
    i INT;
BEGIN
    FOR i IN 1..50 LOOP
        rules := rules || format('
            rule "AutoRule%s" salience %s {
                when Data.value > %s
                then Data.flag%s = true;
            }
        ', i, 1000 - i, i * 2, i);
    END LOOP;

    -- Execute with generated rules
    RAISE NOTICE 'Executing 50 auto-generated rules...';
    PERFORM run_rule_engine(
        '{"Data": {"value": 100}}',
        rules
    );
END $$;

-- ============================================================================
-- TEST 6: Debugging Overhead Test
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 6: Debug Mode Overhead'
\echo '========================================='

\echo 'Normal execution (RETE):'
SELECT run_rule_engine(
    '{"Order": {"total": 500, "items": 10}}',
    '
    rule "Calculate" {
        when Order.total > 0
        then Order.per_item = Order.total / Order.items;
    }
    rule "Discount" {
        when Order.total > 400
        then Order.discount = Order.total * 0.1;
    }
    '
) AS result \gset

\echo 'With debugging enabled:'
SELECT * FROM run_rule_engine_debug(
    '{"Order": {"total": 500, "items": 10}}',
    '
    rule "Calculate" {
        when Order.total > 0
        then Order.per_item = Order.total / Order.items;
    }
    rule "Discount" {
        when Order.total > 400
        then Order.discount = Order.total * 0.1;
    }
    '
);

-- ============================================================================
-- TEST 7: Real-World Scenario (E-commerce Order Processing)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 7: Real-World E-commerce Scenario'
\echo '========================================='

SELECT run_rule_engine(
    '{
        "Order": {
            "total": 1250,
            "items_count": 5,
            "customer_type": "gold",
            "shipping_country": "US",
            "has_coupon": true
        },
        "Customer": {
            "lifetime_value": 5000,
            "orders_count": 15,
            "satisfaction_score": 4.8
        }
    }',
    '
    rule "VIPCustomer" salience 100 {
        when Customer.lifetime_value > 1000
        then Customer.vip = true;
    }
    rule "BaseDiscount" salience 90 {
        when Order.customer_type == "gold"
        then Order.discount_pct = 10;
    }
    rule "VIPBonus" salience 80 {
        when Customer.vip == true && Order.total > 1000
        then Order.discount_pct = 15;
    }
    rule "CouponBonus" salience 70 {
        when Order.has_coupon == true
        then Order.discount_pct = Order.discount_pct + 5;
    }
    rule "CalculateDiscount" salience 60 {
        when Order.discount_pct > 0
        then Order.discount_amount = Order.total * Order.discount_pct / 100;
    }
    rule "ApplyDiscount" salience 50 {
        when Order.discount_amount > 0
        then Order.final_total = Order.total - Order.discount_amount;
    }
    rule "FreeShipping" salience 40 {
        when Order.final_total > 1000
        then Order.free_shipping = true;
    }
    rule "LoyaltyPoints" salience 30 {
        when Customer.vip == true
        then Order.loyalty_points = Order.final_total * 2;
    }
    '
) AS result \gset

\echo 'Final result:' :result

-- ============================================================================
-- SUMMARY
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'PERFORMANCE TEST SUMMARY'
\echo '========================================='
\echo 'All tests completed!'
\echo 'RETE engine is now the default for run_rule_engine()'
\echo 'Expected: 2-24x faster than traditional forward chaining'
\echo ''
\echo 'Debug sessions created:'
SELECT COUNT(*) AS debug_sessions FROM (SELECT * FROM debug_list_sessions()) AS sessions;

\echo ''
\echo 'To view debug events for a session:'
\echo 'SELECT * FROM debug_get_events(''session_<uuid>'');'
