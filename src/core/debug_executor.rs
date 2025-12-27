//! Debug-enabled executor that captures RETE events
//!
//! This executor wraps the standard executor and captures all events
//! during rule execution for time-travel debugging.

use crate::debug::{
    current_timestamp, save_event_to_db, save_session_to_db, ReteEvent, GLOBAL_EVENT_STORE,
};
use rust_rule_engine::{Facts, KnowledgeBase, RustRuleEngine, Value};
use serde_json::json;

/// Execute rules with debugging enabled
/// Returns (final_facts, session_id)
pub fn execute_rules_debug(
    facts: &Facts,
    rules: Vec<rust_rule_engine::Rule>,
    session_id: String,
    rules_grl: String,
) -> Result<(Facts, String), String> {
    // Convert Facts to JSON for event storage
    let initial_facts_json = facts_to_json(facts);

    // Create debug session
    GLOBAL_EVENT_STORE.create_session(session_id.clone(), rules_grl.clone(), initial_facts_json);

    // Record ExecutionStarted event
    let start_event = ReteEvent::ExecutionStarted {
        timestamp: current_timestamp(),
        session_id: session_id.clone(),
        rules_count: rules.len(),
        initial_facts_count: count_facts(facts),
        rules_grl,
        initial_facts: facts_to_json(facts),
    };

    GLOBAL_EVENT_STORE
        .add_event(&session_id, start_event.clone())
        .map_err(|e| format!("Failed to record start event: {}", e))?;

    // Also save to PostgreSQL for persistence
    let _ = save_event_to_db(&session_id, &start_event);

    // Create knowledge base and engine
    let kb = KnowledgeBase::new("PostgresExtension");
    let mut engine = RustRuleEngine::new(kb);

    // Register built-in functions
    crate::functions::registration::register_all_functions(&mut engine);

    // Register action handler for 'print' with event capture
    let _session_id_clone = session_id.clone();
    engine.register_action_handler("print", move |args, _context| {
        if let Some(val) = args.get("0") {
            pgrx::log!("RULE ENGINE PRINT: {:?}", val);
        } else {
            pgrx::log!("RULE ENGINE PRINT: <no value>");
        }
        Ok(())
    });

    // Add rules to engine and capture rule definitions
    let mut rule_names = Vec::new();
    for (idx, rule) in rules.into_iter().enumerate() {
        let rule_name = rule.name.clone();
        rule_names.push(rule_name);

        if let Err(e) = engine.knowledge_base_mut().add_rule(rule) {
            // Record error event
            let error_event = ReteEvent::ExecutionError {
                step: 0,
                timestamp: current_timestamp(),
                error_type: "RuleAdditionError".to_string(),
                error_message: format!("Failed to add rule #{}: {}", idx + 1, e),
                context: json!({
                    "rule_index": idx,
                }),
            };

            let _ = GLOBAL_EVENT_STORE.add_event(&session_id, error_event);
            let _ = GLOBAL_EVENT_STORE.error_session(&session_id);

            return Err(format!("Failed to add rule #{}: {}", idx + 1, e));
        }
    }

    // Clone facts for execution (engine may modify them)
    let execution_facts = facts.clone();

    // Execute engine
    let start_time = current_timestamp();
    let execution_result = engine.execute(&execution_facts);

    let duration_ms = current_timestamp() - start_time;

    match execution_result {
        Ok(_result) => {
            // Execution successful - record completion event
            let final_facts_json = facts_to_json(&execution_facts);

            let complete_event = ReteEvent::ExecutionCompleted {
                step: GLOBAL_EVENT_STORE.next_step(&session_id).unwrap_or(1),
                timestamp: current_timestamp(),
                total_rules_fired: 0,    // TODO: Track actual fired rules
                total_facts_modified: 0, // TODO: Track actual modifications
                duration_ms,
                final_facts: final_facts_json,
            };

            GLOBAL_EVENT_STORE
                .add_event(&session_id, complete_event.clone())
                .map_err(|e| format!("Failed to record completion event: {}", e))?;

            GLOBAL_EVENT_STORE
                .complete_session(&session_id)
                .map_err(|e| format!("Failed to complete session: {}", e))?;

            // Save completion event to PostgreSQL
            let _ = save_event_to_db(&session_id, &complete_event);

            // Save final session state to PostgreSQL
            if let Ok(session) = GLOBAL_EVENT_STORE.get_session(&session_id) {
                let _ = save_session_to_db(&session);
            }

            Ok((execution_facts, session_id))
        }
        Err(e) => {
            // Execution failed - record error event
            let error_event = ReteEvent::ExecutionError {
                step: GLOBAL_EVENT_STORE.next_step(&session_id).unwrap_or(1),
                timestamp: current_timestamp(),
                error_type: "ExecutionError".to_string(),
                error_message: e.to_string(),
                context: json!({}),
            };

            let _ = GLOBAL_EVENT_STORE.add_event(&session_id, error_event.clone());
            let _ = GLOBAL_EVENT_STORE.error_session(&session_id);

            // Save error event to PostgreSQL
            let _ = save_event_to_db(&session_id, &error_event);

            // Save error session state to PostgreSQL
            if let Ok(session) = GLOBAL_EVENT_STORE.get_session(&session_id) {
                let _ = save_session_to_db(&session);
            }

            Err(format!("Rule execution failed: {}", e))
        }
    }
}

/// Convert Facts to JSON for event storage
fn facts_to_json(facts: &Facts) -> serde_json::Value {
    let mut map = serde_json::Map::new();

    let all_facts = facts.get_all_facts();
    for (key, value) in all_facts.iter() {
        let json_value = value_to_json(value);
        map.insert(key.clone(), json_value);
    }

    serde_json::Value::Object(map)
}

/// Convert a single Value to JSON
fn value_to_json(val: &Value) -> serde_json::Value {
    match val {
        Value::String(s) => json!(s),
        Value::Integer(i) => json!(i),
        Value::Number(n) => json!(n),
        Value::Boolean(b) => json!(b),
        Value::Array(arr) => {
            let arr_values: Vec<serde_json::Value> = arr.iter().map(value_to_json).collect();
            json!(arr_values)
        }
        Value::Object(obj) => {
            let mut map = serde_json::Map::new();
            for (k, v) in obj.iter() {
                map.insert(k.clone(), value_to_json(v));
            }
            serde_json::Value::Object(map)
        }
        Value::Null => serde_json::Value::Null,
        Value::Expression(expr) => json!(expr),
    }
}

/// Count the number of facts in the Facts object
fn count_facts(facts: &Facts) -> usize {
    facts.count()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_rule_engine::Value;

    #[test]
    fn test_facts_to_json() {
        let facts = Facts::new();
        facts.set("name", Value::String("Alice".to_string()));
        facts.set("age", Value::Integer(30));

        let json = facts_to_json(&facts);
        assert_eq!(json["name"], "Alice");
        assert_eq!(json["age"], 30);
    }

    #[test]
    fn test_count_facts() {
        let facts = Facts::new();
        facts.set("name", Value::String("Alice".to_string()));
        facts.set("age", Value::Integer(30));

        let count = count_facts(&facts);
        assert!(count >= 2);
    }

    #[test]
    fn test_value_to_json_array() {
        let arr = Value::Array(vec![
            Value::Integer(1),
            Value::Integer(2),
            Value::Integer(3),
        ]);

        let json = value_to_json(&arr);
        assert_eq!(json, json!([1, 2, 3]));
    }
}
