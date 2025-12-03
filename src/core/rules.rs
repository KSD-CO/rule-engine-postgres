use rust_rule_engine::GRLParser;

/// Parse and validate GRL rules
pub fn parse_and_validate_rules(rules_grl: &str) -> Result<Vec<rust_rule_engine::Rule>, String> {
    // Parse rules from GRL
    let rules =
        GRLParser::parse_rules(rules_grl).map_err(|e| format!("Invalid GRL syntax: {}", e))?;

    // Validate that at least one rule was found
    if rules.is_empty() {
        return Err("No valid rules found in GRL".to_string());
    }

    Ok(rules)
}
