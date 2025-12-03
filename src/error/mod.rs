pub mod codes;

use codes::ErrorCode;

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
