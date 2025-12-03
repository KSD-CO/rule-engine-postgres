-- Native Backward Chaining Tests using rust-rule-engine v1.7
-- Tests the built-in BackwardEngine functionality

\echo '========================================='
\echo 'Native Backward Chaining Tests'
\echo 'Using rust-rule-engine v1.7 BackwardEngine'
\echo '========================================='

-- Test 1: Simple Goal Query - Can User Buy Product?
\echo ''
\echo 'Test 1: Simple Goal Query'
\echo 'Goal: Can User buy product? (User.CanBuy == true)'
\echo 'Expected: provable = true, with proof trace'

SELECT query_backward_chaining(
    '{
        "User": {
            "Age": 25,
            "HasMoney": true,
            "IsVerified": true,
            "CanBuy": false
        }
    }',
    E'rule "AgeCheck" {
        when
            User.Age >= 18
        then
            User.IsAdult = true;
    }

    rule "PurchaseEligibility" {
        when
            User.IsAdult == true &&
            User.HasMoney == true &&
            User.IsVerified == true
        then
            User.CanBuy = true;
    }',
    'User.CanBuy == true'
)::jsonb AS can_buy_result;

-- Test 2: Loan Approval Goal Query
\echo ''
\echo 'Test 2: Loan Approval Query'
\echo 'Goal: Is loan approved? (Loan.Approved == true)'
\echo 'Expected: provable = true if all prerequisites met'

SELECT query_backward_chaining(
    '{
        "Applicant": {
            "CreditScore": 750,
            "Income": 80000,
            "Employment": "full-time"
        },
        "Loan": {
            "Amount": 50000,
            "Approved": false
        },
        "Checks": {
            "GoodCredit": false,
            "StableIncome": false
        }
    }',
    E'rule "CheckCredit" {
        when
            Applicant.CreditScore >= 700
        then
            Checks.GoodCredit = true;
    }

    rule "CheckIncome" {
        when
            Applicant.Income >= 50000 &&
            Applicant.Employment == "full-time"
        then
            Checks.StableIncome = true;
    }

    rule "ApproveLoan" {
        when
            Checks.GoodCredit == true &&
            Checks.StableIncome == true &&
            Loan.Amount <= 100000
        then
            Loan.Approved = true;
    }',
    'Loan.Approved == true'
)::jsonb AS loan_approval_query;

-- Test 3: Medical Diagnosis Query
\echo ''
\echo 'Test 3: Medical Diagnosis Query'
\echo 'Goal: Does patient have Flu? (Diagnosis.HasFlu == true)'
\echo 'Expected: provable = true based on symptoms'

SELECT query_backward_chaining(
    '{
        "Patient": {
            "Fever": true,
            "Cough": true,
            "Fatigue": true,
            "Temperature": 38.5
        },
        "Symptoms": {
            "HasFeverAndCough": false
        },
        "Diagnosis": {
            "HasFlu": false
        }
    }',
    E'rule "IdentifySymptoms" {
        when
            Patient.Fever == true &&
            Patient.Cough == true &&
            Patient.Temperature >= 38.0
        then
            Symptoms.HasFeverAndCough = true;
    }

    rule "DiagnoseFlu" {
        when
            Symptoms.HasFeverAndCough == true &&
            Patient.Fatigue == true
        then
            Diagnosis.HasFlu = true;
    }',
    'Diagnosis.HasFlu == true'
)::jsonb AS flu_diagnosis_query;

-- Test 4: Multiple Goals Query
\echo ''
\echo 'Test 4: Multiple Goals Query'
\echo 'Goals: Multiple conditions to check'
\echo 'Expected: Array of results for each goal'

SELECT query_backward_chaining_multi(
    '{
        "User": {
            "Age": 25,
            "Income": 60000,
            "IsStudent": false
        },
        "Eligibility": {
            "CanVote": false,
            "CanRetire": false,
            "QualifiesForDiscount": false
        }
    }',
    E'rule "VotingAge" {
        when
            User.Age >= 18
        then
            Eligibility.CanVote = true;
    }

    rule "RetirementAge" {
        when
            User.Age >= 65
        then
            Eligibility.CanRetire = true;
    }

    rule "StudentDiscount" {
        when
            User.IsStudent == true &&
            User.Age < 26
        then
            Eligibility.QualifiesForDiscount = true;
    }',
    ARRAY[
        'Eligibility.CanVote == true',
        'Eligibility.CanRetire == true',
        'Eligibility.QualifiesForDiscount == true'
    ]
)::jsonb AS multiple_goals_result;

-- Test 5: Unprovable Goal (Negative Case)
\echo ''
\echo 'Test 5: Unprovable Goal'
\echo 'Goal: Can user access admin? (User.IsAdmin == true)'
\echo 'Expected: provable = false (no rules can prove this)'

SELECT query_backward_chaining(
    '{
        "User": {
            "Role": "user",
            "IsAdmin": false
        }
    }',
    E'rule "UserRole" {
        when
            User.Role == "admin"
        then
            User.IsAdmin = true;
    }',
    'User.IsAdmin == true'
)::jsonb AS unprovable_goal;

-- Test 6: Simple Boolean Query (Production Mode)
\echo ''
\echo 'Test 6: Simple Boolean Query (Fast, No Proof Trace)'
\echo 'Goal: Is order valid? (Order.Valid == true)'
\echo 'Expected: true/false only'

SELECT can_prove_goal(
    '{
        "Order": {
            "Total": 150,
            "PaymentConfirmed": true,
            "Valid": false
        }
    }',
    E'rule "ValidateOrder" {
        when
            Order.Total > 0 &&
            Order.PaymentConfirmed == true
        then
            Order.Valid = true;
    }',
    'Order.Valid == true'
) AS is_order_valid;

-- Test 7: Complex Goal with Multiple Conditions
\echo ''
\echo 'Test 7: Complex Goal Query'
\echo 'Goal: Can transaction proceed? (Transaction.Approved == true)'
\echo 'Expected: provable = true after multiple rule chains'

SELECT query_backward_chaining(
    '{
        "Account": {
            "Balance": 5000,
            "Status": "active",
            "Verified": true
        },
        "Transaction": {
            "Amount": 1000,
            "Approved": false
        },
        "Checks": {
            "HasFunds": false,
            "AccountGood": false
        }
    }',
    E'rule "CheckFunds" {
        when
            Account.Balance >= Transaction.Amount
        then
            Checks.HasFunds = true;
    }

    rule "CheckAccount" {
        when
            Account.Status == "active" &&
            Account.Verified == true
        then
            Checks.AccountGood = true;
    }

    rule "ApproveTransaction" {
        when
            Checks.HasFunds == true &&
            Checks.AccountGood == true
        then
            Transaction.Approved = true;
    }',
    'Transaction.Approved == true'
)::jsonb AS transaction_approval;

-- Test 8: Goal with OR Conditions
\echo ''
\echo 'Test 8: Goal with OR Conditions'
\echo 'Goal: Is user premium? (User.IsPremium == true)'
\echo 'Expected: provable = true if ANY condition met'

SELECT query_backward_chaining(
    '{
        "User": {
            "PaymentTier": "gold",
            "YearsActive": 2,
            "IsPremium": false
        }
    }',
    E'rule "PremiumByPayment" {
        when
            User.PaymentTier == "gold" || User.PaymentTier == "platinum"
        then
            User.IsPremium = true;
    }

    rule "PremiumByLoyalty" {
        when
            User.YearsActive >= 5
        then
            User.IsPremium = true;
    }',
    'User.IsPremium == true'
)::jsonb AS premium_status;

-- Test 9: Nested Goal Dependencies
\echo ''
\echo 'Test 9: Nested Goal Dependencies (3 levels deep)'
\echo 'Goal: Final approval (Approval.Final == true)'
\echo 'Expected: provable = true through 3-level chain'

SELECT query_backward_chaining(
    '{
        "Data": {
            "Value": 100
        },
        "Level1": {
            "Check": false
        },
        "Level2": {
            "Check": false
        },
        "Approval": {
            "Final": false
        }
    }',
    E'rule "Level1Check" {
        when
            Data.Value >= 50
        then
            Level1.Check = true;
    }

    rule "Level2Check" {
        when
            Level1.Check == true
        then
            Level2.Check = true;
    }

    rule "FinalApproval" {
        when
            Level2.Check == true
        then
            Approval.Final = true;
    }',
    'Approval.Final == true'
)::jsonb AS nested_approval;

-- Test 10: Performance Comparison
\echo ''
\echo 'Test 10: Performance Test - Backward vs Forward'
\echo 'Testing query performance with timing'

\timing on

-- Backward chaining query
SELECT query_backward_chaining(
    '{
        "X": {"a": 10, "b": 20, "result": false}
    }',
    E'rule "Calculate" {
        when
            X.a > 0 && X.b > 0
        then
            X.result = true;
    }',
    'X.result == true'
)::jsonb->'query_time_ms' AS backward_time_ms;

\timing off

\echo ''
\echo '========================================='
\echo 'Native Backward Chaining Tests Complete!'
\echo '========================================='
\echo ''
\echo 'Key Features Tested:'
\echo '1. Simple goal queries'
\echo '2. Multi-level rule chains'
\echo '3. Multiple goals in one query'
\echo '4. Unprovable goals (negative cases)'
\echo '5. Production mode (boolean only)'
\echo '6. Complex conditions (AND/OR)'
\echo '7. Nested dependencies'
\echo '8. Performance metrics'
\echo ''
\echo 'New PostgreSQL Functions Available:'
\echo '- query_backward_chaining(facts, rules, goal) → JSON with proof'
\echo '- query_backward_chaining_multi(facts, rules, goals[]) → Array of results'
\echo '- can_prove_goal(facts, rules, goal) → Boolean (fast)'
\echo ''
