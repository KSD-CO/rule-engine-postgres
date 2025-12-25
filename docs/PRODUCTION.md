# Production Deployment Guide

Complete guide for deploying Rule Engine with NATS integration to production.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Infrastructure Requirements](#infrastructure-requirements)
- [NATS Cluster Setup](#nats-cluster-setup)
- [PostgreSQL Setup](#postgresql-setup)
- [Worker Deployment](#worker-deployment)
- [Docker Deployment](#docker-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [Security](#security)
- [Monitoring & Alerting](#monitoring--alerting)
- [Backup & Recovery](#backup--recovery)
- [Scaling](#scaling)
- [High Availability](#high-availability)
- [Performance Optimization](#performance-optimization)
- [Troubleshooting](#troubleshooting)

## Overview

This guide covers production deployment of:
- NATS JetStream cluster (3+ nodes)
- PostgreSQL with Rule Engine extension
- Webhook workers (Node.js or Go)
- Monitoring stack (Prometheus + Grafana)
- Load balancing and auto-scaling

### Deployment Options

| Option | Complexity | Cost | Recommended For |
|--------|------------|------|-----------------|
| **Docker Compose** | Low | Low | Small deployments, single server |
| **Kubernetes** | High | Medium-High | Large scale, multi-server, auto-scaling |
| **Cloud Managed** | Medium | Medium | Quick setup, managed services |
| **Bare Metal** | Medium | Low | Full control, on-premise |

## Architecture

### Production Topology

```
                           ┌─────────────────┐
                           │   Load Balancer │
                           │   (nginx/HAProxy)│
                           └────────┬────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
                    ▼               ▼               ▼
            ┌──────────────┐┌──────────────┐┌──────────────┐
            │ PostgreSQL 1 ││ PostgreSQL 2 ││ PostgreSQL 3 │
            │  (Primary)   ││  (Standby)   ││  (Standby)   │
            └──────┬───────┘└──────────────┘└──────────────┘
                   │
                   │ Publishes
                   ▼
            ┌──────────────────────────────────────┐
            │         NATS Cluster (3 nodes)       │
            │  ┌──────┐    ┌──────┐    ┌──────┐  │
            │  │NATS-1│◄──►│NATS-2│◄──►│NATS-3│  │
            │  └──────┘    └──────┘    └──────┘  │
            │         JetStream Enabled           │
            └───────────────┬──────────────────────┘
                           │
                           │ Distributes
                           ▼
            ┌────────────────────────────────────┐
            │   Worker Pool (Auto-scaling)       │
            │  ┌────────┐ ┌────────┐ ┌────────┐│
            │  │Worker 1│ │Worker 2│ │Worker N││
            │  └────────┘ └────────┘ └────────┘│
            │     Queue Group: webhook-workers   │
            └────────────────┬───────────────────┘
                             │
                             ▼
                   External Webhooks
```

### Component Sizing

**Small Deployment** (< 10K webhooks/day):
- NATS: 1 node, 2GB RAM, 2 vCPUs
- PostgreSQL: 1 instance, 4GB RAM, 2 vCPUs
- Workers: 2-3 instances, 1GB RAM each

**Medium Deployment** (10K-100K webhooks/day):
- NATS: 3 nodes, 4GB RAM, 4 vCPUs each
- PostgreSQL: Primary + 1 standby, 8GB RAM, 4 vCPUs
- Workers: 5-10 instances, 2GB RAM each

**Large Deployment** (> 100K webhooks/day):
- NATS: 3-5 nodes, 8GB RAM, 8 vCPUs each
- PostgreSQL: Primary + 2 standbys, 16GB+ RAM, 8+ vCPUs
- Workers: 10-50+ instances (auto-scaling), 2GB RAM each

## Infrastructure Requirements

### Compute Resources

**Minimum Requirements:**
- 3 servers total (1 PostgreSQL, 1 NATS, 1 worker)
- 8GB RAM total
- 4 vCPUs total
- 50GB disk

**Recommended Production:**
- 7+ servers (1 PG primary, 1 PG standby, 3 NATS nodes, 2+ workers)
- 48GB+ RAM total
- 20+ vCPUs total
- 500GB+ disk (SSD recommended)

### Network Requirements

- **Latency:** < 10ms between components (same datacenter)
- **Bandwidth:** 100+ Mbps (1 Gbps recommended)
- **Ports:**
  - PostgreSQL: 5432
  - NATS: 4222 (client), 6222 (cluster), 8222 (monitoring)
  - Workers: Outbound HTTPS (443)

### Operating System

- **Recommended:** Ubuntu 22.04 LTS, Debian 12, RHEL 9
- **Docker:** 20.10+
- **Kubernetes:** 1.24+ (if using K8s)

## NATS Cluster Setup

### Single Node (Development)

```bash
# Using Docker
docker run -d --name nats \
  -p 4222:4222 \
  -p 8222:8222 \
  -v $(pwd)/nats-data:/data \
  nats:latest \
  -js \
  -sd /data \
  -m 8222
```

### 3-Node Cluster (Production)

**Node 1:**
```bash
docker run -d --name nats-1 \
  --network nats-cluster \
  -p 4222:4222 \
  -p 8222:8222 \
  -v /data/nats-1:/data \
  nats:latest \
  -js \
  -sd /data \
  -cluster nats://0.0.0.0:6222 \
  -cluster_name PROD \
  -m 8222
```

**Node 2:**
```bash
docker run -d --name nats-2 \
  --network nats-cluster \
  -p 4223:4222 \
  -v /data/nats-2:/data \
  nats:latest \
  -js \
  -sd /data \
  -cluster nats://0.0.0.0:6222 \
  -cluster_name PROD \
  -routes nats://nats-1:6222
```

**Node 3:**
```bash
docker run -d --name nats-3 \
  --network nats-cluster \
  -p 4224:4222 \
  -v /data/nats-3:/data \
  nats:latest \
  -js \
  -sd /data \
  -cluster nats://0.0.0.0:6222 \
  -cluster_name PROD \
  -routes nats://nats-1:6222,nats://nats-2:6222
```

**Verify Cluster:**
```bash
nats server ls
# Should show 3 servers

nats server report jetstream
# Should show JetStream info for all nodes
```

### NATS Configuration File

Create `nats-server.conf`:

```
# Server name
server_name: nats-prod-1

# Network
port: 4222
max_payload: 2MB
max_pending: 64MB
write_deadline: "10s"

# Monitoring
http_port: 8222

# Clustering
cluster {
  name: PROD
  port: 6222
  routes: [
    nats://nats-1:6222
    nats://nats-2:6222
    nats://nats-3:6222
  ]
}

# JetStream
jetstream {
  store_dir: /data
  max_memory_store: 1GB
  max_file_store: 10GB
}

# Logging
debug: false
trace: false
logtime: true
log_file: "/var/log/nats/nats-server.log"

# Security
authorization {
  token: $NATS_TOKEN
}
```

Use with:
```bash
docker run -d --name nats \
  -v $(pwd)/nats-server.conf:/etc/nats/nats-server.conf \
  -v /data/nats:/data \
  nats:latest \
  -c /etc/nats/nats-server.conf
```

## PostgreSQL Setup

### Installation

```bash
# Install PostgreSQL 15
sudo apt update
sudo apt install postgresql-15 postgresql-contrib-15

# Or use Docker
docker run -d --name postgres \
  -e POSTGRES_PASSWORD=secure_password \
  -v postgres-data:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:15
```

### Install Rule Engine Extension

```bash
# Build and install extension
cd rule-engine-postgre-extensions
cargo pgrx install --release

# Or copy pre-built extension
sudo cp target/release/rule_engine.so /usr/lib/postgresql/15/lib/
sudo cp sql/*.sql /usr/share/postgresql/15/extension/
```

### Configure PostgreSQL

Edit `/etc/postgresql/15/main/postgresql.conf`:

```
# Memory
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 64MB
maintenance_work_mem = 1GB

# WAL
wal_level = replica
max_wal_size = 4GB
checkpoint_completion_target = 0.9

# Connections
max_connections = 200
shared_preload_libraries = 'pg_stat_statements'

# Performance
random_page_cost = 1.1  # For SSD
effective_io_concurrency = 200
```

### Create Database and Apply Migrations

```bash
# Create database
psql -U postgres -c "CREATE DATABASE webhooks_prod;"

# Create extension
psql -U postgres -d webhooks_prod -c "CREATE EXTENSION rule_engine;"

# Apply migrations
psql -U postgres -d webhooks_prod -f migrations/001_initial_schema.sql
psql -U postgres -d webhooks_prod -f migrations/002_builtin_functions.sql
# ... all migrations ...
psql -U postgres -d webhooks_prod -f migrations/007_nats_integration.sql
```

### Configure NATS Connection

```sql
-- Update NATS configuration
UPDATE rule_nats_config
SET nats_url = 'nats://nats-1:4222,nats-2:4222,nats-3:4222',
    max_connections = 50,
    auth_token = 'your_secure_token'
WHERE config_name = 'default';

-- Initialize connection
SELECT rule_nats_init('default');

-- Verify
SELECT rule_nats_health_check('default');
```

## Worker Deployment

### Docker Image (Node.js)

Create `Dockerfile`:

```dockerfile
FROM node:18-alpine

WORKDIR /app

COPY examples/nats-workers/nodejs/package*.json ./
RUN npm ci --production

COPY examples/nats-workers/nodejs/ ./

USER node

CMD ["node", "worker.js"]
```

Build:
```bash
docker build -t webhook-worker:latest -f Dockerfile .
```

### Docker Image (Go)

Already provided at `examples/nats-workers/go/Dockerfile`

Build:
```bash
cd examples/nats-workers/go
docker build -t webhook-worker-go:latest .
```

### Run Workers

```bash
# Start multiple workers
for i in {1..5}; do
  docker run -d \
    --name worker-$i \
    --network prod-network \
    -e NATS_URL="nats://nats-1:4222,nats-2:4222,nats-3:4222" \
    -e DATABASE_URL="postgresql://user:pass@postgres:5432/webhooks_prod" \
    -e CONSUMER_NAME="worker-$i" \
    -e QUEUE_GROUP="webhook-workers" \
    --restart unless-stopped \
    webhook-worker:latest
done
```

## Docker Deployment

### Docker Compose (Full Stack)

Create `docker-compose.prod.yml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: webhooks_prod
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    networks:
      - prod-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER"]
      interval: 10s
      timeout: 5s
      retries: 5

  nats-1:
    image: nats:latest
    command: [
      "-js",
      "-sd", "/data",
      "-cluster", "nats://0.0.0.0:6222",
      "-cluster_name", "PROD",
      "-m", "8222"
    ]
    ports:
      - "4222:4222"
      - "8222:8222"
    volumes:
      - nats-1-data:/data
    networks:
      - prod-network
    restart: unless-stopped

  nats-2:
    image: nats:latest
    command: [
      "-js",
      "-sd", "/data",
      "-cluster", "nats://0.0.0.0:6222",
      "-cluster_name", "PROD",
      "-routes", "nats://nats-1:6222",
      "-m", "8223"
    ]
    volumes:
      - nats-2-data:/data
    networks:
      - prod-network
    restart: unless-stopped
    depends_on:
      - nats-1

  nats-3:
    image: nats:latest
    command: [
      "-js",
      "-sd", "/data",
      "-cluster", "nats://0.0.0.0:6222",
      "-cluster_name", "PROD",
      "-routes", "nats://nats-1:6222,nats://nats-2:6222",
      "-m", "8224"
    ]
    volumes:
      - nats-3-data:/data
    networks:
      - prod-network
    restart: unless-stopped
    depends_on:
      - nats-1
      - nats-2

  worker:
    image: webhook-worker:latest
    environment:
      NATS_URL: nats://nats-1:4222,nats-2:4222,nats-3:4222
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/webhooks_prod
      QUEUE_GROUP: webhook-workers
    networks:
      - prod-network
    restart: unless-stopped
    depends_on:
      - postgres
      - nats-1
      - nats-2
      - nats-3
    deploy:
      replicas: 5

  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    networks:
      - prod-network
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD}
    volumes:
      - grafana-data:/var/lib/grafana
    ports:
      - "3000:3000"
    networks:
      - prod-network
    restart: unless-stopped

networks:
  prod-network:
    driver: bridge

volumes:
  postgres-data:
  nats-1-data:
  nats-2-data:
  nats-3-data:
  prometheus-data:
  grafana-data:
```

Deploy:
```bash
# Create .env file
cat > .env <<EOF
POSTGRES_USER=webhooks
POSTGRES_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PASSWORD=$(openssl rand -base64 16)
EOF

# Start stack
docker-compose -f docker-compose.prod.yml up -d

# Check status
docker-compose -f docker-compose.prod.yml ps

# View logs
docker-compose -f docker-compose.prod.yml logs -f worker
```

## Kubernetes Deployment

### Namespace

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: webhooks
```

### NATS StatefulSet

```yaml
# nats-statefulset.yaml
apiVersion: v1
kind: Service
metadata:
  name: nats
  namespace: webhooks
spec:
  selector:
    app: nats
  clusterIP: None
  ports:
    - name: client
      port: 4222
    - name: cluster
      port: 6222
    - name: monitor
      port: 8222
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nats
  namespace: webhooks
spec:
  serviceName: nats
  replicas: 3
  selector:
    matchLabels:
      app: nats
  template:
    metadata:
      labels:
        app: nats
    spec:
      containers:
        - name: nats
          image: nats:latest
          args:
            - "-js"
            - "-sd"
            - "/data"
            - "-cluster"
            - "nats://0.0.0.0:6222"
            - "-cluster_name"
            - "K8S"
            - "-routes"
            - "nats://nats-0.nats:6222,nats://nats-1.nats:6222,nats://nats-2.nats:6222"
            - "-m"
            - "8222"
          ports:
            - containerPort: 4222
              name: client
            - containerPort: 6222
              name: cluster
            - containerPort: 8222
              name: monitor
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "2000m"
              memory: "4Gi"
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
```

### Worker Deployment

```yaml
# worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webhook-worker
  namespace: webhooks
spec:
  replicas: 5
  selector:
    matchLabels:
      app: webhook-worker
  template:
    metadata:
      labels:
        app: webhook-worker
    spec:
      containers:
        - name: worker
          image: webhook-worker:latest
          env:
            - name: NATS_URL
              value: "nats://nats-0.nats:4222,nats://nats-1.nats:4222,nats://nats-2.nats:4222"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: connection-string
            - name: CONSUMER_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: QUEUE_GROUP
              value: "webhook-workers"
          resources:
            requests:
              cpu: "200m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "1Gi"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webhook-worker-hpa
  namespace: webhooks
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webhook-worker
  minReplicas: 3
  maxReplicas: 50
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

Deploy to Kubernetes:
```bash
kubectl apply -f namespace.yaml
kubectl apply -f nats-statefulset.yaml
kubectl apply -f worker-deployment.yaml

# Check status
kubectl get pods -n webhooks
kubectl get hpa -n webhooks
```

## Security

### NATS Authentication

**Token-based:**
```bash
# Generate secure token
TOKEN=$(openssl rand -base64 32)

# Start NATS with token
docker run -d --name nats \
  -e NATS_TOKEN=$TOKEN \
  nats:latest \
  -auth $TOKEN
```

**User/Password:**
```
# nats-server.conf
authorization {
  users = [
    {user: "webhook_user", password: "$2a$11$..."}  # bcrypt hash
  ]
}
```

### TLS/SSL

Generate certificates:
```bash
# Generate CA
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -out ca.pem

# Generate server cert
openssl genrsa -out server-key.pem 4096
openssl req -new -key server-key.pem -out server.csr
openssl x509 -req -days 365 -in server.csr -CA ca.pem -CAkey ca-key.pem -out server.pem
```

Configure NATS:
```
tls {
  cert_file: "/certs/server.pem"
  key_file: "/certs/server-key.pem"
  ca_file: "/certs/ca.pem"
  verify: true
}
```

### PostgreSQL Security

```sql
-- Create dedicated user
CREATE USER webhook_worker WITH PASSWORD 'secure_password';

-- Grant minimal permissions
GRANT CONNECT ON DATABASE webhooks_prod TO webhook_worker;
GRANT SELECT ON rule_nats_config TO webhook_worker;
GRANT SELECT ON rule_webhooks TO webhook_worker;
GRANT INSERT ON rule_nats_publish_history TO webhook_worker;
GRANT UPDATE ON rule_nats_consumer_stats TO webhook_worker;

-- Enable SSL
-- Edit postgresql.conf:
-- ssl = on
-- ssl_cert_file = '/path/to/server.crt'
-- ssl_key_file = '/path/to/server.key'
```

## Monitoring & Alerting

### Prometheus Configuration

`prometheus.yml`:
```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'nats'
    static_configs:
      - targets: ['nats-1:8222', 'nats-2:8222', 'nats-3:8222']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']
```

### Key Metrics to Monitor

**NATS:**
- `nats_core_connections` - Active connections
- `nats_jetstream_messages` - Message count
- `nats_jetstream_bytes` - Storage usage

**PostgreSQL:**
- `pg_stat_database_tup_inserted` - Inserts/sec
- `pg_stat_database_conflicts` - Conflicts
- Connection count

**Workers:**
- Message processing rate
- Error rate
- Average latency

### Grafana Dashboards

Import dashboards:
- NATS JetStream: Dashboard ID 15196
- PostgreSQL: Dashboard ID 9628

### Alerts

```yaml
# alerting-rules.yml
groups:
  - name: nats
    rules:
      - alert: NATSHighMessageBacklog
        expr: nats_jetstream_messages > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "NATS message backlog is high"

      - alert: NATSNoActiveWorkers
        expr: sum(nats_consumer_active) == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "No active NATS workers"

  - name: webhooks
    rules:
      - alert: HighWebhookFailureRate
        expr: rate(webhook_failures_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Webhook failure rate > 10%"
```

## Backup & Recovery

### NATS Backup

```bash
# Backup JetStream state
nats stream backup WEBHOOKS /backups/webhooks-$(date +%Y%m%d).tar.gz

# Restore
nats stream restore WEBHOOKS /backups/webhooks-20240115.tar.gz
```

### PostgreSQL Backup

```bash
# Full backup
pg_dump -U postgres -d webhooks_prod -F c -f /backups/webhooks-$(date +%Y%m%d).dump

# Backup specific tables
pg_dump -U postgres -d webhooks_prod -t rule_webhooks -t rule_nats_config -F c -f /backups/config-$(date +%Y%m%d).dump

# Restore
pg_restore -U postgres -d webhooks_prod /backups/webhooks-20240115.dump
```

### Automated Backups

```bash
# Cron job (daily at 2 AM)
0 2 * * * /usr/local/bin/backup-webhooks.sh
```

`backup-webhooks.sh`:
```bash
#!/bin/bash
DATE=$(date +%Y%m%d)
BACKUP_DIR=/backups

# Backup PostgreSQL
pg_dump -U postgres -d webhooks_prod -F c -f $BACKUP_DIR/pg-$DATE.dump

# Backup NATS
nats stream backup WEBHOOKS $BACKUP_DIR/nats-$DATE.tar.gz

# Upload to S3
aws s3 cp $BACKUP_DIR/pg-$DATE.dump s3://my-backups/
aws s3 cp $BACKUP_DIR/nats-$DATE.tar.gz s3://my-backups/

# Cleanup old backups (keep 30 days)
find $BACKUP_DIR -name "*.dump" -mtime +30 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete
```

## Scaling

### Horizontal Scaling

**Add Workers:**
```bash
# Docker
docker run -d --name worker-6 ... webhook-worker:latest

# Kubernetes
kubectl scale deployment webhook-worker --replicas=10 -n webhooks
```

**Auto-scaling (Kubernetes):**
Already configured in HPA above. Scales based on CPU/memory.

**Custom Metrics Scaling:**
```yaml
# Scale based on NATS queue depth
metrics:
  - type: External
    external:
      metric:
        name: nats_jetstream_messages
      target:
        type: Value
        value: "1000"  # Scale when > 1000 messages
```

### Vertical Scaling

**Increase Resources:**
```yaml
# Kubernetes
resources:
  requests:
    cpu: "1000m"      # Was 200m
    memory: "2Gi"     # Was 256Mi
  limits:
    cpu: "4000m"      # Was 1000m
    memory: "8Gi"     # Was 1Gi
```

## High Availability

### NATS HA

- Deploy 3 or 5 nodes (odd number)
- Use clustered mode
- Configure automatic failover

### PostgreSQL HA

**Streaming Replication:**
```bash
# On primary
# Edit postgresql.conf
wal_level = replica
max_wal_senders = 3

# On standby
# Create recovery.conf
primary_conninfo = 'host=primary port=5432 user=replicator'
hot_standby = on
```

**Automated Failover (Patroni):**
- Use Patroni for automatic failover
- Integrates with etcd/Consul/Zookeeper
- Automatic leader election

### Load Balancing

**PostgreSQL:**
```
Primary (writes) ──┬─► Standby 1 (reads)
                   └─► Standby 2 (reads)
```

**NATS:**
Clients automatically balance across cluster nodes.

## Performance Optimization

See [NATS_INTEGRATION.md#performance-tuning](NATS_INTEGRATION.md#performance-tuning)

## Troubleshooting

### Check Component Health

```bash
# NATS
nats server ping
nats server report jetstream

# PostgreSQL
psql -c "SELECT 1"

# Workers
docker logs worker-1 --tail 100
```

### Common Issues

**High Latency:**
- Check network between components
- Review worker count
- Check NATS backlog

**Message Loss:**
- Verify JetStream enabled
- Check disk space
- Review acknowledgment settings

**Worker Crashes:**
- Check memory limits
- Review error logs
- Verify webhook endpoints

## Conclusion

This guide provides a production-ready deployment of:
✅ High-availability NATS cluster
✅ Replicated PostgreSQL
✅ Auto-scaling workers
✅ Monitoring and alerting
✅ Backup and recovery
✅ Security best practices

For support, see [NATS_INTEGRATION.md](NATS_INTEGRATION.md).
