// Query functions for Rule Repository
// Implements the core CRUD operations for rules

use crate::error::RuleEngineError;
use crate::repository::validation::*;
use crate::repository::version::SemanticVersion;
use pgrx::prelude::*;
use pgrx::spi::SpiTupleTable;

/// Save a rule to the repository with versioning
///
/// # Arguments
/// * `name` - Unique rule name (alphanumeric + underscore/hyphen)
/// * `grl_content` - GRL rule definition
/// * `version` - Optional semantic version (auto-incremented if None)
/// * `description` - Optional rule description
/// * `change_notes` - Optional notes about what changed in this version
///
/// # Returns
/// Rule ID on success
///
/// # Errors
/// * `RE-001` - Invalid rule name format
/// * `RE-002` - GRL content validation failed
/// * `RE-003` - Invalid semantic version format
///
/// # Example
/// ```sql
/// SELECT rule_save('discount_rule', 'rule "Discount" { ... }', '1.0.0', 'Discount calculator');
/// ```
#[pg_extern]
pub fn rule_save(
    name: String,
    grl_content: String,
    version: Option<String>,
    description: Option<String>,
    change_notes: Option<String>,
) -> Result<i32, RuleEngineError> {
    // Validate inputs
    validate_rule_name(&name)?;
    validate_grl_content(&grl_content)?;

    // Get current user
    let current_user: String = Spi::get_one("SELECT user")
        .ok()
        .flatten()
        .unwrap_or_else(|| "unknown".to_string());

    // Check if rule exists using EXISTS
    let rule_exists: bool = Spi::get_one(&format!(
        "SELECT EXISTS(SELECT 1 FROM rule_definitions WHERE name = '{}')",
        name.replace("'", "''")
    ))?
    .unwrap_or(false);

    let rule_id = if rule_exists {
        // Rule exists - get ID and update metadata
        let id: i32 = Spi::get_one(&format!(
            "SELECT id FROM rule_definitions WHERE name = '{}'",
            name.replace("'", "''")
        ))?
        .ok_or_else(|| RuleEngineError::DatabaseError("Failed to get rule ID".to_string()))?;

        Spi::run(&format!(
            "UPDATE rule_definitions SET updated_at = NOW(), updated_by = '{}' WHERE id = {}",
            current_user.replace("'", "''"),
            id
        ))?;
        id
    } else {
        // Create new rule
        let desc_sql = description
            .as_ref()
            .map(|d| format!("'{}'", d.replace("'", "''")))
            .unwrap_or_else(|| "NULL".to_string());

        let new_id: i32 = Spi::get_one(&format!(
            "INSERT INTO rule_definitions (name, description, created_by, updated_by, is_active) 
             VALUES ('{}', {}, '{}', '{}', true) 
             RETURNING id",
            name.replace("'", "''"),
            desc_sql,
            current_user.replace("'", "''"),
            current_user.replace("'", "''")
        ))?
        .ok_or_else(|| RuleEngineError::DatabaseError("Failed to insert rule".to_string()))?;
        new_id
    };

    // Determine version number
    let version_number = match version {
        Some(v) => {
            validate_version(&v)?;
            v
        }
        None => {
            // Auto-increment: get latest version and increment patch
            let latest_version: Option<String> = Spi::get_one(&format!(
                "SELECT version FROM rule_versions 
                 WHERE rule_id = {} 
                 ORDER BY created_at DESC 
                 LIMIT 1",
                rule_id
            ))?;

            match latest_version {
                Some(latest) => {
                    let sem_ver = SemanticVersion::parse(&latest)?;
                    sem_ver.increment_patch().to_string()
                }
                None => "1.0.0".to_string(), // First version
            }
        }
    };

    // Check if version already exists
    let version_exists: bool = Spi::get_one(&format!(
        "SELECT EXISTS(SELECT 1 FROM rule_versions WHERE rule_id = {} AND version = '{}')",
        rule_id,
        version_number.replace("'", "''")
    ))?
    .unwrap_or(false);

    if version_exists {
        return Err(RuleEngineError::InvalidInput(format!(
            "Version {} already exists for rule. Use a different version number.",
            version_number
        )));
    }

    // Check if this is the first version
    let is_first_version: Option<bool> = Spi::get_one(&format!(
        "SELECT NOT EXISTS(SELECT 1 FROM rule_versions WHERE rule_id = {})",
        rule_id
    ))?;

    // Insert new version (first version is automatically default)
    let change_notes_sql = change_notes
        .as_ref()
        .map(|c| format!("'{}'", c.replace("'", "''")))
        .unwrap_or_else(|| "NULL".to_string());

    Spi::run(&format!(
        "INSERT INTO rule_versions (rule_id, version, grl_content, change_notes, created_by, is_default)
         VALUES ({}, '{}', '{}', {}, '{}', {})",
        rule_id,
        version_number.replace("'", "''"),
        grl_content.replace("'", "''"),
        change_notes_sql,
        current_user.replace("'", "''"),
        is_first_version.unwrap_or(false)
    ))?;

    Ok(rule_id)
}

/// Get GRL content for a rule
///
/// # Arguments
/// * `name` - Rule name
/// * `version` - Optional specific version (uses default if None)
///
/// # Returns
/// GRL content (TEXT)
///
/// # Example
/// ```sql
/// SELECT rule_get('discount_rule');
/// SELECT rule_get('discount_rule', '1.0.0');
/// ```
#[pg_extern]
pub fn rule_get(name: String, version: Option<String>) -> Result<String, RuleEngineError> {
    validate_rule_name(&name)?;

    if let Some(ref v) = version {
        validate_version(v)?;
    }

    let grl_content: Option<String> = match &version {
        Some(v) => {
            // Get specific version
            Spi::get_one(&format!(
                "SELECT rv.grl_content 
                 FROM rule_versions rv
                 JOIN rule_definitions rd ON rv.rule_id = rd.id
                 WHERE rd.name = '{}' AND rv.version = '{}' AND rd.is_active = true",
                name.replace("'", "''"),
                v.replace("'", "''")
            ))?
        }
        None => {
            // Get default version
            Spi::get_one(&format!(
                "SELECT rv.grl_content 
                 FROM rule_versions rv
                 JOIN rule_definitions rd ON rv.rule_id = rd.id
                 WHERE rd.name = '{}' AND rv.is_default = true AND rd.is_active = true",
                name.replace("'", "''")
            ))?
        }
    };

    grl_content.ok_or_else(|| {
        RuleEngineError::RuleNotFound(format!(
            "Rule '{}' {} not found",
            name,
            version
                .map(|v| format!("version '{}'", v))
                .unwrap_or_else(|| "(default)".to_string())
        ))
    })
}

/// Activate a specific version as the default
///
/// # Arguments
/// * `name` - Rule name
/// * `version` - Version to activate
///
/// # Example
/// ```sql
/// SELECT rule_activate('discount_rule', '1.0.0');
/// ```
#[pg_extern]
pub fn rule_activate(name: String, version: String) -> Result<bool, RuleEngineError> {
    validate_rule_name(&name)?;
    validate_version(&version)?;

    // Check if rule and version exist
    let version_id: Option<i32> = Spi::get_one(&format!(
        "SELECT rv.id 
         FROM rule_versions rv
         JOIN rule_definitions rd ON rv.rule_id = rd.id
         WHERE rd.name = '{}' AND rv.version = '{}'",
        name.replace("'", "''"),
        version.replace("'", "''")
    ))?;

    let version_id = version_id.ok_or_else(|| {
        RuleEngineError::RuleNotFound(format!("Rule '{}' version '{}' not found", name, version))
    })?;

    // Set as default (trigger will unset others)
    Spi::run(&format!(
        "UPDATE rule_versions SET is_default = true WHERE id = {}",
        version_id
    ))?;

    Ok(true)
}

/// Delete a rule or specific version
///
/// # Arguments
/// * `name` - Rule name
/// * `version` - Optional specific version (deletes all versions if None)
///
/// # Example
/// ```sql
/// SELECT rule_delete('discount_rule', '1.0.0');
/// SELECT rule_delete('discount_rule'); -- Delete entire rule
/// ```
#[pg_extern]
pub fn rule_delete(name: String, version: Option<String>) -> Result<bool, RuleEngineError> {
    validate_rule_name(&name)?;

    if let Some(ref v) = version {
        validate_version(v)?;

        // Check if it's the default version
        let is_default: bool = Spi::get_one(&format!(
            "SELECT rv.is_default 
             FROM rule_versions rv
             JOIN rule_definitions rd ON rv.rule_id = rd.id
             WHERE rd.name = '{}' AND rv.version = '{}'",
            name.replace("'", "''"),
            v.replace("'", "''")
        ))?
        .unwrap_or(false);

        if is_default {
            return Err(RuleEngineError::InvalidInput(
                "Cannot delete default version. Activate another version first.".to_string(),
            ));
        }

        // Delete specific version
        let rows_deleted = Spi::get_one::<i64>(&format!(
            "DELETE FROM rule_versions rv
             USING rule_definitions rd
             WHERE rv.rule_id = rd.id AND rd.name = '{}' AND rv.version = '{}'
             RETURNING 1",
            name.replace("'", "''"),
            v.replace("'", "''")
        ))?;

        Ok(rows_deleted.is_some())
    } else {
        // Delete entire rule (cascade will delete versions)
        let rows_deleted = Spi::get_one::<i64>(&format!(
            "DELETE FROM rule_definitions WHERE name = '{}' RETURNING 1",
            name.replace("'", "''")
        ))?;

        Ok(rows_deleted.is_some())
    }
}

/// Add a tag to a rule
#[pg_extern]
pub fn rule_tag_add(name: String, tag: String) -> Result<bool, RuleEngineError> {
    validate_rule_name(&name)?;
    validate_tag(&tag)?;

    let rule_id: Option<i32> = Spi::get_one(&format!(
        "SELECT id FROM rule_definitions WHERE name = '{}'",
        name.replace("'", "''")
    ))?;

    let rule_id = rule_id
        .ok_or_else(|| RuleEngineError::RuleNotFound(format!("Rule '{}' not found", name)))?;

    Spi::run(&format!(
        "INSERT INTO rule_tags (rule_id, tag) VALUES ({}, '{}') ON CONFLICT DO NOTHING",
        rule_id,
        tag.replace("'", "''")
    ))?;

    Ok(true)
}

/// Remove a tag from a rule
#[pg_extern]
pub fn rule_tag_remove(name: String, tag: String) -> Result<bool, RuleEngineError> {
    validate_rule_name(&name)?;

    let rows_deleted = Spi::get_one::<i64>(&format!(
        "DELETE FROM rule_tags rt
         USING rule_definitions rd
         WHERE rt.rule_id = rd.id AND rd.name = '{}' AND rt.tag = '{}'
         RETURNING 1",
        name.replace("'", "''"),
        tag.replace("'", "''")
    ))?;

    Ok(rows_deleted.is_some())
}

/// Execute a stored rule by name
///
/// # Arguments
/// * `name` - Rule name
/// * `facts_json` - Input facts as JSON string
/// * `version` - Optional specific version (uses default if None)
///
/// # Returns
/// Modified facts (JSON string)
///
/// # Example
/// ```sql
/// SELECT rule_execute_by_name('discount_rule', '{"Order": {"Amount": 150}}');
/// SELECT rule_execute_by_name('discount_rule', '{"Order": {"Amount": 150}}', '1.0.0');
/// ```
#[pg_extern]
pub fn rule_execute_by_name(
    name: String,
    facts_json: String,
    version: Option<String>,
) -> Result<String, RuleEngineError> {
    // Get the GRL content
    let grl_content = rule_get(name, version)?;

    // Execute using existing run_rule_engine
    let result = crate::api::engine::run_rule_engine(&facts_json, &grl_content);
    Ok(result)
}

/// Query backward chaining goal using stored rule by name
///
/// # Arguments
/// * `name` - Rule name
/// * `facts_json` - Input facts as JSON string
/// * `goal` - Goal query (e.g., "User.CanBuy == true")
/// * `version` - Optional specific version (uses default if None)
///
/// # Returns
/// JSON with provability result and proof trace
///
/// # Example
/// ```sql
/// SELECT rule_query_by_name('eligibility_rules', '{"User": {"Age": 25}}', 'User.CanVote == true');
/// SELECT rule_query_by_name('eligibility_rules', '{"User": {"Age": 25}}', 'User.CanVote == true', '1.0.0');
/// ```
#[pg_extern]
pub fn rule_query_by_name(
    name: String,
    facts_json: String,
    goal: String,
    version: Option<String>,
) -> Result<String, RuleEngineError> {
    // Get the GRL content
    let grl_content = rule_get(name, version)?;

    // Execute using backward chaining
    let result = crate::api::backward::query_backward_chaining(&facts_json, &grl_content, &goal);
    Ok(result)
}

/// Check if goal can be proven using stored rule by name (fast boolean check)
///
/// # Arguments
/// * `name` - Rule name
/// * `facts_json` - Input facts as JSON string
/// * `goal` - Goal query
/// * `version` - Optional specific version (uses default if None)
///
/// # Returns
/// Boolean - true if goal is provable
///
/// # Example
/// ```sql
/// SELECT rule_can_prove_by_name('eligibility_rules', '{"User": {"Age": 25}}', 'User.CanVote == true');
/// ```
#[pg_extern]
pub fn rule_can_prove_by_name(
    name: String,
    facts_json: String,
    goal: String,
    version: Option<String>,
) -> Result<bool, RuleEngineError> {
    // Get the GRL content
    let grl_content = rule_get(name, version)?;

    // Execute using fast boolean check
    let result = crate::api::backward::can_prove_goal(&facts_json, &grl_content, &goal);
    Ok(result)
}
