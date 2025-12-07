use pgrx::prelude::*;

/// Create a rule trigger for automatic execution on table changes
///
/// # Arguments
/// * `name` - Unique name for the trigger
/// * `table_name` - Target table to monitor (must exist)
/// * `rule_name` - Rule to execute (must exist in rule_definitions)
/// * `event_type` - Event type: INSERT, UPDATE, or DELETE
///
/// # Returns
/// Trigger ID
///
/// # Errors
/// - ERR_RT001: Invalid event_type
/// - ERR_RT002: Rule not found
/// - ERR_RT003: Table not found
///
/// # Example
/// ```sql
/// SELECT rule_trigger_create(
///     'order_discount_trigger',
///     'orders',
///     'order_discount_rule',
///     'INSERT'
/// );
/// ```
#[pg_extern]
fn rule_trigger_create(
    name: &str,
    table_name: &str,
    rule_name: &str,
    event_type: &str,
) -> Result<i32, Box<dyn std::error::Error + Send + Sync + 'static>> {
    let result = Spi::get_one::<i32>(&format!(
        "SELECT rule_trigger_create('{}', '{}', '{}', '{}')",
        name.replace("'", "''"),
        table_name.replace("'", "''"),
        rule_name.replace("'", "''"),
        event_type.replace("'", "''")
    ))?;

    result.ok_or_else(|| "Failed to create trigger".into())
}

/// Enable or disable a rule trigger
///
/// # Arguments
/// * `trigger_id` - ID of the trigger to enable/disable
/// * `enabled` - TRUE to enable, FALSE to disable (default: TRUE)
///
/// # Returns
/// TRUE if successful
///
/// # Errors
/// - ERR_RT004: Trigger not found
///
/// # Example
/// ```sql
/// -- Disable trigger
/// SELECT rule_trigger_enable(1, FALSE);
///
/// -- Re-enable trigger
/// SELECT rule_trigger_enable(1, TRUE);
/// ```
#[pg_extern]
fn rule_trigger_enable(
    trigger_id: i32,
    enabled: default!(bool, true),
) -> Result<bool, Box<dyn std::error::Error + Send + Sync + 'static>> {
    let result = Spi::get_one::<bool>(&format!(
        "SELECT rule_trigger_enable({}, {})",
        trigger_id, enabled
    ))?;

    result.ok_or_else(|| "Failed to enable/disable trigger".into())
}

/// Get execution history for a rule trigger
///
/// # Arguments
/// * `trigger_id` - ID of the trigger
/// * `start_time` - Start of time range (default: 1 day ago)
/// * `end_time` - End of time range (default: now)
///
/// # Returns
/// JSON array of history records
///
/// # Example
/// ```sql
/// -- Get last 24 hours
/// SELECT rule_trigger_history(1);
///
/// -- Get last week  
/// SELECT rule_trigger_history(
///     1,
///     NOW() - INTERVAL '7 days',
///     NOW()
/// );
/// ```
#[pg_extern]
fn rule_trigger_history(
    trigger_id: i32,
    start_time: default!(Option<TimestampWithTimeZone>, "NULL"),
    end_time: default!(Option<TimestampWithTimeZone>, "NULL"),
) -> Result<String, Box<dyn std::error::Error + Send + Sync + 'static>> {
    let start_clause = match start_time {
        Some(ts) => format!("'{}'::timestamptz", ts),
        None => "NOW() - INTERVAL '1 day'".to_string(),
    };

    let end_clause = match end_time {
        Some(ts) => format!("'{}'::timestamptz", ts),
        None => "NOW()".to_string(),
    };

    let query = format!(
        "SELECT json_agg(row_to_json(t)) FROM rule_trigger_history({}, {}, {}) t",
        trigger_id, start_clause, end_clause
    );

    let result = Spi::get_one::<String>(&query)?;
    
    Ok(result.unwrap_or_else(|| "[]".to_string()))
}

/// Delete a rule trigger
///
/// # Arguments
/// * `trigger_id` - ID of the trigger to delete
///
/// # Returns
/// TRUE if successful
///
/// # Errors
/// - ERR_RT005: Trigger not found
///
/// # Example
/// ```sql
/// SELECT rule_trigger_delete(1);
/// ```
#[pg_extern]
fn rule_trigger_delete(
    trigger_id: i32,
) -> Result<bool, Box<dyn std::error::Error + Send + Sync + 'static>> {
    let result = Spi::get_one::<bool>(&format!(
        "SELECT rule_trigger_delete({})",
        trigger_id
    ))?;

    result.ok_or_else(|| "Failed to delete trigger".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[pg_test]
    fn test_trigger_lifecycle() {
        // Create test table
        Spi::run("CREATE TABLE test_orders (id SERIAL PRIMARY KEY, amount NUMERIC, discount NUMERIC)")
            .expect("Failed to create test table");

        // Create test rule
        Spi::run(
            "INSERT INTO rule_definitions (name, content_json, version) 
             VALUES ('test_rule', '{}'::JSONB, 1)",
        )
        .expect("Failed to create test rule");

        // Create trigger
        let trigger_id = rule_trigger_create(
            "test_trigger",
            "test_orders",
            "test_rule",
            "INSERT",
        )
        .expect("Failed to create trigger");

        assert!(trigger_id > 0, "Trigger ID should be positive");

        // Disable trigger
        let disabled = rule_trigger_enable(trigger_id, false)
            .expect("Failed to disable trigger");
        assert!(disabled, "Should return true when disabling");

        // Re-enable trigger
        let enabled = rule_trigger_enable(trigger_id, true)
            .expect("Failed to enable trigger");
        assert!(enabled, "Should return true when enabling");

        // Delete trigger
        let deleted = rule_trigger_delete(trigger_id)
            .expect("Failed to delete trigger");
        assert!(deleted, "Should return true when deleting");

        // Cleanup
        Spi::run("DROP TABLE test_orders CASCADE").ok();
        Spi::run("DELETE FROM rule_definitions WHERE name = 'test_rule'").ok();
    }
}
