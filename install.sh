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

# Allow overriding PostgreSQL version (default 16)
PG_VERSION=${PG_VERSION:-16}

echo "Building extension (release mode) for PostgreSQL ${PG_VERSION}..."
# Ensure default features (pg17) are disabled before enabling a single pg feature
cargo build --release --no-default-features --features pg${PG_VERSION}

echo ""
echo "Installing extension files..."

# Copy shared library
echo "  - Copying .so file..."
# The produced .so name may vary depending on the crate name. Try known candidates.
SO_CANDIDATES=("target/release/librule_engine_postgres.so" "target/release/librule_engine_postgre_extensions.so" "target/release/librule_engine_postgres-*.so" )
SO_PATH=""
for candidate in "${SO_CANDIDATES[@]}"; do
    # Use globbing for patterns
    for f in $candidate; do
        if [ -f "$f" ]; then
            SO_PATH="$f"
            break 2
        fi
    done
done
if [ -z "$SO_PATH" ]; then
    echo "❌ Error: compiled shared library not found in target/release/. Looked for patterns: ${SO_CANDIDATES[*]}"
    exit 1
fi
# Install to the correct PostgreSQL lib directory, strip the leading 'lib' from the filename
SO_BASENAME=$(basename "$SO_PATH")
TARGET_NAME=$(echo "$SO_BASENAME" | sed 's/^lib//')

# Determine module filename from control file (module_pathname = '$libdir/<name>')
MODULE_NAME="rule_engine_postgre_extensions.so"
if [ -f rule_engine_postgre_extensions.control ]; then
    # extract the module_pathname value and strip $libdir/
    mp=$(grep -E "^module_pathname\s*=" rule_engine_postgre_extensions.control | sed -E "s/.*=\s*'\$?libdir\/(.+)'/\1/" ) || true
    if [ -n "$mp" ]; then
        MODULE_NAME="$mp"
    fi
fi

# Primary install: copy to the module filename expected by the control file
DEST_DIR="/usr/lib/postgresql/${PG_VERSION}/lib"
echo "  - Installing shared object to ${DEST_DIR}/${MODULE_NAME} ..."
sudo cp "$SO_PATH" "${DEST_DIR}/${MODULE_NAME}"

# Fallback: also copy to the stripped lib name for compatibility
if [ "${MODULE_NAME}" != "${TARGET_NAME}" ]; then
    echo "  - Also installing fallback name ${DEST_DIR}/${TARGET_NAME} ..."
    sudo cp "$SO_PATH" "${DEST_DIR}/${TARGET_NAME}" || true
fi

# Copy control file
echo "  - Copying control file..."
sudo cp rule_engine_postgre_extensions.control "/usr/share/postgresql/${PG_VERSION}/extension/"

# Copy SQL files
echo "  - Copying SQL files..."
sudo cp rule_engine_postgre_extensions--*.sql "/usr/share/postgresql/${PG_VERSION}/extension/"

echo ""
echo "Restarting PostgreSQL..."
sudo systemctl restart postgresql
echo "sudo chmod 644 /usr/share/postgresql/${PG_VERSION}/extension/rule_engine_postgre_extensions--1.0.0.sql"
echo "sudo -u postgres psql -d postgres -f tests.sql"
echo ""
echo "✅ Installation complete!"
echo ""
echo "To enable the extension, run in psql:"
echo "  DROP EXTENSION IF EXISTS rule_engine_postgre_extensions;"
echo "  CREATE EXTENSION rule_engine_postgre_extensions;"
echo ""
echo "To test, run:"
echo "  psql -U postgres -d your_database -f tests.sql"
