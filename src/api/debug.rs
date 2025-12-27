//! Debug API - SQL functions for time-travel debugging

use crate::core::{execute_rules_debug, json_to_facts, parse_and_validate_rules};
use crate::debug::GLOBAL_EVENT_STORE;
use crate::error::{codes, create_custom_error};
use pgrx::prelude::*;
use uuid::Uuid;

// Simple error wrapper for pgrx
#[derive(Debug)]
struct DebugError(String);

impl std::fmt::Display for DebugError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for DebugError {}

/// Execute rules with debugging enabled
/// Returns session info and results as JSONB
#[allow(clippy::type_complexity)]
#[pg_extern]
fn run_rule_engine_debug(
    facts_json: &str,
    rules_grl: &str,
) -> Result<
    TableIterator<
        'static,
        (
            name!(session_id, String),
            name!(total_steps, i64),
            name!(total_events, i64),
            name!(result, pgrx::JsonB),
        ),
    >,
    Box<dyn std::error::Error + Send + Sync>,
> {
    // Generate unique session ID
    let session_id = format!("session_{}", Uuid::new_v4());

    // Parse facts from JSON
    #[allow(unused_assignments)]
    let mut facts = json_to_facts(facts_json)
        .map_err(|e| create_custom_error(&codes::INVALID_JSON, e.to_string()))?;

    // Parse and validate rules
    let rules = parse_and_validate_rules(rules_grl)
        .map_err(|e| create_custom_error(&codes::INVALID_GRL, e.to_string()))?;

    // Preprocess GRL with built-in functions (v1.7.0+)
    let mut facts_value: serde_json::Value = serde_json::from_str(facts_json)
        .map_err(|e| create_custom_error(&codes::INVALID_JSON, e.to_string()))?;

    let transformed_grl = match crate::functions::preprocessing::preprocess_grl_with_functions(
        rules_grl,
        &mut facts_value,
    ) {
        Ok(grl) => grl,
        Err(e) => {
            return Err(Box::new(DebugError(create_custom_error(
                &codes::INVALID_GRL,
                format!("Function preprocessing error: {}", e),
            ))) as Box<dyn std::error::Error + Send + Sync>)
        }
    };

    // Update facts with preprocessed values
    facts = json_to_facts(&facts_value.to_string())
        .map_err(|e| create_custom_error(&codes::INVALID_JSON, e.to_string()))?;

    // Execute with debugging
    let (final_facts, session_id) = execute_rules_debug(&facts, rules, session_id, transformed_grl)
        .map_err(|e| {
            Box::new(DebugError(create_custom_error(&codes::EXECUTION_FAILED, e)))
                as Box<dyn std::error::Error + Send + Sync>
        })?;

    // Get session info
    let session = GLOBAL_EVENT_STORE.get_session(&session_id).map_err(|e| {
        Box::new(DebugError(create_custom_error(&codes::EXECUTION_FAILED, e)))
            as Box<dyn std::error::Error + Send + Sync>
    })?;

    // Convert final facts to JSON
    let final_facts_json = crate::core::facts_to_json(&final_facts);

    // Build result
    let result = serde_json::json!({
        "session_id": session_id,
        "facts": final_facts_json,
        "duration_ms": session.duration_ms(),
        "status": format!("{:?}", session.status),
    });

    let total_steps = session.current_step as i64;
    let total_events = session.event_count() as i64;

    Ok(TableIterator::once((
        session_id,
        total_steps,
        total_events,
        pgrx::JsonB(result),
    )))
}

/// Get all events for a debug session
#[allow(clippy::type_complexity)]
#[pg_extern]
fn debug_get_events(
    session_id: &str,
) -> Result<
    TableIterator<
        'static,
        (
            name!(step, i64),
            name!(event_type, String),
            name!(description, String),
            name!(event_data, pgrx::JsonB),
        ),
    >,
    Box<dyn std::error::Error + Send + Sync>,
> {
    let session = GLOBAL_EVENT_STORE.get_session(session_id).map_err(|e| {
        Box::new(DebugError(create_custom_error(&codes::EXECUTION_FAILED, e)))
            as Box<dyn std::error::Error + Send + Sync>
    })?;

    let mut results = Vec::new();

    for event in &session.events {
        let event_json = serde_json::to_value(event).map_err(|e| {
            Box::new(DebugError(create_custom_error(
                &codes::SERIALIZATION_FAILED,
                e.to_string(),
            ))) as Box<dyn std::error::Error + Send + Sync>
        })?;

        results.push((
            event.step() as i64,
            event.event_type().to_string(),
            event.description(),
            pgrx::JsonB(event_json),
        ));
    }

    Ok(TableIterator::new(results))
}

/// Get session info
#[allow(clippy::type_complexity)]
#[pg_extern]
fn debug_get_session(
    session_id: &str,
) -> Result<
    TableIterator<
        'static,
        (
            name!(session_id, String),
            name!(started_at, i64),
            name!(completed_at, Option<i64>),
            name!(duration_ms, i64),
            name!(status, String),
            name!(total_steps, i64),
            name!(total_events, i64),
            name!(rules_grl, String),
        ),
    >,
    Box<dyn std::error::Error + Send + Sync>,
> {
    let session = GLOBAL_EVENT_STORE.get_session(session_id).map_err(|e| {
        Box::new(DebugError(create_custom_error(&codes::EXECUTION_FAILED, e)))
            as Box<dyn std::error::Error + Send + Sync>
    })?;

    Ok(TableIterator::once((
        session.session_id.clone(),
        session.started_at,
        session.completed_at,
        session.duration_ms(),
        format!("{:?}", session.status),
        session.current_step as i64,
        session.event_count() as i64,
        session.rules_grl.clone(),
    )))
}

/// List all debug sessions
#[pg_extern]
#[allow(clippy::type_complexity)]
fn debug_list_sessions() -> Result<
    TableIterator<
        'static,
        (
            name!(session_id, String),
            name!(started_at, i64),
            name!(duration_ms, i64),
            name!(status, String),
            name!(total_events, i64),
        ),
    >,
    Box<dyn std::error::Error + Send + Sync>,
> {
    let sessions = GLOBAL_EVENT_STORE.get_all_sessions();

    let mut results = Vec::new();
    for session in sessions {
        results.push((
            session.session_id.clone(),
            session.started_at,
            session.duration_ms(),
            format!("{:?}", session.status),
            session.event_count() as i64,
        ));
    }

    Ok(TableIterator::new(results))
}

/// Delete a debug session
#[pg_extern]
fn debug_delete_session(
    session_id: &str,
) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    GLOBAL_EVENT_STORE.delete_session(session_id).map_err(|e| {
        Box::new(DebugError(create_custom_error(&codes::EXECUTION_FAILED, e)))
            as Box<dyn std::error::Error + Send + Sync>
    })?;

    Ok(true)
}

/// Clear all debug sessions
#[pg_extern]
fn debug_clear_all_sessions() -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    GLOBAL_EVENT_STORE.clear_all();
    Ok(true)
}

#[cfg(test)]
mod tests {
    // Tests will be added in integration testing phase
}
