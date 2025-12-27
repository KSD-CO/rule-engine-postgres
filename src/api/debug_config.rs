//! Debug configuration API - SQL functions for runtime debug control

use pgrx::prelude::*;

/// Enable debug mode globally
/// Returns true if successful
#[pg_extern]
fn debug_enable() -> bool {
    crate::debug::enable_debug();
    true
}

/// Disable debug mode globally
/// Returns true if successful
#[pg_extern]
fn debug_disable() -> bool {
    crate::debug::disable_debug();
    true
}

/// Enable PostgreSQL persistence for debug events
/// Returns true if successful
#[pg_extern]
fn debug_enable_persistence() -> bool {
    crate::debug::enable_persistence();
    true
}

/// Disable PostgreSQL persistence (in-memory only)
/// Returns true if successful
#[pg_extern]
fn debug_disable_persistence() -> bool {
    crate::debug::disable_persistence();
    true
}

/// Get current debug configuration status
/// Returns JSONB with debug_enabled and persistence_enabled flags
#[pg_extern]
fn debug_status() -> pgrx::JsonB {
    let (debug_enabled, persistence_enabled) = crate::debug::get_debug_config();

    let status = serde_json::json!({
        "debug_enabled": debug_enabled,
        "persistence_enabled": persistence_enabled
    });

    pgrx::JsonB(status)
}

#[cfg(test)]
mod tests {
    // Tests will be added in integration testing phase
}
