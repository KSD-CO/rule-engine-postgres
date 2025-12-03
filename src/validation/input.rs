use super::limits::{check_not_empty, check_size_limit, MAX_INPUT_SIZE};

/// Validate facts JSON input
pub fn validate_facts_input(json: &str) -> Result<(), String> {
    check_not_empty(json, "Facts JSON")?;
    check_size_limit(json, MAX_INPUT_SIZE)?;
    Ok(())
}

/// Validate rules GRL input
pub fn validate_rules_input(grl: &str) -> Result<(), String> {
    check_not_empty(grl, "Rules GRL")?;
    check_size_limit(grl, MAX_INPUT_SIZE)?;
    Ok(())
}
