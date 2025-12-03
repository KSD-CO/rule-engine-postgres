use rust_rule_engine::backward::{BackwardConfig, BackwardEngine, SearchStrategy};
use rust_rule_engine::{Facts, KnowledgeBase};

/// Execute backward chaining query on facts
/// Returns whether the goal can be proven
pub fn query_goal(
    facts: &Facts,
    rules: Vec<rust_rule_engine::Rule>,
    goal: &str,
) -> Result<QueryResult, String> {
    // Create knowledge base and add rules
    let kb = KnowledgeBase::new("BackwardChaining");
    for rule in rules {
        kb.add_rule(rule)
            .map_err(|e| format!("Failed to add rule: {}", e))?;
    }

    // Create backward engine with config
    let config = BackwardConfig {
        max_depth: 50,
        max_solutions: 10,
        enable_memoization: true,
        strategy: SearchStrategy::DepthFirst,
    };

    let mut engine = BackwardEngine::with_config(kb, config);

    // Clone facts for mutable query (BackwardEngine requires &mut Facts)
    let mut facts_mut = facts.clone();

    // Execute query
    let result = engine
        .query(goal, &mut facts_mut)
        .map_err(|e| format!("Query failed: {}", e))?;

    // Extract proof trace as string
    let proof_trace = if result.provable {
        Some(format!("{:?}", result.proof_trace))
    } else {
        None
    };

    Ok(QueryResult {
        is_provable: result.provable,
        proof_trace,
        goals_explored: result.stats.goals_explored,
        rules_evaluated: result.stats.rules_evaluated,
        query_time_ms: result.stats.duration_ms.map(|d| d as f64).unwrap_or(0.0),
    })
}

/// Result of backward chaining query
#[derive(Debug, Clone)]
pub struct QueryResult {
    pub is_provable: bool,
    pub proof_trace: Option<String>,
    pub goals_explored: usize,
    pub rules_evaluated: usize,
    pub query_time_ms: f64,
}

impl QueryResult {
    /// Convert to JSON string
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string(&serde_json::json!({
            "provable": self.is_provable,
            "proof_trace": self.proof_trace,
            "goals_explored": self.goals_explored,
            "rules_evaluated": self.rules_evaluated,
            "query_time_ms": self.query_time_ms
        }))
        .map_err(|e| format!("Failed to serialize result: {}", e))
    }
}

/// Execute backward chaining with multiple goals
pub fn query_multiple_goals(
    facts: &Facts,
    rules: Vec<rust_rule_engine::Rule>,
    goals: Vec<&str>,
) -> Result<Vec<QueryResult>, String> {
    let kb = KnowledgeBase::new("BackwardChaining");
    for rule in rules {
        kb.add_rule(rule)
            .map_err(|e| format!("Failed to add rule: {}", e))?;
    }

    let config = BackwardConfig {
        max_depth: 50,
        max_solutions: 10,
        enable_memoization: true,
        strategy: SearchStrategy::DepthFirst,
    };

    let mut engine = BackwardEngine::with_config(kb, config);

    let mut results = Vec::new();
    for goal in goals {
        let mut facts_mut = facts.clone();

        let result = engine
            .query(goal, &mut facts_mut)
            .map_err(|e| format!("Query '{}' failed: {}", goal, e))?;

        let proof_trace = if result.provable {
            Some(format!("{:?}", result.proof_trace))
        } else {
            None
        };

        results.push(QueryResult {
            is_provable: result.provable,
            proof_trace,
            goals_explored: result.stats.goals_explored,
            rules_evaluated: result.stats.rules_evaluated,
            query_time_ms: result.stats.duration_ms.map(|d| d as f64).unwrap_or(0.0),
        });
    }

    Ok(results)
}

/// Execute backward chaining with production config (fast, boolean only)
pub fn query_goal_production(
    facts: &Facts,
    rules: Vec<rust_rule_engine::Rule>,
    goal: &str,
) -> Result<bool, String> {
    let kb = KnowledgeBase::new("BackwardChaining");
    for rule in rules {
        kb.add_rule(rule)
            .map_err(|e| format!("Failed to add rule: {}", e))?;
    }

    // Production config: minimal depth, single solution
    let config = BackwardConfig {
        max_depth: 20,
        max_solutions: 1,
        enable_memoization: true,
        strategy: SearchStrategy::DepthFirst,
    };

    let mut engine = BackwardEngine::with_config(kb, config);
    let mut facts_mut = facts.clone();

    let result = engine
        .query(goal, &mut facts_mut)
        .map_err(|e| format!("Query failed: {}", e))?;

    Ok(result.provable)
}
