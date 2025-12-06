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
echo "Note: Using 'cargo pgrx install' instead of 'cargo pgrx package'"
echo "      This directly installs to PostgreSQL directories."
echo ""

# Use sudo for cargo pgrx install since it writes to system directories
sudo -E env "PATH=$PATH" cargo pgrx install --pg-config "$PG_CONFIG" --release

# cargo pgrx install handles all file copying automatically
echo ""
echo "✅ Extension files installed by cargo pgrx install"

echo ""
echo "Restarting PostgreSQL..."
if [ "$(uname)" = "Darwin" ]; then
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
