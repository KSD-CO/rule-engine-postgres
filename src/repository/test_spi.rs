use crate::repository::validation::*;
use pgrx::prelude::*;
use pgrx::spi::Spi;

#[pg_extern]
pub fn test_spi_simple() -> Result<String, Box<dyn std::error::Error>> {
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

    // Step 3: Check if rule exists (parameterized)
    let rule_id_opt: Option<i32> = Spi::connect(|client| {
        client
            .select("SELECT id FROM rule_definitions WHERE name = $1", None, &[name.into()])?
            .first()
            .get_one::<i32>()
    })?;

    Ok(format!("Step 3 result: {:?}", rule_id_opt))
}
