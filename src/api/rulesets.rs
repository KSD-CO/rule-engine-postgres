use pgrx::prelude::*;

/// Create a new rule set
///
/// # Arguments
/// * `name` - Unique name for the rule set
/// * `description` - Optional description of the rule set
///
/// # Returns
/// The ID of the newly created rule set
///
/// # Example
/// ```sql
/// SELECT ruleset_create('loan_processing', 'Rules for loan application processing');
/// ```
#[pg_extern]
fn ruleset_create(
    name: &str,
    description: Option<&str>,
) -> Result<i32, Box<dyn std::error::Error>> {
    let result: Option<i32> = Spi::connect(|client| {
        client
            .select(
                "SELECT ruleset_create($1, $2)",
                None,
                &[
                    name.into(),
                    description
                        .map(|d| d.into())
                        .unwrap_or_else(|| Option::<String>::None.into()),
                ],
            )?
            .first()
            .get_one::<i32>()
    })?;
    result.ok_or_else(|| "Failed to create rule set".into())
}

/// Add a rule to a rule set with execution order
///
/// # Arguments
/// * `ruleset_id` - ID of the rule set
/// * `rule_name` - Name of the rule to add
/// * `rule_version` - Optional version of the rule (NULL for default version)
/// * `order` - Execution order (lower numbers execute first)
///
/// # Returns
/// `true` if the rule was added successfully
///
/// # Example
/// ```sql
/// SELECT ruleset_add_rule(1, 'credit_check', NULL, 0);
/// SELECT ruleset_add_rule(1, 'income_verification', '1.0.0', 1);
/// ```
#[pg_extern]
fn ruleset_add_rule(
    ruleset_id: i32,
    rule_name: &str,
    rule_version: Option<&str>,
    order: default!(i32, 0),
) -> Result<bool, Box<dyn std::error::Error>> {
    let result: Option<bool> = Spi::connect(|client| {
        client
            .select(
                "SELECT ruleset_add_rule($1, $2, $3, $4)",
                None,
                &[
                    ruleset_id.into(),
                    rule_name.into(),
                    rule_version
                        .map(|v| v.into())
                        .unwrap_or_else(|| Option::<String>::None.into()),
                    order.into(),
                ],
            )?
            .first()
            .get_one::<bool>()
    })?;
    result.ok_or_else(|| "Failed to add rule to rule set".into())
}

/// Remove a rule from a rule set
///
/// # Arguments
/// * `ruleset_id` - ID of the rule set
/// * `rule_name` - Name of the rule to remove
/// * `rule_version` - Optional version of the rule
///
/// # Returns
/// `true` if the rule was removed successfully
///
/// # Example
/// ```sql
/// SELECT ruleset_remove_rule(1, 'old_rule', NULL);
/// ```
#[pg_extern]
fn ruleset_remove_rule(
    ruleset_id: i32,
    rule_name: &str,
    rule_version: Option<&str>,
) -> Result<bool, Box<dyn std::error::Error>> {
    let result: Option<bool> = Spi::connect(|client| {
        client
            .select(
                "SELECT ruleset_remove_rule($1, $2, $3)",
                None,
                &[
                    ruleset_id.into(),
                    rule_name.into(),
                    rule_version
                        .map(|v| v.into())
                        .unwrap_or_else(|| Option::<String>::None.into()),
                ],
            )?
            .first()
            .get_one::<bool>()
    })?;
    Ok(result.unwrap_or(false))
}

/// Execute all rules in a rule set sequentially
///
/// # Arguments
/// * `ruleset_id` - ID of the rule set to execute
/// * `facts_json` - JSON string containing the initial facts
///
/// # Returns
/// JSON string with the final state after all rules have executed
///
/// # Example
/// ```sql
/// SELECT ruleset_execute(1, '{"age": 25, "income": 50000}');
/// ```
#[pg_extern]
fn ruleset_execute(
    ruleset_id: i32,
    facts_json: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let result: Option<String> = Spi::connect(|client| {
        client
            .select(
                "SELECT ruleset_execute($1, $2)",
                None,
                &[ruleset_id.into(), facts_json.into()],
            )?
            .first()
            .get_one::<String>()
    })?;
    result.ok_or_else(|| "Failed to execute rule set".into())
}

/// Delete a rule set and all its members
///
/// # Arguments
/// * `ruleset_id` - ID of the rule set to delete
///
/// # Returns
/// `true` if the rule set was deleted successfully
///
/// # Example
/// ```sql
/// SELECT ruleset_delete(1);
/// ```
#[pg_extern]
fn ruleset_delete(ruleset_id: i32) -> Result<bool, Box<dyn std::error::Error>> {
    let result: Option<bool> = Spi::connect(|client| {
        client
            .select("SELECT ruleset_delete($1)", None, &[ruleset_id.into()])?
            .first()
            .get_one::<bool>()
    })?;
    Ok(result.unwrap_or(false))
}
