#!/bin/bash
# Manual pre-commit checks - run this anytime to validate code

set -e

echo "🔍 Running all pre-commit checks..."
echo ""

# 1. Check formatting
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  Checking code formatting..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! cargo fmt --all -- --check; then
    echo ""
    echo "❌ Code formatting check failed!"
    echo "   Run: cargo fmt --all"
    exit 1
fi
echo "✅ Formatting OK"
echo ""

# 2. Run clippy for PostgreSQL 16
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  Running clippy for PostgreSQL 16..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! cargo clippy --all-targets --no-default-features --features pg16 -- -D warnings; then
    echo ""
    echo "❌ Clippy failed for PostgreSQL 16!"
    echo "   Fix warnings above"
    exit 1
fi
echo "✅ Clippy PG16 OK"
echo ""

# 3. Run clippy for PostgreSQL 17
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  Running clippy for PostgreSQL 17..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! cargo clippy --all-targets --no-default-features --features pg17 -- -D warnings; then
    echo ""
    echo "❌ Clippy failed for PostgreSQL 17!"
    echo "   Fix warnings above"
    exit 1
fi
echo "✅ Clippy PG17 OK"
echo ""

# 4. Check if there are any TODO/FIXME comments (warning only)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  Checking for TODO/FIXME comments..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if grep -r "TODO\|FIXME" src/ 2>/dev/null | grep -v ".git" || true; then
    echo "⚠️  Found TODO/FIXME comments (not blocking)"
else
    echo "✅ No TODO/FIXME found"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All checks passed! Safe to commit."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
