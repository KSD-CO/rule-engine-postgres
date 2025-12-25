# Build stage
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

WORKDIR /build

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-s -w" -o webhook-worker .

# Runtime stage
FROM alpine:latest

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/webhook-worker .

# Create non-root user
RUN addgroup -g 1000 worker && \
    adduser -D -u 1000 -G worker worker && \
    chown -R worker:worker /app

USER worker

# Environment variables with defaults
ENV NATS_URL=nats://localhost:4222 \
    DATABASE_URL=postgresql://localhost/postgres?sslmode=disable \
    STREAM_NAME=WEBHOOKS \
    CONSUMER_NAME=webhook-worker-1 \
    QUEUE_GROUP=webhook-workers \
    SUBJECT=webhooks.* \
    BATCH_SIZE=10

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD pgrep -x webhook-worker || exit 1

# Run worker
CMD ["./webhook-worker"]
