pub mod codes;

use codes::ErrorCode;
use std::fmt;

/// Rule Engine Error Types
#[derive(Debug)]
pub enum RuleEngineError {
    /// Rule not found
    RuleNotFound(String),
    /// Invalid input
    InvalidInput(String),
    /// Database error
    DatabaseError(String),
    /// Execution error from rust-rule-engine
    ExecutionError(rust_rule_engine::RuleEngineError),
}

impl fmt::Display for RuleEngineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RuleEngineError::RuleNotFound(msg) => write!(f, "Rule not found: {}", msg),
            RuleEngineError::InvalidInput(msg) => write!(f, "Invalid input: {}", msg),
            RuleEngineError::DatabaseError(msg) => write!(f, "Database error: {}", msg),
            RuleEngineError::ExecutionError(e) => write!(f, "Execution error: {}", e),
        }
    }
}

impl std::error::Error for RuleEngineError {}

impl From<rust_rule_engine::RuleEngineError> for RuleEngineError {
    fn from(err: rust_rule_engine::RuleEngineError) -> Self {
        RuleEngineError::ExecutionError(err)
    }
}

impl From<serde_json::Error> for RuleEngineError {
    fn from(err: serde_json::Error) -> Self {
        RuleEngineError::InvalidInput(format!("JSON error: {}", err))
    }
}

impl From<pgrx::spi::SpiError> for RuleEngineError {
    fn from(err: pgrx::spi::SpiError) -> Self {
        RuleEngineError::DatabaseError(format!("Database error: {:?}", err))
    }
}

/// Create a JSON error response with code, message, and timestamp
#[allow(dead_code)]
pub fn create_error_response(error_code: &ErrorCode, message: &str) -> String {
    serde_json::json!({
        "error": message,
        "error_code": error_code.code,
        "timestamp": chrono::Utc::now().to_rfc3339()
    })
    .to_string()
}

/// Create a JSON error response with custom message (overrides default)
pub fn create_custom_error(error_code: &ErrorCode, custom_message: String) -> String {
    create_error_response(error_code, &custom_message)
}

/// Create a JSON error response with default message
#[allow(dead_code)]
pub fn create_default_error(error_code: &ErrorCode) -> String {
    create_error_response(error_code, error_code.default_message)
}
