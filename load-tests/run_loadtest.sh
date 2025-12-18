#!/bin/bash

# PostgreSQL Rule Engine - Load Testing Script
# This script runs comprehensive load tests using pgbench

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-postgres}
DB_USER=${DB_USER:-$(whoami)}  # Auto-detect current user
DB_PASSWORD=${DB_PASSWORD:-postgres}

# pgbench parameters
CLIENTS=${CLIENTS:-10}        # Number of concurrent clients
THREADS=${THREADS:-4}         # Number of threads
DURATION=${DURATION:-60}      # Test duration in seconds
RATE=${RATE:-0}              # Rate limit (0 = unlimited)

# Output directory
OUTPUT_DIR="results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="${OUTPUT_DIR}/loadtest_${TIMESTAMP}.txt"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     PostgreSQL Rule Engine - Load Testing Suite         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Display configuration
echo -e "${YELLOW}Configuration:${NC}"
echo "  Database: $DB_HOST:$DB_PORT/$DB_NAME (user: $DB_USER)"
echo "  Clients: $CLIENTS"
echo "  Threads: $THREADS"
echo "  Duration: ${DURATION}s"
echo "  Rate limit: $([ $RATE -eq 0 ] && echo 'unlimited' || echo "${RATE} tps")"
echo "  Results: $RESULT_FILE"
echo ""

# Export password for non-interactive authentication
export PGPASSWORD=$DB_PASSWORD

# Connection string
CONN_STR="-h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"

# Function to run a test
run_test() {
    local test_name=$1
    local script_file=$2
    local description=$3

    echo -e "${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│ Test: ${test_name}${NC}"
    echo -e "${BLUE}│ ${description}${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}"

    echo "Running test: $test_name" >> "$RESULT_FILE"
    echo "Description: $description" >> "$RESULT_FILE"
    echo "Started: $(date)" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"

    # Run pgbench
    if pgbench $CONN_STR \
        -n \
        -c $CLIENTS \
        -j $THREADS \
        -T $DURATION \
        $([ $RATE -ne 0 ] && echo "-R $RATE") \
        -f "$script_file" \
        -P 10 \
        2>&1 | tee -a "$RESULT_FILE"; then

        echo -e "${GREEN}✓ Test completed successfully${NC}"
    else
        echo -e "${RED}✗ Test failed${NC}"
    fi

    echo "" >> "$RESULT_FILE"
    echo "Completed: $(date)" >> "$RESULT_FILE"
    echo "═══════════════════════════════════════════════════════════" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"
    echo ""
}

# Function to check if database is accessible
check_database() {
    echo -n "Checking database connection... "
    if psql $CONN_STR -c "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}Error: Cannot connect to database${NC}"
        echo "Please check your connection parameters:"
        echo "  DB_HOST=$DB_HOST"
        echo "  DB_PORT=$DB_PORT"
        echo "  DB_NAME=$DB_NAME"
        echo "  DB_USER=$DB_USER"
        exit 1
    fi
}

# Function to check if extension is installed
check_extension() {
    echo -n "Checking rule engine extension... "
    if psql $CONN_STR -c "SELECT rule_engine_version()" > /dev/null 2>&1; then
        VERSION=$(psql $CONN_STR -t -c "SELECT rule_engine_version()")
        echo -e "${GREEN}✓ (version: $VERSION)${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo -e "${RED}Error: Rule engine extension not installed${NC}"
        echo "Run: CREATE EXTENSION rule_engine_postgre_extensions;"
        exit 1
    fi
}

# Function to setup test environment
setup_test_env() {
    echo -e "${YELLOW}Setting up test environment...${NC}"
    if psql $CONN_STR -f setup.sql > /dev/null; then
        echo -e "${GREEN}✓ Setup complete${NC}"
    else
        echo -e "${RED}✗ Setup failed${NC}"
        exit 1
    fi
    echo ""
}

# Function to cleanup
cleanup_test_env() {
    echo ""
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    if psql $CONN_STR -f cleanup.sql > /dev/null; then
        echo -e "${GREEN}✓ Cleanup complete${NC}"
    else
        echo -e "${RED}✗ Cleanup failed${NC}"
    fi
}

# Function to generate summary report
generate_summary() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Test Summary                          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"

    echo ""
    echo "Full results saved to: $RESULT_FILE"
    echo ""

    # Extract TPS from results
    echo -e "${YELLOW}Throughput Summary (TPS - Transactions Per Second):${NC}"
    grep -A 2 "^transaction type:" "$RESULT_FILE" | \
        awk '/including connections establishing/ {print "  " prev ": " $1 " tps"; prev=""}
             /^transaction type:/ {prev=$0; sub(/.*: /, "", prev)}' | \
        sed 's/transaction type: //' | \
        head -n 20

    echo ""
    echo -e "${YELLOW}Performance Targets (from README):${NC}"
    echo "  Simple rule (1 condition):      800-1250 tps (target)"
    echo "  Complex rule (5 conditions):    350-476 tps (target)"
    echo "  Webhook calls:                  100-200 tps (target)"
    echo "  Datasource fetch (cached):      500-1000 tps (target)"
    echo ""
}

# Main execution
main() {
    # Pre-flight checks
    check_database
    check_extension

    # Setup
    setup_test_env

    # Initialize result file
    echo "PostgreSQL Rule Engine - Load Test Results" > "$RESULT_FILE"
    echo "Generated: $(date)" >> "$RESULT_FILE"
    echo "Configuration: Clients=$CLIENTS, Threads=$THREADS, Duration=${DURATION}s" >> "$RESULT_FILE"
    echo "═══════════════════════════════════════════════════════════" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"

    # Run all tests
    run_test "01. Simple Rule" \
        "01_simple_rule.sql" \
        "Forward chaining with 1 condition"

    run_test "02. Complex Rules" \
        "02_complex_rule.sql" \
        "Multiple rules with complex conditions"

    run_test "03. Repository Save" \
        "03_repository_save.sql" \
        "Concurrent rule saves with versioning"

    run_test "04. Repository Execute" \
        "04_repository_execute.sql" \
        "Execute saved rules by name"

    run_test "05. Webhook Calls" \
        "05_webhook_call.sql" \
        "HTTP callouts with queue processing"

    run_test "06. Datasource Fetch" \
        "06_datasource_fetch.sql" \
        "External API fetching with caching"

    # Cleanup
    cleanup_test_env

    # Generate summary
    generate_summary
}

# Help text
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  DB_HOST             Database host (default: localhost)"
    echo "  DB_PORT             Database port (default: 5432)"
    echo "  DB_NAME             Database name (default: postgres)"
    echo "  DB_USER             Database user (default: postgres)"
    echo "  DB_PASSWORD         Database password (default: postgres)"
    echo "  CLIENTS             Number of concurrent clients (default: 10)"
    echo "  THREADS             Number of threads (default: 4)"
    echo "  DURATION            Test duration in seconds (default: 60)"
    echo "  RATE                Rate limit in TPS, 0=unlimited (default: 0)"
    echo ""
    echo "Examples:"
    echo "  # Basic run with defaults"
    echo "  ./run_loadtest.sh"
    echo ""
    echo "  # Custom configuration"
    echo "  CLIENTS=50 DURATION=120 ./run_loadtest.sh"
    echo ""
    echo "  # Different database"
    echo "  DB_HOST=prod.example.com DB_NAME=mydb ./run_loadtest.sh"
    echo ""
    exit 0
fi

# Run main
main
