#!/bin/bash
# Bump version across all files
# Usage: ./bump-version.sh <new-version>
# Example: ./bump-version.sh 1.2.0

set -e

if [ -z "$1" ]; then
    echo "Usage: ./bump-version.sh <new-version>"
    echo "Example: ./bump-version.sh 1.2.0"
    exit 1
fi

NEW_VERSION="$1"
OLD_VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [ -z "$OLD_VERSION" ]; then
    echo "❌ Error: Could not extract current version from Cargo.toml"
    exit 1
fi

echo "🔄 Bumping version: $OLD_VERSION → $NEW_VERSION"
echo ""

# Validate version format (semantic versioning)
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "❌ Error: Invalid version format. Use semantic versioning (e.g., 1.2.0)"
    exit 1
fi

# Check if migration SQL file might be needed
IFS='.' read -r old_major old_minor old_patch <<< "$OLD_VERSION"
IFS='.' read -r new_major new_minor new_patch <<< "$NEW_VERSION"

NEEDS_MIGRATION=false
if [ "$old_major" != "$new_major" ] || [ "$old_minor" != "$new_minor" ]; then
    NEEDS_MIGRATION=true
fi

# 1. Update Cargo.toml
echo "📝 Updating Cargo.toml..."
sed -i.bak "s/^version = \"$OLD_VERSION\"/version = \"$NEW_VERSION\"/" Cargo.toml
rm Cargo.toml.bak

# 2. Update control file
echo "📝 Updating rule_engine_postgre_extensions.control..."
sed -i.bak "s/^default_version = '$OLD_VERSION'/default_version = '$NEW_VERSION'/" rule_engine_postgre_extensions.control
rm rule_engine_postgre_extensions.control.bak

# 3. Update README.md badge
echo "📝 Updating README.md version badge..."
sed -i.bak "s/version-$OLD_VERSION-/version-$NEW_VERSION-/g" README.md
rm README.md.bak

# 4. Check for SQL migration file
if [ "$NEEDS_MIGRATION" = true ]; then
    MIGRATION_FILE="rule_engine_postgre_extensions--${OLD_VERSION}--${NEW_VERSION}.sql"
    if [ ! -f "$MIGRATION_FILE" ]; then
        echo ""
        echo "⚠️  Creating migration file: $MIGRATION_FILE"
        cat > "$MIGRATION_FILE" << EOF
-- Migration from ${OLD_VERSION} to ${NEW_VERSION}

-- Add any schema changes here
-- Example:
-- ALTER TABLE rule_definitions ADD COLUMN new_field TEXT;

-- Update extension version
UPDATE pg_extension
SET extversion = '${NEW_VERSION}'
WHERE extname = 'rule_engine_postgre_extensions';
EOF
        echo "   Created with template. Please update with actual changes!"
    else
        echo "✅ Migration file already exists: $MIGRATION_FILE"
    fi
    
    # Check if new version SQL file exists
    NEW_SQL_FILE="rule_engine_postgre_extensions--${NEW_VERSION}.sql"
    if [ ! -f "$NEW_SQL_FILE" ]; then
        echo "⚠️  You may need to create: $NEW_SQL_FILE"
        echo "   Or it might be automatically handled by the existing migration"
    fi
fi

# 5. Update CHANGELOG.md
echo "📝 Updating CHANGELOG.md..."
TODAY=$(date +%Y-%m-%d)

if grep -q "## \[${NEW_VERSION}\]" CHANGELOG.md 2>/dev/null; then
    echo "   Section [${NEW_VERSION}] already exists in CHANGELOG.md"
else
    # Add new version section after ## [Unreleased] if it exists, or at the top
    if grep -q "## \[Unreleased\]" CHANGELOG.md; then
        sed -i.bak "/## \[Unreleased\]/a\\
\\
## [${NEW_VERSION}] - ${TODAY}\\
\\
### Added\\
- \\
\\
### Changed\\
- \\
\\
### Fixed\\
- \\
" CHANGELOG.md
    else
        sed -i.bak "1a\\
## [${NEW_VERSION}] - ${TODAY}\\
\\
### Added\\
- \\
\\
### Changed\\
- \\
\\
### Fixed\\
- \\
\\
" CHANGELOG.md
    fi
    rm CHANGELOG.md.bak
    echo "   Added new section [${NEW_VERSION}] to CHANGELOG.md"
    echo "   ⚠️  Please fill in the changes!"
fi

echo ""
echo "✅ Version bump complete: $OLD_VERSION → $NEW_VERSION"
echo ""
echo "📋 Updated files:"
echo "   - Cargo.toml"
echo "   - rule_engine_postgre_extensions.control"
echo "   - README.md"
echo "   - CHANGELOG.md"

if [ "$NEEDS_MIGRATION" = true ]; then
    echo "   - $MIGRATION_FILE (created/checked)"
fi

echo ""
echo "🔍 Next steps:"
echo "   1. Review changes: git diff"
echo "   2. Update CHANGELOG.md with actual changes"
if [ "$NEEDS_MIGRATION" = true ]; then
    echo "   3. Update migration file: $MIGRATION_FILE"
fi
echo "   4. Run tests: make test"
echo "   5. Build: make build"
echo "   6. Commit: git add . && git commit -m 'Bump version to $NEW_VERSION'"
echo "   7. Tag: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION'"
echo "   8. Push: git push origin main && git push origin v$NEW_VERSION"
echo ""
echo "Run './version.sh' to verify all version references"
