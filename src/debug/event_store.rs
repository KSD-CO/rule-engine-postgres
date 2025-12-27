//! In-memory event store for time-travel debugging
//!
//! This module provides an in-memory storage for RETE events.
//! In Phase 2, this will be extended to persist to PostgreSQL.

use super::events::{current_timestamp, ReteEvent};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, RwLock};

/// A complete execution session with all events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionSession {
    /// Unique session identifier
    pub session_id: String,

    /// When the session started (timestamp in ms)
    pub started_at: i64,

    /// When the session completed (None if still running)
    pub completed_at: Option<i64>,

    /// The GRL rules that were executed
    pub rules_grl: String,

    /// The initial facts (JSON)
    pub initial_facts: serde_json::Value,

    /// All events in chronological order
    pub events: Vec<ReteEvent>,

    /// Current step number
    pub current_step: u64,

    /// Session status
    pub status: SessionStatus,
}

/// Status of an execution session
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionStatus {
    Running,
    Completed,
    Error,
}

impl ExecutionSession {
    /// Create a new execution session
    pub fn new(session_id: String, rules_grl: String, initial_facts: serde_json::Value) -> Self {
        Self {
            session_id,
            started_at: current_timestamp(),
            completed_at: None,
            rules_grl,
            initial_facts,
            events: Vec::new(),
            current_step: 0,
            status: SessionStatus::Running,
        }
    }

    /// Add an event to this session
    pub fn add_event(&mut self, event: ReteEvent) {
        self.events.push(event);
    }

    /// Get the current step number and increment it
    pub fn next_step(&mut self) -> u64 {
        self.current_step += 1;
        self.current_step
    }

    /// Mark session as completed
    pub fn complete(&mut self) {
        self.completed_at = Some(current_timestamp());
        self.status = SessionStatus::Completed;
    }

    /// Mark session as error
    pub fn error(&mut self) {
        self.completed_at = Some(current_timestamp());
        self.status = SessionStatus::Error;
    }

    /// Get all events of a specific type
    #[allow(dead_code)]
    pub fn events_of_type(&self, event_type: &str) -> Vec<&ReteEvent> {
        self.events
            .iter()
            .filter(|e| e.event_type() == event_type)
            .collect()
    }

    /// Get events in a specific step range
    #[allow(dead_code)]
    pub fn events_in_range(&self, from_step: u64, to_step: u64) -> Vec<&ReteEvent> {
        self.events
            .iter()
            .filter(|e| {
                let step = e.step();
                step >= from_step && step <= to_step
            })
            .collect()
    }

    /// Get the total number of events
    pub fn event_count(&self) -> usize {
        self.events.len()
    }

    /// Get session duration in milliseconds
    pub fn duration_ms(&self) -> i64 {
        match self.completed_at {
            Some(completed) => completed - self.started_at,
            None => current_timestamp() - self.started_at,
        }
    }
}

/// In-memory event store
/// Thread-safe storage for multiple execution sessions
#[derive(Debug, Clone)]
pub struct EventStore {
    sessions: Arc<RwLock<Vec<ExecutionSession>>>,
}

impl EventStore {
    /// Create a new event store
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Create a new session and return its ID
    pub fn create_session(
        &self,
        session_id: String,
        rules_grl: String,
        initial_facts: serde_json::Value,
    ) -> String {
        let session = ExecutionSession::new(session_id.clone(), rules_grl, initial_facts);

        let mut sessions = self.sessions.write().unwrap();
        sessions.push(session);

        session_id
    }

    /// Add an event to a session
    pub fn add_event(&self, session_id: &str, event: ReteEvent) -> Result<(), String> {
        let mut sessions = self.sessions.write().unwrap();

        let session = sessions
            .iter_mut()
            .find(|s| s.session_id == session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        session.add_event(event);
        Ok(())
    }

    /// Get the next step number for a session
    pub fn next_step(&self, session_id: &str) -> Result<u64, String> {
        let mut sessions = self.sessions.write().unwrap();

        let session = sessions
            .iter_mut()
            .find(|s| s.session_id == session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        Ok(session.next_step())
    }

    /// Mark a session as completed
    pub fn complete_session(&self, session_id: &str) -> Result<(), String> {
        let mut sessions = self.sessions.write().unwrap();

        let session = sessions
            .iter_mut()
            .find(|s| s.session_id == session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        session.complete();
        Ok(())
    }

    /// Mark a session as error
    pub fn error_session(&self, session_id: &str) -> Result<(), String> {
        let mut sessions = self.sessions.write().unwrap();

        let session = sessions
            .iter_mut()
            .find(|s| s.session_id == session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        session.error();
        Ok(())
    }

    /// Get a session by ID
    pub fn get_session(&self, session_id: &str) -> Result<ExecutionSession, String> {
        let sessions = self.sessions.read().unwrap();

        sessions
            .iter()
            .find(|s| s.session_id == session_id)
            .cloned()
            .ok_or_else(|| format!("Session not found: {}", session_id))
    }

    /// Get all sessions
    pub fn get_all_sessions(&self) -> Vec<ExecutionSession> {
        let sessions = self.sessions.read().unwrap();
        sessions.clone()
    }

    /// Delete a session
    pub fn delete_session(&self, session_id: &str) -> Result<(), String> {
        let mut sessions = self.sessions.write().unwrap();

        let index = sessions
            .iter()
            .position(|s| s.session_id == session_id)
            .ok_or_else(|| format!("Session not found: {}", session_id))?;

        sessions.remove(index);
        Ok(())
    }

    /// Clear all sessions
    pub fn clear_all(&self) {
        let mut sessions = self.sessions.write().unwrap();
        sessions.clear();
    }

    /// Get the number of sessions
    #[allow(dead_code)]
    pub fn session_count(&self) -> usize {
        let sessions = self.sessions.read().unwrap();
        sessions.len()
    }
}

impl Default for EventStore {
    fn default() -> Self {
        Self::new()
    }
}

// Global event store instance
// This will be used by the rule engine to record events
lazy_static::lazy_static! {
    pub static ref GLOBAL_EVENT_STORE: EventStore = EventStore::new();
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_execution_session() {
        let mut session = ExecutionSession::new(
            "test_001".to_string(),
            "rule test {}".to_string(),
            json!({"foo": "bar"}),
        );

        assert_eq!(session.session_id, "test_001");
        assert_eq!(session.current_step, 0);
        assert_eq!(session.status, SessionStatus::Running);

        let step1 = session.next_step();
        assert_eq!(step1, 1);
        assert_eq!(session.current_step, 1);

        session.complete();
        assert_eq!(session.status, SessionStatus::Completed);
        assert!(session.completed_at.is_some());
    }

    #[test]
    fn test_event_store() {
        let store = EventStore::new();

        // Create session
        let session_id = store.create_session(
            "test_002".to_string(),
            "rule test {}".to_string(),
            json!({"x": 1}),
        );

        assert_eq!(session_id, "test_002");
        assert_eq!(store.session_count(), 1);

        // Add event
        let event = ReteEvent::ExecutionStarted {
            timestamp: current_timestamp(),
            session_id: session_id.clone(),
            rules_count: 1,
            initial_facts_count: 1,
            rules_grl: "rule test {}".to_string(),
            initial_facts: json!({"x": 1}),
        };

        store.add_event(&session_id, event).unwrap();

        // Get session
        let session = store.get_session(&session_id).unwrap();
        assert_eq!(session.event_count(), 1);

        // Complete session
        store.complete_session(&session_id).unwrap();
        let session = store.get_session(&session_id).unwrap();
        assert_eq!(session.status, SessionStatus::Completed);

        // Delete session
        store.delete_session(&session_id).unwrap();
        assert_eq!(store.session_count(), 0);
    }

    #[test]
    fn test_event_filtering() {
        let mut session = ExecutionSession::new(
            "test_003".to_string(),
            "rule test {}".to_string(),
            json!({}),
        );

        // Add different types of events
        session.add_event(ReteEvent::ExecutionStarted {
            timestamp: current_timestamp(),
            session_id: "test_003".to_string(),
            rules_count: 1,
            initial_facts_count: 0,
            rules_grl: "rule test {}".to_string(),
            initial_facts: json!({}),
        });

        session.add_event(ReteEvent::FactInserted {
            step: 1,
            timestamp: current_timestamp(),
            handle: 1,
            fact_type: "Order".to_string(),
            data: json!({"total": 100}),
        });

        session.add_event(ReteEvent::RuleFired {
            step: 2,
            timestamp: current_timestamp(),
            rule_name: "test".to_string(),
            activation_id: 1,
            matched_facts: vec![1],
            actions_executed: vec![],
        });

        // Filter by type
        let fact_events = session.events_of_type("FactInserted");
        assert_eq!(fact_events.len(), 1);

        let rule_events = session.events_of_type("RuleFired");
        assert_eq!(rule_events.len(), 1);

        // Filter by step range
        let events_in_range = session.events_in_range(1, 2);
        assert_eq!(events_in_range.len(), 2);
    }
}
