// Test nested objects với rust-rule-engine trực tiếp
use rust_rule_engine::{Engine, EngineOptions};

fn main() {
    // Test 1: Nested object với math trong then clause
    println!("=== Test 1: Nested Object với Math ===");
    let facts = r#"{"Order": {"total": 150, "discount": 0}}"#;
    let rules = r#"
        rule "Discount" {
            when Order.total > 100
            then Order.discount = Order.total * 0.10;
        }
    "#;

    match test_rule(facts, rules) {
        Ok(result) => println!("✅ Result: {}", result),
        Err(e) => println!("❌ Error: {}", e),
    }

    // Test 2: Flat JSON với math
    println!("\n=== Test 2: Flat JSON với Math ===");
    let facts = r#"{"total": 150, "discount": 0}"#;
    let rules = r#"
        rule "Discount" {
            when total > 100
            then discount = total * 0.10;
        }
    "#;

    match test_rule(facts, rules) {
        Ok(result) => println!("✅ Result: {}", result),
        Err(e) => println!("❌ Error: {}", e),
    }

    // Test 3: Nested với constant (không math)
    println!("\n=== Test 3: Nested với Constant ===");
    let facts = r#"{"Order": {"total": 150, "discount": 0}}"#;
    let rules = r#"
        rule "Discount" {
            when Order.total > 100
            then Order.discount = 15.0;
        }
    "#;

    match test_rule(facts, rules) {
        Ok(result) => println!("✅ Result: {}", result),
        Err(e) => println!("❌ Error: {}", e),
    }

    // Test 4: Customer.email nested
    println!("\n=== Test 4: Customer.email Nested ===");
    let facts = r#"{"Customer": {"email": "user@example.com", "approved": false}}"#;
    let rules = r#"
        rule "Test" {
            when Customer.email == "user@example.com"
            then Customer.approved = true;
        }
    "#;

    match test_rule(facts, rules) {
        Ok(result) => println!("✅ Result: {}", result),
        Err(e) => println!("❌ Error: {}", e),
    }
}

fn test_rule(facts_json: &str, rules_grl: &str) -> Result<String, String> {
    let mut engine = Engine::new();

    // Parse rules
    engine
        .add_rules_from_string(rules_grl)
        .map_err(|e| format!("Rule parsing error: {}", e))?;

    // Parse facts
    let mut facts: serde_json::Value = serde_json::from_str(facts_json)
        .map_err(|e| format!("JSON parsing error: {}", e))?;

    // Execute
    let options = EngineOptions {
        allow_shadowing: true,
        max_iterations: 100,
    };

    engine
        .run_with_options(&mut facts, options)
        .map_err(|e| format!("Execution error: {}", e))?;

    Ok(serde_json::to_string_pretty(&facts).unwrap())
}
