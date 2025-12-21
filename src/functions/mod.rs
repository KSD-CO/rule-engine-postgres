/// Built-in functions library for GRL
/// Provides date/time, string, math, and JSON utilities
pub mod datetime;
pub mod json;
pub mod math;
pub mod preprocessing;
pub mod registration;
pub mod string;

use serde_json::Value;
use std::collections::HashMap;

/// Function registry - maps function names to implementations
pub type FunctionImpl = fn(&[Value]) -> Result<Value, String>;

lazy_static::lazy_static! {
    /// Global function registry
    pub static ref FUNCTION_REGISTRY: HashMap<&'static str, FunctionImpl> = {
        let mut m = HashMap::new();

        // Date/time functions
        m.insert("DaysSince", datetime::days_since as FunctionImpl);
        m.insert("AddDays", datetime::add_days as FunctionImpl);
        m.insert("FormatDate", datetime::format_date as FunctionImpl);
        m.insert("Now", datetime::now as FunctionImpl);
        m.insert("Today", datetime::today as FunctionImpl);

        // String functions
        m.insert("IsValidEmail", string::is_valid_email as FunctionImpl);
        m.insert("Contains", string::contains as FunctionImpl);
        m.insert("RegexMatch", string::regex_match as FunctionImpl);
        m.insert("ToUpper", string::to_upper as FunctionImpl);
        m.insert("ToLower", string::to_lower as FunctionImpl);
        m.insert("Trim", string::trim as FunctionImpl);
        m.insert("Length", string::length as FunctionImpl);
        m.insert("Substring", string::substring as FunctionImpl);

        // Math functions
        m.insert("Round", math::round as FunctionImpl);
        m.insert("Abs", math::abs as FunctionImpl);
        m.insert("Min", math::min as FunctionImpl);
        m.insert("Max", math::max as FunctionImpl);
        m.insert("Floor", math::floor as FunctionImpl);
        m.insert("Ceil", math::ceil as FunctionImpl);
        m.insert("Sqrt", math::sqrt as FunctionImpl);

        // JSON functions
        m.insert("JsonParse", json::parse as FunctionImpl);
        m.insert("JsonStringify", json::stringify as FunctionImpl);
        m.insert("JsonGet", json::get as FunctionImpl);
        m.insert("JsonSet", json::set as FunctionImpl);

        m
    };
}

/// Execute a built-in function
pub fn execute_function(name: &str, args: &[Value]) -> Result<Value, String> {
    FUNCTION_REGISTRY
        .get(name)
        .ok_or_else(|| format!("Unknown function: {}", name))
        .and_then(|f| f(args))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_function_registry() {
        assert!(FUNCTION_REGISTRY.contains_key("DaysSince"));
        assert!(FUNCTION_REGISTRY.contains_key("IsValidEmail"));
        assert!(FUNCTION_REGISTRY.contains_key("Round"));
    }

    #[test]
    fn test_execute_function() {
        let result = execute_function("Round", &[json!(3.7), json!(0)]);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), json!(4.0));
    }
}
