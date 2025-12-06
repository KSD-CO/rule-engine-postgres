// Validation functions for rule repository
use crate::error::RuleEngineError;
use regex::Regex;

/// Validate rule name format: alphanumeric + underscore/hyphen, must start with letter
pub fn validate_rule_name(name: &str) -> Result<(), RuleEngineError> {
    if name.is_empty() {
        return Err(RuleEngineError::InvalidInput(
            "Rule name cannot be empty".to_string(),
        ));
    }

    if name.len() > 255 {
        return Err(RuleEngineError::InvalidInput(
            "Rule name cannot exceed 255 characters".to_string(),
        ));
    }

    let re = Regex::new(r"^[a-zA-Z][a-zA-Z0-9_-]*$").unwrap();
    if !re.is_match(name) {
        return Err(RuleEngineError::InvalidInput(
            format!(
                "Invalid rule name '{}'. Must start with letter and contain only alphanumeric, underscore, or hyphen",
                name
            ),
        ));
    }

    Ok(())
}

/// Validate GRL content
pub fn validate_grl_content(grl: &str) -> Result<(), RuleEngineError> {
    if grl.is_empty() {
        return Err(RuleEngineError::InvalidInput(
            "GRL content cannot be empty".to_string(),
        ));
    }

    if grl.len() > 1_048_576 {
        // 1MB
        return Err(RuleEngineError::InvalidInput(
            "GRL content cannot exceed 1MB".to_string(),
        ));
    }

    // Basic GRL syntax check - should contain "rule"
    if !grl.contains("rule") {
        return Err(RuleEngineError::InvalidInput(
            "GRL content must contain at least one rule definition".to_string(),
        ));
    }

    Ok(())
}

/// Validate semantic version format
pub fn validate_version(version: &str) -> Result<(), RuleEngineError> {
    if version.is_empty() {
        return Err(RuleEngineError::InvalidInput(
            "Version cannot be empty".to_string(),
        ));
    }

    let re = Regex::new(r"^\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?$").unwrap();
    if !re.is_match(version) {
        return Err(RuleEngineError::InvalidInput(
            format!(
                "Invalid version '{}'. Must follow semantic versioning (e.g., 1.0.0, 2.1.0-beta)",
                version
            ),
        ));
    }

    Ok(())
}

/// Validate tag format
pub fn validate_tag(tag: &str) -> Result<(), RuleEngineError> {
    if tag.is_empty() {
        return Err(RuleEngineError::InvalidInput(
            "Tag cannot be empty".to_string(),
        ));
    }

    if tag.len() > 50 {
        return Err(RuleEngineError::InvalidInput(
            "Tag cannot exceed 50 characters".to_string(),
        ));
    }

    let re = Regex::new(r"^[a-z][a-z0-9_-]*$").unwrap();
    if !re.is_match(tag) {
        return Err(RuleEngineError::InvalidInput(
            format!(
                "Invalid tag '{}'. Must start with lowercase letter and contain only lowercase, numbers, underscore, or hyphen",
                tag
            ),
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_rule_name() {
        assert!(validate_rule_name("valid_rule").is_ok());
        assert!(validate_rule_name("Rule123").is_ok());
        assert!(validate_rule_name("my-rule-name").is_ok());
        
        assert!(validate_rule_name("").is_err());
        assert!(validate_rule_name("123invalid").is_err());
        assert!(validate_rule_name("invalid name").is_err());
        assert!(validate_rule_name("invalid@name").is_err());
    }

    #[test]
    fn test_validate_version() {
        assert!(validate_version("1.0.0").is_ok());
        assert!(validate_version("2.5.10").is_ok());
        assert!(validate_version("1.0.0-beta").is_ok());
        assert!(validate_version("1.0.0-alpha1").is_ok());
        
        assert!(validate_version("").is_err());
        assert!(validate_version("1.0").is_err());
        assert!(validate_version("v1.0.0").is_err());
        assert!(validate_version("1.0.0-beta.1").is_err());
    }

    #[test]
    fn test_validate_tag() {
        assert!(validate_tag("discount").is_ok());
        assert!(validate_tag("pricing-rule").is_ok());
        assert!(validate_tag("rule_123").is_ok());
        
        assert!(validate_tag("").is_err());
        assert!(validate_tag("Discount").is_err());
        assert!(validate_tag("123tag").is_err());
        assert!(validate_tag("tag with space").is_err());
    }
}
