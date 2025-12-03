#!/bin/bash
# Build .deb package for easy installation

set -e

VERSION="1.0.0"
ARCH="amd64"
PG_VERSION="${1:-16}"  # Default to PostgreSQL 16, allow override with argument
PACKAGE="postgresql-${PG_VERSION}-rule-engine_${VERSION}_${ARCH}"
DIST_DIR="releases/download/v1.0.0"

echo "Building .deb package for PostgreSQL ${PG_VERSION}..."

# Create dist directory
mkdir -p "${DIST_DIR}"

# Build the extension
cargo build --release --no-default-features --features pg${PG_VERSION}

# Create package structure
mkdir -p "${PACKAGE}/DEBIAN"
mkdir -p "${PACKAGE}/usr/lib/postgresql/${PG_VERSION}/lib"
mkdir -p "${PACKAGE}/usr/share/postgresql/${PG_VERSION}/extension"
mkdir -p "${PACKAGE}/usr/share/doc/postgresql-${PG_VERSION}-rule-engine"

# Copy files
cp target/release/librule_engine_postgres.so \
   "${PACKAGE}/usr/lib/postgresql/${PG_VERSION}/lib/rule_engine_postgre_extensions.so"

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
