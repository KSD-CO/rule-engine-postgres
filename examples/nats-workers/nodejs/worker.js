#!/usr/bin/env node

/**
 * NATS Webhook Worker (Node.js)
 *
 * This worker subscribes to NATS JetStream and processes webhook events
 * from the PostgreSQL rule engine.
 *
 * Features:
 * - JetStream consumer with queue group for load balancing
 * - Automatic acknowledgment and retry
 * - HTTP webhook execution
 * - Error handling and logging
 * - Statistics reporting back to PostgreSQL
 */

const { connect, StringCodec, AckPolicy } = require('nats');
const axios = require('axios');
const { Pool } = require('pg');

// Configuration from environment variables
const config = {
  nats: {
    servers: process.env.NATS_URL || 'nats://localhost:4222',
    user: process.env.NATS_USER,
    pass: process.env.NATS_PASS,
  },
  postgres: {
    connectionString: process.env.DATABASE_URL || 'postgresql://localhost/postgres',
  },
  worker: {
    streamName: process.env.STREAM_NAME || 'WEBHOOKS',
    consumerName: process.env.CONSUMER_NAME || 'webhook-worker-1',
    queueGroup: process.env.QUEUE_GROUP || 'webhook-workers',
    subject: process.env.SUBJECT || 'webhooks.*',
    batchSize: parseInt(process.env.BATCH_SIZE || '10'),
  },
};

// Statistics
const stats = {
  messagesProcessed: 0,
  messagesSucceeded: 0,
  messagesFailed: 0,
  totalProcessingTime: 0,
  startTime: Date.now(),
};

// PostgreSQL connection pool
const pgPool = new Pool({
  connectionString: config.postgres.connectionString,
});

// String codec for message encoding/decoding
const sc = StringCodec();

/**
 * Main worker function
 */
async function startWorker() {
  console.log('🚀 Starting NATS Webhook Worker');
  console.log('Configuration:', {
    nats: config.nats.servers,
    stream: config.worker.streamName,
    consumer: config.worker.consumerName,
    queue: config.worker.queueGroup,
    subject: config.worker.subject,
  });

  try {
    // Connect to NATS
    const nc = await connect({
      servers: config.nats.servers,
      user: config.nats.user,
      pass: config.nats.pass,
    });

    console.log(`✅ Connected to NATS at ${nc.getServer()}`);

    // Get JetStream context
    const js = nc.jetstream();

    // Ensure stream exists (optional - usually created by PostgreSQL)
    try {
      const stream = await js.streams.get(config.worker.streamName);
      console.log(`✅ Stream "${config.worker.streamName}" found`);
    } catch (err) {
      console.log(`⚠️  Stream "${config.worker.streamName}" not found - will be created by first publish`);
    }

    // Create or get consumer
    const consumer = await js.consumers.get(
      config.worker.streamName,
      config.worker.consumerName
    ).catch(async () => {
      // Consumer doesn't exist, create it
      console.log(`Creating consumer "${config.worker.consumerName}"...`);
      return await js.consumers.add(config.worker.streamName, {
        durable_name: config.worker.consumerName,
        ack_policy: AckPolicy.Explicit,
        filter_subject: config.worker.subject,
        deliver_group: config.worker.queueGroup,
        max_deliver: 3, // Max 3 delivery attempts
        ack_wait: 30_000_000_000, // 30 seconds in nanoseconds
      });
    });

    console.log(`✅ Consumer "${config.worker.consumerName}" ready`);

    // Start consuming messages
    console.log(`📥 Listening for messages on "${config.worker.subject}"...\n`);

    const messages = await consumer.consume({
      max_messages: config.worker.batchSize,
    });

    // Process messages
    for await (const msg of messages) {
      await processMessage(msg);
    }

  } catch (err) {
    console.error('❌ Fatal error:', err);
    process.exit(1);
  }
}

/**
 * Process a single NATS message
 */
async function processMessage(msg) {
  const startTime = Date.now();
  stats.messagesProcessed++;

  try {
    // Parse message payload
    const payload = JSON.parse(sc.decode(msg.data));
    const subject = msg.subject;

    console.log(`📨 [${stats.messagesProcessed}] Processing: ${subject}`);
    console.log(`   Payload:`, JSON.stringify(payload).substring(0, 100) + '...');

    // Extract webhook URL and data
    // Expected payload format: { webhook_url, data, headers }
    const webhookUrl = payload.webhook_url || payload.url;
    const webhookData = payload.data || payload;
    const webhookHeaders = payload.headers || { 'Content-Type': 'application/json' };

    if (!webhookUrl) {
      throw new Error('Missing webhook_url in payload');
    }

    // Make HTTP request
    const response = await axios({
      method: 'POST',
      url: webhookUrl,
      data: webhookData,
      headers: webhookHeaders,
      timeout: 30000, // 30 seconds
      validateStatus: (status) => status >= 200 && status < 500, // Don't throw on 4xx
    });

    const duration = Date.now() - startTime;

    if (response.status >= 200 && response.status < 300) {
      // Success
      console.log(`   ✅ Success: ${response.status} (${duration}ms)`);

      stats.messagesSucceeded++;
      stats.totalProcessingTime += duration;

      // Acknowledge message
      msg.ack();

    } else {
      // HTTP error (4xx, 5xx)
      console.log(`   ⚠️  HTTP Error: ${response.status} (${duration}ms)`);

      stats.messagesFailed++;

      // Negative acknowledge (will retry)
      msg.nak();
    }

  } catch (err) {
    const duration = Date.now() - startTime;

    console.error(`   ❌ Error: ${err.message} (${duration}ms)`);

    stats.messagesFailed++;

    // Negative acknowledge (will retry)
    msg.nak();
  }

  // Report statistics periodically
  if (stats.messagesProcessed % 100 === 0) {
    await reportStatistics();
  }
}

/**
 * Report statistics back to PostgreSQL
 */
async function reportStatistics() {
  try {
    const avgProcessingTime = stats.totalProcessingTime / stats.messagesSucceeded || 0;
    const uptime = Math.floor((Date.now() - stats.startTime) / 1000);

    console.log('\n📊 Statistics:', {
      processed: stats.messagesProcessed,
      succeeded: stats.messagesSucceeded,
      failed: stats.messagesFailed,
      avgTime: `${avgProcessingTime.toFixed(2)}ms`,
      uptime: `${uptime}s`,
    });

    // Update PostgreSQL consumer stats
    await pgPool.query(
      `SELECT rule_nats_consumer_update_stats($1, $2, $3, $4, $5, $6)`,
      [
        config.worker.streamName,
        config.worker.consumerName,
        stats.messagesProcessed,
        stats.messagesSucceeded,
        stats.messagesFailed,
        avgProcessingTime,
      ]
    );

    console.log('✅ Statistics reported to PostgreSQL\n');
  } catch (err) {
    console.error('⚠️  Failed to report statistics:', err.message);
  }
}

/**
 * Graceful shutdown
 */
async function shutdown(signal) {
  console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);

  // Report final statistics
  await reportStatistics();

  // Close PostgreSQL connection
  await pgPool.end();

  console.log('👋 Worker stopped');
  process.exit(0);
}

// Handle shutdown signals
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// Start the worker
startWorker().catch((err) => {
  console.error('❌ Worker failed:', err);
  process.exit(1);
});
