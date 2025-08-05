# Monitoring Setup Guide

This comprehensive guide covers setting up monitoring, alerting, and observability for Fabstir nodes, applications, and smart contracts.

## Prerequisites

- Running Fabstir node or application
- Basic understanding of metrics and logging
- Access to monitoring infrastructure
- Knowledge of Prometheus/Grafana (helpful)

## Monitoring Architecture

### Overview
```
Metrics Sources → Collection → Storage → Visualization → Alerting
       ↓             ↓           ↓            ↓             ↓
   Node/App     Prometheus   InfluxDB     Grafana    PagerDuty
   Contracts    Loki         TimescaleDB  Datadog    Discord
   Chain        Jaeger                              Email
```

## Node Monitoring

### Metrics Collection
```javascript
import { MetricsCollector } from '@fabstir/monitoring';
import { register, Counter, Gauge, Histogram } from 'prom-client';

class NodeMetrics {
    constructor() {
        // Job processing metrics
        this.jobsProcessed = new Counter({
            name: 'fabstir_jobs_processed_total',
            help: 'Total number of jobs processed',
            labelNames: ['status', 'model']
        });
        
        this.jobProcessingTime = new Histogram({
            name: 'fabstir_job_processing_duration_seconds',
            help: 'Job processing duration in seconds',
            labelNames: ['model'],
            buckets: [1, 5, 10, 30, 60, 120, 300, 600]
        });
        
        this.activeJobs = new Gauge({
            name: 'fabstir_active_jobs',
            help: 'Number of currently active jobs',
            labelNames: ['model']
        });
        
        // Resource metrics
        this.gpuUtilization = new Gauge({
            name: 'fabstir_gpu_utilization_percent',
            help: 'GPU utilization percentage',
            labelNames: ['gpu_index']
        });
        
        this.gpuMemoryUsed = new Gauge({
            name: 'fabstir_gpu_memory_used_bytes',
            help: 'GPU memory used in bytes',
            labelNames: ['gpu_index']
        });
        
        // Economic metrics
        this.earnings = new Counter({
            name: 'fabstir_earnings_eth_total',
            help: 'Total earnings in ETH',
            labelNames: ['token']
        });
        
        this.stakingBalance = new Gauge({
            name: 'fabstir_staking_balance_eth',
            help: 'Current staking balance in ETH'
        });
        
        // Network metrics
        this.peersConnected = new Gauge({
            name: 'fabstir_peers_connected',
            help: 'Number of connected peers'
        });
        
        this.reputation = new Gauge({
            name: 'fabstir_reputation_score',
            help: 'Current reputation score'
        });
        
        // Start collectors
        this.startCollectors();
    }
    
    startCollectors() {
        // Collect system metrics every 15 seconds
        setInterval(() => this.collectSystemMetrics(), 15000);
        
        // Collect GPU metrics every 5 seconds
        setInterval(() => this.collectGPUMetrics(), 5000);
        
        // Collect economic metrics every minute
        setInterval(() => this.collectEconomicMetrics(), 60000);
    }
    
    async collectSystemMetrics() {
        try {
            // CPU and Memory
            const usage = await si.currentLoad();
            const mem = await si.mem();
            
            // Update Prometheus metrics
            systemCpuUsage.set(usage.currentLoad);
            systemMemoryUsage.set((mem.used / mem.total) * 100);
            
            // Disk usage
            const disks = await si.fsSize();
            disks.forEach(disk => {
                diskUsage.set({ mount: disk.mount }, disk.use);
            });
            
            // Network
            const network = await si.networkStats();
            network.forEach(iface => {
                networkBytesReceived.set({ interface: iface.iface }, iface.rx_bytes);
                networkBytesSent.set({ interface: iface.iface }, iface.tx_bytes);
            });
            
        } catch (error) {
            console.error('Failed to collect system metrics:', error);
        }
    }
    
    async collectGPUMetrics() {
        try {
            const gpus = await this.getGPUStats();
            
            gpus.forEach((gpu, index) => {
                this.gpuUtilization.set({ gpu_index: index }, gpu.utilization);
                this.gpuMemoryUsed.set({ gpu_index: index }, gpu.memoryUsed);
                this.gpuTemperature.set({ gpu_index: index }, gpu.temperature);
                this.gpuPowerDraw.set({ gpu_index: index }, gpu.powerDraw);
            });
            
        } catch (error) {
            console.error('Failed to collect GPU metrics:', error);
        }
    }
    
    async collectEconomicMetrics() {
        try {
            // Get staking balance
            const stake = await sdk.nodes.getStake();
            this.stakingBalance.set(parseFloat(ethers.formatEther(stake)));
            
            // Get reputation
            const reputation = await sdk.reputation.get(nodeAddress);
            this.reputation.set(reputation.score);
            
            // Get earnings (from local tracking)
            const earnings = await this.getEarningsFromDB();
            earnings.forEach(earning => {
                this.earnings.inc({
                    token: earning.token
                }, earning.amount);
            });
            
        } catch (error) {
            console.error('Failed to collect economic metrics:', error);
        }
    }
    
    // Job lifecycle tracking
    onJobStarted(jobId, model) {
        this.activeJobs.inc({ model });
        this.jobStartTimes.set(jobId, Date.now());
    }
    
    onJobCompleted(jobId, model, success) {
        this.activeJobs.dec({ model });
        
        const startTime = this.jobStartTimes.get(jobId);
        if (startTime) {
            const duration = (Date.now() - startTime) / 1000;
            this.jobProcessingTime.observe({ model }, duration);
            this.jobStartTimes.delete(jobId);
        }
        
        this.jobsProcessed.inc({
            status: success ? 'success' : 'failed',
            model
        });
    }
    
    // Expose metrics endpoint
    getMetrics() {
        return register.metrics();
    }
}

// Express endpoint for Prometheus
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await nodeMetrics.getMetrics());
});
```

### Health Checks
```javascript
class HealthChecker {
    constructor() {
        this.checks = new Map();
        this.setupChecks();
    }
    
    setupChecks() {
        // Node connectivity
        this.addCheck('node_connectivity', async () => {
            try {
                const blockNumber = await provider.getBlockNumber();
                return {
                    status: 'healthy',
                    blockNumber,
                    message: 'Connected to Base network'
                };
            } catch (error) {
                return {
                    status: 'unhealthy',
                    error: error.message
                };
            }
        });
        
        // Contract accessibility
        this.addCheck('contracts', async () => {
            try {
                await nodeRegistry.getTotalNodes();
                return { status: 'healthy' };
            } catch (error) {
                return {
                    status: 'unhealthy',
                    error: 'Cannot access contracts'
                };
            }
        });
        
        // GPU availability
        this.addCheck('gpu', async () => {
            const gpus = await this.checkGPUs();
            const healthy = gpus.every(gpu => gpu.status === 'available');
            
            return {
                status: healthy ? 'healthy' : 'degraded',
                gpus: gpus.length,
                details: gpus
            };
        });
        
        // Model availability
        this.addCheck('models', async () => {
            const models = await this.checkModels();
            return {
                status: models.length > 0 ? 'healthy' : 'unhealthy',
                available: models
            };
        });
        
        // Disk space
        this.addCheck('disk_space', async () => {
            const disk = await si.fsSize();
            const mainDisk = disk.find(d => d.mount === '/');
            const freePercent = (mainDisk.available / mainDisk.size) * 100;
            
            return {
                status: freePercent > 10 ? 'healthy' : 'unhealthy',
                freePercent: freePercent.toFixed(2),
                freeGB: (mainDisk.available / 1e9).toFixed(2)
            };
        });
    }
    
    addCheck(name, checkFunction) {
        this.checks.set(name, checkFunction);
    }
    
    async runAllChecks() {
        const results = {};
        let overallStatus = 'healthy';
        
        for (const [name, check] of this.checks) {
            try {
                results[name] = await check();
                
                if (results[name].status === 'unhealthy') {
                    overallStatus = 'unhealthy';
                } else if (results[name].status === 'degraded' && overallStatus === 'healthy') {
                    overallStatus = 'degraded';
                }
            } catch (error) {
                results[name] = {
                    status: 'unhealthy',
                    error: error.message
                };
                overallStatus = 'unhealthy';
            }
        }
        
        return {
            status: overallStatus,
            timestamp: new Date().toISOString(),
            checks: results
        };
    }
}

// Health endpoint
app.get('/health', async (req, res) => {
    const health = await healthChecker.runAllChecks();
    const httpStatus = health.status === 'healthy' ? 200 : 503;
    res.status(httpStatus).json(health);
});

// Readiness endpoint
app.get('/ready', async (req, res) => {
    const ready = await nodeManager.isReady();
    res.status(ready ? 200 : 503).json({ ready });
});
```

## Smart Contract Monitoring

### Event Monitoring
```javascript
class ContractMonitor {
    constructor(contracts) {
        this.contracts = contracts;
        this.eventMetrics = new Map();
        this.setupEventListeners();
    }
    
    setupEventListeners() {
        // NodeRegistry events
        this.contracts.nodeRegistry.on('NodeRegistered', (node, metadata) => {
            this.incrementEventMetric('node_registered');
            this.logEvent('NodeRegistered', { node, metadata });
        });
        
        this.contracts.nodeRegistry.on('NodeSlashed', (node, amount, reason) => {
            this.incrementEventMetric('node_slashed');
            this.alert('NodeSlashed', {
                severity: 'high',
                node,
                amount: ethers.formatEther(amount),
                reason
            });
        });
        
        // JobMarketplace events
        this.contracts.jobMarketplace.on('JobPosted', (jobId, renter, modelId, payment) => {
            this.incrementEventMetric('job_posted', { model: modelId });
            
            // Track job value
            jobValueMetric.observe(
                { model: modelId },
                parseFloat(ethers.formatEther(payment))
            );
        });
        
        this.contracts.jobMarketplace.on('JobCompleted', (jobId, resultCID) => {
            this.incrementEventMetric('job_completed');
            this.trackJobCompletion(jobId);
        });
        
        // PaymentEscrow events
        this.contracts.paymentEscrow.on('PaymentReleased', (jobId, host, amount) => {
            this.incrementEventMetric('payment_released');
            paymentReleasedMetric.inc({
                token: 'ETH'
            }, parseFloat(ethers.formatEther(amount)));
        });
        
        // Governance events
        this.contracts.governance.on('ProposalCreated', (proposalId, proposer) => {
            this.incrementEventMetric('proposal_created');
            this.logEvent('ProposalCreated', { proposalId, proposer });
        });
    }
    
    incrementEventMetric(eventName, labels = {}) {
        const metric = this.eventMetrics.get(eventName) || new Counter({
            name: `fabstir_contract_event_${eventName}_total`,
            help: `Total ${eventName} events`,
            labelNames: Object.keys(labels)
        });
        
        metric.inc(labels);
        this.eventMetrics.set(eventName, metric);
    }
    
    async trackJobCompletion(jobId) {
        try {
            const job = await this.contracts.jobMarketplace.getJob(jobId);
            const duration = job.completedAt - job.postedAt;
            
            jobCompletionTime.observe(
                { model: job.modelId },
                duration
            );
            
        } catch (error) {
            console.error('Failed to track job completion:', error);
        }
    }
}
```

### Gas Usage Tracking
```javascript
class GasTracker {
    constructor() {
        this.gasMetrics = {
            used: new Histogram({
                name: 'fabstir_gas_used',
                help: 'Gas used per transaction',
                labelNames: ['method', 'contract'],
                buckets: [21000, 50000, 100000, 200000, 500000, 1000000]
            }),
            
            price: new Gauge({
                name: 'fabstir_gas_price_gwei',
                help: 'Current gas price in gwei'
            }),
            
            cost: new Histogram({
                name: 'fabstir_transaction_cost_eth',
                help: 'Transaction cost in ETH',
                labelNames: ['method', 'contract'],
                buckets: [0.001, 0.01, 0.1, 1]
            })
        };
        
        this.startGasPriceMonitoring();
    }
    
    async trackTransaction(tx, method, contract) {
        const receipt = await tx.wait();
        
        // Track gas used
        this.gasMetrics.used.observe(
            { method, contract },
            receipt.gasUsed.toNumber()
        );
        
        // Calculate cost
        const gasPrice = receipt.effectiveGasPrice || tx.gasPrice;
        const cost = receipt.gasUsed.mul(gasPrice);
        
        this.gasMetrics.cost.observe(
            { method, contract },
            parseFloat(ethers.formatEther(cost))
        );
        
        return receipt;
    }
    
    async startGasPriceMonitoring() {
        setInterval(async () => {
            try {
                const feeData = await provider.getFeeData();
                const gasPriceGwei = parseFloat(
                    ethers.formatUnits(feeData.gasPrice, 'gwei')
                );
                
                this.gasMetrics.price.set(gasPriceGwei);
                
                // Alert on high gas prices
                if (gasPriceGwei > 100) {
                    this.alert('High gas price detected', {
                        price: gasPriceGwei,
                        severity: 'warning'
                    });
                }
                
            } catch (error) {
                console.error('Failed to fetch gas price:', error);
            }
        }, 30000); // Every 30 seconds
    }
}

// Usage
const gasTracker = new GasTracker();

// Wrap contract calls
async function trackedContractCall(contract, method, params, contractName) {
    const tx = await contract[method](...params);
    return await gasTracker.trackTransaction(tx, method, contractName);
}
```

## Application Monitoring

### Performance Monitoring
```javascript
import { performance } from 'perf_hooks';
import { StatsD } from 'node-statsd';

class PerformanceMonitor {
    constructor() {
        this.statsd = new StatsD({
            host: process.env.STATSD_HOST || 'localhost',
            port: 8125,
            prefix: 'fabstir.'
        });
        
        this.timings = new Map();
    }
    
    // Measure API endpoint performance
    middleware() {
        return (req, res, next) => {
            const start = performance.now();
            const path = req.route?.path || req.path;
            
            // Override res.end to capture timing
            const originalEnd = res.end;
            res.end = (...args) => {
                const duration = performance.now() - start;
                
                // Send metrics
                this.statsd.timing(`api.request.duration`, duration, [
                    `method:${req.method}`,
                    `path:${path}`,
                    `status:${res.statusCode}`
                ]);
                
                this.statsd.increment(`api.request.count`, 1, [
                    `method:${req.method}`,
                    `path:${path}`,
                    `status:${res.statusCode}`
                ]);
                
                // Log slow requests
                if (duration > 1000) {
                    console.warn(`Slow request: ${req.method} ${path} took ${duration}ms`);
                }
                
                originalEnd.apply(res, args);
            };
            
            next();
        };
    }
    
    // Measure async operations
    async measureAsync(name, operation, tags = []) {
        const start = performance.now();
        
        try {
            const result = await operation();
            const duration = performance.now() - start;
            
            this.statsd.timing(`operation.${name}.duration`, duration, tags);
            this.statsd.increment(`operation.${name}.success`, 1, tags);
            
            return result;
            
        } catch (error) {
            const duration = performance.now() - start;
            
            this.statsd.timing(`operation.${name}.duration`, duration, tags);
            this.statsd.increment(`operation.${name}.error`, 1, tags);
            
            throw error;
        }
    }
    
    // Track custom metrics
    recordMetric(name, value, type = 'gauge', tags = []) {
        switch (type) {
            case 'gauge':
                this.statsd.gauge(name, value, tags);
                break;
            case 'counter':
                this.statsd.increment(name, value, tags);
                break;
            case 'histogram':
                this.statsd.histogram(name, value, tags);
                break;
            case 'timing':
                this.statsd.timing(name, value, tags);
                break;
        }
    }
}

// Usage
const perfMonitor = new PerformanceMonitor();
app.use(perfMonitor.middleware());

// Measure database queries
const result = await perfMonitor.measureAsync(
    'database.query',
    () => db.query('SELECT * FROM jobs WHERE status = ?', ['active']),
    ['query:get_active_jobs']
);
```

### Error Tracking
```javascript
import * as Sentry from '@sentry/node';

class ErrorTracker {
    constructor() {
        // Initialize Sentry
        Sentry.init({
            dsn: process.env.SENTRY_DSN,
            environment: process.env.NODE_ENV,
            integrations: [
                new Sentry.Integrations.Http({ tracing: true }),
                new Sentry.Integrations.Express({ app })
            ],
            tracesSampleRate: 0.1,
            beforeSend(event, hint) {
                // Filter sensitive data
                if (event.request?.data) {
                    delete event.request.data.privateKey;
                    delete event.request.data.password;
                }
                return event;
            }
        });
        
        this.errorCounts = new Map();
    }
    
    trackError(error, context = {}) {
        // Increment error counter
        const errorType = error.constructor.name;
        const count = (this.errorCounts.get(errorType) || 0) + 1;
        this.errorCounts.set(errorType, count);
        
        // Send to Sentry with context
        Sentry.captureException(error, {
            tags: {
                component: context.component,
                severity: context.severity || 'error'
            },
            extra: context
        });
        
        // Log locally
        console.error(`[${errorType}] ${error.message}`, context);
        
        // Alert on critical errors
        if (context.severity === 'critical') {
            this.sendAlert({
                type: 'critical_error',
                error: error.message,
                context
            });
        }
        
        // Update metrics
        errorMetric.inc({
            type: errorType,
            severity: context.severity || 'error'
        });
    }
    
    // Express error handler
    errorHandler() {
        return (err, req, res, next) => {
            this.trackError(err, {
                component: 'api',
                path: req.path,
                method: req.method,
                userId: req.user?.id
            });
            
            res.status(err.status || 500).json({
                error: process.env.NODE_ENV === 'production' 
                    ? 'Internal server error' 
                    : err.message
            });
        };
    }
}
```

## Logging Infrastructure

### Structured Logging
```javascript
import winston from 'winston';
import { ElasticsearchTransport } from 'winston-elasticsearch';

class Logger {
    constructor() {
        this.logger = winston.createLogger({
            level: process.env.LOG_LEVEL || 'info',
            format: winston.format.combine(
                winston.format.timestamp(),
                winston.format.errors({ stack: true }),
                winston.format.json()
            ),
            defaultMeta: {
                service: 'fabstir-node',
                version: process.env.APP_VERSION,
                nodeId: process.env.NODE_ID
            },
            transports: [
                // Console output
                new winston.transports.Console({
                    format: winston.format.combine(
                        winston.format.colorize(),
                        winston.format.simple()
                    )
                }),
                
                // File output
                new winston.transports.File({
                    filename: 'logs/error.log',
                    level: 'error',
                    maxsize: 10485760, // 10MB
                    maxFiles: 5
                }),
                
                new winston.transports.File({
                    filename: 'logs/combined.log',
                    maxsize: 10485760,
                    maxFiles: 10
                }),
                
                // Elasticsearch
                new ElasticsearchTransport({
                    level: 'info',
                    clientOpts: {
                        node: process.env.ELASTICSEARCH_URL
                    },
                    index: 'fabstir-logs'
                })
            ]
        });
    }
    
    // Structured job logging
    logJob(event, jobId, details) {
        this.logger.info({
            event: `job.${event}`,
            jobId,
            ...details,
            timestamp: Date.now()
        });
    }
    
    // Performance logging
    logPerformance(operation, duration, metadata) {
        this.logger.info({
            event: 'performance',
            operation,
            duration,
            ...metadata
        });
    }
    
    // Audit logging
    logAudit(action, userId, details) {
        this.logger.info({
            event: 'audit',
            action,
            userId,
            ...details,
            timestamp: Date.now()
        });
    }
    
    // Context-aware logging
    child(context) {
        return this.logger.child(context);
    }
}

// Usage
const logger = new Logger();

// Job processing with structured logs
async function processJob(job) {
    const jobLogger = logger.child({ jobId: job.id, model: job.modelId });
    
    jobLogger.info('Job processing started');
    const start = Date.now();
    
    try {
        const result = await runInference(job);
        
        jobLogger.info('Job completed successfully', {
            duration: Date.now() - start,
            tokensUsed: result.tokensUsed
        });
        
        return result;
        
    } catch (error) {
        jobLogger.error('Job processing failed', {
            error: error.message,
            stack: error.stack,
            duration: Date.now() - start
        });
        
        throw error;
    }
}
```

### Log Aggregation
```javascript
// Fluentd configuration for log shipping
const fluentdConfig = `
<source>
  @type tail
  path /var/log/fabstir/*.log
  pos_file /var/log/fluentd/fabstir.pos
  tag fabstir.*
  <parse>
    @type json
    time_key timestamp
    time_format %Y-%m-%dT%H:%M:%S.%L%z
  </parse>
</source>

<filter fabstir.**>
  @type record_transformer
  <record>
    hostname "#{Socket.gethostname}"
    environment "${NODE_ENV}"
    node_id "${NODE_ID}"
  </record>
</filter>

<match fabstir.**>
  @type elasticsearch
  host elasticsearch.example.com
  port 9200
  index_name fabstir-logs-%Y.%m.%d
  type_name _doc
  buffer_type memory
  flush_interval 10s
  retry_limit 5
  retry_wait 1s
</match>
`;
```

## Alerting System

### Alert Manager
```javascript
class AlertManager {
    constructor() {
        this.channels = new Map();
        this.rules = new Map();
        this.alertHistory = [];
        
        this.setupChannels();
        this.setupRules();
    }
    
    setupChannels() {
        // Discord webhook
        this.addChannel('discord', new DiscordAlertChannel({
            webhookUrl: process.env.DISCORD_WEBHOOK_URL
        }));
        
        // Email
        this.addChannel('email', new EmailAlertChannel({
            smtp: process.env.SMTP_SERVER,
            from: 'alerts@fabstir.com',
            to: process.env.ALERT_EMAIL
        }));
        
        // PagerDuty
        this.addChannel('pagerduty', new PagerDutyAlertChannel({
            apiKey: process.env.PAGERDUTY_API_KEY,
            serviceId: process.env.PAGERDUTY_SERVICE_ID
        }));
        
        // Telegram
        this.addChannel('telegram', new TelegramAlertChannel({
            botToken: process.env.TELEGRAM_BOT_TOKEN,
            chatId: process.env.TELEGRAM_CHAT_ID
        }));
    }
    
    setupRules() {
        // Critical alerts
        this.addRule('node_down', {
            condition: (metrics) => metrics.health.status === 'unhealthy',
            severity: 'critical',
            channels: ['pagerduty', 'discord', 'email'],
            message: 'Node is down or unhealthy',
            cooldown: 300 // 5 minutes
        });
        
        // High severity
        this.addRule('high_error_rate', {
            condition: (metrics) => metrics.errorRate > 0.05, // 5% error rate
            severity: 'high',
            channels: ['discord', 'email'],
            message: 'High error rate detected',
            cooldown: 600
        });
        
        this.addRule('low_gpu_availability', {
            condition: (metrics) => metrics.gpuAvailable < 1,
            severity: 'high',
            channels: ['discord'],
            message: 'No GPUs available',
            cooldown: 300
        });
        
        // Medium severity
        this.addRule('low_disk_space', {
            condition: (metrics) => metrics.diskFreePercent < 10,
            severity: 'medium',
            channels: ['discord'],
            message: 'Low disk space warning',
            cooldown: 3600
        });
        
        this.addRule('high_gas_price', {
            condition: (metrics) => metrics.gasPrice > 100,
            severity: 'medium',
            channels: ['discord'],
            message: 'High gas prices detected',
            cooldown: 1800
        });
        
        // Low severity
        this.addRule('reputation_drop', {
            condition: (metrics) => metrics.reputationChange < -10,
            severity: 'low',
            channels: ['discord'],
            message: 'Reputation score decreased',
            cooldown: 3600
        });
    }
    
    async evaluateRules(metrics) {
        for (const [name, rule] of this.rules) {
            try {
                if (rule.condition(metrics)) {
                    await this.triggerAlert(name, rule, metrics);
                }
            } catch (error) {
                console.error(`Error evaluating rule ${name}:`, error);
            }
        }
    }
    
    async triggerAlert(name, rule, metrics) {
        // Check cooldown
        const lastAlert = this.alertHistory.find(a => a.name === name);
        if (lastAlert && Date.now() - lastAlert.timestamp < rule.cooldown * 1000) {
            return; // Still in cooldown
        }
        
        const alert = {
            name,
            severity: rule.severity,
            message: rule.message,
            metrics,
            timestamp: Date.now()
        };
        
        // Send to specified channels
        for (const channelName of rule.channels) {
            const channel = this.channels.get(channelName);
            if (channel) {
                await channel.send(alert);
            }
        }
        
        // Record alert
        this.alertHistory.push(alert);
        
        // Trim history
        if (this.alertHistory.length > 1000) {
            this.alertHistory = this.alertHistory.slice(-500);
        }
    }
}

// Alert channel implementations
class DiscordAlertChannel {
    constructor(config) {
        this.webhookUrl = config.webhookUrl;
    }
    
    async send(alert) {
        const embed = {
            title: `🚨 ${alert.severity.toUpperCase()}: ${alert.message}`,
            color: this.getSeverityColor(alert.severity),
            fields: [
                {
                    name: 'Alert',
                    value: alert.name,
                    inline: true
                },
                {
                    name: 'Time',
                    value: new Date(alert.timestamp).toISOString(),
                    inline: true
                }
            ],
            footer: {
                text: 'Fabstir Monitoring'
            }
        };
        
        await fetch(this.webhookUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ embeds: [embed] })
        });
    }
    
    getSeverityColor(severity) {
        const colors = {
            critical: 0xFF0000, // Red
            high: 0xFF8C00,     // Dark Orange
            medium: 0xFFD700,   // Gold
            low: 0x00CED1       // Dark Turquoise
        };
        return colors[severity] || 0x808080;
    }
}
```

## Dashboards

### Grafana Dashboard Configuration
```json
{
  "dashboard": {
    "title": "Fabstir Node Monitoring",
    "panels": [
      {
        "title": "Job Processing Rate",
        "targets": [
          {
            "expr": "rate(fabstir_jobs_processed_total[5m])",
            "legendFormat": "{{status}} - {{model}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Active Jobs",
        "targets": [
          {
            "expr": "fabstir_active_jobs",
            "legendFormat": "{{model}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "GPU Utilization",
        "targets": [
          {
            "expr": "fabstir_gpu_utilization_percent",
            "legendFormat": "GPU {{gpu_index}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Earnings",
        "targets": [
          {
            "expr": "fabstir_earnings_eth_total",
            "legendFormat": "{{token}}"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(fabstir_errors_total[5m]) / rate(fabstir_jobs_processed_total[5m])",
            "legendFormat": "Error Rate"
          }
        ],
        "type": "graph",
        "alert": {
          "conditions": [
            {
              "evaluator": {
                "params": [0.05],
                "type": "gt"
              }
            }
          ]
        }
      }
    ]
  }
}
```

### Custom Dashboard
```javascript
class MonitoringDashboard {
    constructor() {
        this.metrics = {};
        this.charts = new Map();
        this.setupWebSocket();
    }
    
    setupWebSocket() {
        this.io = require('socket.io')(server);
        
        this.io.on('connection', (socket) => {
            console.log('Dashboard client connected');
            
            // Send initial data
            socket.emit('metrics', this.getMetricsSnapshot());
            
            // Send updates every 5 seconds
            const interval = setInterval(() => {
                socket.emit('metrics', this.getMetricsSnapshot());
            }, 5000);
            
            socket.on('disconnect', () => {
                clearInterval(interval);
            });
        });
    }
    
    getMetricsSnapshot() {
        return {
            timestamp: Date.now(),
            node: {
                status: this.metrics.nodeStatus || 'unknown',
                uptime: process.uptime(),
                version: process.env.APP_VERSION
            },
            jobs: {
                active: this.metrics.activeJobs || 0,
                completed: this.metrics.completedJobs || 0,
                failed: this.metrics.failedJobs || 0,
                successRate: this.calculateSuccessRate()
            },
            resources: {
                cpu: this.metrics.cpuUsage || 0,
                memory: this.metrics.memoryUsage || 0,
                gpu: this.metrics.gpuUtilization || [],
                disk: this.metrics.diskUsage || 0
            },
            economics: {
                earnings: this.metrics.totalEarnings || 0,
                stake: this.metrics.stakingBalance || 0,
                reputation: this.metrics.reputationScore || 0
            },
            alerts: this.getRecentAlerts()
        };
    }
    
    calculateSuccessRate() {
        const total = (this.metrics.completedJobs || 0) + (this.metrics.failedJobs || 0);
        if (total === 0) return 100;
        return ((this.metrics.completedJobs || 0) / total) * 100;
    }
    
    getRecentAlerts() {
        return this.alertHistory
            .slice(-10)
            .map(alert => ({
                ...alert,
                age: Date.now() - alert.timestamp
            }));
    }
}

// Dashboard HTML
const dashboardHTML = `
<!DOCTYPE html>
<html>
<head>
    <title>Fabstir Node Dashboard</title>
    <script src="/socket.io/socket.io.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        .metric-card {
            background: #f5f5f5;
            padding: 20px;
            margin: 10px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }
        .status-healthy { color: #4caf50; }
        .status-degraded { color: #ff9800; }
        .status-unhealthy { color: #f44336; }
    </style>
</head>
<body>
    <div id="dashboard">
        <h1>Fabstir Node Monitoring</h1>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Node Status</h3>
                <div id="node-status" class="metric-value">-</div>
            </div>
            
            <div class="metric-card">
                <h3>Active Jobs</h3>
                <div id="active-jobs" class="metric-value">0</div>
            </div>
            
            <div class="metric-card">
                <h3>Success Rate</h3>
                <div id="success-rate" class="metric-value">0%</div>
            </div>
            
            <div class="metric-card">
                <h3>Total Earnings</h3>
                <div id="earnings" class="metric-value">0 ETH</div>
            </div>
        </div>
        
        <div class="charts">
            <canvas id="jobs-chart"></canvas>
            <canvas id="resources-chart"></canvas>
        </div>
        
        <div id="alerts">
            <h2>Recent Alerts</h2>
            <div id="alerts-list"></div>
        </div>
    </div>
    
    <script>
        const socket = io();
        
        socket.on('metrics', (data) => {
            updateDashboard(data);
        });
        
        function updateDashboard(data) {
            // Update status
            const statusEl = document.getElementById('node-status');
            statusEl.textContent = data.node.status;
            statusEl.className = 'metric-value status-' + data.node.status;
            
            // Update metrics
            document.getElementById('active-jobs').textContent = data.jobs.active;
            document.getElementById('success-rate').textContent = data.jobs.successRate.toFixed(1) + '%';
            document.getElementById('earnings').textContent = data.economics.earnings.toFixed(4) + ' ETH';
            
            // Update charts
            updateJobsChart(data.jobs);
            updateResourcesChart(data.resources);
            
            // Update alerts
            updateAlerts(data.alerts);
        }
    </script>
</body>
</html>
`;
```

## Best Practices

### 1. Metric Design
```javascript
// Good metric naming
const goodMetrics = {
    // Use consistent naming convention
    'fabstir_jobs_processed_total': 'Total jobs processed',
    'fabstir_job_duration_seconds': 'Job processing duration',
    'fabstir_gpu_memory_used_bytes': 'GPU memory usage',
    
    // Include units in metric names
    'fabstir_response_time_milliseconds': 'API response time',
    'fabstir_disk_free_gigabytes': 'Free disk space',
    
    // Use labels for dimensions
    'fabstir_errors_total{type="timeout",severity="high"}': 'Errors by type and severity'
};

// Avoid high cardinality
// Bad: user_id as label (millions of values)
// Good: user_tier as label (few values)
```

### 2. Alert Fatigue Prevention
```javascript
class SmartAlerting {
    constructor() {
        this.alertCounts = new Map();
        this.suppressionRules = [];
    }
    
    shouldAlert(alert) {
        // Implement alert suppression
        if (this.isDuplicate(alert)) return false;
        if (this.isFlapping(alert)) return false;
        if (this.isBusinessHours() && alert.severity === 'low') return false;
        if (this.recentlyAlerted(alert)) return false;
        
        return true;
    }
    
    isFlapping(alert) {
        const history = this.alertCounts.get(alert.name) || [];
        const recentCount = history.filter(
            t => Date.now() - t < 3600000 // Last hour
        ).length;
        
        return recentCount > 5; // More than 5 in an hour
    }
}
```

### 3. Data Retention
```javascript
// Prometheus retention policy
const prometheusConfig = `
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'fabstir-prod'
    
storage:
  tsdb:
    retention.time: 30d
    retention.size: 100GB
    
remote_write:
  - url: https://metrics-storage.example.com/write
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'fabstir_.*'
        action: keep
`;
```

## Troubleshooting

### Common Issues

#### High Memory Usage
```javascript
// Memory profiling
const v8 = require('v8');
const heapSnapshot = v8.writeHeapSnapshot();

// Memory leak detection
class MemoryMonitor {
    checkForLeaks() {
        const usage = process.memoryUsage();
        
        if (usage.heapUsed > 1e9) { // 1GB
            console.warn('High memory usage detected');
            
            // Force garbage collection if available
            if (global.gc) {
                global.gc();
            }
            
            // Log memory stats
            console.log({
                rss: (usage.rss / 1e6).toFixed(2) + ' MB',
                heapTotal: (usage.heapTotal / 1e6).toFixed(2) + ' MB',
                heapUsed: (usage.heapUsed / 1e6).toFixed(2) + ' MB',
                external: (usage.external / 1e6).toFixed(2) + ' MB'
            });
        }
    }
}
```

#### Missing Metrics
```bash
# Debug Prometheus scraping
curl http://localhost:3000/metrics

# Check Prometheus targets
curl http://prometheus:9090/api/v1/targets

# Verify metric exists
curl http://prometheus:9090/api/v1/query?query=fabstir_jobs_processed_total
```

## Next Steps

1. **[Performance Optimization](https://fabstir.com/docs/performance)** - Optimize based on metrics
2. **[Security Monitoring](https://fabstir.com/docs/security-monitoring)** - Security-focused monitoring
3. **[Alerting Playbooks](https://fabstir.com/docs/playbooks)** - Response procedures

## Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Dashboard Gallery](https://grafana.com/grafana/dashboards)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Monitoring Workshop Recording](https://fabstir.com/workshop/monitoring)

---

Need help with monitoring? Join our [DevOps Discord](https://discord.gg/fabstir-devops) →