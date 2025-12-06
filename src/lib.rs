// Module declarations
mod api;
mod core;
mod error;
mod repository;
mod validation;

// Re-export public API functions - Forward Chaining
pub use api::engine::run_rule_engine;
pub use api::health::{rule_engine_health_check, rule_engine_version};

// Re-export public API functions - Backward Chaining
pub use api::backward::{can_prove_goal, query_backward_chaining, query_backward_chaining_multi};

// Re-export public API functions - Rule Repository
pub use repository::queries::{
    rule_save, rule_get, rule_activate, rule_delete, rule_tag_add, rule_tag_remove,
    rule_execute_by_name, rule_query_by_name, rule_can_prove_by_name,
};
pub use repository::test_spi::test_spi_simple;

// PostgreSQL extension magic
pgrx::pg_module_magic!();
