/// Health check function to verify the extension is loaded and working
#[pgrx::pg_extern]
pub fn rule_engine_health_check() -> String {
    serde_json::json!({
        "status": "healthy",
        "extension": "rule_engine_postgre_extensions",
        "version": env!("CARGO_PKG_VERSION"),
        "timestamp": chrono::Utc::now().to_rfc3339()
    })
    .to_string()
}

/// Get extension version information
#[pgrx::pg_extern]
pub fn rule_engine_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}
