-- Health check and version functions
CREATE OR REPLACE FUNCTION rule_engine_health_check()
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_engine_health_check_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_engine_version()
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_engine_version_wrapper'
LANGUAGE C STRICT;

-- Forward chaining API
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

-- Rule Repository API (new in v1.1.0)
CREATE OR REPLACE FUNCTION rule_save(name TEXT, grl_content TEXT, version TEXT, description TEXT, change_notes TEXT)
RETURNS INT
AS 'MODULE_PATHNAME', 'rule_save_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_get(name TEXT, version TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_get_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_activate(name TEXT, version TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_activate_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_delete(name TEXT, version TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_delete_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_tag_add(name TEXT, tag TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_tag_add_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_tag_remove(name TEXT, tag TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_tag_remove_wrapper'
LANGUAGE C STRICT;

CREATE OR REPLACE FUNCTION rule_execute_by_name(name TEXT, facts_json TEXT, version TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_execute_by_name_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_query_by_name(name TEXT, facts_json TEXT, goal TEXT, version TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'rule_query_by_name_wrapper'
LANGUAGE C;

CREATE OR REPLACE FUNCTION rule_can_prove_by_name(name TEXT, facts_json TEXT, goal TEXT, version TEXT)
RETURNS BOOLEAN
AS 'MODULE_PATHNAME', 'rule_can_prove_by_name_wrapper'
LANGUAGE C;

-- Debug/Test function
CREATE OR REPLACE FUNCTION test_spi_simple()
RETURNS TEXT
AS 'MODULE_PATHNAME', 'test_spi_simple_wrapper'
LANGUAGE C STRICT;
