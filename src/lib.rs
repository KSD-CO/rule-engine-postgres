use rust_rule_engine::{Facts, RustRuleEngine, GRLParser, Value};

/// Error codes for better error handling
mod error_codes {
    pub const EMPTY_FACTS: &str = "ERR001";
    pub const EMPTY_RULES: &str = "ERR002";
    pub const FACTS_TOO_LARGE: &str = "ERR003";
    pub const RULES_TOO_LARGE: &str = "ERR004";
    pub const INVALID_JSON: &str = "ERR005";
    pub const NON_OBJECT_JSON: &str = "ERR006";
    pub const FACT_ADD_FAILED: &str = "ERR007";
    pub const INVALID_GRL: &str = "ERR008";
    pub const NO_RULES_FOUND: &str = "ERR009";
    pub const RULE_ADD_FAILED: &str = "ERR010";
    pub const EXECUTION_FAILED: &str = "ERR011";
    pub const SERIALIZATION_FAILED: &str = "ERR012";
}

fn create_error_response(code: &str, message: &str) -> String {
    serde_json::json!({
        "error": message,
        "error_code": code,
        "timestamp": chrono::Utc::now().to_rfc3339()
    }).to_string()
}

/// Health check function to verify the extension is loaded and working
#[pgrx::pg_extern]
pub fn rule_engine_health_check() -> String {
    serde_json::json!({
        "status": "healthy",
        "extension": "rule_engine_postgre_extensions",
        "version": env!("CARGO_PKG_VERSION"),
        "timestamp": chrono::Utc::now().to_rfc3339()
    }).to_string()
}

/// Get extension version information
#[pgrx::pg_extern]
pub fn rule_engine_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[pgrx::pg_extern]
pub fn run_rule_engine(facts_json: &str, rules_grl: &str) -> String {
    // Validate inputs
    if facts_json.is_empty() {
        return create_error_response(
            error_codes::EMPTY_FACTS,
            "Facts JSON cannot be empty"
        );
    }
    if rules_grl.is_empty() {
        return create_error_response(
            error_codes::EMPTY_RULES,
            "Rules GRL cannot be empty"
        );
    }
    if facts_json.len() > 1_000_000 {
        return create_error_response(
            error_codes::FACTS_TOO_LARGE,
            "Facts JSON too large (max 1MB)"
        );
    }
    if rules_grl.len() > 1_000_000 {
        return create_error_response(
            error_codes::RULES_TOO_LARGE,
            "Rules GRL too large (max 1MB)"
        );
    }

    // Parse facts from JSON
    let json_val = match serde_json::from_str::<serde_json::Value>(facts_json) {
        Ok(v) => v,
        Err(e) => return create_error_response(
            error_codes::INVALID_JSON,
            &format!("Invalid JSON syntax in facts: {}", e)
        ),
    };

    // Validate that facts is a JSON object
    if !json_val.is_object() {
        return create_error_response(
            error_codes::NON_OBJECT_JSON,
            "Facts must be a JSON object, not an array or primitive"
        );
    }

    // Create Facts and add each field
    let facts = Facts::new();
    if let serde_json::Value::Object(map) = json_val {
        for (key, value) in map {
            // Use built-in From<serde_json::Value> for Value conversion
            if let Err(e) = facts.add_value(&key, value.into()) {
                return create_error_response(
                    error_codes::FACT_ADD_FAILED,
                    &format!("Failed to add fact '{}': {}", key, e)
                );
            }
        }
    }

    // Parse rules from GRL
    let rules = match GRLParser::parse_rules(rules_grl) {
        Ok(r) => {
            if r.is_empty() {
                return create_error_response(
                    error_codes::NO_RULES_FOUND,
                    "No valid rules found in GRL"
                );
            }
            r
        },
        Err(e) => return create_error_response(
            error_codes::INVALID_GRL,
            &format!("Invalid GRL syntax: {}", e)
        ),
    };

    let kb = rust_rule_engine::KnowledgeBase::new("PostgresExtension");
    let mut engine = RustRuleEngine::new(kb);

    // Register action handler for 'print'
    engine.register_action_handler("print", |args, _context| {
        if let Some(val) = args.get("0") {
            pgrx::log!("RULE ENGINE PRINT: {:?}", val);
        } else {
            pgrx::log!("RULE ENGINE PRINT: <no value>");
        }
        Ok(())
    });

    // Add rules to engine
    for (idx, rule) in rules.into_iter().enumerate() {
        if let Err(e) = engine.knowledge_base_mut().add_rule(rule) {
            return create_error_response(
                error_codes::RULE_ADD_FAILED,
                &format!("Failed to add rule #{}: {}", idx + 1, e)
            );
        }
    }

    // Execute engine
    match engine.execute(&facts) {
        Ok(_result) => {
            // Convert modified facts back to JSON
            match facts_to_json(&facts) {
                Ok(json_str) => json_str,
                Err(e) => create_error_response(
                    error_codes::SERIALIZATION_FAILED,
                    &format!("Failed to serialize result: {}", e)
                ),
            }
        },
        Err(e) => create_error_response(
            error_codes::EXECUTION_FAILED,
            &format!("Rule execution failed: {}", e)
        ),
    }
}

fn engine_value_to_json(value: &Value) -> serde_json::Value {
    match value {
        Value::Null => serde_json::Value::Null,
        Value::Boolean(b) => serde_json::Value::Bool(*b),
        Value::Integer(i) => serde_json::Value::Number((*i).into()),
        Value::Number(n) => {
            serde_json::Number::from_f64(*n)
                .map(serde_json::Value::Number)
                .unwrap_or(serde_json::Value::Null)
        }
        Value::String(s) => serde_json::Value::String(s.clone()),
        Value::Object(map) => {
            let mut obj = serde_json::Map::new();
            for (key, val) in map {
                obj.insert(key.clone(), engine_value_to_json(val));
            }
            serde_json::Value::Object(obj)
        }
        Value::Array(arr) => {
            serde_json::Value::Array(arr.iter().map(engine_value_to_json).collect())
        }
        Value::Expression(s) => serde_json::Value::String(s.clone()),
    }
}

fn facts_to_json(facts: &Facts) -> Result<String, String> {
    let mut result = serde_json::Map::new();

    // Get all facts from Facts
    let all_facts = facts.get_all_facts();
    for (key, value) in all_facts {
        result.insert(key, engine_value_to_json(&value));
    }

    serde_json::to_string(&serde_json::Value::Object(result))
        .map_err(|e| format!("Serialization error: {}", e))
}

pgrx::pg_module_magic!();
