-- Test Case Studies for Rule Engine PostgreSQL Extension
-- These tests verify real-world use cases from README.md

\echo '========================================='
\echo 'Testing Rule Engine Extension'
\echo '========================================='

-- Test 1: Health Check
\echo ''
\echo 'Test 1: Health Check'
SELECT rule_engine_health_check();

-- Test 2: Version Check
\echo ''
\echo 'Test 2: Version'
SELECT rule_engine_version();

-- Test 3: E-Commerce Pricing Rules
\echo ''
\echo 'Test 3: E-Commerce Dynamic Pricing'
\echo 'Expected: Order.discount = 0.20 (20% from LoyaltyBonus)'
\echo 'Expected: Product.discount = 0.25 (25% from FlashSale)'

SELECT run_rule_engine(
    '{
        "Order": {
            "items": 12,
            "total": 150,
            "discount": 0
        },
        "Customer": {
            "tier": "Gold",
            "id": 1001
        },
        "Product": {
            "category": "Electronics",
            "stock": 75
        }
    }',
    'rule "VolumeDiscount" salience 10 {
        when
            Order.items >= 10
        then
            Order.discount = 0.15;
    }

    rule "LoyaltyBonus" salience 20 {
        when
            Customer.tier == "Gold" && Order.total > 100
        then
            Order.discount = 0.20;
    }

    rule "FlashSale" salience 30 {
        when
            Product.category == "Electronics" && Product.stock > 50
        then
            Product.discount = 0.25;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb AS pricing_result;

-- Test 4: Banking Loan Approval
\echo ''
\echo 'Test 4: Banking Loan Approval'
\echo 'Expected: approved = true, maxAmount = 225000, interestRate = 3.5'

SELECT run_rule_engine(
    '{
        "Applicant": {
            "name": "John Doe",
            "creditScore": 780,
            "income": 75000,
            "debtToIncome": 0.25,
            "employmentYears": 5,
            "approved": false,
            "maxAmount": 0,
            "interestRate": 0
        }
    }',
    'rule "HighCreditScore" salience 100 {
        when
            Applicant.creditScore >= 750 && Applicant.income >= 50000
        then
            Applicant.approved = true;
            Applicant.maxAmount = Applicant.income * 3;
            Applicant.interestRate = 3.5;
    }

    rule "MediumCredit" salience 90 {
        when
            Applicant.creditScore >= 650 && Applicant.creditScore < 750 &&
            Applicant.debtToIncome < 0.4
        then
            Applicant.approved = true;
            Applicant.maxAmount = Applicant.income * 2;
            Applicant.interestRate = 5.5;
    }

    rule "LowCredit" salience 80 {
        when
            Applicant.creditScore < 650 || Applicant.debtToIncome >= 0.4
        then
            Applicant.approved = false;
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb AS loan_result;

-- Test 5: SaaS Billing Tiers
\echo ''
\echo 'Test 5: SaaS Usage-Based Billing'
\echo 'Expected: tier = "pro", baseCharge = 99, overageCharge = 27.5'

SELECT run_rule_engine(
    '{
        "Usage": {
            "apiCalls": 50000,
            "storageGB": 75,
            "users": 15,
            "tier": "free",
            "baseCharge": 0,
            "overageCharge": 0
        }
    }',
    'rule "ProTier" salience 80 {
        when
            Usage.apiCalls > 10000 && Usage.apiCalls <= 100000
        then
            Usage.tier = "pro";
            Usage.baseCharge = 99;
    }

    rule "StorageOverage" salience 60 {
        when
            Usage.storageGB > 50
        then
            Usage.overageCharge = Usage.overageCharge + ((Usage.storageGB - 50) * 0.10);
    }

    rule "UserOverage" salience 50 {
        when
            Usage.users > 10
        then
            Usage.overageCharge = Usage.overageCharge + ((Usage.users - 10) * 5);
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb AS billing_result;

-- Test 6: Healthcare Patient Risk Assessment
\echo ''
\echo 'Test 6: Healthcare Patient Risk Assessment'
\echo 'Expected: riskScore = 90, riskLevel = "high"'

SELECT run_rule_engine(
    '{
        "Patient": {
            "age": 68,
            "bmi": 32.0,
            "bloodPressure": "high",
            "diabetes": true,
            "smoking": false,
            "riskScore": 0,
            "riskLevel": "low"
        }
    }',
    'rule "AgeRisk" salience 100 {
        when
            Patient.age > 65
        then
            Patient.riskScore = Patient.riskScore + 15;
    }

    rule "ObesityRisk" salience 90 {
        when
            Patient.bmi > 30
        then
            Patient.riskScore = Patient.riskScore + 20;
    }

    rule "HypertensionRisk" salience 80 {
        when
            Patient.bloodPressure == "high"
        then
            Patient.riskScore = Patient.riskScore + 25;
    }

    rule "DiabetesRisk" salience 70 {
        when
            Patient.diabetes == true
        then
            Patient.riskScore = Patient.riskScore + 30;
    }

    rule "HighRiskLevel" salience 30 {
        when
            Patient.riskScore >= 60
        then
            Patient.riskLevel = "high";
    }'
) AS result \gset

\echo 'Result:'
SELECT :'result'::jsonb AS risk_result;

-- Test 7: Error Handling - Empty Facts
\echo ''
\echo 'Test 7: Error Handling - Empty Facts'
\echo 'Expected: error_code = "ERR001"'

SELECT run_rule_engine(
    '',
    'rule "Test" { when x > 5 then y = 10; }'
)::jsonb AS empty_facts_error;

-- Test 8: Error Handling - Empty Rules
\echo ''
\echo 'Test 8: Error Handling - Empty Rules'
\echo 'Expected: error_code = "ERR002"'

SELECT run_rule_engine(
    '{"User": {"age": 30}}',
    ''
)::jsonb AS empty_rules_error;

-- Test 9: Error Handling - Invalid JSON
\echo ''
\echo 'Test 9: Error Handling - Invalid JSON'
\echo 'Expected: error_code = "ERR005"'

SELECT run_rule_engine(
    '{invalid json',
    'rule "Test" { when x > 5 then y = 10; }'
)::jsonb AS invalid_json_error;

-- Test 10: Error Handling - Invalid GRL Syntax
\echo ''
\echo 'Test 10: Error Handling - Invalid GRL Syntax'
\echo 'Expected: error_code = "ERR008"'

SELECT run_rule_engine(
    '{"User": {"age": 30}}',
    'rule "Invalid" { when x > 5 INVALID y = 10; }'
)::jsonb AS invalid_grl_error;

-- Test 11: Nested Objects
\echo ''
\echo 'Test 11: Nested Objects Support'
\echo 'Expected: Company.Employee.bonus = 5000'

SELECT run_rule_engine(
    '{
        "Company": {
            "name": "TechCorp",
            "Employee": {
                "name": "Alice",
                "salary": 50000,
                "bonus": 0
            }
        }
    }',
    'rule "BonusRule" salience 10 {
        when
            Company.Employee.salary > 40000
        then
            Company.Employee.bonus = 5000;
    }'
)::jsonb AS nested_result;

-- Test 12: Rule Priority (Salience)
\echo ''
\echo 'Test 12: Rule Priority (Salience)'
\echo 'Expected: Counter.value = 10 (higher salience executes first)'

SELECT run_rule_engine(
    '{"Counter": {"value": 0}}',
    'rule "First" salience 1 {
        when
            Counter.value == 0
        then
            Counter.value = 1;
    }

    rule "Second" salience 10 {
        when
            Counter.value == 0
        then
            Counter.value = 10;
    }'
)::jsonb AS salience_result;

-- Test 13: Complex Business Rule - Discount Stacking
\echo ''
\echo 'Test 13: Complex Business Rule - Discount Stacking'
\echo 'Expected: Final discount applied based on highest salience rule'

SELECT run_rule_engine(
    '{
        "Cart": {
            "total": 500,
            "itemCount": 8,
            "discount": 0,
            "finalPrice": 0
        },
        "User": {
            "isVIP": true,
            "hasCoupon": true
        }
    }',
    'rule "VIPDiscount" salience 100 {
        when
            User.isVIP == true && Cart.total > 200
        then
            Cart.discount = 0.30;
    }

    rule "CouponDiscount" salience 90 {
        when
            User.hasCoupon == true
        then
            Cart.discount = 0.15;
    }

    rule "BulkDiscount" salience 80 {
        when
            Cart.itemCount >= 5
        then
            Cart.discount = 0.10;
    }

    rule "CalculateFinalPrice" salience 1 {
        when
            Cart.discount > 0
        then
            Cart.finalPrice = Cart.total * (1 - Cart.discount);
    }'
)::jsonb AS discount_stacking;

-- Test 14: Array/List Handling
\echo ''
\echo 'Test 14: Performance Test - Simple Rule'
\echo 'Measuring execution time for simple rule'

\timing on
SELECT run_rule_engine(
    '{"User": {"age": 30, "status": "pending"}}',
    'rule "CheckAge" salience 10 {
        when
            User.age >= 18
        then
            User.status = "adult";
    }'
)::jsonb AS performance_test;
\timing off

\echo ''
\echo '========================================='
\echo 'All Tests Completed!'
\echo '========================================='
