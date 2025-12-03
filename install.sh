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

echo "Building extension (release mode)..."
cargo build --release --features pg16

echo ""
echo "Installing extension files..."

# Copy shared library
echo "  - Copying .so file..."
sudo cp target/release/librule_engine_postgre_extensions.so /usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so

# Copy control file
echo "  - Copying control file..."
sudo cp rule_engine_postgre_extensions.control /usr/share/postgresql/16/extension/

# Copy SQL files
echo "  - Copying SQL files..."
sudo cp rule_engine_postgre_extensions--*.sql /usr/share/postgresql/16/extension/

echo ""
echo "Restarting PostgreSQL..."
sudo systemctl restart postgresql
echo "sudo chmod 644 /usr/share/postgresql/16/extension/rule_engine_postgre_extensions--1.0.0.sql"
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
