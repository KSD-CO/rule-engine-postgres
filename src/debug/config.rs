//! Debug configuration and settings
//!
//! Controls debug mode behavior (on/off, persistence, etc.)

use std::sync::atomic::{AtomicBool, Ordering};

/// Global debug mode flag
static DEBUG_ENABLED: AtomicBool = AtomicBool::new(true);

/// Global persistence flag (save to PostgreSQL)
static DEBUG_PERSISTENCE: AtomicBool = AtomicBool::new(false);

/// Check if debug mode is enabled
#[allow(dead_code)]
pub fn is_debug_enabled() -> bool {
    DEBUG_ENABLED.load(Ordering::Relaxed)
}

/// Enable debug mode
#[allow(dead_code)]
pub fn enable_debug() {
    DEBUG_ENABLED.store(true, Ordering::Relaxed);
}

/// Disable debug mode
#[allow(dead_code)]
pub fn disable_debug() {
    DEBUG_ENABLED.store(false, Ordering::Relaxed);
}

/// Check if PostgreSQL persistence is enabled
#[allow(dead_code)]
pub fn is_persistence_enabled() -> bool {
    DEBUG_PERSISTENCE.load(Ordering::Relaxed)
}

/// Enable PostgreSQL persistence for debug events
#[allow(dead_code)]
pub fn enable_persistence() {
    DEBUG_PERSISTENCE.store(true, Ordering::Relaxed);
}

/// Disable PostgreSQL persistence (in-memory only)
#[allow(dead_code)]
pub fn disable_persistence() {
    DEBUG_PERSISTENCE.store(false, Ordering::Relaxed);
}

/// Get debug configuration status
#[allow(dead_code)]
pub fn get_debug_config() -> (bool, bool) {
    (is_debug_enabled(), is_persistence_enabled())
}
