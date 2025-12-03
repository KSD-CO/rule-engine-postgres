-- SQL Tests for rule_engine_postgre_extensions
-- Run these tests after installing the extension

-- Setup
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions;

-- Test 1: Basic rule execution
\echo 'Test 1: Basic rule execution'
SELECT run_rule_engine(
    '{"User": {"age": 25}}',
    'rule "SetStatus" { when User.age > 18 then User.status = "adult" }'
) AS result;

-- Test 2: Empty facts error
\echo 'Test 2: Empty facts should return error'
SELECT run_rule_engine('', 'rule "Test" {}') AS result;

-- Test 3: Empty rules error
\echo 'Test 3: Empty rules should return error'
SELECT run_rule_engine('{"test": 1}', '') AS result;

-- Test 4: Invalid JSON error
\echo 'Test 4: Invalid JSON should return error'
SELECT run_rule_engine('{"invalid json', 'rule "Test" {}') AS result;

-- Test 5: Non-object JSON error
\echo 'Test 5: Non-object JSON should return error'
SELECT run_rule_engine('[1, 2, 3]', 'rule "Test" {}') AS result;

-- Test 6: Customer tier classification
\echo 'Test 6: Customer tier classification'
SELECT run_rule_engine(
    '{"Customer": {"points": 1500, "years": 3}}',
    'rule "PlatinumTier" {
        when Customer.points > 1000 and Customer.years > 2
        then Customer.tier = "Platinum"
    }'
) AS result;

-- Test 7: Multiple rules
\echo 'Test 7: Multiple rules execution'
SELECT run_rule_engine(
    '{"Order": {"amount": 150}}',
    '
    rule "HighValue" {
        when Order.amount > 100
        then Order.priority = "high"
    }
    rule "Discount" {
        when Order.amount > 100
        then Order.discount = 0.1
    }
    '
) AS result;

-- Test 8: Fraud detection example
\echo 'Test 8: Fraud detection'
SELECT run_rule_engine(
    '{"Transaction": {"amount": 5000, "country": "VN", "time": "23:30"}}',
    '
    rule "HighValueAlert" {
        when Transaction.amount > 3000
        then Transaction.flag = "review_required"
    }
    '
) AS result;

-- Test 9: Nested objects
\echo 'Test 9: Nested objects handling'
SELECT run_rule_engine(
    '{"Order": {"customer": {"tier": "VIP"}, "total": 500}}',
    'rule "VIPDiscount" {
        when Order.customer.tier == "VIP" and Order.total > 300
        then Order.discount = 0.15
    }'
) AS result;

-- Test 10: Boolean values
\echo 'Test 10: Boolean values'
SELECT run_rule_engine(
    '{"User": {"active": true, "verified": false}}',
    'rule "CheckActive" {
        when User.active == true
        then User.canLogin = true
    }'
) AS result;

\echo ''
\echo 'All tests completed!'
\echo 'Check results above for any errors.'
