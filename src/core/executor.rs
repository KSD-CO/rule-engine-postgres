use rust_rule_engine::{Facts, KnowledgeBase, RustRuleEngine};

/// Execute rules on facts using the rule engine
pub fn execute_rules(facts: &Facts, rules: Vec<rust_rule_engine::Rule>) -> Result<(), String> {
    let kb = KnowledgeBase::new("PostgresExtension");
    let mut engine = RustRuleEngine::new(kb);

    // Register all built-in functions (v1.7.0+)
    crate::functions::registration::register_all_functions(&mut engine);

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
            return Err(format!("Failed to add rule #{}: {}", idx + 1, e));
        }
    }

    // Execute engine
    engine
        .execute(facts)
        .map_err(|e| format!("Rule execution failed: {}", e))?;

    Ok(())
}
