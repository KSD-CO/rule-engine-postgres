// Module declarations
mod api;
mod core;
mod datasources;
mod error;
mod functions;

#[allow(dead_code, unused_imports)]
pub mod nats;

mod repository;
mod validation;

// Re-export public API functions - Forward Chaining
pub use api::engine::run_rule_engine;
pub use api::health::{rule_engine_health_check, rule_engine_version};

// Re-export public API functions - Backward Chaining
pub use api::backward::{can_prove_goal, query_backward_chaining, query_backward_chaining_multi};

// Re-export public API functions - Rule Repository
pub use repository::queries::{
    rule_activate, rule_can_prove_by_name, rule_delete, rule_execute_by_name, rule_get,
    rule_query_by_name, rule_save, rule_tag_add, rule_tag_remove,
};
pub use repository::test_spi::test_spi_simple;

// PostgreSQL extension magic
pgrx::pg_module_magic!();
