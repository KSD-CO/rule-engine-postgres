# Makefile for rule_engine_postgre_extensions
# For PGXN compatibility

EXTENSION = rule_engine_postgre_extensions
DATA = rule_engine_postgre_extensions--1.0.0.sql \
       rule_engine_postgre_extensions--0.1.0--1.0.0.sql
DOCS = README.md DEPLOYMENT.md

# Build with cargo-pgrx
PG_CONFIG = pg_config
SHLIB_LINK = -lpq

all: build

build:
	cargo build --release --features pg16

install: build
	@echo "Installing extension..."
	cargo pgrx install --pg-config $(shell which pg_config)
	chmod 644 rule_engine_postgre_extensions--*.sql
	@echo "Installation complete!"

clean:
	cargo clean

test:
	cargo test
	cargo pgrx test

.PHONY: all build install clean test
