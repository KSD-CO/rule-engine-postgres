-- Test Built-in Functions Fix
-- This tests the fix for built-in functions returning string references

\echo '================================================'
\echo 'Testing Built-in Functions Fix'
\echo '================================================'

-- Need to rebuild and reinstall extension first
\echo ''
\echo 'IMPORTANT: Run these commands first:'
\echo '  cargo pgrx install --release'
\echo '  sudo systemctl restart postgresql'
\echo ''

-- Drop and recreate extension with new code
DROP EXTENSION IF EXISTS rule_engine_postgre_extensions CASCADE;
CREATE EXTENSION rule_engine_postgre_extensions;

\echo ''
\echo '=== Test 1: IsValidEmail (Previously Returned String Reference) ==='
SELECT run_rule_engine(
    '{"Customer": {"email": "user@example.com", "valid": false}}',
    'rule "ValidateEmail" {
        when Customer.email != nil
        then Customer.valid = IsValidEmail(Customer.email);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Customer": {"email": "user@example.com", "valid": true}}'
\echo 'Should NOT contain: "__func_0_isvalidemail"'

\echo ''
\echo '=== Test 2: Min Function ==='
SELECT run_rule_engine(
    '{"Data": {"a": 10.5, "b": 99.99, "minimum": 0}}',
    'rule "FindMin" {
        when Data.a > 0
        then Data.minimum = Min(Data.a, Data.b);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Data": {"a": 10.5, "b": 99.99, "minimum": 10.5}}'
\echo 'Should NOT contain: "__func_0_min"'

\echo ''
\echo '=== Test 3: Round Function ==='
SELECT run_rule_engine(
    '{"Order": {"subtotal": 100.00, "taxRate": 0.08, "total": 0}}',
    'rule "Calculate" {
        when Order.subtotal > 0
        then Order.total = Round(Order.subtotal * (1 + Order.taxRate), 2);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Order": {"subtotal": 100.00, "taxRate": 0.08, "total": 108.0}}'
\echo 'Note: Round result should be numeric, not string reference'

\echo ''
\echo '=== Test 4: ToUpper Function ==='
SELECT run_rule_engine(
    '{"Product": {"name": "laptop", "nameUpper": ""}}',
    'rule "Uppercase" {
        when Product.name != nil
        then Product.nameUpper = ToUpper(Product.name);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Product": {"name": "laptop", "nameUpper": "LAPTOP"}}'

\echo ''
\echo '=== Test 5: Contains Function ==='
SELECT run_rule_engine(
    '{"Product": {"name": "Smartphone Pro Max", "hasKeyword": false}}',
    'rule "CheckKeyword" {
        when Product.name != nil
        then Product.hasKeyword = Contains(Product.name, "Pro");
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Product": {"name": "Smartphone Pro Max", "hasKeyword": true}}'

\echo ''
\echo '=== Test 6: Max Function ==='
SELECT run_rule_engine(
    '{"Stats": {"value1": 42, "value2": 85, "maximum": 0}}',
    'rule "FindMax" {
        when Stats.value1 > 0
        then Stats.maximum = Max(Stats.value1, Stats.value2);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Stats": {"value1": 42, "value2": 85, "maximum": 85}}'

\echo ''
\echo '=== Test 7: Abs Function ==='
SELECT run_rule_engine(
    '{"Balance": {"amount": -42.5, "absolute": 0}}',
    'rule "GetAbsolute" {
        when Balance.amount < 0
        then Balance.absolute = Abs(Balance.amount);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Balance": {"amount": -42.5, "absolute": 42.5}}'

\echo ''
\echo '=== Test 8: Length Function ==='
SELECT run_rule_engine(
    '{"User": {"username": "admin", "length": 0}}',
    'rule "GetLength" {
        when User.username != nil
        then User.length = Length(User.username);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"User": {"username": "admin", "length": 5}}'

\echo ''
\echo '=== Test 9: Multiple Functions in One Rule ==='
SELECT run_rule_engine(
    '{"Customer": {"email": "JOHN@EXAMPLE.COM", "emailValid": false, "emailLower": ""}}',
    'rule "ProcessEmail" {
        when Customer.email != nil
        then Customer.emailValid = IsValidEmail(Customer.email);
             Customer.emailLower = ToLower(Customer.email);
    }'
)::jsonb;

\echo ''
\echo 'Expected: emailValid=true, emailLower="john@example.com"'

\echo ''
\echo '=== Test 10: Nested Function Calls ==='
SELECT run_rule_engine(
    '{"Price": {"value": 10.567, "rounded": 0}}',
    'rule "RoundPrice" {
        when Price.value > 0
        then Price.rounded = Round(Abs(Price.value), 2);
    }'
)::jsonb;

\echo ''
\echo 'Expected: {"Price": {"value": 10.567, "rounded": 10.57}}'
\echo 'Note: This tests if nested functions work (Abs inside Round)'

\echo ''
\echo '================================================'
\echo 'Test Summary'
\echo '================================================'
\echo 'If all tests show ACTUAL VALUES (not string references),'
\echo 'the fix is working correctly!'
\echo ''
\echo 'Key Changes:'
\echo '  - Functions now inject literal values directly into GRL'
\echo '  - No more "__func_X_functionname" field references'
\echo '  - Results are real values, not strings'
\echo '================================================'
