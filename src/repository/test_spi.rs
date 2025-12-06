use crate::repository::validation::*;
use pgrx::prelude::*;
use pgrx::spi::Spi;

#[pg_extern]
pub fn test_spi_simple() -> String {
    let name = "test_rule_3";
    let grl_content = "rule Test { }";

    // Step 1: Validations
    validate_rule_name(name).ok();
    validate_grl_content(grl_content).ok();

    // Step 2: Get user
    let _current_user: String = Spi::get_one("SELECT user")
        .ok()
        .flatten()
        .unwrap_or_else(|| "unknown".to_string());

    // Step 3: Check if rule exists
    let rule_id_opt: Result<Option<i32>, _> = Spi::get_one(&format!(
        "SELECT id FROM rule_definitions WHERE name = '{}'",
        name.replace("'", "''")
    ));

    format!("Step 3 result: {:?}", rule_id_opt)
}
