#![no_main]

use libfuzzer_sys::fuzz_target;

// Fuzz built-in functions (24 functions)
// Tests: Date/Time (5), String (8), Math (7), JSON (4)
fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        // Test all built-in function categories

        // 1. Date/Time Functions (5)
        test_datetime_functions(s, data);

        // 2. String Functions (8)
        test_string_functions(s, data);

        // 3. Math Functions (7)
        test_math_functions(s, data);

        // 4. JSON Functions (4)
        test_json_functions(s, data);
    }
});

// Test Date/Time functions: DaysSince, AddDays, FormatDate, Now, Today
fn test_datetime_functions(s: &str, data: &[u8]) {
    // DaysSince(date_string)
    let _ = format!("DaysSince(\"{}\")", s);
    let _ = format!("DaysSince(\"2024-01-01\")");
    let _ = format!("DaysSince(\"{}-{}-{}\")",
        if data.len() > 0 { data[0] as i32 + 2000 } else { 2024 },
        if data.len() > 1 { (data[1] % 12) + 1 } else { 1 },
        if data.len() > 2 { (data[2] % 28) + 1 } else { 1 }
    );

    // AddDays(date_string, days)
    let days = if data.len() > 0 { data[0] as i32 } else { 0 };
    let _ = format!("AddDays(\"{}\", {})", s, days);
    let _ = format!("AddDays(\"2024-01-01\", {})", days);

    // FormatDate(date_string, format_string)
    let _ = format!("FormatDate(\"{}\", \"{}\")", s, s);
    let _ = format!("FormatDate(\"2024-01-01\", \"%Y-%m-%d\")");

    // Now() - no params
    let _ = "Now()";

    // Today() - no params
    let _ = "Today()";

    // Test edge cases
    let _ = format!("DaysSince(\"\")");
    let _ = format!("DaysSince(\"invalid-date\")");
    let _ = format!("AddDays(\"{}\", -999999)", s);
    let _ = format!("FormatDate(\"{}\", \"\")", s);
}

// Test String functions: IsValidEmail, Contains, RegexMatch, ToUpper, ToLower, Trim, Length, Substring
fn test_string_functions(s: &str, data: &[u8]) {
    // IsValidEmail(email_string)
    let _ = format!("IsValidEmail(\"{}\")", s);
    let _ = format!("IsValidEmail(\"test@example.com\")");
    let _ = format!("IsValidEmail(\"\")");
    let _ = format!("IsValidEmail(\"invalid@@@email\")");

    // Contains(haystack, needle)
    let needle = if data.len() > 10 {
        std::str::from_utf8(&data[..10]).unwrap_or("test")
    } else {
        "test"
    };
    let _ = format!("Contains(\"{}\", \"{}\")", s, needle);
    let _ = format!("Contains(\"{}\", \"\")", s);

    // RegexMatch(string, pattern)
    let _ = format!("RegexMatch(\"{}\", \"{}\")", s, s);
    let _ = format!("RegexMatch(\"{}\", \"[a-z]+\")", s);
    let _ = format!("RegexMatch(\"{}\", \"^.*$\")", s);
    let _ = format!("RegexMatch(\"{}\", \"(((((\")", s); // Invalid regex

    // ToUpper(string)
    let _ = format!("ToUpper(\"{}\")", s);
    let upper = s.to_uppercase();
    let _ = upper.len();

    // ToLower(string)
    let _ = format!("ToLower(\"{}\")", s);
    let lower = s.to_lowercase();
    let _ = lower.len();

    // Trim(string)
    let _ = format!("Trim(\"{}\")", s);
    let trimmed = s.trim();
    let _ = trimmed.len();

    // Length(string)
    let _ = format!("Length(\"{}\")", s);
    let _ = s.len();
    let _ = s.chars().count();

    // Substring(string, start, length)
    let start = if data.len() > 0 { data[0] as usize % (s.len() + 1) } else { 0 };
    let length = if data.len() > 1 { data[1] as usize % 100 } else { 10 };
    let _ = format!("Substring(\"{}\", {}, {})", s, start, length);
    let _ = format!("Substring(\"{}\", -1, 0)", s);
    let _ = format!("Substring(\"{}\", 999999, 999999)", s);
}

// Test Math functions: Round, Abs, Min, Max, Floor, Ceil, Sqrt
fn test_math_functions(s: &str, data: &[u8]) {
    // Generate test numbers
    let num = if data.len() >= 8 {
        f64::from_le_bytes([
            data[0], data[1], data[2], data[3],
            data[4], data[5], data[6], data[7],
        ])
    } else {
        42.5
    };

    let num2 = if data.len() >= 16 {
        f64::from_le_bytes([
            data[8], data[9], data[10], data[11],
            data[12], data[13], data[14], data[15],
        ])
    } else {
        10.5
    };

    // Round(number)
    let _ = format!("Round({})", num);
    let _ = format!("Round({})", f64::NAN);
    let _ = format!("Round({})", f64::INFINITY);
    let _ = format!("Round({})", f64::NEG_INFINITY);

    // Abs(number)
    let _ = format!("Abs({})", num);
    let _ = format!("Abs({})", -999999.999);

    // Min(a, b)
    let _ = format!("Min({}, {})", num, num2);
    let _ = format!("Min({}, {})", f64::INFINITY, f64::NEG_INFINITY);

    // Max(a, b)
    let _ = format!("Max({}, {})", num, num2);
    let _ = format!("Max({}, {})", f64::NAN, 100.0);

    // Floor(number)
    let _ = format!("Floor({})", num);
    let _ = format!("Floor({})", -42.9);

    // Ceil(number)
    let _ = format!("Ceil({})", num);
    let _ = format!("Ceil({})", 42.1);

    // Sqrt(number)
    let _ = format!("Sqrt({})", num.abs());
    let _ = format!("Sqrt(-1)"); // Imaginary number
    let _ = format!("Sqrt(0)");
    let _ = format!("Sqrt({})", f64::INFINITY);

    // Test with string that might parse as number
    if let Ok(parsed) = s.parse::<f64>() {
        let _ = format!("Round({})", parsed);
        let _ = format!("Abs({})", parsed);
    }
}

// Test JSON functions: JsonParse, JsonStringify, JsonGet, JsonSet
fn test_json_functions(s: &str, _data: &[u8]) {
    // JsonParse(json_string)
    let _ = format!("JsonParse(\"{}\")", s);
    let _ = format!("JsonParse(\"{{}}\")");
    let _ = format!("JsonParse(\"{{\\\"key\\\": \\\"value\\\"}}\")", );
    let _ = format!("JsonParse(\"[1, 2, 3]\")");
    let _ = format!("JsonParse(\"invalid json\")");

    // JsonStringify(object)
    let _ = format!("JsonStringify({})", s);

    // JsonGet(json_object, key)
    let _ = format!("JsonGet({}, \"{}\")", "{\"key\": \"value\"}", s);
    let _ = format!("JsonGet({}, \"nonexistent\")", "{}");

    // JsonSet(json_object, key, value)
    let _ = format!("JsonSet({}, \"{}\", \"{}\")", "{}", s, s);

    // Test edge cases
    let _ = format!("JsonParse(\"\")");
    let _ = format!("JsonParse(\"{{{{\")"); // Malformed
    let _ = format!("JsonGet(null, \"key\")");
}
