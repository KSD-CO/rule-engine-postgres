// Module declarations
mod api;
mod core;
mod error;
mod validation;

// Re-export public API functions - Forward Chaining
pub use api::engine::run_rule_engine;
pub use api::health::{rule_engine_health_check, rule_engine_version};

// Re-export public API functions - Backward Chaining
pub use api::backward::{can_prove_goal, query_backward_chaining, query_backward_chaining_multi};

// PostgreSQL extension magic
pgrx::pg_module_magic!();
