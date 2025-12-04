# Docker Quick Start Guide

This guide helps you run the rule-engine-postgres extension using Docker.

## Prerequisites

- Docker 20.10+
- Docker Compose 2.0+

## Quick Start

### 1. Setup Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your settings (optional)
nano .env
```

### 2. Build and Run

```bash
# Build and start PostgreSQL with extension
docker-compose up -d

# Check logs
docker-compose logs -f postgres

# Verify extension is loaded
docker-compose exec postgres psql -U postgres -d ruleengine \
  -c "SELECT rule_engine_version();"
```

### 3. Test the Extension

```bash
# Connect to database
docker-compose exec postgres psql -U postgres -d ruleengine

# Inside psql, run a test query:
SELECT run_rule_engine(
    '{"User": {"age": 30, "status": "active"}}',
    'rule "CheckAge" salience 10 {
        when
            User.age > 18
        then
            User.status = "adult";
    }'
);
```

## Optional Tools

### PgAdmin (Web UI for PostgreSQL)

```bash
# Start with PgAdmin
docker-compose --profile tools up -d

# Access PgAdmin at http://localhost:5050
# Default login: admin@admin.com / admin (configure in .env)
```

## Management Commands

```bash
# Stop containers
docker-compose down

# Stop and remove volumes (WARNING: deletes all data)
docker-compose down -v

# Rebuild image
docker-compose build --no-cache

# View logs
docker-compose logs -f postgres

# Execute SQL file
docker-compose exec -T postgres psql -U postgres -d ruleengine < your-script.sql
```

## Health Check

```bash
# Check if PostgreSQL is ready
docker-compose exec postgres pg_isready -U postgres

# Check extension health
docker-compose exec postgres psql -U postgres -d ruleengine \
  -c "SELECT rule_engine_health_check();"
```

## Backup and Restore

```bash
# Backup database
docker-compose exec -T postgres pg_dump -U postgres ruleengine > backup.sql

# Restore database
docker-compose exec -T postgres psql -U postgres -d ruleengine < backup.sql
```

## Troubleshooting

### Extension not found

```bash
# Check if extension files are installed
docker-compose exec postgres ls -la /usr/share/postgresql/16/extension/ | grep rule_engine

# Check PostgreSQL extension directory
docker-compose exec postgres psql -U postgres -c "SHOW shared_preload_libraries;"
```

### Permission denied

```bash
# Fix volume permissions
docker-compose down
sudo chown -R 999:999 ./postgres_data
docker-compose up -d
```

### Connection refused

```bash
# Check if container is running
docker-compose ps

# Check PostgreSQL logs
docker-compose logs postgres
```

## Production Deployment

For production use:

1. Change default passwords in `.env`
2. Use Docker secrets for sensitive data
3. Configure proper backup strategy
4. Set resource limits in docker-compose.yml
5. Use external volume for data persistence
6. Enable SSL/TLS connections

Example production settings in `.env`:

```bash
POSTGRES_PASSWORD=your_very_secure_password
POSTGRES_DB=ruleengine_prod
MAX_CONNECTIONS=200
SHARED_BUFFERS=256MB
```

## Architecture

```
┌─────────────────┐
│   Docker Host   │
│                 │
│  ┌───────────┐  │
│  │ PostgreSQL│  │
│  │    +      │  │
│  │ Extension │  │
│  └─────┬─────┘  │
│        │        │
│  ┌─────┴─────┐  │
│  │  Volume   │  │
│  │   Data    │  │
│  └───────────┘  │
└─────────────────┘
```

## Performance Tuning

Edit `docker-compose.yml` to add PostgreSQL configuration:

```yaml
services:
  postgres:
    command:
      - "postgres"
      - "-c"
      - "max_connections=200"
      - "-c"
      - "shared_buffers=256MB"
      - "-c"
      - "effective_cache_size=1GB"
      - "-c"
      - "work_mem=4MB"
```

## Next Steps

- Read the [main README](README.md) for usage examples
- Check [DEPLOYMENT.md](DEPLOYMENT.md) for production deployment
- Visit [GitHub Issues](https://github.com/KSD-CO/rule-engine-postgres/issues) for support
