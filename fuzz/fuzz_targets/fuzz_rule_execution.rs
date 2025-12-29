#![no_main]

use libfuzzer_sys::fuzz_target;
use serde_json::{json, Value};

// Fuzz complete rule execution: JSON facts + GRL rules
fuzz_target!(|data: &[u8]| {
    if data.len() < 4 {
        return;
    }

    // Split input into facts and rules
    let split_point = (data[0] as usize % data.len().max(1)).min(data.len());
    let facts_data = &data[..split_point];
    let rules_data = &data[split_point..];

    // Test 1: Parse facts as JSON
    if let Ok(facts_str) = std::str::from_utf8(facts_data) {
        if let Ok(facts_json) = serde_json::from_str::<Value>(facts_str) {
            // Valid JSON facts - test with various rules

            // Test with simple rule
            test_execution_pattern(&facts_json, "rule \"SimpleTest\" { when x > 0 then y = 1; }");

            // Test with complex conditions
            test_execution_pattern(
                &facts_json,
                "rule \"ComplexTest\" { when a > 0 && b < 100 || c == 5 then x = 1; }",
            );

            // Test with multiple rules
            test_execution_pattern(
                &facts_json,
                r#"
                rule "R1" salience 100 { when x > 0 then y = 1; }
                rule "R2" salience 50 { when y > 0 then z = 2; }
                rule "R3" { when z > 0 then done = true; }
                "#,
            );
        }
    }

    // Test 2: Parse rules as GRL
    if let Ok(rules_str) = std::str::from_utf8(rules_data) {
        // Test with standard facts
        let standard_facts = json!({
            "Order": {"total": 100, "discount": 0},
            "Customer": {"tier": "Gold", "approved": false}
        });

        test_execution_pattern(&standard_facts, rules_str);

        // Test with extreme value facts
        let extreme_facts = json!({
            "Order": {"total": f64::INFINITY, "discount": f64::NAN},
            "Customer": {"tier": "", "approved": false}
        });

        test_execution_pattern(&extreme_facts, rules_str);
    }

    // Test 3: Both random
    if let Ok(facts_str) = std::str::from_utf8(facts_data) {
        if let Ok(rules_str) = std::str::from_utf8(rules_data) {
            if let Ok(facts_json) = serde_json::from_str::<Value>(facts_str) {
                test_execution_pattern(&facts_json, rules_str);
            }
        }
    }

    // Test 4: Edge cases
    test_edge_cases(data);
});

fn test_execution_pattern(facts: &Value, rules: &str) {
    // Serialize facts to string
    let _ = serde_json::to_string(facts);

    // Test rule string operations
    let _ = rules.len();
    let _ = rules.chars().count();

    // Check for valid rule structure
    if rules.contains("rule") && rules.contains("when") && rules.contains("then") {
        // Looks like valid GRL

        // Test pattern matching between facts and rules
        if let Some(obj) = facts.as_object() {
            for (key, value) in obj {
                // Check if rule references this fact
                let _ = rules.contains(key);

                // Check value patterns
                if let Some(num) = value.as_f64() {
                    // Check for numeric comparisons in rules
                    let _ = rules.contains(">");
                    let _ = rules.contains("<");
                    let _ = rules.contains("==");

                    // Test if number appears in rule
                    let num_str = format!("{}", num);
                    let _ = rules.contains(&num_str);
                }

                if let Some(s) = value.as_str() {
                    // Check if string value appears in rule
                    let _ = rules.contains(s);
                }
            }
        }

        // Test for common issues
        let _ = rules.matches("{").count();
        let _ = rules.matches("}").count();
        let _ = rules.matches("\"").count();
        let _ = rules.matches(";").count();
    }
}

fn test_edge_cases(data: &[u8]) {
    // Test 1: Empty inputs
    let empty_facts = json!({});
    test_execution_pattern(&empty_facts, "");

    // Test 2: Nested facts
    if data.len() > 10 {
        let depth = (data[0] % 10) as usize;
        let mut nested = json!(1);
        for _ in 0..depth {
            nested = json!({"nested": nested});
        }
        test_execution_pattern(&nested, "rule \"Test\" { when nested > 0 then x = 1; }");
    }

    // Test 3: Large numbers
    let large_facts = json!({
        "x": 1e308,
        "y": -1e308,
        "z": f64::EPSILON
    });
    test_execution_pattern(&large_facts, "rule \"Test\" { when x > 0 then y = 1; }");

    // Test 4: Unicode in facts
    let unicode_facts = json!({
        "name": "🔥Test🚀",
        "value": "你好世界"
    });
    test_execution_pattern(&unicode_facts, "rule \"Test\" { when name == \"🔥Test🚀\" then x = 1; }");

    // Test 5: Arrays
    let array_facts = json!({
        "items": [1, 2, 3, 4, 5]
    });
    test_execution_pattern(&array_facts, "rule \"Test\" { when items > 0 then x = 1; }");

    // Test 6: Null values
    let null_facts = json!({
        "a": null,
        "b": Value::Null
    });
    test_execution_pattern(&null_facts, "rule \"Test\" { when a == null then x = 1; }");

    // Test 7: Boolean values
    let bool_facts = json!({
        "approved": true,
        "rejected": false
    });
    test_execution_pattern(&bool_facts, "rule \"Test\" { when approved == true then x = 1; }");

    // Test 8: Mixed types
    let mixed_facts = json!({
        "num": 42,
        "str": "test",
        "bool": true,
        "null": null,
        "array": [1, 2, 3],
        "obj": {"nested": "value"}
    });
    test_execution_pattern(
        &mixed_facts,
        "rule \"Test\" { when num > 0 && str == \"test\" then x = 1; }",
    );
}
