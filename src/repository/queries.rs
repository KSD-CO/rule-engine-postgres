// Query functions for Rule Repository
// Implements the core CRUD operations for rules

use crate::error::RuleEngineError;
use crate::repository::validation::*;
use crate::repository::version::SemanticVersion;
use pgrx::prelude::*;
// use pgrx::spi::SpiClient; (not needed)
use std::fmt::Write;

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

    // Check if rule exists using EXISTS (parameterized)
    let rule_exists: bool = Spi::connect(|client| {
        client
            .select(
                "SELECT EXISTS(SELECT 1 FROM rule_definitions WHERE name = $1)",
                None,
                &[(&name).into()],
            )?
            .first()
            .get_one()
    })?
    .unwrap_or(false);

    let rule_id = if rule_exists {
        // Rule exists - get ID and update metadata
        let id_opt: Option<i32> = Spi::connect(|client| {
            client
                .select(
                    "SELECT id FROM rule_definitions WHERE name = $1",
                    None,
                    &[(&name).into()],
                )?
                .first()
                .get_one::<i32>()
        })?;

        let id: i32 = id_opt
            .ok_or_else(|| RuleEngineError::DatabaseError("Failed to get rule ID".to_string()))?;

        Spi::connect(|client| -> Result<Option<i64>, pgrx::spi::SpiError> {
            client
                .select(
                    "UPDATE rule_definitions SET updated_at = NOW(), updated_by = $1 WHERE id = $2 RETURNING 1",
                    None,
                    &[current_user.clone().into(), id.into()],
                )?
                .first()
                .get_one::<i64>()
        })?;
        id
    } else {
        // Create new rule
        let desc_sql = description
            .as_ref()
            .map(|d| dollar_quote(d))
            .unwrap_or_else(|| "NULL".to_string());

        let new_id: i32 = Spi::connect(|client| {
            // desc_sql is already either NULL or a dollar-quoted literal; build query string
            let q = format!(
                "INSERT INTO rule_definitions (name, description, created_by, updated_by, is_active) VALUES ($1, {} , $2, $3, true) RETURNING id",
                desc_sql
            );
            client
                .select(
                    &q,
                    None,
                    &[
                        name.clone().into(),
                        current_user.clone().into(),
                        current_user.clone().into(),
                    ],
                )?
                .first()
                .get_one::<i32>()
        })?
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
            let latest_version: Option<String> = Spi::connect(|client| {
                client
                    .select(
                "SELECT version FROM rule_versions WHERE rule_id = $1 ORDER BY created_at DESC LIMIT 1",
                    None,
                        &[rule_id.into()],
                    )?
                    .first()
                    .get_one::<String>()
            })?;

            match latest_version {
                Some(latest) => {
                    let sem_ver = SemanticVersion::parse(&latest)?;
                    sem_ver.increment_patch().to_string()
                }
                None => "1.0.0".to_string(), // First version
            }
        }
    };

    // Check if version already exists (parameterized)
    let version_exists: bool = Spi::connect(|client| {
        client
            .select(
                "SELECT EXISTS(SELECT 1 FROM rule_versions WHERE rule_id = $1 AND version = $2)",
                None,
                &[rule_id.into(), version_number.clone().into()],
            )?
            .first()
            .get_one::<bool>()
    })?
    .unwrap_or(false);

    if version_exists {
        return Err(RuleEngineError::InvalidInput(format!(
            "Version {} already exists for rule. Use a different version number.",
            version_number
        )));
    }

    // Check if this is the first version
    let is_first_version: Option<bool> = Spi::connect(|client| {
        client
            .select(
                "SELECT NOT EXISTS(SELECT 1 FROM rule_versions WHERE rule_id = $1)",
                None,
                &[rule_id.into()],
            )?
            .first()
            .get_one::<bool>()
    })?;

    // Insert new version (first version is automatically default)

    // Use parameterized insert: pass grl_content and change_notes as parameters
    Spi::connect(|client| -> Result<Option<i64>, pgrx::spi::SpiError> {
        client
                .select(
                    "INSERT INTO rule_versions (rule_id, version, grl_content, change_notes, created_by, is_default) VALUES ($1, $2, $3, $4, $5, $6) RETURNING 1",
                    None,
                    &[
                        rule_id.into(),
                        version_number.clone().into(),
                        grl_content.into(),
                        change_notes.into(),
                        current_user.clone().into(),
                        is_first_version.unwrap_or(false).into(),
                    ],
                )?
                .first()
                .get_one::<i64>()
    })?;

    Ok(rule_id)
}

// Helper: create a dollar-quoted SQL literal that won't collide with the
// contained text. It chooses a short tag (DQ, DQ1, DQ2, ...) not present in the
// input and returns a string like $DQ$...$DQ$ which is safe to interpolate.
fn dollar_quote(s: &str) -> String {
    let mut idx: usize = 0;
    loop {
        let tag = if idx == 0 {
            "DQ".to_string()
        } else {
            format!("DQ{}", idx)
        };
        let delim = format!("${}$", tag);
        if !s.contains(&delim) {
            let mut out = String::new();
            write!(&mut out, "${}$", tag).ok();
            out.push_str(s);
            write!(&mut out, "${}$", tag).ok();
            return out;
        }
        idx += 1;
    }
}

// (Unused helpers removed per user request)

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

    // Inputs are validated above (name format and optional version as semver)
    // so it's safe to interpolate them directly here without manual quote-escaping.
    let grl_content: Option<String> = match &version {
        Some(v) => {
            // Get specific version
            Spi::get_one(&format!(
                "SELECT rv.grl_content 
                 FROM rule_versions rv
                 JOIN rule_definitions rd ON rv.rule_id = rd.id
                 WHERE rd.name = '{}' AND rv.version = '{}' AND rd.is_active = true",
                name, v
            ))?
        }
        None => {
            // Get default version
            Spi::get_one(&format!(
                "SELECT rv.grl_content 
                 FROM rule_versions rv
                 JOIN rule_definitions rd ON rv.rule_id = rd.id
                 WHERE rd.name = '{}' AND rv.is_default = true AND rd.is_active = true",
                name
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
    let version_id: Option<i32> = Spi::connect(
        |client| -> Result<Option<i32>, pgrx::spi::SpiError> {
            client
                    .select(
                        "SELECT rv.id FROM rule_versions rv JOIN rule_definitions rd ON rv.rule_id = rd.id WHERE rd.name = $1 AND rv.version = $2",
                        None,
                        &[name.clone().into(), version.clone().into()],
                    )?
                    .first()
                    .get_one::<i32>()
        },
    )?;

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
        let is_default: bool = Spi::connect(|client| -> Result<Option<bool>, pgrx::spi::SpiError> {
                client
                    .select(
                        "SELECT rv.is_default FROM rule_versions rv JOIN rule_definitions rd ON rv.rule_id = rd.id WHERE rd.name = $1 AND rv.version = $2",
                        None,
                        &[name.clone().into(), v.into()],
                    )?
                    .first()
                    .get_one::<bool>()
            })?
        .unwrap_or(false);

        if is_default {
            return Err(RuleEngineError::InvalidInput(
                "Cannot delete default version. Activate another version first.".to_string(),
            ));
        }

        // Delete specific version
        let rows_deleted: Option<i64> = Spi::connect(
            |client| -> Result<Option<i64>, pgrx::spi::SpiError> {
                client
                .select(
                    "DELETE FROM rule_versions rv USING rule_definitions rd WHERE rv.rule_id = rd.id AND rd.name = $1 AND rv.version = $2 RETURNING 1",
                    None,
                    &[name.clone().into(), v.into()],
                )?
                .first()
                .get_one::<i64>()
            },
        )?;

        Ok(rows_deleted.is_some())
    } else {
        // Delete entire rule (cascade will delete versions)
        let rows_deleted: Option<i64> =
            Spi::connect(|client| -> Result<Option<i64>, pgrx::spi::SpiError> {
                client
                    .select(
                        "DELETE FROM rule_definitions WHERE name = $1 RETURNING 1",
                        None,
                        &[name.clone().into()],
                    )?
                    .first()
                    .get_one::<i64>()
            })?;

        Ok(rows_deleted.is_some())
    }
}

/// Add a tag to a rule
#[pg_extern]
pub fn rule_tag_add(name: String, tag: String) -> Result<bool, RuleEngineError> {
    validate_rule_name(&name)?;
    validate_tag(&tag)?;

    let rule_id: Option<i32> = Spi::connect(|client| {
        client
            .select(
                "SELECT id FROM rule_definitions WHERE name = $1",
                None,
                &[name.clone().into()],
            )?
            .first()
            .get_one::<i32>()
    })?;

    let rule_id = rule_id
        .ok_or_else(|| RuleEngineError::RuleNotFound(format!("Rule '{}' not found", name)))?;

    Spi::connect(|client| -> Result<Option<i64>, pgrx::spi::SpiError> {
        client
            .select(
                "INSERT INTO rule_tags (rule_id, tag) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING 1",
                None,
                &[rule_id.into(), tag.clone().into()],
            )?
            .first()
            .get_one::<i64>()
    })?;

    Ok(true)
}

/// Remove a tag from a rule
#[pg_extern]
pub fn rule_tag_remove(name: String, tag: String) -> Result<bool, RuleEngineError> {
    validate_rule_name(&name)?;

    let rows_deleted: Option<i64> = Spi::connect(|client| {
        client
                .select(
                    "DELETE FROM rule_tags rt USING rule_definitions rd WHERE rt.rule_id = rd.id AND rd.name = $1 AND rt.tag = $2 RETURNING 1",
                    None,
                    &[name.into(), tag.into()],
                )?
            .first()
            .get_one::<i64>()
    })?;

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
