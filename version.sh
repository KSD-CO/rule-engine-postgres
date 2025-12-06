#!/bin/bash
# Show current version from Cargo.toml

set -e

VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not extract version from Cargo.toml"
    exit 1
fi

echo "Current version: $VERSION"

# Show where this version is used
echo ""
echo "📋 Version references:"
echo ""

# Check Cargo.toml
echo "✅ Cargo.toml:                    $VERSION"

# Check control file
CONTROL_VERSION=$(grep '^default_version = ' rule_engine_postgre_extensions.control | sed "s/default_version = '\\(.*\\)'/\\1/")
if [ "$CONTROL_VERSION" = "$VERSION" ]; then
    echo "✅ control file:                 $CONTROL_VERSION"
else
    echo "⚠️  control file:                 $CONTROL_VERSION (MISMATCH!)"
fi

# Check if SQL file exists
SQL_FILE="rule_engine_postgre_extensions--${VERSION}.sql"
if [ -f "$SQL_FILE" ]; then
    echo "✅ SQL file:                     $SQL_FILE"
else
    echo "⚠️  SQL file:                     $SQL_FILE (NOT FOUND!)"
fi

# Check CHANGELOG
if grep -q "## \[${VERSION}\]" CHANGELOG.md 2>/dev/null; then
    echo "✅ CHANGELOG.md:                 Has [${VERSION}] section"
else
    echo "⚠️  CHANGELOG.md:                 Missing [${VERSION}] section"
fi

# Check README badge
if grep -q "version-${VERSION}-" README.md 2>/dev/null; then
    echo "✅ README.md badge:              ${VERSION}"
else
    echo "⚠️  README.md badge:              Not updated"
fi

echo ""
echo "🔍 Release artifacts will be created at:"
echo "   releases/download/v${VERSION}/"
