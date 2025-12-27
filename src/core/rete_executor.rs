//! RETE-based executor for high performance
//!
//! Uses IncrementalEngine (RETE algorithm) for 2-24x faster execution
//! compared to traditional forward chaining.

use rust_rule_engine::rete::facts::FactValue;
use rust_rule_engine::rete::{GrlReteLoader, IncrementalEngine, TypedFacts};
use serde_json::Value as JsonValue;

/// Execute rules using RETE engine (high performance)
pub fn execute_rules_rete(facts_json: &JsonValue, rules_grl: &str) -> Result<JsonValue, String> {
    // Create RETE engine
    let mut rete = IncrementalEngine::new();

    // Load GRL rules into RETE
    let rule_count = GrlReteLoader::load_from_string(rules_grl, &mut rete)
        .map_err(|e| format!("Failed to load GRL into RETE: {}", e))?;

    if rule_count == 0 {
        return Err("No rules loaded".to_string());
    }

    // Convert JSON facts to TypedFacts and insert into working memory
    let fact_handles = json_to_typed_facts(facts_json, &mut rete)?;

    // Fire all rules
    let _fired_rules = rete.fire_all();

    // Extract final facts from working memory
    let final_facts = extract_facts_from_rete(&rete, &fact_handles)?;

    Ok(final_facts)
}

/// Convert JSON object to TypedFacts and insert into RETE
fn json_to_typed_facts(
    json: &JsonValue,
    rete: &mut IncrementalEngine,
) -> Result<Vec<(String, rust_rule_engine::rete::working_memory::FactHandle)>, String> {
    let mut handles = Vec::new();

    match json {
        JsonValue::Object(map) => {
            for (fact_type, fact_data) in map {
                let mut typed_facts = TypedFacts::new();

                // Convert fact data to TypedFacts
                if let JsonValue::Object(fields) = fact_data {
                    for (field_name, field_value) in fields {
                        set_typed_field(&mut typed_facts, field_name, field_value)?;
                    }
                }

                // Insert into RETE working memory
                let handle = rete.insert(fact_type.clone(), typed_facts);
                handles.push((fact_type.clone(), handle));
            }
            Ok(handles)
        }
        _ => Err("Facts must be a JSON object".to_string()),
    }
}

/// Set a field in TypedFacts from JSON value
fn set_typed_field(facts: &mut TypedFacts, name: &str, value: &JsonValue) -> Result<(), String> {
    match value {
        JsonValue::String(s) => facts.set(name, FactValue::String(s.clone())),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                facts.set(name, FactValue::Integer(i));
            } else if let Some(f) = n.as_f64() {
                facts.set(name, FactValue::Float(f));
            } else {
                return Err(format!("Invalid number: {}", n));
            }
        }
        JsonValue::Bool(b) => facts.set(name, FactValue::Boolean(*b)),
        JsonValue::Null => facts.set(name, FactValue::Null),
        JsonValue::Array(arr) => {
            // Convert array recursively
            let fact_arr: Result<Vec<FactValue>, String> =
                arr.iter().map(json_to_fact_value).collect();
            facts.set(name, FactValue::Array(fact_arr?));
        }
        JsonValue::Object(_) => {
            // Nested objects: store as JSON string for now
            // TODO: Support nested TypedFacts
            facts.set(name, FactValue::String(value.to_string()));
        }
    }
    Ok(())
}

/// Convert JSON value to FactValue
fn json_to_fact_value(value: &JsonValue) -> Result<FactValue, String> {
    match value {
        JsonValue::String(s) => Ok(FactValue::String(s.clone())),
        JsonValue::Number(n) => {
            if let Some(i) = n.as_i64() {
                Ok(FactValue::Integer(i))
            } else if let Some(f) = n.as_f64() {
                Ok(FactValue::Float(f))
            } else {
                Err(format!("Invalid number: {}", n))
            }
        }
        JsonValue::Bool(b) => Ok(FactValue::Boolean(*b)),
        JsonValue::Null => Ok(FactValue::Null),
        JsonValue::Array(arr) => {
            let fact_arr: Result<Vec<FactValue>, String> =
                arr.iter().map(json_to_fact_value).collect();
            Ok(FactValue::Array(fact_arr?))
        }
        JsonValue::Object(_) => Ok(FactValue::String(value.to_string())),
    }
}

/// Extract final facts from RETE working memory
fn extract_facts_from_rete(
    rete: &IncrementalEngine,
    handles: &[(String, rust_rule_engine::rete::working_memory::FactHandle)],
) -> Result<JsonValue, String> {
    let mut result = serde_json::Map::new();

    for (fact_type, handle) in handles {
        if let Some(fact) = rete.working_memory().get(handle) {
            // Convert TypedFacts back to JSON
            let fact_json = typed_facts_to_json(&fact.data);
            result.insert(fact_type.clone(), fact_json);
        }
    }

    Ok(JsonValue::Object(result))
}

/// Convert TypedFacts to JSON
fn typed_facts_to_json(facts: &TypedFacts) -> JsonValue {
    let mut map = serde_json::Map::new();

    // Get all fields from TypedFacts
    let all_facts = facts.get_all();
    for (key, value) in all_facts.iter() {
        let json_value = fact_value_to_json(value);
        map.insert(key.clone(), json_value);
    }

    JsonValue::Object(map)
}

/// Convert FactValue to JSON
fn fact_value_to_json(value: &FactValue) -> JsonValue {
    match value {
        FactValue::String(s) => JsonValue::String(s.clone()),
        FactValue::Integer(i) => JsonValue::Number((*i).into()),
        FactValue::Float(f) => serde_json::Number::from_f64(*f)
            .map(JsonValue::Number)
            .unwrap_or(JsonValue::Null),
        FactValue::Boolean(b) => JsonValue::Bool(*b),
        FactValue::Array(arr) => {
            let json_arr: Vec<JsonValue> = arr.iter().map(fact_value_to_json).collect();
            JsonValue::Array(json_arr)
        }
        FactValue::Null => JsonValue::Null,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_rete_execution() {
        let facts = json!({
            "Order": {
                "quantity": 10,
                "price": 100
            }
        });

        let grl = r#"
            rule "CalculateTotal" {
                when
                    Order.quantity > 0
                then
                    Order.total = Order.quantity * Order.price;
            }
        "#;

        let result = execute_rules_rete(&facts, grl).unwrap();

        // Check that total was calculated
        assert_eq!(result["Order"]["quantity"], 10);
        assert_eq!(result["Order"]["price"], 100);
        assert_eq!(result["Order"]["total"], 1000);
    }
}
