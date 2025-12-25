-- Test Nested Objects Fix
-- This tests the fix for nested JSON support (dotted key flattening)

\echo '================================================'
\echo 'Testing Nested Objects Fix'
\echo '================================================'

-- Drop and recreate extension with new code
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions;

\echo ''
\echo '=== Test 1: Original README Example (Previously FAILED) ==='
SELECT run_rule_engine(
    '{"Order": {"total": 150, "discount": 0}}',
    'rule "Discount" {
        when Order.total > 100
        then Order.discount = Order.total * 0.10;
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Order": {"total": 150, "discount": 15.0}}'

\echo ''
\echo '=== Test 2: Nested with Multiple Fields ==='
SELECT run_rule_engine(
    '{"Customer": {"age": 25, "discount": 0, "eligible": false}}',
    'rule "SeniorDiscount" {
        when Customer.age >= 18
        then Customer.eligible = true; Customer.discount = 0.10;
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Customer": {"age": 25, "discount": 0.10, "eligible": true}}'

\echo ''
\echo '=== Test 3: E-Commerce Example ==='
SELECT run_rule_engine(
    '{"Customer": {"tier": "Gold"}, "Order": {"items": 12, "discount": 0}}',
    'rule "GoldDiscount" salience 10 {
        when Customer.tier == "Gold" && Order.items >= 10
        then Order.discount = 0.15;
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Customer": {"tier": "Gold"}, "Order": {"items": 12, "discount": 0.15}}'

\echo ''
\echo '=== Test 4: Backward Chaining with Nested ==='
SELECT query_backward_chaining(
    '{"User": {"age": 25}}',
    'rule "Vote" { when User.age >= 18 then User.canVote = true; }',
    'User.canVote == true'
)::jsonb -> 'provable';

\echo ''
\echo 'Expected: true'

\echo ''
\echo '=== Test 5: Complex Math Expression ==='
SELECT run_rule_engine(
    '{"Order": {"subtotal": 100.00, "taxRate": 0.08, "total": 0, "discount": 0, "final": 0}}',
    'rule "Calculate" {
        when Order.subtotal > 0
        then Order.total = Order.subtotal * (1 + Order.taxRate);
             Order.discount = Order.total * 0.10;
             Order.final = Order.total - Order.discount;
    }'
)::jsonb;

\echo ''
\echo 'Expected: Order.total=108, Order.discount=10.8, Order.final=97.2'

\echo ''
\echo '=== Test 6: Flat JSON Still Works ==='
SELECT run_rule_engine(
    '{"total": 150, "discount": 0}',
    'rule "Discount" {
        when total > 100
        then discount = total * 0.10;
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"total": 150, "discount": 15.0}'

\echo ''
\echo '=== Test 7: Deep Nesting ==='
SELECT run_rule_engine(
    '{"Company": {"Employee": {"Salary": {"base": 5000, "bonus": 0}}}}',
    'rule "Bonus" {
        when Company.Employee.Salary.base > 3000
        then Company.Employee.Salary.bonus = Company.Employee.Salary.base * 0.20;
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Company": {"Employee": {"Salary": {"base": 5000, "bonus": 1000}}}}'

\echo ''
\echo '================================================'
\echo 'Test Summary'
\echo '================================================'
\echo 'If all tests show expected values, the fix is working!'
\echo ''
\echo 'Key Changes:'
\echo '  - json_to_facts() now flattens nested JSON to dotted keys'
\echo '  - facts_to_json() now reconstructs nested structure from dotted keys'
\echo '  - Both flat and nested JSON are supported'
\echo '================================================'
