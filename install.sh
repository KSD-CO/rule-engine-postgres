#!/bin/bash

# Installation script for rule_engine_postgre_extensions
# Run with: ./install.sh (NOT with sudo!)

set -e

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "❌ Error: Do not run this script with sudo!"
    echo "The script will ask for sudo password when needed."
    exit 1
fi

# Auto-detect PostgreSQL version if not specified
if [ -z "$PG_VERSION" ]; then
    if command -v pg_config &> /dev/null; then
        PG_VERSION=$(pg_config --version | sed 's/^PostgreSQL \([0-9]*\).*/\1/')
        echo "Auto-detected PostgreSQL version: $PG_VERSION"
    else
        PG_VERSION=17
        echo "⚠️  Warning: Could not detect PostgreSQL version, defaulting to $PG_VERSION"
    fi
fi

echo "Building extension (release mode) for PostgreSQL ${PG_VERSION}..."
# Use cargo pgrx install for direct installation (package has pgrx_embed issues)
if command -v pg_config &> /dev/null; then
    PG_CONFIG=$(which pg_config)
else
    # Try common paths
    if [ -f "/usr/lib/postgresql/${PG_VERSION}/bin/pg_config" ]; then
        PG_CONFIG="/usr/lib/postgresql/${PG_VERSION}/bin/pg_config"
    elif [ -f "/opt/homebrew/opt/postgresql@${PG_VERSION}/bin/pg_config" ]; then
        PG_CONFIG="/opt/homebrew/opt/postgresql@${PG_VERSION}/bin/pg_config"
    else
        echo "❌ Error: pg_config not found for PostgreSQL ${PG_VERSION}"
        exit 1
    fi
fi

echo "Using pg_config: $PG_CONFIG"
echo ""
echo "Building extension binary..."
cargo build --release --no-default-features --features pg${PG_VERSION}

echo ""
echo "Installing extension files..."

# Detect OS for correct paths
if [ "$(uname)" = "Darwin" ]; then
    # macOS paths
    LIB_DIR="/opt/homebrew/lib/postgresql@${PG_VERSION}"
    EXT_DIR="/opt/homebrew/share/postgresql@${PG_VERSION}/extension"
    SO_EXT="dylib"
else
    # Linux paths
    LIB_DIR="/usr/lib/postgresql/${PG_VERSION}/lib"
    EXT_DIR="/usr/share/postgresql/${PG_VERSION}/extension"
    SO_EXT="so"
fi

# Find the shared library
SO_PATH="target/release/librule_engine_postgres.${SO_EXT}"

if [ ! -f "$SO_PATH" ]; then
    echo "❌ Error: Shared library not found at $SO_PATH"
    echo "Build output:"
    ls -la target/release/ | grep rule_engine || echo "No matching files found"
    exit 1
fi

echo "  - Installing shared library to $LIB_DIR"
sudo cp "$SO_PATH" "${LIB_DIR}/rule_engine_postgre_extensions.${SO_EXT}"

# Copy control file
echo "  - Copying control file to $EXT_DIR"
sudo cp rule_engine_postgre_extensions.control "${EXT_DIR}/"

# Copy SQL files
echo "  - Copying SQL files to $EXT_DIR"
sudo cp rule_engine_postgre_extensions--*.sql "${EXT_DIR}/"
sudo chmod 644 "${EXT_DIR}/rule_engine_postgre_extensions--"*.sql

echo ""
echo "Restarting PostgreSQL..."
if [ "$(uname)" = "Darwin" ]; then
    brew services restart postgresql@${PG_VERSION}
else
    # Try common systemd unit names for Debian/Ubuntu packaged clusters
    if sudo systemctl list-units --full --all | grep -q "postgresql@${PG_VERSION}-main.service"; then
        sudo systemctl restart postgresql@${PG_VERSION}-main || true
    elif sudo systemctl list-units --full --all | grep -q "postgresql@${PG_VERSION}.service"; then
        sudo systemctl restart postgresql@${PG_VERSION} || true
    elif sudo systemctl list-units --full --all | grep -q "postgresql.service"; then
        sudo systemctl restart postgresql || true
    else
        echo "Warning: no matching postgresql systemd unit found to restart. You may need to restart PostgreSQL manually."
    fi

    # If restart failed or asserted, show recent journal for debugging
    echo "If PostgreSQL failed to restart, recent journal entries follow:"
    sudo journalctl -u postgresql@${PG_VERSION}.service -n 50 --no-pager || true
    sudo journalctl -u postgresql.service -n 50 --no-pager || true
fi
echo ""
echo "✅ Installation complete!"
echo ""
echo "For FRESH INSTALL (first time):"
echo "  psql -d your_database -c \"CREATE EXTENSION rule_engine_postgre_extensions;\""
echo "  psql -d your_database -c \"SELECT rule_engine_version();\""
echo ""
echo "For UPGRADE (existing installation):"
echo "  psql -d your_database -c \"ALTER EXTENSION rule_engine_postgre_extensions UPDATE TO '1.5.0';\""
echo "  psql -d your_database -c \"SELECT rule_engine_version();\""
echo ""
echo "See docs/UPGRADE_INSTRUCTIONS.md for detailed upgrade guide."
echo ""
echo "To run tests:"
echo "  psql -d your_database -f tests.sql"
echo "  # Phase 1 tests (Rule Repository, Rule Sets, Stats, Event Triggers):"
echo "  psql -d your_database -f tests/test_rule_sets_and_stats.sql"
echo "  # Phase 2 tests (Testing, Validation, Debugging, Templates):"
echo "  psql -d your_database -f tests/test_phase2_developer_experience.sql"
echo "  # Phase 4.2 tests (Webhooks - v1.5.0):"
echo "  psql -d your_database -f tests/test_webhooks.sql"
