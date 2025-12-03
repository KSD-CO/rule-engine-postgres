use crate::core::{json_to_facts, parse_and_validate_rules, query_goal, query_multiple_goals};
use crate::error::{codes, create_custom_error};
use crate::validation::{validate_facts_input, validate_rules_input};

/// Query a goal using backward chaining
/// Returns JSON with provability status, proof trace, and metrics
#[pgrx::pg_extern]
pub fn query_backward_chaining(facts_json: &str, rules_grl: &str, goal: &str) -> String {
    // Validate inputs
    if let Err(e) = validate_facts_input(facts_json) {
        return create_custom_error(&codes::EMPTY_FACTS, e);
    }
    if let Err(e) = validate_rules_input(rules_grl) {
        return create_custom_error(&codes::EMPTY_RULES, e);
    }
    if goal.is_empty() {
        return create_custom_error(
            &codes::INVALID_JSON,
            "Goal query cannot be empty".to_string(),
        );
    }

    // Parse facts
    let facts = match json_to_facts(facts_json) {
        Ok(f) => f,
        Err(e) => return create_custom_error(&codes::INVALID_JSON, e),
    };

    // Parse rules
    let rules = match parse_and_validate_rules(rules_grl) {
        Ok(r) => r,
        Err(e) => {
            if e.contains("No valid rules") {
                return create_custom_error(&codes::NO_RULES_FOUND, e);
            }
            return create_custom_error(&codes::INVALID_GRL, e);
        }
    };

    // Execute backward chaining query
    match query_goal(&facts, rules, goal) {
        Ok(result) => match result.to_json() {
            Ok(json) => json,
            Err(e) => create_custom_error(&codes::SERIALIZATION_FAILED, e),
        },
        Err(e) => create_custom_error(&codes::EXECUTION_FAILED, e),
    }
}

/// Query multiple goals using backward chaining
/// Returns array of results
#[pgrx::pg_extern]
pub fn query_backward_chaining_multi(
    facts_json: &str,
    rules_grl: &str,
    goals: Vec<String>,
) -> String {
    // Validate inputs
    if let Err(e) = validate_facts_input(facts_json) {
        return create_custom_error(&codes::EMPTY_FACTS, e);
    }
    if let Err(e) = validate_rules_input(rules_grl) {
        return create_custom_error(&codes::EMPTY_RULES, e);
    }
    if goals.is_empty() {
        return create_custom_error(
            &codes::INVALID_JSON,
            "Goals array cannot be empty".to_string(),
        );
    }

    // Parse facts
    let facts = match json_to_facts(facts_json) {
        Ok(f) => f,
        Err(e) => return create_custom_error(&codes::INVALID_JSON, e),
    };

    // Parse rules
    let rules = match parse_and_validate_rules(rules_grl) {
        Ok(r) => r,
        Err(e) => {
            if e.contains("No valid rules") {
                return create_custom_error(&codes::NO_RULES_FOUND, e);
            }
            return create_custom_error(&codes::INVALID_GRL, e);
        }
    };

    // Convert Vec<String> to Vec<&str>
    let goal_refs: Vec<&str> = goals.iter().map(|s| s.as_str()).collect();

    // Execute backward chaining queries
    match query_multiple_goals(&facts, rules, goal_refs) {
        Ok(results) => {
            let json_results: Vec<_> = results
                .iter()
                .map(|r| {
                    serde_json::json!({
                        "provable": r.is_provable,
                        "proof_trace": r.proof_trace,
                        "goals_explored": r.goals_explored,
                        "rules_evaluated": r.rules_evaluated,
                        "query_time_ms": r.query_time_ms
                    })
                })
                .collect();

            serde_json::to_string(&json_results).unwrap_or_else(|e| {
                create_custom_error(&codes::SERIALIZATION_FAILED, e.to_string())
            })
        }
        Err(e) => create_custom_error(&codes::EXECUTION_FAILED, e),
    }
}

/// Simple boolean query - just returns true/false (production mode)
#[pgrx::pg_extern]
pub fn can_prove_goal(facts_json: &str, rules_grl: &str, goal: &str) -> bool {
    // Parse inputs (skip validation for performance in production mode)
    let facts = match json_to_facts(facts_json) {
        Ok(f) => f,
        Err(_) => return false,
    };

    let rules = match parse_and_validate_rules(rules_grl) {
        Ok(r) => r,
        Err(_) => return false,
    };

    // Execute query with production config (no proof trace)
    crate::core::query_goal_production(&facts, rules, goal).unwrap_or_default()
}
