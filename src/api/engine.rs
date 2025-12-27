use crate::core::execute_rules_rete;
use crate::error::{codes, create_custom_error};
use crate::validation::{validate_facts_input, validate_rules_input};

/// Execute rules using traditional forward chaining algorithm
/// Useful for simple rules or when predictable execution order is needed
#[pgrx::pg_extern]
pub fn run_rule_engine_fc(facts_json: &str, rules_grl: &str) -> String {
    use crate::core::executor::execute_rules;
    use crate::core::facts::{facts_to_json, json_to_facts};
    use crate::core::rules::parse_and_validate_rules;

    // Validate inputs
    if let Err(e) = validate_facts_input(facts_json) {
        return create_custom_error(&codes::EMPTY_FACTS, e);
    }
    if let Err(e) = validate_rules_input(rules_grl) {
        return create_custom_error(&codes::EMPTY_RULES, e);
    }

    // Parse facts from JSON
    let mut facts_value: serde_json::Value = match serde_json::from_str(facts_json) {
        Ok(v) => v,
        Err(e) => return create_custom_error(&codes::INVALID_JSON, e.to_string()),
    };

    // Preprocess GRL with built-in functions (v1.7.0+)
    let transformed_grl = match crate::functions::preprocessing::preprocess_grl_with_functions(
        rules_grl,
        &mut facts_value,
    ) {
        Ok(grl) => grl,
        Err(e) => {
            return create_custom_error(
                &codes::INVALID_GRL,
                format!("Function preprocessing error: {}", e),
            )
        }
    };

    // Convert to Facts object
    let facts = match json_to_facts(&serde_json::to_string(&facts_value).unwrap()) {
        Ok(f) => f,
        Err(e) => return create_custom_error(&codes::INVALID_JSON, e),
    };

    // Parse rules
    let rules = match parse_and_validate_rules(&transformed_grl) {
        Ok(r) => r,
        Err(e) => return create_custom_error(&codes::INVALID_GRL, e),
    };

    // Execute rules using traditional forward chaining
    if let Err(e) = execute_rules(&facts, rules) {
        return create_custom_error(&codes::EXECUTION_FAILED, e);
    }

    // Convert result back to JSON
    match facts_to_json(&facts) {
        Ok(json) => json,
        Err(e) => create_custom_error(&codes::EXECUTION_FAILED, e),
    }
}

/// Execute rules using RETE algorithm (high performance, incremental evaluation)
/// Best for batch processing, complex rules, and high-throughput scenarios
#[pgrx::pg_extern]
pub fn run_rule_engine_rete(facts_json: &str, rules_grl: &str) -> String {
    // Validate inputs
    if let Err(e) = validate_facts_input(facts_json) {
        return create_custom_error(&codes::EMPTY_FACTS, e);
    }
    if let Err(e) = validate_rules_input(rules_grl) {
        return create_custom_error(&codes::EMPTY_RULES, e);
    }

    // Parse facts from JSON
    let mut facts_value: serde_json::Value = match serde_json::from_str(facts_json) {
        Ok(v) => v,
        Err(e) => return create_custom_error(&codes::INVALID_JSON, e.to_string()),
    };

    // Preprocess GRL with built-in functions (v1.7.0+)
    let transformed_grl = match crate::functions::preprocessing::preprocess_grl_with_functions(
        rules_grl,
        &mut facts_value,
    ) {
        Ok(grl) => grl,
        Err(e) => {
            return create_custom_error(
                &codes::INVALID_GRL,
                format!("Function preprocessing error: {}", e),
            )
        }
    };

    // Execute rules using RETE engine (high performance)
    let result_value = match execute_rules_rete(&facts_value, &transformed_grl) {
        Ok(v) => v,
        Err(e) => return create_custom_error(&codes::EXECUTION_FAILED, e),
    };

    // Convert result to JSON string
    result_value.to_string()
}

/// Main function to execute GRL rules on JSON facts
/// Default uses RETE algorithm for optimal performance
/// Automatically enables debug mode if debug_enable() was called
#[pgrx::pg_extern]
pub fn run_rule_engine(facts_json: &str, rules_grl: &str) -> String {
    // Check if debug mode is enabled
    if crate::debug::is_debug_enabled() {
        // Debug mode enabled - capture events and return detailed info
        // Note: This returns JSON string with session info, not just facts
        pgrx::log!("Debug mode enabled - executing with event capture");

        use crate::core::execute_rules_debug;
        use crate::core::facts::json_to_facts;
        use crate::core::rules::parse_and_validate_rules;
        use uuid::Uuid;

        // Validate inputs
        if let Err(e) = validate_facts_input(facts_json) {
            return create_custom_error(&codes::EMPTY_FACTS, e);
        }
        if let Err(e) = validate_rules_input(rules_grl) {
            return create_custom_error(&codes::EMPTY_RULES, e);
        }

        // Parse facts from JSON
        let mut facts_value: serde_json::Value = match serde_json::from_str(facts_json) {
            Ok(v) => v,
            Err(e) => return create_custom_error(&codes::INVALID_JSON, e.to_string()),
        };

        // Preprocess GRL
        let transformed_grl = match crate::functions::preprocessing::preprocess_grl_with_functions(
            rules_grl,
            &mut facts_value,
        ) {
            Ok(grl) => grl,
            Err(e) => {
                return create_custom_error(
                    &codes::INVALID_GRL,
                    format!("Function preprocessing error: {}", e),
                )
            }
        };

        // Convert to Facts
        let facts = match json_to_facts(&facts_value.to_string()) {
            Ok(f) => f,
            Err(e) => return create_custom_error(&codes::INVALID_JSON, e),
        };

        // Parse rules
        let rules = match parse_and_validate_rules(&transformed_grl) {
            Ok(r) => r,
            Err(e) => return create_custom_error(&codes::INVALID_GRL, e),
        };

        // Generate session ID
        let session_id = format!("session_{}", Uuid::new_v4());

        // Execute with debugging
        match execute_rules_debug(&facts, rules, session_id.clone(), transformed_grl) {
            Ok((final_facts, _)) => {
                // Return just the facts (same format as non-debug mode)
                use crate::core::facts::facts_to_json;
                match facts_to_json(&final_facts) {
                    Ok(json) => {
                        pgrx::log!(
                            "Debug session: {} (use debug_get_events() to view)",
                            session_id
                        );
                        json
                    }
                    Err(e) => create_custom_error(&codes::EXECUTION_FAILED, e),
                }
            }
            Err(e) => create_custom_error(&codes::EXECUTION_FAILED, e),
        }
    } else {
        // Normal mode - no debug overhead
        // Validate inputs
        if let Err(e) = validate_facts_input(facts_json) {
            return create_custom_error(&codes::EMPTY_FACTS, e);
        }
        if let Err(e) = validate_rules_input(rules_grl) {
            return create_custom_error(&codes::EMPTY_RULES, e);
        }

        // Parse facts from JSON
        let mut facts_value: serde_json::Value = match serde_json::from_str(facts_json) {
            Ok(v) => v,
            Err(e) => return create_custom_error(&codes::INVALID_JSON, e.to_string()),
        };

        // Preprocess GRL with built-in functions (v1.7.0+)
        let transformed_grl = match crate::functions::preprocessing::preprocess_grl_with_functions(
            rules_grl,
            &mut facts_value,
        ) {
            Ok(grl) => grl,
            Err(e) => {
                return create_custom_error(
                    &codes::INVALID_GRL,
                    format!("Function preprocessing error: {}", e),
                )
            }
        };

        // Execute rules using RETE engine (high performance)
        let result_value = match execute_rules_rete(&facts_value, &transformed_grl) {
            Ok(v) => v,
            Err(e) => return create_custom_error(&codes::EXECUTION_FAILED, e),
        };

        // Convert result to JSON string
        result_value.to_string()
    }
}
