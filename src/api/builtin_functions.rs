/// PostgreSQL wrapper functions for built-in GRL functions
/// Allows calling built-in functions directly from SQL for testing

use pgrx::prelude::*;
use serde_json::Value;

use crate::functions;

/// Execute a built-in function from SQL
///
/// # Example
/// ```sql
/// SELECT rule_function_call('Round', '[3.14159, 2]'::jsonb);
/// -- Returns: 3.14
/// ```
#[pg_extern]
fn rule_function_call(
    function_name: &str,
    args_json: pgrx::JsonB,
) -> Result<pgrx::JsonB, Box<dyn std::error::Error + Send + Sync>> {
    // Parse args from JSONB
    let args_value: Value = serde_json::from_value(args_json.0.clone())?;

    let args_array = args_value
        .as_array()
        .ok_or("Arguments must be a JSON array")?;

    // Execute function
    let result = functions::execute_function(function_name, args_array)
        .map_err(|e| format!("Function execution error: {}", e))?;

    Ok(pgrx::JsonB(result))
}

/// List all available built-in functions
///
/// # Example
/// ```sql
/// SELECT * FROM rule_function_list();
/// ```
#[pg_extern]
fn rule_function_list() -> TableIterator<'static, (name!(function_name, String), name!(category, String), name!(description, String))> {
    let functions = vec![
        // Date/time functions
        ("DaysSince".to_string(), "datetime".to_string(), "Calculate days since a given date".to_string()),
        ("AddDays".to_string(), "datetime".to_string(), "Add days to a date".to_string()),
        ("FormatDate".to_string(), "datetime".to_string(), "Format a date with custom format".to_string()),
        ("Now".to_string(), "datetime".to_string(), "Get current timestamp".to_string()),
        ("Today".to_string(), "datetime".to_string(), "Get current date".to_string()),

        // String functions
        ("IsValidEmail".to_string(), "string".to_string(), "Validate email address".to_string()),
        ("Contains".to_string(), "string".to_string(), "Check if string contains substring".to_string()),
        ("RegexMatch".to_string(), "string".to_string(), "Match string against regex pattern".to_string()),
        ("ToUpper".to_string(), "string".to_string(), "Convert string to uppercase".to_string()),
        ("ToLower".to_string(), "string".to_string(), "Convert string to lowercase".to_string()),
        ("Trim".to_string(), "string".to_string(), "Trim whitespace from both ends".to_string()),
        ("Length".to_string(), "string".to_string(), "Get string length".to_string()),
        ("Substring".to_string(), "string".to_string(), "Get substring".to_string()),

        // Math functions
        ("Round".to_string(), "math".to_string(), "Round a number to specified decimal places".to_string()),
        ("Abs".to_string(), "math".to_string(), "Absolute value".to_string()),
        ("Min".to_string(), "math".to_string(), "Minimum of two or more numbers".to_string()),
        ("Max".to_string(), "math".to_string(), "Maximum of two or more numbers".to_string()),
        ("Floor".to_string(), "math".to_string(), "Floor (round down)".to_string()),
        ("Ceil".to_string(), "math".to_string(), "Ceiling (round up)".to_string()),
        ("Sqrt".to_string(), "math".to_string(), "Square root".to_string()),

        // JSON functions
        ("JsonParse".to_string(), "json".to_string(), "Parse JSON string to object".to_string()),
        ("JsonStringify".to_string(), "json".to_string(), "Convert object to JSON string".to_string()),
        ("JsonGet".to_string(), "json".to_string(), "Get value from JSON object by path".to_string()),
        ("JsonSet".to_string(), "json".to_string(), "Set value in JSON object by path".to_string()),
    ];

    TableIterator::new(functions)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rule_function_call() {
        let args = pgrx::JsonB(serde_json::json!([3.14159, 2]));
        let result = rule_function_call("Round", args).unwrap();
        assert_eq!(result.0, serde_json::json!(3.14));
    }
}
