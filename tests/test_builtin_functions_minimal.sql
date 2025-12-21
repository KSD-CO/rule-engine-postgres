-- Minimal test for Built-in Functions (v1.7.0)
-- Tests functions in WHEN conditions (primary use case)

\echo '========================================='
\echo 'Testing Built-in Functions via GRL'
\echo '========================================='

-- Test 1: Email Validation in When Condition
\echo ''
\echo 'Test 1: IsValidEmail in When Condition'
\echo 'Expected: Customer.approved = true'
SELECT run_rule_engine(
    '{
        "Customer": {
            "email": "valid@example.com",
            "approved": false
        }
    }',
    'rule "ValidEmail" {
        when IsValidEmail(Customer.email) == true
        then Customer.approved = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Customer' -> 'approved' AS approved;

-- Test 2: Invalid Email - Should NOT Approve
\echo ''
\echo 'Test 2: Invalid Email - Should NOT Approve'
\echo 'Expected: Customer.approved = false (unchanged)'
SELECT run_rule_engine(
    '{
        "Customer": {
            "email": "not-an-email",
            "approved": false
        }
    }',
    'rule "ValidEmail" {
        when IsValidEmail(Customer.email) == true
        then Customer.approved = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Customer' -> 'approved' AS approved;

-- Test 3: ToUpper in When Condition
\echo ''
\echo 'Test 3: ToUpper in When Condition'
\echo 'Expected: Product.isElectronics = true'
SELECT run_rule_engine(
    '{
        "Product": {
            "category": "electronics",
            "isElectronics": false
        }
    }',
    'rule "CheckCategory" {
        when ToUpper(Product.category) == "ELECTRONICS"
        then Product.isElectronics = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Product' -> 'isElectronics' AS is_electronics;

-- Test 4: Min Function in When Condition
\echo ''
\echo 'Test 4: Min Function in When Condition'
\echo 'Expected: Prices.hasLowPrice = true'
SELECT run_rule_engine(
    '{
        "Prices": {
            "p1": 10.0,
            "p2": 50.0,
            "p3": 30.0,
            "hasLowPrice": false
        }
    }',
    'rule "CheckMinPrice" {
        when Min(Prices.p1, Prices.p2, Prices.p3) < 15.0
        then Prices.hasLowPrice = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Prices' -> 'hasLowPrice' AS has_low_price;

-- Test 5: Round Function in When Condition
\echo ''
\echo 'Test 5: Round Function in When Condition'
\echo 'Expected: Price.isRounded = true'
SELECT run_rule_engine(
    '{
        "Price": {
            "value": 10.567,
            "isRounded": false
        }
    }',
    'rule "CheckRounded" {
        when Round(Price.value, 2) == 10.57
        then Price.isRounded = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Price' -> 'isRounded' AS is_rounded;

-- Test 6: DaysSince Function in When Condition
\echo ''
\echo 'Test 6: DaysSince in When Condition'
\echo 'Expected: Order.isOld = true'
SELECT run_rule_engine(
    '{
        "Order": {
            "createdAt": "2024-01-01",
            "isOld": false
        }
    }',
    'rule "CheckAge" {
        when DaysSince(Order.createdAt) > 30
        then Order.isOld = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Order' -> 'isOld' AS is_old;

-- Test 7: Length Function in When Condition
\echo ''
\echo 'Test 7: Length in When Condition'
\echo 'Expected: Text.isShort = true'
SELECT run_rule_engine(
    '{
        "Text": {
            "value": "hello",
            "isShort": false
        }
    }',
    'rule "CheckLength" {
        when Length(Text.value) < 10
        then Text.isShort = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Text' -> 'isShort' AS is_short;

-- Test 8: Abs Function in When Condition
\echo ''
\echo 'Test 8: Abs in When Condition'
\echo 'Expected: Number.isSmall = true'
SELECT run_rule_engine(
    '{
        "Number": {
            "value": -42,
            "isSmall": false
        }
    }',
    'rule "CheckAbs" {
        when Abs(Number.value) < 50
        then Number.isSmall = true;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb -> 'Number' -> 'isSmall' AS is_small;

\echo ''
\echo '========================================='
\echo 'Minimal Built-in Functions Tests Complete!'
\echo '========================================='
