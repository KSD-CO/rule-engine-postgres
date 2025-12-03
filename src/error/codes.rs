/// Error code structure with code and default message
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct ErrorCode {
    pub code: &'static str,
    pub default_message: &'static str,
}

/// Error codes for better error handling
pub const EMPTY_FACTS: ErrorCode = ErrorCode {
    code: "ERR001",
    default_message: "Facts JSON cannot be empty",
};

pub const EMPTY_RULES: ErrorCode = ErrorCode {
    code: "ERR002",
    default_message: "Rules GRL cannot be empty",
};

#[allow(dead_code)]
pub const FACTS_TOO_LARGE: ErrorCode = ErrorCode {
    code: "ERR003",
    default_message: "Facts JSON too large (max 1MB)",
};

#[allow(dead_code)]
pub const RULES_TOO_LARGE: ErrorCode = ErrorCode {
    code: "ERR004",
    default_message: "Rules GRL too large (max 1MB)",
};

pub const INVALID_JSON: ErrorCode = ErrorCode {
    code: "ERR005",
    default_message: "Invalid JSON syntax in facts",
};

#[allow(dead_code)]
pub const NON_OBJECT_JSON: ErrorCode = ErrorCode {
    code: "ERR006",
    default_message: "Facts must be a JSON object, not an array or primitive",
};

#[allow(dead_code)]
pub const FACT_ADD_FAILED: ErrorCode = ErrorCode {
    code: "ERR007",
    default_message: "Failed to add fact",
};

pub const INVALID_GRL: ErrorCode = ErrorCode {
    code: "ERR008",
    default_message: "Invalid GRL syntax",
};

pub const NO_RULES_FOUND: ErrorCode = ErrorCode {
    code: "ERR009",
    default_message: "No valid rules found in GRL",
};

#[allow(dead_code)]
pub const RULE_ADD_FAILED: ErrorCode = ErrorCode {
    code: "ERR010",
    default_message: "Failed to add rule",
};

pub const EXECUTION_FAILED: ErrorCode = ErrorCode {
    code: "ERR011",
    default_message: "Rule execution failed",
};

pub const SERIALIZATION_FAILED: ErrorCode = ErrorCode {
    code: "ERR012",
    default_message: "Failed to serialize result",
};
