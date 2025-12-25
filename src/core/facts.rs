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
/// Converts dotted keys back to nested objects:
/// - facts["Order.total"] = 150 → {"Order": {"total": 150}}
/// - facts["total"] = 150 → {"total": 150}
pub fn facts_to_json(facts: &Facts) -> Result<String, String> {
    let mut result = serde_json::Map::new();

    // Get all facts from Facts
    let all_facts = facts.get_all_facts();
    for (key, value) in all_facts {
        // Convert dotted keys to nested structure
        insert_nested_value(&mut result, &key, engine_value_to_json(&value));
    }

    serde_json::to_string(&serde_json::Value::Object(result))
        .map_err(|e| format!("Serialization error: {}", e))
}

/// Insert a value into nested JSON structure using dotted key
/// Example: key="Order.total", value=150
///   → result["Order"]["total"] = 150
fn insert_nested_value(
    result: &mut serde_json::Map<String, serde_json::Value>,
    key: &str,
    value: serde_json::Value,
) {
    let parts: Vec<&str> = key.split('.').collect();

    if parts.len() == 1 {
        // Simple key - insert directly
        result.insert(key.to_string(), value);
        return;
    }

    // Navigate/create nested structure
    let mut current = result;
    for (i, part) in parts.iter().enumerate() {
        if i == parts.len() - 1 {
            // Last part - insert value
            current.insert(part.to_string(), value);
            break;
        } else {
            // Intermediate part - ensure object exists
            current = current
                .entry(part.to_string())
                .or_insert_with(|| serde_json::Value::Object(serde_json::Map::new()))
                .as_object_mut()
                .expect("Expected object in nested path");
        }
    }
}

/// Parse JSON string and create Facts object
/// Supports both flat and nested JSON:
/// - Flat: {"total": 150} → facts["total"] = 150
/// - Nested: {"Order": {"total": 150}} → facts["Order.total"] = 150
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
        // Flatten nested objects into dotted keys
        flatten_and_add_to_facts(&facts, None, &serde_json::Value::Object(map))?;
    }

    Ok(facts)
}

/// Recursively flatten nested JSON objects into dotted keys and add to Facts
/// Example: {"Order": {"total": 150, "discount": 0}}
///   → facts["Order.total"] = 150
///   → facts["Order.discount"] = 0
fn flatten_and_add_to_facts(
    facts: &Facts,
    prefix: Option<&str>,
    value: &serde_json::Value,
) -> Result<(), String> {
    match value {
        serde_json::Value::Object(map) => {
            // Recursively flatten nested objects
            for (key, val) in map {
                let new_prefix = match prefix {
                    Some(p) => format!("{}.{}", p, key),
                    None => key.clone(),
                };

                if val.is_object() {
                    // Recurse into nested object
                    flatten_and_add_to_facts(facts, Some(&new_prefix), val)?;
                } else {
                    // Leaf value - add to facts
                    if let Err(e) = facts.add_value(&new_prefix, val.clone().into()) {
                        return Err(format!("Failed to add fact '{}': {}", new_prefix, e));
                    }
                }
            }
        }
        _ => {
            // Non-object value at top level - add directly
            if let Some(key) = prefix {
                if let Err(e) = facts.add_value(key, value.clone().into()) {
                    return Err(format!("Failed to add fact '{}': {}", key, e));
                }
            }
        }
    }

    Ok(())
}
