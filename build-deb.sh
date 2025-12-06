#!/bin/bash
# Build .deb package for easy installation

set -e

# Extract version from Cargo.toml
VERSION=$(grep '^version = ' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')

if [ -z "$VERSION" ]; then
    echo "❌ Error: Could not extract version from Cargo.toml"
    exit 1
fi

ARCH="amd64"
PG_VERSION="${1:-17}"  # Default to PostgreSQL 17, allow override with argument
PACKAGE="postgresql-${PG_VERSION}-rule-engine_${VERSION}_${ARCH}"
DIST_DIR="releases/download/v${VERSION}"

echo "Building .deb package for PostgreSQL ${PG_VERSION}..."

# Create dist directory
mkdir -p "${DIST_DIR}"

# Build the extension with cargo pgrx package
echo "Building with cargo pgrx package..."
PG_CONFIG="/usr/lib/postgresql/${PG_VERSION}/bin/pg_config"
if [ ! -f "$PG_CONFIG" ]; then
    echo "❌ Error: pg_config not found at $PG_CONFIG"
    echo "Please install postgresql-server-dev-${PG_VERSION}"
    exit 1
fi

# Build pgrx_embed first to avoid "Failed to find pgrx_embed binary" error
echo "Building pgrx_embed..."
cargo build --release --bin pgrx_embed --no-default-features --features pg${PG_VERSION}

# Now run package (which needs pgrx_embed)
echo "Running cargo pgrx package..."
cargo pgrx package --pg-config "$PG_CONFIG"

# Create package structure
mkdir -p "${PACKAGE}/DEBIAN"
mkdir -p "${PACKAGE}/usr/lib/postgresql/${PG_VERSION}/lib"
mkdir -p "${PACKAGE}/usr/share/postgresql/${PG_VERSION}/extension"
mkdir -p "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine"

# Copy files from cargo pgrx package output
SOURCE_DIR="target/release/rule_engine_postgre_extensions-pg${PG_VERSION}/usr"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Error: Build output not found at $SOURCE_DIR"
    exit 1
fi

cp "${SOURCE_DIR}/lib/postgresql/${PG_VERSION}/lib/rule_engine_postgre_extensions.so" \
   "${PACKAGE}/usr/lib/postgresql/${PG_VERSION}/lib/"

cp rule_engine_postgre_extensions.control \
   "${PACKAGE}/usr/share/postgresql/${PG_VERSION}/extension/"

cp rule_engine_postgre_extensions--*.sql \
   "${PACKAGE}/usr/share/postgresql/${PG_VERSION}/extension/"

# Fix permissions
chmod 644 "${PACKAGE}/usr/share/postgresql/${PG_VERSION}/extension/"*.sql

# Copy documentation (optional files)
cp README.md "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine/" 2>/dev/null || true
cp DEPLOYMENT.md "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine/" 2>/dev/null || true
cp LICENSE "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine/" 2>/dev/null || true
cp BUILD.md "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine/" 2>/dev/null || true
cp DOCKER.md "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine/" 2>/dev/null || true

# Create control file
cat > "${PACKAGE}/DEBIAN/control" << EOF
Package: postgresql-${PG_VERSION}-rule-engine
Version: ${VERSION}
Section: database
Priority: optional
Architecture: ${ARCH}
Depends: postgresql-${PG_VERSION}
Maintainer: Ton That Vu <ttvuhm@gmail.com>
Description: PostgreSQL extension for rule engine with GRL syntax
 Production-ready PostgreSQL extension for running business rules.
Homepage: https://github.com/KSD-CO/rule-engine-postgres
EOF

# Build package
dpkg-deb --build "${PACKAGE}"

# Move to dist directory
mv "${PACKAGE}.deb" "${DIST_DIR}/"

echo "✅ Package built: ${DIST_DIR}/${PACKAGE}.deb"
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${DIST_DIR}/${PACKAGE}.deb"
echo "  sudo apt-get install -f  # Fix dependencies if needed"
echo ""
echo "To build for different PostgreSQL version:"
echo "  ./build-deb.sh 17  # For PostgreSQL 17"
echo "  ./build-deb.sh 16  # For PostgreSQL 16"
echo ""
echo "Upload to GitHub Releases:"
echo "  gh release create v${VERSION} ${DIST_DIR}/${PACKAGE}.deb --title 'v${VERSION}'"
