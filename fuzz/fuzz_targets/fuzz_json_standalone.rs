#![no_main]

use libfuzzer_sys::fuzz_target;
use serde_json;

// Standalone JSON fuzzing without pgrx dependencies
fuzz_target!(|data: &[u8]| {
    // Convert random bytes to string
    if let Ok(s) = std::str::from_utf8(data) {
        // Try to parse as JSON - should not crash on any input
        let _ = serde_json::from_str::<serde_json::Value>(s);

        // If it's valid JSON, test more edge cases
        if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(s) {
            // Test serialization round-trip
            let _ = serde_json::to_string(&json_value);

            // Test pretty printing
            let _ = serde_json::to_string_pretty(&json_value);

            // Test compact serialization
            if let Ok(serialized) = serde_json::to_string(&json_value) {
                // Try to parse back
                let _ = serde_json::from_str::<serde_json::Value>(&serialized);
            }

            // Test if it's an object
            if json_value.is_object() {
                // Test accessing nested values
                if let Some(obj) = json_value.as_object() {
                    for (key, value) in obj {
                        // Test key/value operations
                        let _ = key.len();
                        let _ = key.chars().count();
                        let _ = key.is_empty();

                        // Test value type checks
                        let _ = value.is_null();
                        let _ = value.is_boolean();
                        let _ = value.is_number();
                        let _ = value.is_string();
                        let _ = value.is_array();
                        let _ = value.is_object();

                        // Test value extraction
                        if let Some(num) = value.as_f64() {
                            let _ = num.is_finite();
                            let _ = num.is_infinite();
                            let _ = num.is_nan();
                        }

                        if let Some(s) = value.as_str() {
                            let _ = s.len();
                            let _ = s.chars().count();
                        }
                    }
                }
            }

            // Test array operations
            if let Some(arr) = json_value.as_array() {
                let _ = arr.len();
                let _ = arr.is_empty();
                for item in arr {
                    let _ = serde_json::to_string(item);
                }
            }
        }
    }
});
