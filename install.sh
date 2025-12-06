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

# Allow overriding PostgreSQL version (default 17)
PG_VERSION=${PG_VERSION:-17}

echo "Building extension (release mode) for PostgreSQL ${PG_VERSION}..."
# Use cargo pgrx package for proper build
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
cargo pgrx package --pg-config "$PG_CONFIG"

echo ""
echo "Installing extension files..."

# Detect OS for correct paths
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

# Determine paths based on OS
if [ "$OS" = "darwin" ] || [ "$(uname)" = "Darwin" ]; then
    # macOS paths
    LIB_DIR="/opt/homebrew/opt/postgresql@${PG_VERSION}/lib/postgresql"
    EXT_DIR="/opt/homebrew/opt/postgresql@${PG_VERSION}/share/postgresql@${PG_VERSION}/extension"
    SO_EXT="dylib"
    PACKAGE_DIR="target/release/rule_engine_postgre_extensions-pg${PG_VERSION}/opt/homebrew/opt/postgresql@${PG_VERSION}"
else
    # Linux paths
    LIB_DIR="/usr/lib/postgresql/${PG_VERSION}/lib"
    EXT_DIR="/usr/share/postgresql/${PG_VERSION}/extension"
    SO_EXT="so"
    PACKAGE_DIR="target/release/rule_engine_postgre_extensions-pg${PG_VERSION}/usr"
fi

# Find the shared library from cargo pgrx package output
if [ "$OS" = "darwin" ] || [ "$(uname)" = "Darwin" ]; then
    SO_PATH="${PACKAGE_DIR}/lib/postgresql/rule_engine_postgre_extensions.${SO_EXT}"
else
    SO_PATH="${PACKAGE_DIR}/lib/postgresql/${PG_VERSION}/lib/rule_engine_postgre_extensions.${SO_EXT}"
fi

if [ ! -f "$SO_PATH" ]; then
    echo "❌ Error: Shared library not found at $SO_PATH"
    echo "Looking for alternative paths..."
    find target/release -name "*rule_engine*.${SO_EXT}" || true
    exit 1
fi

echo "  - Installing shared library from $SO_PATH to $LIB_DIR"
sudo cp "$SO_PATH" "${LIB_DIR}/rule_engine_postgre_extensions.${SO_EXT}"

# Copy control file
echo "  - Copying control file..."
sudo cp rule_engine_postgre_extensions.control "${EXT_DIR}/"

# Copy SQL files
echo "  - Copying SQL files..."
sudo cp rule_engine_postgre_extensions--*.sql "${EXT_DIR}/"
sudo chmod 644 "${EXT_DIR}/rule_engine_postgre_extensions--"*.sql

echo ""
echo "Restarting PostgreSQL..."
if [ "$OS" = "darwin" ] || [ "$(uname)" = "Darwin" ]; then
    brew services restart postgresql@${PG_VERSION}
else
    sudo systemctl restart postgresql@${PG_VERSION} || sudo systemctl restart postgresql
fi
echo ""
echo "✅ Installation complete!"
echo ""
echo "To enable the extension, run in psql:"
echo "  DROP EXTENSION IF EXISTS rule_engine_postgre_extensions;"
echo "  CREATE EXTENSION rule_engine_postgre_extensions;"
echo ""
echo "To test, run:"
echo "  psql -U postgres -d your_database -f tests.sql"
