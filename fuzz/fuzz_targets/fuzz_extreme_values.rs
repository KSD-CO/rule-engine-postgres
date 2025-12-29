#![no_main]

use libfuzzer_sys::fuzz_target;
use serde_json::{json, Value};

// Simplified: use raw bytes instead of Arbitrary derive
fuzz_target!(|data: &[u8]| {
    // Generate pseudo-random values from input bytes
    let number = if data.len() >= 8 {
        f64::from_le_bytes([
            data[0], data[1], data[2], data[3],
            data[4], data[5], data[6], data[7],
        ])
    } else {
        0.0
    };

    let string_len = if data.len() >= 10 {
        u16::from_le_bytes([data[8], data[9]]) % 1000 // Max 1000 chars
    } else {
        0
    };

    let nesting_depth = if data.len() >= 11 {
        data[10] % 50 // Max 50 levels
    } else {
        0
    };
    // Test extreme numeric values
    let extreme_numbers = vec![
        number,
        f64::MAX,
        f64::MIN,
        f64::INFINITY,
        f64::NEG_INFINITY,
        f64::NAN,
        0.0,
        -0.0,
        f64::EPSILON,
        1.7976931348623157e+308, // Near max
        -1.7976931348623157e+308,
        2.2250738585072014e-308, // Near min positive
        1e-300,
        1e300,
    ];

    for num in extreme_numbers {
        // Test JSON with extreme numbers
        let json_obj = json!({
            "Order": {
                "total": num,
                "discount": 0
            }
        });

        // Should not crash when serializing
        let _ = serde_json::to_string(&json_obj);
    }

    // Test extreme string lengths (limited to prevent OOM)
    let long_string = "x".repeat(string_len as usize);
    let json_with_long_string = json!({
        "Customer": {
            "name": long_string
        }
    });
    let _ = serde_json::to_string(&json_with_long_string);

    // Test deep nesting (limited to prevent stack overflow)
    let depth = nesting_depth as usize;
    let mut nested = Value::Number(serde_json::Number::from(42));
    for _ in 0..depth {
        nested = json!({ "nested": nested });
    }
    let _ = serde_json::to_string(&nested);

    // Test arrays with many elements
    let array_size = (string_len % 1000) as usize;
    let large_array: Vec<Value> = (0..array_size)
        .map(|i| Value::Number(serde_json::Number::from(i)))
        .collect();
    let json_with_array = json!({
        "items": large_array
    });
    let _ = serde_json::to_string(&json_with_array);

    // Test objects with many keys
    let key_count = (string_len % 1000) as usize;
    let mut obj = serde_json::Map::new();
    for i in 0..key_count {
        obj.insert(format!("field_{}", i), Value::Number(serde_json::Number::from(i)));
    }
    let json_with_many_keys = Value::Object(obj);
    let _ = serde_json::to_string(&json_with_many_keys);

    // Test special characters and unicode
    let special_chars = vec![
        "\0",          // Null byte
        "\n\r\t",      // Whitespace
        "\"'\\",       // Quotes and backslash
        "🔥💎🚀",      // Emoji
        "\u{0000}",    // Unicode null
        "\u{FFFF}",    // Max BMP
        "你好世界",    // Chinese
        "مرحبا",       // Arabic
        "🏴‍☠️",        // Complex emoji
    ];

    for special in special_chars {
        let json_special = json!({
            "data": special
        });
        let _ = serde_json::to_string(&json_special);
    }
});
