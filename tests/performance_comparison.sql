-- Performance Comparison: RETE vs Traditional Forward Chaining
-- Compares execution times between the two engines

\timing on

-- ============================================================================
-- COMPARISON TEST 1: Simple Rule
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 1: Simple Rule - Performance Comparison'
\echo '========================================='

\echo 'Traditional Forward Chaining:'
SELECT run_rule_engine_legacy(
    '{"Order": {"total": 150, "country": "US"}}',
    'rule "HighValue" { when Order.total > 100 then Order.approved = true; }'
) AS result \gset

\echo ''
\echo 'RETE Engine:'
SELECT run_rule_engine(
    '{"Order": {"total": 150, "country": "US"}}',
    'rule "HighValue" { when Order.total > 100 then Order.approved = true; }'
) AS result \gset

-- ============================================================================
-- COMPARISON TEST 2: Multiple Rules (10 rules)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 2: Multiple Rules (10 rules) - Performance Comparison'
\echo '========================================='

\echo 'Traditional Forward Chaining:'
SELECT run_rule_engine_legacy(
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

\echo ''
\echo 'RETE Engine:'
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

-- ============================================================================
-- COMPARISON TEST 3: Chained Rules
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 3: Chained Rules - Performance Comparison'
\echo '========================================='

\echo 'Traditional Forward Chaining:'
SELECT run_rule_engine_legacy(
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

\echo ''
\echo 'RETE Engine:'
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

-- ============================================================================
-- COMPARISON TEST 4: E-commerce Scenario
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 4: Real-World E-commerce - Performance Comparison'
\echo '========================================='

\echo 'Traditional Forward Chaining:'
SELECT run_rule_engine_legacy(
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

\echo ''
\echo 'RETE Engine:'
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

-- ============================================================================
-- SUMMARY
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'PERFORMANCE COMPARISON SUMMARY'
\echo '========================================='
\echo 'All comparison tests completed!'
\echo ''
\echo 'RETE Engine Benefits:'
\echo '- Incremental evaluation: Only re-evaluates affected rules'
\echo '- Pattern sharing: Common conditions evaluated once'
\echo '- Expected speedup: 2-24x depending on rule complexity'
\echo '- Best for: Many rules, complex conditions, chained dependencies'
