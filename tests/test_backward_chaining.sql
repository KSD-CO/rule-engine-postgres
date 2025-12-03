-- Backward Chaining Test Suite for Rule Engine PostgreSQL Extension
-- Demonstrates goal-driven reasoning by working backwards from desired outcomes

\echo '========================================='
\echo 'Backward Chaining Tests'
\echo '========================================='

-- Test 1: Medical Diagnosis - Work backwards from diagnosis to symptoms
\echo ''
\echo 'Test 1: Medical Diagnosis (Backward Chaining)'
\echo 'Goal: Diagnose illness based on symptoms'
\echo 'Chain: Symptoms -> Infer Condition -> Make Diagnosis'
\echo 'Expected: Diagnosis = "Influenza", Severity = "moderate"'

SELECT run_rule_engine(
    '{
        "Patient": {
            "symptoms": {
                "fever": true,
                "cough": true,
                "fatigue": true,
                "shortnessOfBreath": false,
                "chestPain": false
            },
            "vitals": {
                "temperature": 38.5,
                "heartRate": 95,
                "bloodPressure": "120/80"
            },
            "diagnosis": "unknown",
            "treatment": "none",
            "severity": "unknown"
        },
        "Rules": {
            "hasCommonCold": false,
            "hasFlu": false,
            "hasPneumonia": false,
            "needsAntibiotics": false,
            "needsHospitalization": false
        }
    }',
    E'rule "DiagnoseFlu" salience 100 {
        when
            Rules.hasFlu == true
        then
            Patient.diagnosis = "Influenza";
            Patient.severity = "moderate";
            Patient.treatment = "Rest, fluids, antiviral medication";
    }

    rule "DiagnosePneumonia" salience 100 {
        when
            Rules.hasPneumonia == true
        then
            Patient.diagnosis = "Pneumonia";
            Patient.severity = "severe";
            Patient.treatment = "Antibiotics, possible hospitalization";
    }

    rule "InferFlu" salience 200 {
        when
            Patient.symptoms.fever == true &&
            Patient.symptoms.cough == true &&
            Patient.symptoms.fatigue == true &&
            Patient.vitals.temperature >= 38.0
        then
            Rules.hasFlu = true;
    }

    rule "InferPneumonia" salience 200 {
        when
            Patient.symptoms.fever == true &&
            Patient.symptoms.cough == true &&
            Patient.symptoms.shortnessOfBreath == true &&
            Patient.symptoms.chestPain == true
        then
            Rules.hasPneumonia = true;
    }'
)::jsonb AS medical_diagnosis;

-- Test 2: IT Troubleshooting - Work backwards from root cause to observations
\echo ''
\echo 'Test 2: IT System Troubleshooting (Backward Chaining)'
\echo 'Goal: Identify root cause of system failure'
\echo 'Chain: Observations -> Infer Issue -> Identify Root Cause -> Suggest Solution'
\echo 'Expected: rootCause = "Server resource exhaustion", priority = "critical"'

SELECT run_rule_engine(
    '{
        "System": {
            "observations": {
                "serverNotResponding": true,
                "pingFails": true,
                "logsShowErrors": true,
                "diskSpaceAvailable": 5,
                "memoryUsage": 95,
                "cpuUsage": 85
            },
            "diagnostics": {
                "networkIssue": false,
                "resourceExhaustion": false,
                "applicationCrash": false
            },
            "rootCause": "unknown",
            "solution": "investigating",
            "priority": "unknown"
        }
    }',
    E'rule "IdentifyResourceExhaustion" salience 100 {
        when
            System.diagnostics.resourceExhaustion == true
        then
            System.rootCause = "Server resource exhaustion";
            System.solution = "Free up disk space, restart services";
            System.priority = "critical";
    }

    rule "IdentifyNetworkIssue" salience 100 {
        when
            System.diagnostics.networkIssue == true
        then
            System.rootCause = "Network connectivity failure";
            System.solution = "Check network cables, router, firewall";
            System.priority = "high";
    }

    rule "InferResourceExhaustion" salience 200 {
        when
            System.observations.diskSpaceAvailable < 10 ||
            System.observations.memoryUsage > 90 ||
            System.observations.cpuUsage > 90
        then
            System.diagnostics.resourceExhaustion = true;
    }

    rule "InferNetworkIssue" salience 200 {
        when
            System.observations.serverNotResponding == true &&
            System.observations.pingFails == true
        then
            System.diagnostics.networkIssue = true;
    }

    rule "EscalateCritical" salience 50 {
        when
            System.priority == "critical"
        then
            System.solution = System.solution + " [ESCALATE]";
    }'
)::jsonb AS troubleshooting_result;

-- Test 3: Loan Decision - Work backwards from approval to prerequisites
\echo ''
\echo 'Test 3: Loan Approval Decision Tree (Backward Chaining)'
\echo 'Goal: Approve loan by verifying all prerequisites'
\echo 'Chain: Raw Data -> Verify Checks -> Determine Eligibility -> Make Decision'
\echo 'Expected: decision = "approved", interestRate = 3.5, maxLoanAmount = 320000'

SELECT run_rule_engine(
    '{
        "Applicant": {
            "data": {
                "age": 35,
                "income": 80000,
                "creditScore": 720,
                "employment": "full-time",
                "employmentYears": 8,
                "existingDebt": 15000,
                "requestedAmount": 50000
            },
            "checks": {
                "hasStableIncome": false,
                "hasGoodCredit": false,
                "hasLowDebtRatio": false,
                "meetsAgeRequirement": false,
                "hasLongEmployment": false
            },
            "eligibility": {
                "qualifiesForLoan": false,
                "qualifiesForPremiumRate": false
            },
            "decision": "pending",
            "interestRate": 0,
            "maxLoanAmount": 0
        }
    }',
    E'rule "ApprovePremiumLoan" salience 100 {
        when
            Applicant.eligibility.qualifiesForPremiumRate == true
        then
            Applicant.decision = "approved";
            Applicant.interestRate = 3.5;
            Applicant.maxLoanAmount = Applicant.data.income * 4;
    }

    rule "InferPremiumEligibility" salience 200 {
        when
            Applicant.checks.hasGoodCredit == true &&
            Applicant.checks.hasStableIncome == true &&
            Applicant.checks.hasLowDebtRatio == true &&
            Applicant.checks.hasLongEmployment == true
        then
            Applicant.eligibility.qualifiesForPremiumRate = true;
            Applicant.eligibility.qualifiesForLoan = true;
    }

    rule "CheckGoodCredit" salience 300 {
        when
            Applicant.data.creditScore >= 700
        then
            Applicant.checks.hasGoodCredit = true;
    }

    rule "CheckStableIncome" salience 300 {
        when
            Applicant.data.income >= 50000 &&
            Applicant.data.employment == "full-time"
        then
            Applicant.checks.hasStableIncome = true;
    }

    rule "CheckLowDebtRatio" salience 300 {
        when
            Applicant.data.existingDebt < (Applicant.data.income * 0.3)
        then
            Applicant.checks.hasLowDebtRatio = true;
    }

    rule "CheckLongEmployment" salience 300 {
        when
            Applicant.data.employmentYears >= 5
        then
            Applicant.checks.hasLongEmployment = true;
    }'
)::jsonb AS loan_decision;

-- Test 4: Simple Goal Achievement
\echo ''
\echo 'Test 4: Goal Achievement (Can Drive?)'
\echo 'Goal: Determine if person can drive'
\echo 'Prerequisites: Age >= 18, Has License, Has Vehicle with Fuel'
\echo 'Expected: canDrive = true'

SELECT run_rule_engine(
    '{
        "Goal": {"canDrive": false},
        "Person": {
            "hasLicense": true,
            "age": 25,
            "hasCar": true,
            "carHasFuel": true
        },
        "Checks": {
            "isOldEnough": false,
            "hasValidLicense": false,
            "hasVehicle": false
        }
    }',
    E'rule "CanDrive" salience 100 {
        when
            Checks.isOldEnough == true &&
            Checks.hasValidLicense == true &&
            Checks.hasVehicle == true
        then
            Goal.canDrive = true;
    }

    rule "CheckAge" salience 200 {
        when
            Person.age >= 18
        then
            Checks.isOldEnough = true;
    }

    rule "CheckLicense" salience 200 {
        when
            Person.hasLicense == true
        then
            Checks.hasValidLicense = true;
    }

    rule "CheckVehicle" salience 200 {
        when
            Person.hasCar == true &&
            Person.carHasFuel == true
        then
            Checks.hasVehicle = true;
    }'
)::jsonb AS can_drive_result;

-- Test 5: Multi-Level Backward Chaining
\echo ''
\echo 'Test 5: Multi-Level Decision Tree'
\echo 'Goal: Approve vacation request'
\echo 'Chain: Basic Checks -> Manager Approval -> Budget Check -> Final Approval'
\echo 'Expected: vacationApproved = true'

SELECT run_rule_engine(
    '{
        "Employee": {
            "id": 123,
            "daysRequested": 5,
            "remainingDays": 10,
            "performanceRating": 4,
            "yearsOfService": 3
        },
        "Checks": {
            "hasSufficientDays": false,
            "hasGoodPerformance": false,
            "hasLongService": false,
            "managerApproved": false,
            "budgetApproved": false
        },
        "Approval": {
            "vacationApproved": false,
            "reason": "pending"
        }
    }',
    E'rule "ApproveVacation" salience 100 {
        when
            Checks.managerApproved == true &&
            Checks.budgetApproved == true
        then
            Approval.vacationApproved = true;
            Approval.reason = "All requirements met";
    }

    rule "ManagerApproval" salience 200 {
        when
            Checks.hasSufficientDays == true &&
            Checks.hasGoodPerformance == true
        then
            Checks.managerApproved = true;
    }

    rule "BudgetApproval" salience 200 {
        when
            Checks.hasLongService == true
        then
            Checks.budgetApproved = true;
    }

    rule "CheckDays" salience 300 {
        when
            Employee.daysRequested <= Employee.remainingDays
        then
            Checks.hasSufficientDays = true;
    }

    rule "CheckPerformance" salience 300 {
        when
            Employee.performanceRating >= 3
        then
            Checks.hasGoodPerformance = true;
    }

    rule "CheckService" salience 300 {
        when
            Employee.yearsOfService >= 2
        then
            Checks.hasLongService = true;
    }'
)::jsonb AS vacation_approval;

-- Test 6: Backward Chaining with Failure Path
\echo ''
\echo 'Test 6: Loan Rejection (Backward Chaining Failure)'
\echo 'Goal: Reject loan when prerequisites not met'
\echo 'Expected: decision = "rejected", reason includes failure details'

SELECT run_rule_engine(
    '{
        "Applicant": {
            "data": {
                "creditScore": 580,
                "income": 30000,
                "employment": "part-time"
            },
            "checks": {
                "hasGoodCredit": false,
                "hasStableIncome": false
            },
            "decision": "pending",
            "reason": ""
        }
    }',
    E'rule "ApproveLoan" salience 100 {
        when
            Applicant.checks.hasGoodCredit == true &&
            Applicant.checks.hasStableIncome == true
        then
            Applicant.decision = "approved";
    }

    rule "RejectLoan" salience 90 {
        when
            Applicant.decision == "pending"
        then
            Applicant.decision = "rejected";
            Applicant.reason = "Failed to meet minimum requirements";
    }

    rule "CheckCredit" salience 200 {
        when
            Applicant.data.creditScore >= 650
        then
            Applicant.checks.hasGoodCredit = true;
    }

    rule "CheckIncome" salience 200 {
        when
            Applicant.data.income >= 50000 &&
            Applicant.data.employment == "full-time"
        then
            Applicant.checks.hasStableIncome = true;
    }'
)::jsonb AS loan_rejection;

\echo ''
\echo '========================================='
\echo 'Backward Chaining Tests Completed!'
\echo '========================================='
\echo ''
\echo 'Key Concepts Demonstrated:'
\echo '1. Goal-driven reasoning (work from desired outcome)'
\echo '2. Multi-level inference chains'
\echo '3. Prerequisite verification'
\echo '4. Decision trees with salience-based execution order'
\echo '5. Both success and failure paths'
\echo ''
