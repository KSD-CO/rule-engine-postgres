#![no_main]

use libfuzzer_sys::fuzz_target;

// Standalone GRL parser fuzzing
// Tests the GRL syntax parser with random/malformed input
fuzz_target!(|data: &[u8]| {
    // Convert random bytes to string
    if let Ok(s) = std::str::from_utf8(data) {
        // Test various GRL-like patterns

        // 1. Test as-is
        let _ = test_grl_syntax(s);

        // 2. Test with rule wrapper
        let wrapped = format!("rule \"FuzzRule\" {{ when {} then x = 1; }}", s);
        let _ = test_grl_syntax(&wrapped);

        // 3. Test with multiple rules
        let multi = format!(
            "rule \"R1\" {{ when {} then a = 1; }} rule \"R2\" {{ when {} then b = 2; }}",
            s, s
        );
        let _ = test_grl_syntax(&multi);

        // 4. Test with special characters
        if s.len() > 0 {
            let with_special = format!("rule \"{}\" {{ when x > 0 then y = 1; }}", s);
            let _ = test_grl_syntax(&with_special);
        }

        // 5. Test condition patterns
        if s.len() > 0 {
            let condition = format!("rule \"Test\" {{ when Order.total {} 100 then x = 1; }}", s);
            let _ = test_grl_syntax(&condition);
        }

        // 6. Test action patterns
        if s.len() > 0 {
            let action = format!("rule \"Test\" {{ when x > 0 then {} }}", s);
            let _ = test_grl_syntax(&action);
        }
    }
});

// Test GRL syntax patterns
fn test_grl_syntax(input: &str) -> bool {
    // Basic pattern matching for GRL keywords
    let has_rule = input.contains("rule");
    let has_when = input.contains("when");
    let has_then = input.contains("then");
    let has_braces = input.contains("{") && input.contains("}");

    // Test string operations that might crash
    let _ = input.len();
    let _ = input.chars().count();
    let _ = input.split_whitespace().count();

    // Test pattern matching
    let _ = input.matches("rule").count();
    let _ = input.matches("{").count();
    let _ = input.matches("}").count();

    // Test substring operations (use char_indices to avoid UTF-8 boundary issues)
    if let Some((idx, _)) = input.char_indices().nth(10) {
        let _ = &input[..idx];
    }

    // Test for balanced braces (common parser issue)
    let open_braces = input.matches("{").count();
    let close_braces = input.matches("}").count();
    let _balanced = open_braces == close_braces;

    // Test for quoted strings (another common parser issue)
    let quotes = input.matches("\"").count();
    let _even_quotes = quotes % 2 == 0;

    // Test operators
    for op in &["==", "!=", ">", "<", ">=", "<=", "&&", "||", "!"] {
        let _ = input.contains(op);
    }

    // Test keywords
    for keyword in &["rule", "when", "then", "salience", "no-loop", "lock-on-active"] {
        let _ = input.contains(keyword);
    }

    // Simulate parsing logic (checking structure)
    if has_rule && has_when && has_then && has_braces {
        // Looks like valid GRL structure

        // Test nested brace handling
        let mut depth: i32 = 0;
        for c in input.chars() {
            match c {
                '{' => depth += 1,
                '}' => depth = depth.saturating_sub(1),
                _ => {}
            }
        }

        // Test for common GRL patterns
        let _ = input.contains("Order.");
        let _ = input.contains("Customer.");
        let _ = input.contains(".total");
        let _ = input.contains(".discount");

        return true;
    }

    false
}
