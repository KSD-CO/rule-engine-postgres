#!/bin/bash

# Fuzzing test script for Rule Engine PostgreSQL
# This script runs all fuzz targets with configurable duration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DURATION=${1:-10}  # Default 10 seconds per target
MAX_LEN=${2:-4096} # Default max input size 4KB

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Rule Engine PostgreSQL - Fuzzing Tests  ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo ""

# Check if nightly is installed
if ! rustup toolchain list | grep -q nightly; then
    echo -e "${YELLOW}⚠️  Rust nightly not found. Installing...${NC}"
    rustup install nightly
    echo -e "${GREEN}✅ Rust nightly installed${NC}"
    echo ""
fi

# Check if cargo-fuzz is installed
if ! cargo fuzz --version &> /dev/null; then
    echo -e "${YELLOW}⚠️  cargo-fuzz not found. Installing...${NC}"
    cargo install cargo-fuzz
    echo -e "${GREEN}✅ cargo-fuzz installed${NC}"
    echo ""
fi

# List available fuzz targets
echo -e "${BLUE}Available fuzz targets:${NC}"
cargo fuzz list
echo ""

echo -e "${BLUE}Configuration:${NC}"
echo -e "  Duration per target: ${YELLOW}${DURATION}s${NC}"
echo -e "  Max input size: ${YELLOW}${MAX_LEN} bytes${NC}"
echo ""

# Fuzz targets (all standalone targets)
TARGETS=(
    "fuzz_json_standalone"
    "fuzz_extreme_values"
    "fuzz_grl_parser"
    "fuzz_rule_execution"
    "fuzz_builtin_functions"
)

# Track results
TOTAL=0
PASSED=0
FAILED=0

for target in "${TARGETS[@]}"; do
    TOTAL=$((TOTAL + 1))
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Running: ${YELLOW}${target}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Run fuzzer
    if cargo +nightly fuzz run "${target}" -- \
        -max_total_time="${DURATION}" \
        -max_len="${MAX_LEN}" \
        -print_final_stats=1; then
        echo -e "${GREEN}✅ ${target} - PASSED (no crashes)${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ ${target} - FAILED (crash or error)${NC}"
        FAILED=$((FAILED + 1))

        # Check for crash artifacts
        if ls fuzz/artifacts/"${target}"/crash-* 1> /dev/null 2>&1; then
            echo -e "${RED}   Crash artifacts found:${NC}"
            ls -lh fuzz/artifacts/"${target}"/crash-*
        fi
    fi
    echo ""
done

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Summary                       ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "Total targets:  ${TOTAL}"
echo -e "${GREEN}Passed:         ${PASSED}${NC}"
echo -e "${RED}Failed:         ${FAILED}${NC}"
echo ""

if [ "${FAILED}" -gt 0 ]; then
    echo -e "${RED}⚠️  Some fuzz targets found crashes!${NC}"
    echo -e "${YELLOW}Check artifacts in fuzz/artifacts/ directory${NC}"
    exit 1
else
    echo -e "${GREEN}🎉 All fuzz targets passed!${NC}"
    exit 0
fi
