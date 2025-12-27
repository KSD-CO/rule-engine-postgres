//! PostgreSQL-backed event store for persistent time-travel debugging
//!
//! This module provides persistent storage for execution events in PostgreSQL.
//! Events are stored in the rule_execution_events table for long-term analysis.

use super::event_store::{ExecutionSession, SessionStatus};
use super::events::ReteEvent;
use pgrx::prelude::*;

/// Save an event to PostgreSQL
pub fn save_event_to_db(session_id: &str, event: &ReteEvent) -> Result<(), String> {
    let event_json = serde_json::to_value(event)
        .map_err(|e| format!("Failed to serialize event: {}", e))?;

    Spi::run(&format!(
        "INSERT INTO rule_execution_events (session_id, step, event_timestamp, event_type, event_data)
         VALUES ($1, $2, $3, $4, $5)",
    ))
    .map_err(|e| format!("Failed to insert event: {:?}", e))?
    .args(&[
        session_id,
        &(event.step() as i64),
        &event.timestamp(),
        event.event_type(),
        &pgrx::JsonB(event_json),
    ])
    .execute()
    .map_err(|e| format!("Failed to execute insert: {:?}", e))?;

    Ok(())
}

/// Save session metadata to PostgreSQL
pub fn save_session_to_db(session: &ExecutionSession) -> Result<(), String> {
    let status_str = match session.status {
        SessionStatus::Running => "running",
        SessionStatus::Completed => "completed",
        SessionStatus::Error => "error",
    };

    Spi::run(&format!(
        "INSERT INTO rule_execution_sessions
         (session_id, started_at, completed_at, rules_grl, initial_facts, total_steps, total_events, status, duration_ms)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (session_id) DO UPDATE SET
            completed_at = EXCLUDED.completed_at,
            total_steps = EXCLUDED.total_steps,
            total_events = EXCLUDED.total_events,
            status = EXCLUDED.status,
            duration_ms = EXCLUDED.duration_ms",
    ))
    .map_err(|e| format!("Failed to prepare session insert: {:?}", e))?
    .args(&[
        &session.session_id,
        &session.started_at,
        &session.completed_at,
        &session.rules_grl,
        &pgrx::JsonB(session.initial_facts.clone()),
        &(session.current_step as i64),
        &(session.event_count() as i64),
        status_str,
        &session.duration_ms(),
    ])
    .execute()
    .map_err(|e| format!("Failed to execute session insert: {:?}", e))?;

    Ok(())
}

/// Load session from PostgreSQL
pub fn load_session_from_db(session_id: &str) -> Result<ExecutionSession, String> {
    let result = Spi::get_one::<pgrx::JsonB>(&format!(
        "SELECT row_to_json(s) FROM rule_execution_sessions s WHERE session_id = $1"
    ))
    .args(&[session_id])
    .map_err(|e| format!("Failed to load session: {:?}", e))?
    .ok_or_else(|| format!("Session not found: {}", session_id))?;

    let session_data = result.0;

    // Parse session data
    let session_id = session_data["session_id"]
        .as_str()
        .ok_or("Missing session_id")?
        .to_string();
    let started_at = session_data["started_at"]
        .as_i64()
        .ok_or("Missing started_at")?;
    let completed_at = session_data["completed_at"].as_i64();
    let rules_grl = session_data["rules_grl"]
        .as_str()
        .ok_or("Missing rules_grl")?
        .to_string();
    let initial_facts = session_data["initial_facts"].clone();
    let total_steps = session_data["total_steps"].as_i64().unwrap_or(0) as u64;
    let status_str = session_data["status"]
        .as_str()
        .ok_or("Missing status")?;

    let status = match status_str {
        "running" => SessionStatus::Running,
        "completed" => SessionStatus::Completed,
        "error" => SessionStatus::Error,
        _ => SessionStatus::Error,
    };

    // Load events for this session
    let events = load_events_from_db(&session_id)?;

    Ok(ExecutionSession {
        session_id,
        started_at,
        completed_at,
        rules_grl,
        initial_facts,
        events,
        current_step: total_steps,
        status,
    })
}

/// Load all events for a session from PostgreSQL
pub fn load_events_from_db(session_id: &str) -> Result<Vec<ReteEvent>, String> {
    let mut events = Vec::new();

    Spi::connect(|client| {
        let query = "SELECT event_data FROM rule_execution_events
                     WHERE session_id = $1
                     ORDER BY step ASC";

        let mut cursor = client
            .open_cursor(query, Some(1))
            .args(&[session_id]);

        while let Some(row) = cursor.next() {
            let event_json: pgrx::JsonB = row["event_data"]
                .value()
                .ok_or("Missing event_data")?
                .ok_or("Null event_data")?;

            let event: ReteEvent = serde_json::from_value(event_json.0)
                .map_err(|e| format!("Failed to deserialize event: {}", e))?;

            events.push(event);
        }

        Ok(events)
    })
}

/// List all sessions from PostgreSQL
pub fn list_sessions_from_db() -> Result<Vec<ExecutionSession>, String> {
    let mut sessions = Vec::new();

    Spi::connect(|client| {
        let query = "SELECT session_id FROM rule_execution_sessions ORDER BY started_at DESC LIMIT 100";

        let mut cursor = client.open_cursor(query, None);

        while let Some(row) = cursor.next() {
            let session_id: String = row["session_id"]
                .value()
                .ok_or("Missing session_id")?
                .ok_or("Null session_id")?;

            // Load full session (could be optimized to avoid loading all events)
            if let Ok(session) = load_session_from_db(&session_id) {
                sessions.push(session);
            }
        }

        Ok(sessions)
    })
}

/// Delete session and its events from PostgreSQL
pub fn delete_session_from_db(session_id: &str) -> Result<(), String> {
    // Events will be deleted via CASCADE
    Spi::run("DELETE FROM rule_execution_sessions WHERE session_id = $1")
        .map_err(|e| format!("Failed to delete session: {:?}", e))?
        .args(&[session_id])
        .execute()
        .map_err(|e| format!("Failed to execute delete: {:?}", e))?;

    Ok(())
}

/// Clear all debugging data from PostgreSQL
pub fn clear_all_sessions_from_db() -> Result<(), String> {
    Spi::run("TRUNCATE TABLE rule_execution_events, rule_execution_sessions CASCADE")
        .map_err(|e| format!("Failed to truncate tables: {:?}", e))?
        .execute()
        .map_err(|e| format!("Failed to execute truncate: {:?}", e))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    // Tests require PostgreSQL connection, will be integration tests
}
