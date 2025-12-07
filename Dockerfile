# Dockerfile for PostgreSQL with rule-engine-postgre-extensions
# Using PostgreSQL 17 (latest stable) on Debian Bookworm
FROM postgres:17-bookworm

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    pkg-config \
    libssl-dev \
    postgresql-server-dev-17 \
    && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install cargo-pgrx
RUN cargo install cargo-pgrx --version 0.16.1 --locked

# Initialize pgrx with PostgreSQL 17
RUN cargo pgrx init --pg17 /usr/bin/pg_config

# Copy extension source code
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY rule_engine_postgre_extensions.control ./
COPY rule_engine_postgre_extensions--*.sql ./
COPY migrations ./migrations

# Build the extension (don't use cargo pgrx install - pgrx_embed not available)
RUN cargo build --release --no-default-features --features pg17

# Manually install files
RUN PG_LIB=$(pg_config --pkglibdir) && \
    PG_SHARE=$(pg_config --sharedir) && \
    mkdir -p "$PG_LIB" "$PG_SHARE/extension" && \
    cp target/release/librule_engine_postgres.so "$PG_LIB/rule_engine_postgre_extensions.so" && \
    cp rule_engine_postgre_extensions.control "$PG_SHARE/extension/" && \
    cp rule_engine_postgre_extensions--*.sql "$PG_SHARE/extension/" && \
    cp migrations/*.sql "$PG_SHARE/extension/"

# Clean up build dependencies to reduce image size
RUN apt-get purge -y \
    build-essential \
    curl \
    git \
    && apt-get autoremove -y \
    && rm -rf /root/.cargo /root/.rustup /build

# Set environment variables
ENV POSTGRES_DB=ruleengine
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres

# Expose PostgreSQL port
EXPOSE 5432

# Create initialization script
RUN echo '#!/bin/bash\n\
set -e\n\
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL\n\
    CREATE EXTENSION IF NOT EXISTS rule_engine_postgre_extensions;\n\
    SELECT rule_engine_version();\n\
    SELECT rule_engine_health_check();\n\
EOSQL\n' > /docker-entrypoint-initdb.d/init-extension.sh \
    && chmod +x /docker-entrypoint-initdb.d/init-extension.sh

# Start PostgreSQL
CMD ["postgres"]
