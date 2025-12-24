#!/bin/bash
# =============================================================================
# Run All Tests for Rule Engine NATS Integration
# =============================================================================
#
# This script runs all test suites in the correct order:
# 1. Rust unit tests
# 2. SQL integration tests
# 3. SQL function tests
#
# Usage:
#   ./tests/run_all_tests.sh [database_name]
#
# Environment variables:
#   PGHOST     - PostgreSQL host (default: localhost)
#   PGPORT     - PostgreSQL port (default: 5432)
#   PGUSER     - PostgreSQL user (default: postgres)
#   PGPASSWORD - PostgreSQL password
#   PGDATABASE - PostgreSQL database (default: postgres)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PGHOST=${PGHOST:-localhost}
PGPORT=${PGPORT:-5432}
PGUSER=${PGUSER:-postgres}
PGDATABASE=${1:-${PGDATABASE:-postgres}}

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check for cargo
    if ! command -v cargo &> /dev/null; then
        print_error "cargo not found. Please install Rust."
        exit 1
    fi
    print_success "cargo found"

    # Check for psql
    if ! command -v psql &> /dev/null; then
        print_error "psql not found. Please install PostgreSQL client."
        exit 1
    fi
    print_success "psql found"

    # Check PostgreSQL connection
    if ! psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "SELECT 1" &> /dev/null; then
        print_error "Cannot connect to PostgreSQL at $PGHOST:$PGPORT"
        print_info "Connection details: host=$PGHOST port=$PGPORT user=$PGUSER database=$PGDATABASE"
        exit 1
    fi
    print_success "PostgreSQL connection OK"

    # Check if migration 007 is applied
    if ! psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -tc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='rule_nats_config')" | grep -q t; then
        print_warning "Migration 007 not applied. Some tests may fail."
        print_info "Run: psql -h $PGHOST -p $PGPORT -U $PGUSER -d $PGDATABASE -f migrations/007_nats_integration.sql"
    else
        print_success "Migration 007 is applied"
    fi
}

run_rust_tests() {
    print_header "Running Rust Unit Tests"

    print_info "Compiling and running Rust tests..."

    if cargo test --lib nats::tests 2>&1 | tee /tmp/rust_tests.log; then
        # Parse results
        local results=$(grep "test result:" /tmp/rust_tests.log | tail -1)
        if [[ $results =~ ([0-9]+)\ passed ]]; then
            local passed=${BASH_REMATCH[1]}
            PASSED_TESTS=$((PASSED_TESTS + passed))
            TOTAL_TESTS=$((TOTAL_TESTS + passed))
            print_success "Rust tests: $passed passed"
        fi

        if [[ $results =~ ([0-9]+)\ failed ]]; then
            local failed=${BASH_REMATCH[1]}
            if [ "$failed" != "0" ]; then
                FAILED_TESTS=$((FAILED_TESTS + failed))
                TOTAL_TESTS=$((TOTAL_TESTS + failed))
                print_error "Rust tests: $failed failed"
                return 1
            fi
        fi
    else
        print_error "Rust tests failed to run"
        return 1
    fi

    rm -f /tmp/rust_tests.log
    return 0
}

run_sql_integration_tests() {
    print_header "Running SQL Integration Tests"

    print_info "Running schema and integration tests..."

    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        -f tests/sql/test_nats_integration.sql 2>&1 | tee /tmp/sql_integration.log; then

        # Count PASS/FAIL from output
        local passed=$(grep -c "^PASS:" /tmp/sql_integration.log || true)
        local failed=$(grep -c "^FAIL:" /tmp/sql_integration.log || true)

        PASSED_TESTS=$((PASSED_TESTS + passed))
        FAILED_TESTS=$((FAILED_TESTS + failed))
        TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))

        print_success "SQL integration tests: $passed passed, $failed failed"

        if [ "$failed" != "0" ]; then
            print_error "Some SQL integration tests failed"
            grep "^FAIL:" /tmp/sql_integration.log
            return 1
        fi
    else
        print_error "SQL integration tests failed to run"
        return 1
    fi

    rm -f /tmp/sql_integration.log
    return 0
}

run_sql_function_tests() {
    print_header "Running SQL Function Tests"

    print_info "Running function and API tests..."

    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        -f tests/sql/test_nats_functions.sql 2>&1 | tee /tmp/sql_functions.log; then

        # Count PASS/FAIL/SKIP from output
        local passed=$(grep -c "^PASS " /tmp/sql_functions.log || true)
        local failed=$(grep -c "^FAIL " /tmp/sql_functions.log || true)
        local skipped=$(grep -c "^SKIP " /tmp/sql_functions.log || true)

        PASSED_TESTS=$((PASSED_TESTS + passed))
        FAILED_TESTS=$((FAILED_TESTS + failed))
        SKIPPED_TESTS=$((SKIPPED_TESTS + skipped))
        TOTAL_TESTS=$((TOTAL_TESTS + passed + failed))

        print_success "SQL function tests: $passed passed, $failed failed, $skipped skipped"

        if [ "$failed" != "0" ]; then
            print_error "Some SQL function tests failed"
            grep "^FAIL " /tmp/sql_functions.log
            return 1
        fi
    else
        print_error "SQL function tests failed to run"
        return 1
    fi

    rm -f /tmp/sql_functions.log
    return 0
}

print_summary() {
    print_header "Test Summary"

    echo ""
    echo "Total Tests:   $TOTAL_TESTS"
    echo -e "${GREEN}Passed:        $PASSED_TESTS${NC}"

    if [ "$FAILED_TESTS" != "0" ]; then
        echo -e "${RED}Failed:        $FAILED_TESTS${NC}"
    else
        echo -e "Failed:        $FAILED_TESTS"
    fi

    if [ "$SKIPPED_TESTS" != "0" ]; then
        echo -e "${YELLOW}Skipped:       $SKIPPED_TESTS${NC}"
    fi

    if [ "$TOTAL_TESTS" -gt "0" ]; then
        local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
        echo ""
        echo "Success Rate:  ${success_rate}%"
    fi

    echo ""

    if [ "$FAILED_TESTS" == "0" ]; then
        print_success "ALL TESTS PASSED! 🎉"
        return 0
    else
        print_error "SOME TESTS FAILED"
        return 1
    fi
}

# Main execution
main() {
    echo ""
    print_header "Rule Engine NATS Integration - Test Suite"

    print_info "Database: $PGDATABASE @ $PGHOST:$PGPORT"
    print_info "User: $PGUSER"
    echo ""

    check_prerequisites

    # Run all test suites
    local all_passed=0

    if run_rust_tests; then
        print_success "Rust tests completed"
    else
        print_error "Rust tests failed"
        all_passed=1
    fi

    if run_sql_integration_tests; then
        print_success "SQL integration tests completed"
    else
        print_error "SQL integration tests failed"
        all_passed=1
    fi

    if run_sql_function_tests; then
        print_success "SQL function tests completed"
    else
        print_error "SQL function tests failed"
        all_passed=1
    fi

    # Print final summary
    if print_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main
main "$@"
