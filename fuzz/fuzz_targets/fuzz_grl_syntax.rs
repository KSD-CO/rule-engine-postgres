#![no_main]

use libfuzzer_sys::fuzz_target;
use rule_engine_postgres::core::rules::parse_and_validate_rules;

fuzz_target!(|data: &[u8]| {
    // Convert random bytes to string
    if let Ok(s) = std::str::from_utf8(data) {
        // Try to parse GRL syntax - should not crash on any input
        // This tests the GRL parser with random/malformed input
        let _ = parse_and_validate_rules(s);

        // Test with common GRL patterns corrupted
        if s.contains("rule") || s.contains("when") || s.contains("then") {
            // Test various corruptions
            let corrupted1 = s.replace("when", "when when");
            let _ = parse_and_validate_rules(&corrupted1);

            let corrupted2 = s.replace("then", "then then");
            let _ = parse_and_validate_rules(&corrupted2);

            let corrupted3 = s.replace("{", "{{");
            let _ = parse_and_validate_rules(&corrupted3);

            let corrupted4 = s.replace("}", "}}");
            let _ = parse_and_validate_rules(&corrupted4);
        }
    }
});
