//! Event types for time-travel debugging
//!
//! This module defines all events that can occur during RETE engine execution.
//! Events are immutable and form a complete audit trail.

use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

/// Unique identifier for a fact in working memory
pub type FactHandle = u64;

/// Unique identifier for a rule activation
pub type ActivationId = u64;

/// All events that can occur during rule engine execution
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ReteEvent {
    // === Working Memory Events ===
    /// A new fact was inserted into working memory
    FactInserted {
        step: u64,
        timestamp: i64,
        handle: FactHandle,
        fact_type: String,
        data: serde_json::Value,
    },

    /// An existing fact was modified
    FactModified {
        step: u64,
        timestamp: i64,
        handle: FactHandle,
        old_data: serde_json::Value,
        new_data: serde_json::Value,
        changed_fields: Vec<String>,
    },

    /// A fact was retracted (removed) from working memory
    FactRetracted {
        step: u64,
        timestamp: i64,
        handle: FactHandle,
        fact_type: String,
        data: serde_json::Value, // Store for reconstruction
    },

    // === Rule Evaluation Events ===
    /// A rule was evaluated against current facts
    RuleEvaluated {
        step: u64,
        timestamp: i64,
        rule_name: String,
        rule_index: usize,
        matched: bool,
        reason: String, // "All conditions matched" or detailed failure reason
        matched_facts: Vec<FactHandle>,
        condition_results: Vec<ConditionResult>,
    },

    /// A rule was activated (added to agenda)
    RuleActivated {
        step: u64,
        timestamp: i64,
        rule_name: String,
        activation_id: ActivationId,
        salience: i32,
        matched_facts: Vec<FactHandle>,
    },

    /// A rule was fired (action executed)
    RuleFired {
        step: u64,
        timestamp: i64,
        rule_name: String,
        activation_id: ActivationId,
        matched_facts: Vec<FactHandle>,
        actions_executed: Vec<String>,
    },

    /// A rule activation was removed from agenda
    RuleDeactivated {
        step: u64,
        timestamp: i64,
        rule_name: String,
        activation_id: ActivationId,
        reason: String, // "no-loop", "retracted fact", "lock-on-active", etc
    },

    // === RETE Network Events (detailed) ===
    /// An alpha node (simple pattern) was evaluated
    AlphaNodeMatched {
        step: u64,
        timestamp: i64,
        node_id: String,
        pattern: String, // "Order.total > 1000"
        fact_handle: FactHandle,
        matched: bool,
        actual_value: Option<serde_json::Value>,
    },

    /// A beta node (join) was evaluated
    BetaNodeJoined {
        step: u64,
        timestamp: i64,
        node_id: String,
        left_facts: Vec<FactHandle>,
        right_fact: FactHandle,
        joined: bool,
        reason: String,
    },

    // === Agenda Events ===
    /// Snapshot of agenda state (pending activations)
    AgendaStateSnapshot {
        step: u64,
        timestamp: i64,
        pending_activations: Vec<ActivationSnapshot>,
    },

    // === Meta Events ===
    /// Execution session started
    ExecutionStarted {
        timestamp: i64,
        session_id: String,
        rules_count: usize,
        initial_facts_count: usize,
        rules_grl: String,
        initial_facts: serde_json::Value,
    },

    /// Execution session completed
    ExecutionCompleted {
        step: u64,
        timestamp: i64,
        total_rules_fired: usize,
        total_facts_modified: usize,
        duration_ms: i64,
        final_facts: serde_json::Value,
    },

    /// An error occurred during execution
    ExecutionError {
        step: u64,
        timestamp: i64,
        error_type: String,
        error_message: String,
        context: serde_json::Value,
    },
}

/// Result of evaluating a single condition in a rule
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConditionResult {
    pub index: usize,
    pub condition_text: String,
    pub matched: bool,
    pub reason: String, // "Order.total = 500 < 1000" or "matched"
    pub involved_facts: Vec<FactHandle>,
}

/// Snapshot of a rule activation in the agenda
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivationSnapshot {
    pub activation_id: ActivationId,
    pub rule_name: String,
    pub salience: i32,
    pub matched_facts: Vec<FactHandle>,
    pub agenda_group: String,
}

impl ReteEvent {
    /// Get the step number for this event
    pub fn step(&self) -> u64 {
        match self {
            ReteEvent::FactInserted { step, .. }
            | ReteEvent::FactModified { step, .. }
            | ReteEvent::FactRetracted { step, .. }
            | ReteEvent::RuleEvaluated { step, .. }
            | ReteEvent::RuleActivated { step, .. }
            | ReteEvent::RuleFired { step, .. }
            | ReteEvent::RuleDeactivated { step, .. }
            | ReteEvent::AlphaNodeMatched { step, .. }
            | ReteEvent::BetaNodeJoined { step, .. }
            | ReteEvent::AgendaStateSnapshot { step, .. }
            | ReteEvent::ExecutionCompleted { step, .. }
            | ReteEvent::ExecutionError { step, .. } => *step,
            ReteEvent::ExecutionStarted { .. } => 0,
        }
    }

    /// Get the timestamp for this event
    #[allow(dead_code)]
    pub fn timestamp(&self) -> i64 {
        match self {
            ReteEvent::FactInserted { timestamp, .. }
            | ReteEvent::FactModified { timestamp, .. }
            | ReteEvent::FactRetracted { timestamp, .. }
            | ReteEvent::RuleEvaluated { timestamp, .. }
            | ReteEvent::RuleActivated { timestamp, .. }
            | ReteEvent::RuleFired { timestamp, .. }
            | ReteEvent::RuleDeactivated { timestamp, .. }
            | ReteEvent::AlphaNodeMatched { timestamp, .. }
            | ReteEvent::BetaNodeJoined { timestamp, .. }
            | ReteEvent::AgendaStateSnapshot { timestamp, .. }
            | ReteEvent::ExecutionStarted { timestamp, .. }
            | ReteEvent::ExecutionCompleted { timestamp, .. }
            | ReteEvent::ExecutionError { timestamp, .. } => *timestamp,
        }
    }

    /// Get the event type as a string
    pub fn event_type(&self) -> &'static str {
        match self {
            ReteEvent::FactInserted { .. } => "FactInserted",
            ReteEvent::FactModified { .. } => "FactModified",
            ReteEvent::FactRetracted { .. } => "FactRetracted",
            ReteEvent::RuleEvaluated { .. } => "RuleEvaluated",
            ReteEvent::RuleActivated { .. } => "RuleActivated",
            ReteEvent::RuleFired { .. } => "RuleFired",
            ReteEvent::RuleDeactivated { .. } => "RuleDeactivated",
            ReteEvent::AlphaNodeMatched { .. } => "AlphaNodeMatched",
            ReteEvent::BetaNodeJoined { .. } => "BetaNodeJoined",
            ReteEvent::AgendaStateSnapshot { .. } => "AgendaStateSnapshot",
            ReteEvent::ExecutionStarted { .. } => "ExecutionStarted",
            ReteEvent::ExecutionCompleted { .. } => "ExecutionCompleted",
            ReteEvent::ExecutionError { .. } => "ExecutionError",
        }
    }

    /// Create a human-readable description of this event
    pub fn description(&self) -> String {
        match self {
            ReteEvent::FactInserted { fact_type, .. } => {
                format!("Inserted {} fact", fact_type)
            }
            ReteEvent::FactModified { changed_fields, .. } => {
                format!("Modified fields: {}", changed_fields.join(", "))
            }
            ReteEvent::FactRetracted { fact_type, .. } => {
                format!("Retracted {} fact", fact_type)
            }
            ReteEvent::RuleEvaluated {
                rule_name, matched, ..
            } => {
                if *matched {
                    format!("Rule '{}': MATCHED", rule_name)
                } else {
                    format!("Rule '{}': NOT MATCHED", rule_name)
                }
            }
            ReteEvent::RuleActivated { rule_name, .. } => {
                format!("Rule '{}' activated", rule_name)
            }
            ReteEvent::RuleFired { rule_name, .. } => format!("Rule '{}' fired", rule_name),
            ReteEvent::RuleDeactivated {
                rule_name, reason, ..
            } => {
                format!("Rule '{}' deactivated: {}", rule_name, reason)
            }
            ReteEvent::AlphaNodeMatched {
                pattern, matched, ..
            } => {
                if *matched {
                    format!("Pattern '{}': MATCHED", pattern)
                } else {
                    format!("Pattern '{}': NOT MATCHED", pattern)
                }
            }
            ReteEvent::BetaNodeJoined { joined, .. } => {
                if *joined {
                    "Beta join: SUCCESS".to_string()
                } else {
                    "Beta join: FAILED".to_string()
                }
            }
            ReteEvent::AgendaStateSnapshot {
                pending_activations,
                ..
            } => {
                format!("Agenda: {} pending activations", pending_activations.len())
            }
            ReteEvent::ExecutionStarted {
                rules_count,
                initial_facts_count,
                ..
            } => {
                format!(
                    "Execution started: {} rules, {} facts",
                    rules_count, initial_facts_count
                )
            }
            ReteEvent::ExecutionCompleted {
                total_rules_fired,
                duration_ms,
                ..
            } => {
                format!(
                    "Execution completed: {} rules fired in {}ms",
                    total_rules_fired, duration_ms
                )
            }
            ReteEvent::ExecutionError { error_message, .. } => {
                format!("Error: {}", error_message)
            }
        }
    }
}

/// Helper to get current timestamp in milliseconds since epoch
pub fn current_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_event_serialization() {
        let event = ReteEvent::FactInserted {
            step: 1,
            timestamp: current_timestamp(),
            handle: 123,
            fact_type: "Order".to_string(),
            data: json!({"total": 500}),
        };

        let json = serde_json::to_string(&event).unwrap();
        let deserialized: ReteEvent = serde_json::from_str(&json).unwrap();

        assert_eq!(event.step(), deserialized.step());
        assert_eq!(event.event_type(), deserialized.event_type());
    }

    #[test]
    fn test_event_description() {
        let event = ReteEvent::RuleFired {
            step: 5,
            timestamp: current_timestamp(),
            rule_name: "HighValue".to_string(),
            activation_id: 1,
            matched_facts: vec![1, 2],
            actions_executed: vec!["Order.approved = true".to_string()],
        };

        assert_eq!(event.description(), "Rule 'HighValue' fired");
        assert_eq!(event.event_type(), "RuleFired");
        assert_eq!(event.step(), 5);
    }

    #[test]
    fn test_condition_result() {
        let result = ConditionResult {
            index: 0,
            condition_text: "Order.total > 1000".to_string(),
            matched: false,
            reason: "Order.total = 500 < 1000".to_string(),
            involved_facts: vec![1],
        };

        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("Order.total"));
    }
}
