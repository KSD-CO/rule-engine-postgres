#!/bin/bash
# Quick pre-commit check - only runs lints without full rebuild

set -e

echo "⚡ Quick pre-commit checks (using existing build)..."
echo ""

# 1. Check formatting
echo "1️⃣  Checking code formatting..."
if ! cargo fmt --all -- --check; then
    echo "❌ Code formatting check failed!"
    echo "   Run: cargo fmt --all"
    exit 1
fi
echo "✅ Formatting OK"
echo ""

# 2. Run clippy (using existing build cache)
echo "2️⃣  Running clippy (quick mode)..."
if ! cargo clippy --no-default-features --features pg17 -- -D warnings 2>&1 | grep -E "(error|warning:|Checking|Finished)"; then
    echo "❌ Clippy failed!"
    exit 1
fi
echo "✅ Clippy OK"
echo ""

echo "✅ Quick checks passed!"
