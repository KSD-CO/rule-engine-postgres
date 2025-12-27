//! Time-Travel Debugging Module (v2.0.0)
//!
//! This module provides event sourcing-based debugging for the RETE rule engine.
//! It captures all execution events and allows:
//! - Time-travel to any execution step
//! - Analysis of why rules fired or didn't fire
//! - Timeline branching for what-if scenarios
//! - Complete audit trail of all state changes

pub mod config;
pub mod event_store;
pub mod events;
pub mod pg_store_simple;

// Re-export commonly used types
pub use event_store::GLOBAL_EVENT_STORE;
pub use events::{current_timestamp, ReteEvent};

// Export config functions (used by pgrx externally)
#[allow(unused_imports)]
pub use config::{
    disable_debug, disable_persistence, enable_debug, enable_persistence, get_debug_config,
    is_debug_enabled, is_persistence_enabled,
};

// Export PostgreSQL store functions (used by pgrx externally)
#[allow(unused_imports)]
pub use pg_store_simple::{
    delete_session_from_db, load_session_from_db, save_event_to_db, save_session_to_db,
};
