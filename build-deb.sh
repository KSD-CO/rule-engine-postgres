#!/bin/bash
# Build .deb package for easy installation

set -e

VERSION="1.0.0"
ARCH="amd64"
PACKAGE="postgresql-16-rule-engine_${VERSION}_${ARCH}"

echo "Building .deb package..."

# Build the extension
cargo build --release --features pg16

# Create package structure
mkdir -p "${PACKAGE}/DEBIAN"
mkdir -p "${PACKAGE}/usr/lib/postgresql/16/lib"
mkdir -p "${PACKAGE}/usr/share/postgresql/16/extension"
mkdir -p "${PACKAGE}/usr/share/doc/postgresql-16-rule-engine"

# Copy files
cp target/release/librule_engine_postgre_extensions.so \
   "${PACKAGE}/usr/lib/postgresql/16/lib/rule_engine_postgre_extensions.so"

cp rule_engine_postgre_extensions.control \
   "${PACKAGE}/usr/share/postgresql/16/extension/"

cp rule_engine_postgre_extensions--*.sql \
   "${PACKAGE}/usr/share/postgresql/16/extension/"

# Fix permissions
chmod 644 "${PACKAGE}/usr/share/postgresql/16/extension/"*.sql

# Copy documentation
cp README.md DEPLOYMENT.md LICENSE \
   "${PACKAGE}/usr/share/doc/postgresql-16-rule-engine/"

# Create control file
cat > "${PACKAGE}/DEBIAN/control" << EOF
Package: postgresql-16-rule-engine
Version: ${VERSION}
Section: database
Priority: optional
Architecture: ${ARCH}
Depends: postgresql-16
Maintainer: Your Name <your.email@example.com>
Description: PostgreSQL extension for rule engine with GRL syntax
 Production-ready PostgreSQL extension for running business rules.
Homepage: https://github.com/KSD-CO/rule-engine-postgres
EOF

# Build package
dpkg-deb --build "${PACKAGE}"

echo "✅ Package built: ${PACKAGE}.deb"
echo ""
echo "Install with:"
echo "  sudo dpkg -i ${PACKAGE}.deb"
echo "  sudo apt-get install -f  # Fix dependencies if needed"
