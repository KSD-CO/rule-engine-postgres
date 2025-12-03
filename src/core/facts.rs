use rust_rule_engine::{Facts, Value};
use serde_json;

/// Convert engine Value to serde_json Value
pub fn engine_value_to_json(value: &Value) -> serde_json::Value {
    match value {
        Value::Null => serde_json::Value::Null,
        Value::Boolean(b) => serde_json::Value::Bool(*b),
        Value::Integer(i) => serde_json::Value::Number((*i).into()),
        Value::Number(n) => serde_json::Number::from_f64(*n)
            .map(serde_json::Value::Number)
            .unwrap_or(serde_json::Value::Null),
        Value::String(s) => serde_json::Value::String(s.clone()),
        Value::Object(map) => {
            let mut obj = serde_json::Map::new();
            for (key, val) in map {
                obj.insert(key.clone(), engine_value_to_json(val));
            }
            serde_json::Value::Object(obj)
        }
        Value::Array(arr) => {
            serde_json::Value::Array(arr.iter().map(engine_value_to_json).collect())
        }
        Value::Expression(s) => serde_json::Value::String(s.clone()),
    }
}

/// Convert Facts to JSON string
pub fn facts_to_json(facts: &Facts) -> Result<String, String> {
    let mut result = serde_json::Map::new();

    // Get all facts from Facts
    let all_facts = facts.get_all_facts();
    for (key, value) in all_facts {
        result.insert(key, engine_value_to_json(&value));
    }

    serde_json::to_string(&serde_json::Value::Object(result))
        .map_err(|e| format!("Serialization error: {}", e))
}

/// Parse JSON string and create Facts object
pub fn json_to_facts(json_str: &str) -> Result<Facts, String> {
    // Parse JSON
    let json_val = serde_json::from_str::<serde_json::Value>(json_str)
        .map_err(|e| format!("Invalid JSON syntax: {}", e))?;

    // Validate that it's a JSON object
    if !json_val.is_object() {
        return Err("Facts must be a JSON object, not an array or primitive".to_string());
    }

    // Create Facts and add each field
    let facts = Facts::new();
    if let serde_json::Value::Object(map) = json_val {
        for (key, value) in map {
            // Use built-in From<serde_json::Value> for Value conversion
            if let Err(e) = facts.add_value(&key, value.into()) {
                return Err(format!("Failed to add fact '{}': {}", key, e));
            }
        }
    }

    Ok(facts)
}
