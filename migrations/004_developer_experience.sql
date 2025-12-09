-- Migration 004: Developer Experience (Phase 2, v1.4.0)
-- Created: 2025-12-09
-- Description: Testing framework, validation, debugging, and templates

-- ============================================================================
-- 2.1 RULE TESTING FRAMEWORK
-- ============================================================================

-- Table: rule_test_cases
-- Stores test definitions for rules
CREATE TABLE IF NOT EXISTS rule_test_cases (
    test_id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL UNIQUE,
    rule_name TEXT NOT NULL,
    rule_version TEXT DEFAULT 'latest',
    description TEXT,
    input_facts JSONB NOT NULL,
    expected_output JSONB,
    expected_modifications JSONB,
    assertions JSONB, -- Array of assertions: [{type: 'equals', path: 'customer.tier', value: 'gold'}]
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}',
    enabled BOOLEAN DEFAULT true
);

-- Table: rule_test_results
-- Stores test execution results
CREATE TABLE IF NOT EXISTS rule_test_results (
    result_id SERIAL PRIMARY KEY,
    test_id INTEGER REFERENCES rule_test_cases(test_id) ON DELETE CASCADE,
    executed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    passed BOOLEAN NOT NULL,
    execution_time_ms NUMERIC,
    actual_output JSONB,
    actual_modifications JSONB,
    error_message TEXT,
    assertion_results JSONB -- Array of assertion results
);

-- Table: rule_test_coverage
-- Tracks which rules have tests
CREATE TABLE IF NOT EXISTS rule_test_coverage (
    rule_name TEXT PRIMARY KEY,
    total_tests INTEGER DEFAULT 0,
    passing_tests INTEGER DEFAULT 0,
    failing_tests INTEGER DEFAULT 0,
    last_test_run TIMESTAMPTZ,
    coverage_score NUMERIC DEFAULT 0, -- Calculated coverage percentage
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Index for test queries
CREATE INDEX IF NOT EXISTS idx_test_cases_rule ON rule_test_cases(rule_name, rule_version);
CREATE INDEX IF NOT EXISTS idx_test_results_test ON rule_test_results(test_id, executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_test_results_passed ON rule_test_results(passed);

-- ============================================================================
-- 2.1 API: RULE TESTING FUNCTIONS
-- ============================================================================

-- Function: rule_test_create
-- Creates a new test case for a rule
CREATE OR REPLACE FUNCTION rule_test_create(
    p_test_name TEXT,
    p_rule_name TEXT,
    p_input_facts JSONB,
    p_expected_output JSONB DEFAULT NULL,
    p_rule_version TEXT DEFAULT 'latest',
    p_description TEXT DEFAULT NULL,
    p_assertions JSONB DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_test_id INTEGER;
BEGIN
    INSERT INTO rule_test_cases (
        test_name, rule_name, rule_version, description,
        input_facts, expected_output, assertions
    ) VALUES (
        p_test_name, p_rule_name, p_rule_version, p_description,
        p_input_facts, p_expected_output, p_assertions
    ) RETURNING test_id INTO v_test_id;

    RETURN v_test_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_test_run
-- Runs a single test case
CREATE OR REPLACE FUNCTION rule_test_run(p_test_id INTEGER)
RETURNS JSON AS $$
DECLARE
    v_test rule_test_cases%ROWTYPE;
    v_actual_output TEXT;
    v_actual_json JSONB;
    v_passed BOOLEAN;
    v_error_message TEXT;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time_ms NUMERIC;
    v_assertion_results JSONB;
    v_result_id INTEGER;
BEGIN
    -- Get test case
    SELECT * INTO v_test FROM rule_test_cases WHERE test_id = p_test_id;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Test case not found'
        );
    END IF;

    IF NOT v_test.enabled THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Test case is disabled'
        );
    END IF;

    -- Record start time
    v_start_time := clock_timestamp();

    BEGIN
        -- Execute the rule
        SELECT rule_execute_by_name(
            v_test.rule_name,
            v_test.input_facts,
            v_test.rule_version
        ) INTO v_actual_output;

        -- Parse JSON output
        v_actual_json := v_actual_output::JSONB;

        -- Check assertions
        IF v_test.assertions IS NOT NULL THEN
            v_assertion_results := rule_test_check_assertions(v_actual_json, v_test.assertions);
            v_passed := (v_assertion_results->>'all_passed')::BOOLEAN;
            v_error_message := v_assertion_results->>'summary';
        ELSIF v_test.expected_output IS NOT NULL THEN
            -- Simple output comparison
            v_passed := (v_actual_json = v_test.expected_output);
            v_error_message := CASE
                WHEN NOT v_passed THEN
                    format('Expected: %s, Got: %s', v_test.expected_output, v_actual_json)
                ELSE NULL
            END;
        ELSE
            -- No assertions, just check if execution succeeded
            v_passed := true;
        END IF;

    EXCEPTION WHEN OTHERS THEN
        v_passed := false;
        v_error_message := SQLERRM;
        v_actual_json := NULL;
    END;

    -- Record end time
    v_end_time := clock_timestamp();
    v_execution_time_ms := EXTRACT(EPOCH FROM (v_end_time - v_start_time)) * 1000;

    -- Store result
    INSERT INTO rule_test_results (
        test_id, passed, execution_time_ms,
        actual_output, error_message, assertion_results
    ) VALUES (
        p_test_id, v_passed, v_execution_time_ms,
        v_actual_json, v_error_message, v_assertion_results
    ) RETURNING result_id INTO v_result_id;

    -- Update coverage
    PERFORM rule_test_update_coverage(v_test.rule_name);

    RETURN json_build_object(
        'test_id', p_test_id,
        'test_name', v_test.test_name,
        'passed', v_passed,
        'execution_time_ms', v_execution_time_ms,
        'actual_output', v_actual_json,
        'expected_output', v_test.expected_output,
        'error_message', v_error_message,
        'assertion_results', v_assertion_results,
        'result_id', v_result_id
    );
END;
$$ LANGUAGE plpgsql;

-- Function: rule_test_check_assertions
-- Internal function to check test assertions
CREATE OR REPLACE FUNCTION rule_test_check_assertions(
    p_actual JSONB,
    p_assertions JSONB
) RETURNS JSONB AS $$
DECLARE
    v_assertion JSONB;
    v_results JSONB := '[]'::JSONB;
    v_passed BOOLEAN;
    v_all_passed BOOLEAN := true;
    v_actual_value JSONB;
    v_expected_value JSONB;
    v_assertion_type TEXT;
    v_path TEXT;
BEGIN
    -- Iterate through assertions
    FOR v_assertion IN SELECT jsonb_array_elements(p_assertions)
    LOOP
        v_assertion_type := v_assertion->>'type';
        v_path := v_assertion->>'path';
        v_expected_value := v_assertion->'value';

        -- Extract actual value using JSON path
        BEGIN
            EXECUTE format('SELECT $1#>%L', string_to_array(v_path, '.'))
            INTO v_actual_value
            USING p_actual;
        EXCEPTION WHEN OTHERS THEN
            v_actual_value := NULL;
        END;

        -- Perform assertion check
        CASE v_assertion_type
            WHEN 'equals' THEN
                v_passed := (v_actual_value = v_expected_value);
            WHEN 'not_equals' THEN
                v_passed := (v_actual_value != v_expected_value);
            WHEN 'exists' THEN
                v_passed := (v_actual_value IS NOT NULL);
            WHEN 'not_exists' THEN
                v_passed := (v_actual_value IS NULL);
            WHEN 'contains' THEN
                v_passed := (v_actual_value ? (v_expected_value->>0));
            WHEN 'greater_than' THEN
                v_passed := ((v_actual_value->>0)::NUMERIC > (v_expected_value->>0)::NUMERIC);
            WHEN 'less_than' THEN
                v_passed := ((v_actual_value->>0)::NUMERIC < (v_expected_value->>0)::NUMERIC);
            ELSE
                v_passed := false;
        END CASE;

        v_all_passed := v_all_passed AND v_passed;

        v_results := v_results || jsonb_build_object(
            'type', v_assertion_type,
            'path', v_path,
            'expected', v_expected_value,
            'actual', v_actual_value,
            'passed', v_passed
        );
    END LOOP;

    RETURN jsonb_build_object(
        'all_passed', v_all_passed,
        'results', v_results,
        'summary', CASE
            WHEN v_all_passed THEN 'All assertions passed'
            ELSE format('%s of %s assertions failed',
                jsonb_array_length(v_results) - (
                    SELECT COUNT(*) FROM jsonb_array_elements(v_results)
                    WHERE value->>'passed' = 'true'
                ),
                jsonb_array_length(v_results)
            )
        END
    );
END;
$$ LANGUAGE plpgsql;

-- Function: rule_test_run_all
-- Runs all tests for a specific rule
CREATE OR REPLACE FUNCTION rule_test_run_all(p_rule_name TEXT DEFAULT NULL)
RETURNS TABLE (
    test_id INTEGER,
    test_name TEXT,
    rule_name TEXT,
    passed BOOLEAN,
    execution_time_ms NUMERIC,
    error_message TEXT
) AS $$
DECLARE
    v_test RECORD;
    v_result JSON;
BEGIN
    FOR v_test IN
        SELECT tc.test_id, tc.test_name, tc.rule_name
        FROM rule_test_cases tc
        WHERE (p_rule_name IS NULL OR tc.rule_name = p_rule_name)
          AND tc.enabled = true
        ORDER BY tc.test_name
    LOOP
        v_result := rule_test_run(v_test.test_id);

        RETURN QUERY SELECT
            (v_result->>'test_id')::INTEGER,
            v_result->>'test_name',
            v_test.rule_name,
            (v_result->>'passed')::BOOLEAN,
            (v_result->>'execution_time_ms')::NUMERIC,
            v_result->>'error_message';
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_test_coverage
-- Returns test coverage statistics for a rule
CREATE OR REPLACE FUNCTION rule_test_coverage(p_rule_name TEXT)
RETURNS JSON AS $$
DECLARE
    v_coverage rule_test_coverage%ROWTYPE;
BEGIN
    SELECT * INTO v_coverage FROM rule_test_coverage WHERE rule_name = p_rule_name;

    IF NOT FOUND THEN
        RETURN json_build_object(
            'rule_name', p_rule_name,
            'total_tests', 0,
            'passing_tests', 0,
            'failing_tests', 0,
            'coverage_score', 0
        );
    END IF;

    RETURN row_to_json(v_coverage);
END;
$$ LANGUAGE plpgsql;

-- Function: rule_test_update_coverage
-- Internal function to update coverage statistics
CREATE OR REPLACE FUNCTION rule_test_update_coverage(p_rule_name TEXT)
RETURNS VOID AS $$
DECLARE
    v_total INTEGER;
    v_passing INTEGER;
    v_failing INTEGER;
BEGIN
    -- Get latest test results
    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE passed = true),
        COUNT(*) FILTER (WHERE passed = false)
    INTO v_total, v_passing, v_failing
    FROM (
        SELECT DISTINCT ON (test_id) test_id, passed
        FROM rule_test_results rtr
        JOIN rule_test_cases rtc ON rtr.test_id = rtc.test_id
        WHERE rtc.rule_name = p_rule_name
        ORDER BY test_id, executed_at DESC
    ) latest_results;

    -- Upsert coverage
    INSERT INTO rule_test_coverage (
        rule_name, total_tests, passing_tests, failing_tests,
        last_test_run, coverage_score
    ) VALUES (
        p_rule_name, v_total, v_passing, v_failing,
        CURRENT_TIMESTAMP,
        CASE WHEN v_total > 0 THEN (v_passing::NUMERIC / v_total * 100) ELSE 0 END
    )
    ON CONFLICT (rule_name) DO UPDATE SET
        total_tests = EXCLUDED.total_tests,
        passing_tests = EXCLUDED.passing_tests,
        failing_tests = EXCLUDED.failing_tests,
        last_test_run = EXCLUDED.last_test_run,
        coverage_score = EXCLUDED.coverage_score,
        updated_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2.2 RULE VALIDATION & LINTING
-- ============================================================================

-- Function: rule_validate
-- Validates GRL syntax and structure
CREATE OR REPLACE FUNCTION rule_validate(p_grl TEXT)
RETURNS JSON AS $$
DECLARE
    v_errors TEXT[] := '{}';
    v_warnings TEXT[] := '{}';
    v_test_result TEXT;
BEGIN
    -- Try to compile the rule
    BEGIN
        SELECT run_rule_engine('{}'::JSONB, p_grl) INTO v_test_result;
    EXCEPTION WHEN OTHERS THEN
        v_errors := array_append(v_errors, 'Syntax error: ' || SQLERRM);
    END;

    -- Check for empty rule
    IF trim(p_grl) = '' THEN
        v_errors := array_append(v_errors, 'Rule cannot be empty');
    END IF;

    -- Check for basic GRL structure
    IF p_grl !~ 'rule\s+\w+' THEN
        v_errors := array_append(v_errors, 'Missing rule declaration');
    END IF;

    -- Warning: Check for complex conditions
    IF (length(p_grl) - length(replace(p_grl, '&&', ''))) / 2 > 5 THEN
        v_warnings := array_append(v_warnings, 'Complex condition: More than 5 AND operators may impact performance');
    END IF;

    -- Warning: Check for deep nesting
    IF (length(p_grl) - length(replace(p_grl, '{', ''))) > 10 THEN
        v_warnings := array_append(v_warnings, 'Deep nesting detected: Consider refactoring');
    END IF;

    RETURN json_build_object(
        'valid', array_length(v_errors, 1) IS NULL,
        'errors', v_errors,
        'warnings', v_warnings,
        'error_count', COALESCE(array_length(v_errors, 1), 0),
        'warning_count', COALESCE(array_length(v_warnings, 1), 0)
    );
END;
$$ LANGUAGE plpgsql;

-- Function: rule_lint
-- Performs detailed linting with best practices check
CREATE OR REPLACE FUNCTION rule_lint(
    p_grl TEXT,
    p_strict_mode BOOLEAN DEFAULT false
) RETURNS JSON AS $$
DECLARE
    v_validation JSON;
    v_issues JSONB := '[]'::JSONB;
    v_lines TEXT[];
    v_line TEXT;
    v_line_num INTEGER;
BEGIN
    -- First validate syntax
    v_validation := rule_validate(p_grl);

    -- Add validation errors as issues
    IF (v_validation->>'error_count')::INTEGER > 0 THEN
        v_issues := v_issues || jsonb_build_object(
            'type', 'error',
            'category', 'syntax',
            'message', 'Syntax validation failed',
            'details', v_validation->'errors'
        );
    END IF;

    -- Split into lines for line-by-line analysis
    v_lines := string_to_array(p_grl, E'\n');

    FOR v_line_num IN 1..array_length(v_lines, 1) LOOP
        v_line := v_lines[v_line_num];

        -- Check for unused variables (simple heuristic)
        IF v_line ~ '^\s*\w+\s*:=.*' AND NOT (p_grl ~ ('\y' || split_part(trim(v_line), ' ', 1) || '\y')) THEN
            v_issues := v_issues || jsonb_build_object(
                'type', 'warning',
                'category', 'unused_variable',
                'line', v_line_num,
                'message', format('Potentially unused variable at line %s', v_line_num)
            );
        END IF;

        -- Check for long lines
        IF p_strict_mode AND length(v_line) > 120 THEN
            v_issues := v_issues || jsonb_build_object(
                'type', 'style',
                'category', 'line_length',
                'line', v_line_num,
                'message', format('Line %s exceeds 120 characters', v_line_num)
            );
        END IF;

        -- Check for TODO comments
        IF v_line ~* 'TODO|FIXME' THEN
            v_issues := v_issues || jsonb_build_object(
                'type', 'info',
                'category', 'todo',
                'line', v_line_num,
                'message', format('TODO/FIXME found at line %s', v_line_num)
            );
        END IF;
    END LOOP;

    -- Best practices checks
    IF p_grl !~ 'salience' THEN
        v_issues := v_issues || jsonb_build_object(
            'type', 'info',
            'category', 'best_practice',
            'message', 'Consider adding salience for rule prioritization'
        );
    END IF;

    RETURN jsonb_build_object(
        'passed', jsonb_array_length(v_issues) = 0,
        'issue_count', jsonb_array_length(v_issues),
        'issues', v_issues,
        'validation', v_validation
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2.3 RULE DEBUGGING TOOLS
-- ============================================================================

-- Table: rule_debug_traces
-- Stores execution traces for debugging
CREATE TABLE IF NOT EXISTS rule_debug_traces (
    trace_id SERIAL PRIMARY KEY,
    session_id TEXT,
    rule_name TEXT,
    step_number INTEGER,
    step_type TEXT, -- 'condition', 'action', 'fact_change'
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    evaluated_condition TEXT,
    condition_result BOOLEAN,
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_debug_traces_session ON rule_debug_traces(session_id, step_number);

-- Function: rule_debug_execute
-- Executes rules with detailed step-by-step tracing
CREATE OR REPLACE FUNCTION rule_debug_execute(
    p_facts JSONB,
    p_rules TEXT,
    p_session_id TEXT DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
    v_session_id TEXT;
    v_result TEXT;
    v_trace_count INTEGER;
BEGIN
    v_session_id := COALESCE(p_session_id, 'debug_' || extract(epoch from now())::TEXT);

    -- Note: Full step-by-step tracing would require Rust implementation
    -- This is a simplified version that executes and stores results

    -- Execute the rule
    BEGIN
        SELECT run_rule_engine(p_facts, p_rules) INTO v_result;

        -- Store initial and final state as trace
        INSERT INTO rule_debug_traces (
            session_id, rule_name, step_number, step_type,
            description, before_facts, after_facts
        ) VALUES (
            v_session_id, 'debug_session', 1, 'execution',
            'Rule execution completed', p_facts, v_result::JSONB
        );

    EXCEPTION WHEN OTHERS THEN
        INSERT INTO rule_debug_traces (
            session_id, rule_name, step_number, step_type,
            description, before_facts
        ) VALUES (
            v_session_id, 'debug_session', 1, 'error',
            'Error: ' || SQLERRM, p_facts
        );
    END;

    SELECT COUNT(*) INTO v_trace_count FROM rule_debug_traces WHERE session_id = v_session_id;

    RETURN json_build_object(
        'session_id', v_session_id,
        'result', v_result,
        'trace_count', v_trace_count,
        'message', 'Debug session completed. Use rule_trace_get() to retrieve detailed trace.'
    );
END;
$$ LANGUAGE plpgsql;

-- Function: rule_trace_get
-- Retrieves execution trace for a debug session
CREATE OR REPLACE FUNCTION rule_trace_get(p_session_id TEXT)
RETURNS TABLE (
    step_number INTEGER,
    step_type TEXT,
    description TEXT,
    before_facts JSONB,
    after_facts JSONB,
    timestamp TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rdt.step_number,
        rdt.step_type,
        rdt.description,
        rdt.before_facts,
        rdt.after_facts,
        rdt.timestamp
    FROM rule_debug_traces rdt
    WHERE rdt.session_id = p_session_id
    ORDER BY rdt.step_number;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2.4 RULE TEMPLATES
-- ============================================================================

-- Table: rule_templates
-- Stores reusable rule templates with parameters
CREATE TABLE IF NOT EXISTS rule_templates (
    template_id SERIAL PRIMARY KEY,
    template_name TEXT NOT NULL UNIQUE,
    description TEXT,
    grl_template TEXT NOT NULL,
    parameters JSONB NOT NULL, -- [{name: 'threshold', type: 'number', default: 100}]
    category TEXT,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    tags TEXT[] DEFAULT '{}'
);

-- Table: rule_template_instances
-- Tracks instances created from templates
CREATE TABLE IF NOT EXISTS rule_template_instances (
    instance_id SERIAL PRIMARY KEY,
    template_id INTEGER REFERENCES rule_templates(template_id) ON DELETE CASCADE,
    rule_name TEXT NOT NULL,
    parameter_values JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT DEFAULT CURRENT_USER
);

CREATE INDEX IF NOT EXISTS idx_templates_category ON rule_templates(category);
CREATE INDEX IF NOT EXISTS idx_template_instances_template ON rule_template_instances(template_id);

-- Function: rule_template_create
-- Creates a new rule template
CREATE OR REPLACE FUNCTION rule_template_create(
    p_template_name TEXT,
    p_grl_template TEXT,
    p_parameters JSONB,
    p_description TEXT DEFAULT NULL,
    p_category TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_template_id INTEGER;
BEGIN
    INSERT INTO rule_templates (
        template_name, grl_template, parameters, description, category
    ) VALUES (
        p_template_name, p_grl_template, p_parameters, p_description, p_category
    ) RETURNING template_id INTO v_template_id;

    RETURN v_template_id;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_template_instantiate
-- Creates a rule instance from a template
CREATE OR REPLACE FUNCTION rule_template_instantiate(
    p_template_id INTEGER,
    p_parameter_values JSONB,
    p_rule_name TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
    v_template rule_templates%ROWTYPE;
    v_grl TEXT;
    v_param JSONB;
    v_param_name TEXT;
    v_param_value TEXT;
    v_rule_name TEXT;
BEGIN
    -- Get template
    SELECT * INTO v_template FROM rule_templates WHERE template_id = p_template_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Template not found: %', p_template_id;
    END IF;

    v_grl := v_template.grl_template;
    v_rule_name := COALESCE(p_rule_name, v_template.template_name || '_' || extract(epoch from now())::TEXT);

    -- Replace parameters in template
    FOR v_param IN SELECT jsonb_array_elements(v_template.parameters)
    LOOP
        v_param_name := v_param->>'name';
        v_param_value := p_parameter_values->>v_param_name;

        -- Use default if value not provided
        IF v_param_value IS NULL THEN
            v_param_value := v_param->>'default';
        END IF;

        IF v_param_value IS NULL THEN
            RAISE EXCEPTION 'Required parameter not provided: %', v_param_name;
        END IF;

        -- Replace {{param_name}} with value
        v_grl := replace(v_grl, '{{' || v_param_name || '}}', v_param_value);
    END LOOP;

    -- Track instance
    INSERT INTO rule_template_instances (
        template_id, rule_name, parameter_values
    ) VALUES (
        p_template_id, v_rule_name, p_parameter_values
    );

    -- Update usage count
    UPDATE rule_templates
    SET usage_count = usage_count + 1
    WHERE template_id = p_template_id;

    RETURN v_grl;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_template_list
-- Lists all available templates
CREATE OR REPLACE FUNCTION rule_template_list(p_category TEXT DEFAULT NULL)
RETURNS TABLE (
    template_id INTEGER,
    template_name TEXT,
    description TEXT,
    category TEXT,
    parameters JSONB,
    usage_count INTEGER,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rt.template_id,
        rt.template_name,
        rt.description,
        rt.category,
        rt.parameters,
        rt.usage_count,
        rt.created_at
    FROM rule_templates rt
    WHERE (p_category IS NULL OR rt.category = p_category)
    ORDER BY rt.usage_count DESC, rt.template_name;
END;
$$ LANGUAGE plpgsql;

-- Function: rule_template_get
-- Gets a specific template by ID or name
CREATE OR REPLACE FUNCTION rule_template_get(p_identifier TEXT)
RETURNS JSON AS $$
DECLARE
    v_template rule_templates%ROWTYPE;
BEGIN
    -- Try as integer ID first, then as name
    BEGIN
        SELECT * INTO v_template FROM rule_templates
        WHERE template_id = p_identifier::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        SELECT * INTO v_template FROM rule_templates
        WHERE template_name = p_identifier;
    END;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Template not found');
    END IF;

    RETURN row_to_json(v_template);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VIEWS FOR DEVELOPER EXPERIENCE
-- ============================================================================

-- View: test_suite_summary
-- Overview of all test suites
CREATE OR REPLACE VIEW test_suite_summary AS
SELECT
    rtc.rule_name,
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE enabled = true) as enabled_tests,
    COUNT(DISTINCT rtc.test_id) FILTER (
        WHERE EXISTS (
            SELECT 1 FROM rule_test_results rtr
            WHERE rtr.test_id = rtc.test_id
            AND rtr.passed = true
            ORDER BY rtr.executed_at DESC LIMIT 1
        )
    ) as passing_tests,
    MAX(rtr.executed_at) as last_run,
    ROUND(AVG(rtr.execution_time_ms)::NUMERIC, 2) as avg_execution_time_ms
FROM rule_test_cases rtc
LEFT JOIN rule_test_results rtr ON rtc.test_id = rtr.test_id
GROUP BY rtc.rule_name;

-- View: recent_test_failures
-- Shows recent test failures for debugging
CREATE OR REPLACE VIEW recent_test_failures AS
SELECT
    rtr.result_id,
    rtc.test_name,
    rtc.rule_name,
    rtr.executed_at,
    rtr.error_message,
    rtr.execution_time_ms
FROM rule_test_results rtr
JOIN rule_test_cases rtc ON rtr.test_id = rtc.test_id
WHERE rtr.passed = false
ORDER BY rtr.executed_at DESC
LIMIT 50;

-- View: template_usage_stats
-- Template popularity and usage statistics
CREATE OR REPLACE VIEW template_usage_stats AS
SELECT
    rt.template_name,
    rt.category,
    rt.usage_count,
    COUNT(rti.instance_id) as total_instances,
    MAX(rti.created_at) as last_used,
    rt.created_at
FROM rule_templates rt
LEFT JOIN rule_template_instances rti ON rt.template_id = rti.template_id
GROUP BY rt.template_id, rt.template_name, rt.category, rt.usage_count, rt.created_at
ORDER BY rt.usage_count DESC;

-- ============================================================================
-- SAMPLE TEMPLATES
-- ============================================================================

-- Insert common rule templates
INSERT INTO rule_templates (template_name, description, grl_template, parameters, category, tags) VALUES
(
    'threshold_check',
    'Checks if a numeric value exceeds a threshold',
    'rule ThresholdCheck "Check if {{field}} exceeds {{threshold}}" salience 10 {
    when
        {{field}} > {{threshold}}
    then
        Result.triggered = true;
        Result.message = "{{field}} exceeded threshold of {{threshold}}";
        Retract("ThresholdCheck");
    }',
    '[{"name": "field", "type": "string", "description": "Field path to check"},
      {"name": "threshold", "type": "number", "description": "Threshold value"}]'::JSONB,
    'validation',
    ARRAY['threshold', 'validation', 'numeric']
),
(
    'tier_assignment',
    'Assigns tier based on value ranges',
    'rule TierAssignment "Assign tier based on {{metric}}" salience 10 {
    when
        {{metric}} >= {{tier1_min}} && {{metric}} < {{tier2_min}}
    then
        Result.tier = "{{tier1_name}}";
        Retract("TierAssignment");
    }',
    '[{"name": "metric", "type": "string", "description": "Metric to evaluate"},
      {"name": "tier1_min", "type": "number", "description": "Tier 1 minimum value"},
      {"name": "tier2_min", "type": "number", "description": "Tier 2 minimum value"},
      {"name": "tier1_name", "type": "string", "description": "Tier 1 name", "default": "Bronze"}]'::JSONB,
    'classification',
    ARRAY['tier', 'classification', 'range']
),
(
    'discount_rule',
    'Applies discount based on conditions',
    'rule DiscountRule "Apply {{discount_pct}}% discount when {{condition}}" salience 10 {
    when
        {{condition}}
    then
        Result.discount = {{discount_pct}};
        Result.discount_applied = true;
        Retract("DiscountRule");
    }',
    '[{"name": "condition", "type": "string", "description": "Condition expression"},
      {"name": "discount_pct", "type": "number", "description": "Discount percentage"}]'::JSONB,
    'pricing',
    ARRAY['discount', 'pricing', 'promotion']
)
ON CONFLICT (template_name) DO NOTHING;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Add migration record
INSERT INTO schema_migrations (version, description, applied_at)
VALUES ('004', 'Developer Experience - Testing, Validation, Debugging, Templates', CURRENT_TIMESTAMP)
ON CONFLICT (version) DO NOTHING;

-- Output success message
DO $$
BEGIN
    RAISE NOTICE '✅ Migration 004 completed successfully!';
    RAISE NOTICE '📦 Added: Rule Testing Framework (2.1)';
    RAISE NOTICE '✓ Created tables: rule_test_cases, rule_test_results, rule_test_coverage';
    RAISE NOTICE '✓ Functions: rule_test_create, rule_test_run, rule_test_run_all, rule_test_coverage';
    RAISE NOTICE '';
    RAISE NOTICE '🔍 Added: Rule Validation & Linting (2.2)';
    RAISE NOTICE '✓ Functions: rule_validate, rule_lint';
    RAISE NOTICE '';
    RAISE NOTICE '🐛 Added: Rule Debugging Tools (2.3)';
    RAISE NOTICE '✓ Created table: rule_debug_traces';
    RAISE NOTICE '✓ Functions: rule_debug_execute, rule_trace_get';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Added: Rule Templates (2.4)';
    RAISE NOTICE '✓ Created tables: rule_templates, rule_template_instances';
    RAISE NOTICE '✓ Functions: rule_template_create, rule_template_instantiate, rule_template_list';
    RAISE NOTICE '✓ Added 3 sample templates';
    RAISE NOTICE '';
    RAISE NOTICE '📊 Added: Developer Experience Views';
    RAISE NOTICE '✓ Views: test_suite_summary, recent_test_failures, template_usage_stats';
END $$;
