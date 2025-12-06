use rule_engine_postgres::{rule_engine_health_check, rule_engine_version, run_rule_engine};
use std::fs;

#[test]
fn test_ecommerce_pricing_rules() {
    // Load test data
    let facts = fs::read_to_string("tests/fixtures/ecommerce_pricing.json")
        .expect("Failed to read ecommerce_pricing.json");
    let rules = fs::read_to_string("tests/fixtures/ecommerce_pricing.grl")
        .expect("Failed to read ecommerce_pricing.grl");

    // Execute rules (Note: This is unit test, not actual PostgreSQL test)
    // In real scenario, this would be tested via SQL queries
    let result_json = run_rule_engine(&facts, &rules);

    // Parse result
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    // Verify results
    // Customer is Gold tier with Order.total > 100, so LoyaltyBonus (salience 20) should fire
    // This should set discount to 0.20 (20%)
    assert!(
        result.get("Order").is_some(),
        "Order should exist in result"
    );

    let order = &result["Order"];
    let discount = order["discount"].as_f64().unwrap_or(0.0);

    // LoyaltyBonus has highest salience (20) and should override VolumeDiscount (10)
    assert_eq!(
        discount, 0.20,
        "Discount should be 20% from LoyaltyBonus rule"
    );

    // Product discount should be set by FlashSale rule (salience 30)
    let product = &result["Product"];
    let product_discount = product["discount"].as_f64().unwrap_or(0.0);
    assert_eq!(
        product_discount, 0.25,
        "Product discount should be 25% from FlashSale"
    );
}

#[test]
fn test_loan_approval_high_credit() {
    let facts = fs::read_to_string("tests/fixtures/loan_approval.json")
        .expect("Failed to read loan_approval.json");
    let rules = fs::read_to_string("tests/fixtures/loan_approval.grl")
        .expect("Failed to read loan_approval.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let applicant = &result["Applicant"];

    // High credit score (780) with good income (75000) should be approved
    assert!(
        applicant["approved"].as_bool().unwrap(),
        "Should be approved"
    );

    // maxAmount should be income * 3 = 225000
    assert_eq!(
        applicant["maxAmount"].as_f64().unwrap(),
        225000.0,
        "Max amount incorrect"
    );

    // Interest rate should be 3.5% for high credit
    assert_eq!(
        applicant["interestRate"].as_f64().unwrap(),
        3.5,
        "Interest rate incorrect"
    );
}

#[test]
fn test_billing_tiers_pro_tier() {
    let facts = fs::read_to_string("tests/fixtures/billing_tiers.json")
        .expect("Failed to read billing_tiers.json");
    let rules = fs::read_to_string("tests/fixtures/billing_tiers.grl")
        .expect("Failed to read billing_tiers.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let usage = &result["Usage"];

    // 50000 API calls should be Pro tier
    assert_eq!(usage["tier"].as_str().unwrap(), "pro", "Should be pro tier");

    // Base charge for pro tier
    assert_eq!(
        usage["baseCharge"].as_f64().unwrap(),
        99.0,
        "Base charge incorrect"
    );

    // Storage overage: (75 - 50) * 0.10 = 2.5
    // User overage: (15 - 10) * 5 = 25
    // Total overage: 2.5 + 25 = 27.5
    let overage = usage["overageCharge"].as_f64().unwrap();
    assert!(
        (overage - 27.5).abs() < 0.01,
        "Overage charge incorrect: expected 27.5, got {}",
        overage
    );
}

#[test]
fn test_patient_risk_assessment_high_risk() {
    let facts = fs::read_to_string("tests/fixtures/patient_risk.json")
        .expect("Failed to read patient_risk.json");
    let rules = fs::read_to_string("tests/fixtures/patient_risk.grl")
        .expect("Failed to read patient_risk.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let patient = &result["Patient"];

    // Risk score calculation:
    // Age > 65: +15
    // BMI > 30: +20
    // High blood pressure: +25
    // Diabetes: +30
    // Total: 90
    let risk_score = patient["riskScore"].as_i64().unwrap();
    assert_eq!(risk_score, 90, "Risk score incorrect");

    // Risk score >= 60 should be "high" risk level
    assert_eq!(
        patient["riskLevel"].as_str().unwrap(),
        "high",
        "Should be high risk"
    );
}

#[test]
fn test_empty_facts_error() {
    let rules = "rule \"Test\" { when x > 5 then y = 10; }";
    let result_json = run_rule_engine("", rules);

    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse error JSON");

    assert!(result.get("error").is_some(), "Should return error");
    assert_eq!(result["error_code"].as_str().unwrap(), "ERR001");
}

#[test]
fn test_empty_rules_error() {
    let facts = r#"{"User": {"age": 30}}"#;
    let result_json = run_rule_engine(facts, "");

    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse error JSON");

    assert!(result.get("error").is_some(), "Should return error");
    assert_eq!(result["error_code"].as_str().unwrap(), "ERR002");
}

#[test]
fn test_invalid_json_error() {
    let rules = "rule \"Test\" { when x > 5 then y = 10; }";
    let result_json = run_rule_engine("{invalid json", rules);

    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse error JSON");

    assert!(result.get("error").is_some(), "Should return error");
    assert_eq!(result["error_code"].as_str().unwrap(), "ERR005");
}

#[test]
fn test_invalid_grl_syntax_error() {
    let facts = r#"{"User": {"age": 30}}"#;
    let rules = "rule \"Invalid\" { when x > 5 INVALID y = 10; }";

    let result_json = run_rule_engine(facts, rules);

    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse error JSON");

    assert!(result.get("error").is_some(), "Should return error");
    assert_eq!(result["error_code"].as_str().unwrap(), "ERR008");
}

#[test]
fn test_health_check() {
    let result_json = rule_engine_health_check();
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse health check JSON");

    assert_eq!(result["status"].as_str().unwrap(), "healthy");
    assert_eq!(
        result["extension"].as_str().unwrap(),
        "rule_engine_postgre_extensions"
    );
    assert!(result.get("version").is_some());
    assert!(result.get("timestamp").is_some());
}

#[test]
fn test_version() {
    let version = rule_engine_version();
    assert!(!version.is_empty(), "Version should not be empty");
    assert!(version.contains("."), "Version should contain dots");
}

#[test]
fn test_nested_objects() {
    let facts = r#"{
        "Company": {
            "name": "TechCorp",
            "Employee": {
                "name": "Alice",
                "salary": 50000,
                "bonus": 0
            }
        }
    }"#;

    let rules = r#"
        rule "BonusRule" salience 10 {
            when
                Company.Employee.salary > 40000
            then
                Company.Employee.bonus = 5000;
        }
    "#;

    let result_json = run_rule_engine(facts, rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let bonus = result["Company"]["Employee"]["bonus"].as_i64().unwrap();
    assert_eq!(bonus, 5000, "Bonus should be set to 5000");
}

#[test]
fn test_multiple_rules_execution_order() {
    let facts = r#"{"Counter": {"value": 0}}"#;

    let rules = r#"
        rule "First" salience 1 {
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
        }
    "#;

    let result_json = run_rule_engine(facts, rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    // Rule with higher salience (10) should execute first
    let counter = result["Counter"]["value"].as_i64().unwrap();
    assert_eq!(counter, 10, "Higher salience rule should execute first");
}

// ========================================
// Backward Chaining Tests
// ========================================

#[test]
fn test_backward_chaining_medical_diagnosis() {
    let facts = fs::read_to_string("tests/fixtures/backward_chaining_diagnosis.json")
        .expect("Failed to read backward_chaining_diagnosis.json");
    let rules = fs::read_to_string("tests/fixtures/backward_chaining_diagnosis.grl")
        .expect("Failed to read backward_chaining_diagnosis.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let patient = &result["Patient"];
    let rules_inferred = &result["Rules"];

    // Backward chaining: symptoms -> infer condition -> diagnose
    // Patient has fever (38.5), cough, fatigue -> should infer Flu
    assert!(
        rules_inferred["hasFlu"].as_bool().unwrap(),
        "Should infer Flu"
    );
    assert_eq!(
        patient["diagnosis"].as_str().unwrap(),
        "Influenza",
        "Diagnosis should be Influenza"
    );
    assert_eq!(
        patient["severity"].as_str().unwrap(),
        "moderate",
        "Severity should be moderate"
    );

    // Should not infer pneumonia (missing shortnessOfBreath and chestPain)
    assert!(
        !rules_inferred["hasPneumonia"].as_bool().unwrap(),
        "Should not infer Pneumonia"
    );
}

#[test]
fn test_backward_chaining_it_troubleshooting() {
    let facts = fs::read_to_string("tests/fixtures/backward_chaining_troubleshooting.json")
        .expect("Failed to read backward_chaining_troubleshooting.json");
    let rules = fs::read_to_string("tests/fixtures/backward_chaining_troubleshooting.grl")
        .expect("Failed to read backward_chaining_troubleshooting.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let system = &result["System"];
    let diagnostics = &system["diagnostics"];

    // Backward chaining: observations -> infer issue -> identify root cause
    // Server not responding + ping fails -> network issue
    assert!(
        diagnostics["networkIssue"].as_bool().unwrap(),
        "Should infer network issue"
    );

    // High memory/cpu + low disk -> resource exhaustion
    assert!(
        diagnostics["resourceExhaustion"].as_bool().unwrap(),
        "Should infer resource exhaustion"
    );

    // Root cause should be identified (resource exhaustion is more critical)
    assert_eq!(
        system["rootCause"].as_str().unwrap(),
        "Server resource exhaustion"
    );
    assert_eq!(system["priority"].as_str().unwrap(), "critical");

    // Should have escalation in solution
    let solution = system["solution"].as_str().unwrap();
    assert!(
        solution.contains("ESCALATE"),
        "Critical issue should be escalated"
    );
}

#[test]
fn test_backward_chaining_loan_decision() {
    let facts = fs::read_to_string("tests/fixtures/backward_chaining_loan_decision.json")
        .expect("Failed to read backward_chaining_loan_decision.json");
    let rules = fs::read_to_string("tests/fixtures/backward_chaining_loan_decision.grl")
        .expect("Failed to read backward_chaining_loan_decision.grl");

    let result_json = run_rule_engine(&facts, &rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    let applicant = &result["Applicant"];
    let checks = &applicant["checks"];
    let eligibility = &applicant["eligibility"];

    // Backward chaining: data -> verify checks -> determine eligibility -> make decision

    // All base checks should pass
    assert!(
        checks["hasGoodCredit"].as_bool().unwrap(),
        "Credit score 720 >= 700"
    );
    assert!(
        checks["hasStableIncome"].as_bool().unwrap(),
        "Income 80k >= 50k and full-time"
    );
    assert!(
        checks["hasLowDebtRatio"].as_bool().unwrap(),
        "15k debt < 24k (30% of 80k)"
    );
    assert!(
        checks["meetsAgeRequirement"].as_bool().unwrap(),
        "Age 35 is between 21-65"
    );
    assert!(
        checks["hasLongEmployment"].as_bool().unwrap(),
        "8 years >= 5 years"
    );

    // Should qualify for premium rate (all checks pass)
    assert!(
        eligibility["qualifiesForPremiumRate"].as_bool().unwrap(),
        "Should qualify for premium"
    );
    assert!(
        eligibility["qualifiesForLoan"].as_bool().unwrap(),
        "Should qualify for loan"
    );

    // Decision should be approved with premium rate
    assert_eq!(
        applicant["decision"].as_str().unwrap(),
        "approved",
        "Should be approved"
    );
    assert_eq!(
        applicant["interestRate"].as_f64().unwrap(),
        3.5,
        "Premium rate should be 3.5%"
    );

    // Max loan amount should be income * 4 = 320,000
    assert_eq!(
        applicant["maxLoanAmount"].as_f64().unwrap(),
        320000.0,
        "Max amount should be 320k"
    );
}

#[test]
fn test_backward_chaining_decision_tree() {
    // Test a simple backward chaining decision tree
    let facts = r#"{
        "Goal": {
            "canDrive": false
        },
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
    }"#;

    let rules = r#"
        // Goal rule - Can drive if all prerequisites met
        rule "CanDrive" salience 100 {
            when
                Checks.isOldEnough == true &&
                Checks.hasValidLicense == true &&
                Checks.hasVehicle == true
            then
                Goal.canDrive = true;
        }

        // Prerequisite checks
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
        }
    "#;

    let result_json = run_rule_engine(facts, rules);
    let result: serde_json::Value =
        serde_json::from_str(&result_json).expect("Failed to parse result JSON");

    // All checks should pass
    assert!(result["Checks"]["isOldEnough"].as_bool().unwrap());
    assert!(result["Checks"]["hasValidLicense"].as_bool().unwrap());
    assert!(result["Checks"]["hasVehicle"].as_bool().unwrap());

    // Goal should be achieved
    assert!(
        result["Goal"]["canDrive"].as_bool().unwrap(),
        "Should be able to drive"
    );
}
