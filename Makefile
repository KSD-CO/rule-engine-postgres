# Makefile for rule_engine_postgre_extensions
# For PGXN compatibility and easy building

EXTENSION = rule_engine_postgre_extensions
DATA = rule_engine_postgre_extensions--1.0.0.sql \
       rule_engine_postgre_extensions--0.1.0--1.0.0.sql
DOCS = README.md DEPLOYMENT.md
VERSION = 1.0.0
PG_VERSION ?= 17

# Build with cargo-pgrx
PG_CONFIG = pg_config
SHLIB_LINK = -lpq

.PHONY: all build install clean test deb deb-all help

all: build

help:
	@echo "Available targets:"
	@echo "  make build          - Build extension (default PG 17)"
	@echo "  make build PG_VERSION=16 - Build for PostgreSQL 16"
	@echo "  make install        - Install extension"
	@echo "  make test           - Run tests"
	@echo "  make ci             - Run CI checks (format, clippy, compilation)"
	@echo "  make fmt            - Format code"
	@echo "  make deb            - Build .deb package (default PG 17)"
	@echo "  make deb PG_VERSION=16 - Build .deb for PostgreSQL 16"
	@echo "  make deb-all        - Build .deb for all supported versions (16, 17)"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make docker-build   - Build Docker image"
	@echo "  make docker-run     - Run Docker container"

build:
	@echo "Building for PostgreSQL $(PG_VERSION)..."
	cargo build --release --no-default-features --features pg$(PG_VERSION)

install: build
	@echo "Installing extension..."
	cargo pgrx install --pg-config $(shell which pg_config)
	chmod 644 rule_engine_postgre_extensions--*.sql
	@echo "Installation complete!"

clean:
	cargo clean
	rm -rf postgresql-*-rule-engine_*_amd64/
	rm -rf dist/
	rm -rf releases/

test:
	cargo test --no-default-features --features pg$(PG_VERSION)
	cargo pgrx test pg$(PG_VERSION)

# Build .deb package
deb:
	@echo "Building .deb package for PostgreSQL $(PG_VERSION)..."
	chmod +x build-deb.sh
	./build-deb.sh $(PG_VERSION)

# Build .deb for all supported PostgreSQL versions
deb-all:
	@echo "Building .deb packages for all PostgreSQL versions (16, 17)..."
	$(MAKE) clean
	$(MAKE) deb PG_VERSION=16
	$(MAKE) clean
	$(MAKE) deb PG_VERSION=17
	@echo "✅ All packages built!"
	@ls -lh releases/download/v*/postgresql-*.deb

# Docker targets
docker-build:
	@echo "Building Docker image..."
	docker build -t rule-engine-postgres:latest .
	docker build -t rule-engine-postgres:$(VERSION) .

docker-run:
	@echo "Running Docker container..."
	docker-compose up -d

docker-stop:
	docker-compose down

docker-clean:
	docker-compose down -v
	docker rmi rule-engine-postgres:latest rule-engine-postgres:$(VERSION) || true
fmt:
	cargo fmt --all

ci:
	@echo "Running CI checks..."
	@echo "1. Checking code formatting..."
	cargo fmt --all -- --check
	@echo "✅ Format check passed"
	@echo ""
	@echo "2. Running clippy..."
	cargo clippy --all-targets --no-default-features --features pg$(PG_VERSION) -- -D warnings
	@echo "✅ Clippy check passed"
	@echo ""
	@echo "3. Checking compilation..."
	cargo check --no-default-features --features pg$(PG_VERSION)
	@echo "✅ Compilation check passed"
	@echo ""
	@echo "✅ All CI checks passed!"
	@echo "Note: Run 'make test' separately to run tests (requires pgrx init)"

