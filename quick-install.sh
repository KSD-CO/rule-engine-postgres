#!/bin/bash
# Quick install script for rule-engine-postgres
# Usage: curl -fsSL https://your-domain.com/install.sh | bash

set -e

echo "🚀 Installing rule-engine-postgres..."
echo ""

# Detect OS
if [ "$(uname)" = "Darwin" ]; then
    OS="macos"
    VERSION=$(sw_vers -productVersion)
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "❌ Cannot detect OS. Please install manually."
    exit 1
fi

# Detect PostgreSQL version
PG_VERSION=$(psql --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "16")

echo "Detected: $OS $VERSION with PostgreSQL $PG_VERSION"
echo ""

# Get latest release version from GitHub API
LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/KSD-CO/rule-engine-postgres/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' || echo "1.1.0")

echo "Latest version: v${LATEST_VERSION}"
echo ""

# Check if pre-built binary exists
BINARY_URL="https://github.com/KSD-CO/rule-engine-postgres/releases/download/v${LATEST_VERSION}/postgresql-${PG_VERSION}-rule-engine_${LATEST_VERSION}_amd64.deb"

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "📦 Downloading pre-built package..."

    # Try to download pre-built package
    if curl -fsSL "$BINARY_URL" -o /tmp/rule-engine.deb; then
        echo "✅ Installing from pre-built package..."
        sudo dpkg -i /tmp/rule-engine.deb
        sudo apt-get install -f -y
        rm /tmp/rule-engine.deb
    else
        echo "⚠️  Pre-built package not available. Building from source..."

        # Install dependencies
        sudo apt-get update
        sudo apt-get install -y postgresql-server-dev-$PG_VERSION \
            build-essential pkg-config clang libpq-dev curl

        # Install Rust
        if ! command -v cargo &> /dev/null; then
            echo "Installing Rust..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source $HOME/.cargo/env
        fi

        # Install cargo-pgrx
        cargo install cargo-pgrx --version 0.16.1 --locked

        # Clone and build
        git clone https://github.com/KSD-CO/rule-engine-postgres.git /tmp/rule-engine
        cd /tmp/rule-engine
        
        # Build with cargo pgrx package
        cargo pgrx package --pg-config /usr/lib/postgresql/$PG_VERSION/bin/pg_config

        # Install
        sudo cp target/release/rule_engine_postgre_extensions-pg$PG_VERSION/usr/lib/postgresql/$PG_VERSION/lib/rule_engine_postgre_extensions.so \
            /usr/lib/postgresql/$PG_VERSION/lib/
        sudo cp rule_engine_postgre_extensions.control \
            /usr/share/postgresql/$PG_VERSION/extension/
        sudo cp rule_engine_postgre_extensions--*.sql \
            /usr/share/postgresql/$PG_VERSION/extension/
        sudo chmod 644 /usr/share/postgresql/$PG_VERSION/extension/rule_engine_postgre_extensions--*.sql

        # Cleanup
        cd ~
        rm -rf /tmp/rule-engine
    fi
else
    echo "❌ Unsupported OS: $OS"
    echo "Please install manually following the instructions at:"
    echo "https://github.com/KSD-CO/rule-engine-postgres"
    exit 1
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "To enable the extension, run:"
echo "  sudo -u postgres psql -d your_database -c 'CREATE EXTENSION rule_engine_postgre_extensions;'"
echo ""
echo "Test installation:"
echo "  sudo -u postgres psql -d postgres -c \"SELECT rule_engine_version();\""
