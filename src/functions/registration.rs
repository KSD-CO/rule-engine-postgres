/// Register all built-in functions with rust-rule-engine

use rust_rule_engine::{RuleEngineError, RustRuleEngine, Value};
use serde_json::Value as JsonValue;

use super::{datetime, json, math, string};

/// Convert string error to RuleEngineError
fn to_eval_error(msg: String) -> RuleEngineError {
    RuleEngineError::EvaluationError { message: msg }
}

/// Register all built-in functions with the rule engine
pub fn register_all_functions(engine: &mut RustRuleEngine) {
    register_datetime_functions(engine);
    register_string_functions(engine);
    register_math_functions(engine);
    register_json_functions(engine);
}

/// Register date/time functions
fn register_datetime_functions(engine: &mut RustRuleEngine) {
    // DaysSince
    engine.register_function("DaysSince", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = datetime::days_since(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // AddDays
    engine.register_function("AddDays", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = datetime::add_days(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // FormatDate
    engine.register_function("FormatDate", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = datetime::format_date(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Now
    engine.register_function("Now", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = datetime::now(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Today
    engine.register_function("Today", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = datetime::today(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });
}

/// Register string functions
fn register_string_functions(engine: &mut RustRuleEngine) {
    // IsValidEmail
    engine.register_function("IsValidEmail", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::is_valid_email(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Contains
    engine.register_function("Contains", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::contains(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // RegexMatch
    engine.register_function("RegexMatch", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::regex_match(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // ToUpper
    engine.register_function("ToUpper", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::to_upper(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // ToLower
    engine.register_function("ToLower", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::to_lower(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Trim
    engine.register_function("Trim", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::trim(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Length
    engine.register_function("Length", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::length(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Substring
    engine.register_function("Substring", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = string::substring(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });
}

/// Register math functions
fn register_math_functions(engine: &mut RustRuleEngine) {
    // Round
    engine.register_function("Round", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::round(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Abs
    engine.register_function("Abs", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::abs(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Min
    engine.register_function("Min", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::min(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Max
    engine.register_function("Max", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::max(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Floor
    engine.register_function("Floor", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::floor(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Ceil
    engine.register_function("Ceil", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::ceil(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // Sqrt
    engine.register_function("Sqrt", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = math::sqrt(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });
}

/// Register JSON functions
fn register_json_functions(engine: &mut RustRuleEngine) {
    // JsonParse
    engine.register_function("JsonParse", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = json::parse(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // JsonStringify
    engine.register_function("JsonStringify", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = json::stringify(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // JsonGet
    engine.register_function("JsonGet", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = json::get(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });

    // JsonSet
    engine.register_function("JsonSet", |args, _facts| {
        let json_args: Vec<JsonValue> = args.iter().map(value_to_json).collect();
        let result = json::set(&json_args)
            .map_err(to_eval_error)?;
        json_to_value(&result).map_err(to_eval_error)
    });
}

/// Convert rust-rule-engine Value to serde_json Value
fn value_to_json(val: &Value) -> JsonValue {
    match val {
        Value::String(s) => JsonValue::String(s.clone()),
        Value::Integer(i) => JsonValue::Number((*i).into()),
        Value::Number(n) => {
            if let Some(num) = serde_json::Number::from_f64(*n) {
                JsonValue::Number(num)
            } else {
                JsonValue::Null
            }
        }
        Value::Boolean(b) => JsonValue::Bool(*b),
        Value::Array(arr) => {
            JsonValue::Array(arr.iter().map(value_to_json).collect())
        }
        Value::Object(obj) => {
            let map: serde_json::Map<String, JsonValue> = obj
                .iter()
                .map(|(k, v)| (k.clone(), value_to_json(v)))
                .collect();
            JsonValue::Object(map)
        }
        Value::Null => JsonValue::Null,
        Value::Expression(expr) => JsonValue::String(expr.clone()), // Treat expressions as strings
    }
}

/// Convert serde_json Value to rust-rule-engine Value
fn json_to_value(val: &JsonValue) -> Result<Value, String> {
    match val {
        JsonValue::String(s) => Ok(Value::String(s.clone())),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                Ok(Value::Integer(i))
            } else if let Some(f) = n.as_f64() {
                Ok(Value::Number(f))
            } else {
                Err("Invalid number".to_string())
            }
        }
        JsonValue::Bool(b) => Ok(Value::Boolean(*b)),
        JsonValue::Array(arr) => {
            let values: Result<Vec<Value>, String> =
                arr.iter().map(json_to_value).collect();
            Ok(Value::Array(values?))
        }
        JsonValue::Object(obj) => {
            let map: Result<std::collections::HashMap<String, Value>, String> = obj
                .iter()
                .map(|(k, v)| json_to_value(v).map(|val| (k.clone(), val)))
                .collect();
            Ok(Value::Object(map?))
        }
        JsonValue::Null => Ok(Value::Null),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_rule_engine::KnowledgeBase;

    #[test]
    fn test_register_all_functions() {
        let kb = KnowledgeBase::new("test");
        let mut engine = RustRuleEngine::new(kb);

        // Should not panic
        register_all_functions(&mut engine);
    }

    #[test]
    fn test_value_conversion() {
        let json_val = JsonValue::String("test".to_string());
        let engine_val = json_to_value(&json_val).unwrap();
        let back_to_json = value_to_json(&engine_val);
        assert_eq!(json_val, back_to_json);
    }
}
