use crate::core::{execute_rules, facts_to_json, json_to_facts, parse_and_validate_rules};
use crate::error::{codes, create_custom_error};
use crate::validation::{validate_facts_input, validate_rules_input};

/// Main function to execute GRL rules on JSON facts
#[pgrx::pg_extern]
pub fn run_rule_engine(facts_json: &str, rules_grl: &str) -> String {
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
        Err(e) => return create_custom_error(&codes::INVALID_GRL, format!("Function preprocessing error: {}", e)),
    };

    // Convert enhanced facts to Facts object
    let facts = match json_to_facts(&serde_json::to_string(&facts_value).unwrap()) {
        Ok(f) => f,
        Err(e) => return create_custom_error(&codes::INVALID_JSON, e),
    };

    // Parse rules from transformed GRL
    let rules = match parse_and_validate_rules(&transformed_grl) {
        Ok(r) => r,
        Err(e) => {
            if e.contains("No valid rules") {
                return create_custom_error(&codes::NO_RULES_FOUND, e);
            }
            return create_custom_error(&codes::INVALID_GRL, e);
        }
    };

    // Execute rules
    if let Err(e) = execute_rules(&facts, rules) {
        return create_custom_error(&codes::EXECUTION_FAILED, e);
    }

    // Convert modified facts back to JSON
    match facts_to_json(&facts) {
        Ok(json_str) => json_str,
        Err(e) => create_custom_error(&codes::SERIALIZATION_FAILED, e),
    }
}
