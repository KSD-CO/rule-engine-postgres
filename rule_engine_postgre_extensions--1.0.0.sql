CREATE OR REPLACE FUNCTION run_rule_engine(facts_json TEXT, rules_grl TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'run_rule_engine_wrapper'
LANGUAGE C STRICT;

-- Backward chaining API
CREATE OR REPLACE FUNCTION query_backward_chaining(facts_json TEXT, rules_grl TEXT, goal TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'query_backward_chaining_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION query_backward_chaining_multi(facts_json TEXT, rules_grl TEXT, goals TEXT[])
RETURNS TEXT
AS 'MODULE_PATHNAME', 'query_backward_chaining_multi_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION can_prove_goal(facts_json TEXT, rules_grl TEXT, goal TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'can_prove_goal_wrapper'
LANGUAGE C STRICT;