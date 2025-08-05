# Monitoring & Alerting Best Practices

This guide covers comprehensive monitoring and alerting strategies for Fabstir infrastructure operations.

## Why It Matters

Effective monitoring enables:
- **Early problem detection** - Fix issues before users notice
- **Performance optimization** - Identify bottlenecks and inefficiencies
- **Capacity planning** - Scale proactively based on trends
- **Incident response** - Quickly diagnose and resolve issues
- **Compliance** - Meet SLA and audit requirements

## Monitoring Architecture

### Four Golden Signals
```yaml
golden_signals:
  latency:
    description: "Time to process requests"
    metrics:
      - http_request_duration_seconds
      - job_processing_time_seconds
      - blockchain_transaction_time_seconds
    
  traffic:
    description: "Volume of requests"
    metrics:
      - http_requests_per_second
      - jobs_submitted_per_minute
      - active_websocket_connections
    
  errors:
    description: "Rate of failed requests"
    metrics:
      - http_error_rate
      - job_failure_rate
      - smart_contract_revert_rate
    
  saturation:
    description: "Resource utilization"
    metrics:
      - cpu_utilization_percent
      - memory_usage_percent
      - gpu_utilization_percent
      - queue_depth
```

### Metrics Collection Stack
```javascript
class MetricsCollector {
    constructor() {
        this.prometheus = new PrometheusClient();
        this.statsd = new StatsD({
            host: 'localhost',
            port: 8125,
            prefix: 'fabstir.'
        });
        this.customMetrics = new Map();
        this.aggregationInterval = 10000; // 10 seconds
    }
    
    // Initialize standard metrics
    initializeMetrics() {
        // Counter metrics
        this.jobsProcessed = new this.prometheus.Counter({
            name: 'fabstir_jobs_processed_total',
            help: 'Total number of jobs processed',
            labelNames: ['status', 'model', 'region']
        });
        
        // Gauge metrics
        this.activeJobs = new this.prometheus.Gauge({
            name: 'fabstir_active_jobs',
            help: 'Number of currently active jobs',
            labelNames: ['model', 'priority']
        });
        
        // Histogram metrics
        this.jobDuration = new this.prometheus.Histogram({
            name: 'fabstir_job_duration_seconds',
            help: 'Job processing duration in seconds',
            labelNames: ['model', 'success'],
            buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120]
        });
        
        // Summary metrics
        this.paymentAmount = new this.prometheus.Summary({
            name: 'fabstir_payment_amount_eth',
            help: 'Payment amounts in ETH',
            labelNames: ['token'],
            percentiles: [0.5, 0.9, 0.95, 0.99]
        });
    }
    
    // Record custom metrics
    recordMetric(name, value, labels = {}) {
        const metric = this.getOrCreateMetric(name);
        
        if (metric.type === 'counter') {
            metric.inc(labels, value);
        } else if (metric.type === 'gauge') {
            metric.set(labels, value);
        } else if (metric.type === 'histogram') {
            metric.observe(labels, value);
        }
        
        // Also send to StatsD for real-time dashboards
        this.statsd.gauge(name, value);
    }
    
    // Collect system metrics
    async collectSystemMetrics() {
        const metrics = {
            cpu: await this.getCPUMetrics(),
            memory: await this.getMemoryMetrics(),
            disk: await this.getDiskMetrics(),
            network: await this.getNetworkMetrics(),
            gpu: await this.getGPUMetrics()
        };
        
        // Record metrics
        this.recordMetric('system.cpu.usage', metrics.cpu.usage);
        this.recordMetric('system.memory.used', metrics.memory.used);
        this.recordMetric('system.memory.available', metrics.memory.available);
        this.recordMetric('system.disk.usage', metrics.disk.usage);
        this.recordMetric('system.network.rx_bytes', metrics.network.rxBytes);
        this.recordMetric('system.network.tx_bytes', metrics.network.txBytes);
        
        if (metrics.gpu) {
            metrics.gpu.forEach((gpu, index) => {
                this.recordMetric('system.gpu.utilization', gpu.utilization, { gpu: index });
                this.recordMetric('system.gpu.memory_used', gpu.memoryUsed, { gpu: index });
                this.recordMetric('system.gpu.temperature', gpu.temperature, { gpu: index });
            });
        }
        
        return metrics;
    }
    
    // Aggregate and push metrics
    startAggregation() {
        setInterval(async () => {
            try {
                // Collect all metrics
                const systemMetrics = await this.collectSystemMetrics();
                const appMetrics = await this.collectApplicationMetrics();
                const blockchainMetrics = await this.collectBlockchainMetrics();
                
                // Push to time series database
                await this.pushToTimeSeries({
                    timestamp: Date.now(),
                    system: systemMetrics,
                    application: appMetrics,
                    blockchain: blockchainMetrics
                });
                
            } catch (error) {
                console.error('Metrics collection error:', error);
                this.recordMetric('metrics.collection.errors', 1);
            }
        }, this.aggregationInterval);
    }
}
```

## Application Monitoring

### Request Tracing
```javascript
class DistributedTracing {
    constructor() {
        this.tracer = new OpenTelemetryTracer({
            serviceName: 'fabstir-node',
            exporterUrl: process.env.JAEGER_ENDPOINT
        });
    }
    
    // Middleware for HTTP tracing
    traceMiddleware() {
        return (req, res, next) => {
            const span = this.tracer.startSpan('http_request', {
                attributes: {
                    'http.method': req.method,
                    'http.url': req.url,
                    'http.target': req.path,
                    'user.id': req.user?.id,
                    'request.id': req.id
                }
            });
            
            // Add trace context to request
            req.span = span;
            req.traceId = span.context().traceId;
            
            // Trace response
            const originalSend = res.send;
            res.send = function(data) {
                span.setAttributes({
                    'http.status_code': res.statusCode,
                    'http.response_size': Buffer.byteLength(data)
                });
                
                if (res.statusCode >= 400) {
                    span.setStatus({ code: 2, message: 'HTTP error' });
                }
                
                span.end();
                return originalSend.call(this, data);
            };
            
            next();
        };
    }
    
    // Trace async operations
    async traceOperation(name, operation, attributes = {}) {
        const span = this.tracer.startSpan(name, { attributes });
        
        try {
            const result = await operation(span);
            span.setStatus({ code: 1 }); // OK
            return result;
        } catch (error) {
            span.setStatus({ code: 2, message: error.message });
            span.recordException(error);
            throw error;
        } finally {
            span.end();
        }
    }
    
    // Trace job processing
    async traceJob(job, processor) {
        return this.traceOperation(
            'job_processing',
            async (span) => {
                span.setAttributes({
                    'job.id': job.id,
                    'job.model': job.modelId,
                    'job.payment': job.payment,
                    'job.renter': job.renter
                });
                
                // Trace sub-operations
                const modelLoadSpan = this.tracer.startSpan('model_loading', {
                    parent: span
                });
                const model = await this.loadModel(job.modelId);
                modelLoadSpan.end();
                
                const inferenceSpan = this.tracer.startSpan('inference', {
                    parent: span
                });
                const result = await processor.process(model, job);
                inferenceSpan.end();
                
                return result;
            },
            {
                'job.priority': job.priority,
                'job.deadline': job.deadline
            }
        );
    }
}
```

### Health Checks
```javascript
class HealthCheckSystem {
    constructor() {
        this.checks = new Map();
        this.results = new Map();
        this.checkInterval = 30000; // 30 seconds
    }
    
    // Register health check
    registerCheck(name, check) {
        this.checks.set(name, {
            name,
            check,
            critical: check.critical || false,
            timeout: check.timeout || 5000
        });
    }
    
    // Standard health checks
    setupStandardChecks() {
        // Database connectivity
        this.registerCheck('database', {
            check: async () => {
                const start = Date.now();
                await db.query('SELECT 1');
                return {
                    status: 'healthy',
                    latency: Date.now() - start
                };
            },
            critical: true
        });
        
        // Redis connectivity
        this.registerCheck('redis', {
            check: async () => {
                const start = Date.now();
                await redis.ping();
                return {
                    status: 'healthy',
                    latency: Date.now() - start
                };
            },
            critical: true
        });
        
        // Blockchain connectivity
        this.registerCheck('blockchain', {
            check: async () => {
                const start = Date.now();
                const blockNumber = await provider.getBlockNumber();
                return {
                    status: 'healthy',
                    latency: Date.now() - start,
                    blockNumber
                };
            },
            critical: true
        });
        
        // Disk space
        this.registerCheck('disk_space', {
            check: async () => {
                const stats = await checkDiskSpace('/');
                const usagePercent = (stats.used / stats.total) * 100;
                
                return {
                    status: usagePercent < 80 ? 'healthy' : 
                           usagePercent < 90 ? 'warning' : 'critical',
                    usage: usagePercent,
                    available: stats.available
                };
            }
        });
        
        // Memory usage
        this.registerCheck('memory', {
            check: async () => {
                const mem = process.memoryUsage();
                const totalMem = os.totalmem();
                const usagePercent = (mem.rss / totalMem) * 100;
                
                return {
                    status: usagePercent < 80 ? 'healthy' : 
                           usagePercent < 90 ? 'warning' : 'critical',
                    usage: usagePercent,
                    rss: mem.rss,
                    heapUsed: mem.heapUsed
                };
            }
        });
        
        // Model availability
        this.registerCheck('models', {
            check: async () => {
                const requiredModels = ['gpt-4', 'llama-2-70b'];
                const available = await modelManager.getAvailableModels();
                const missing = requiredModels.filter(m => !available.includes(m));
                
                return {
                    status: missing.length === 0 ? 'healthy' : 'degraded',
                    available: available.length,
                    missing
                };
            }
        });
    }
    
    // Run all health checks
    async runHealthChecks() {
        const results = new Map();
        const promises = [];
        
        for (const [name, check] of this.checks) {
            promises.push(
                this.runSingleCheck(name, check)
                    .then(result => results.set(name, result))
            );
        }
        
        await Promise.all(promises);
        
        // Determine overall health
        const overallHealth = this.calculateOverallHealth(results);
        
        // Store results
        this.results = results;
        this.lastCheck = Date.now();
        
        return {
            status: overallHealth,
            timestamp: this.lastCheck,
            checks: Object.fromEntries(results)
        };
    }
    
    async runSingleCheck(name, check) {
        try {
            const timeout = new Promise((_, reject) => 
                setTimeout(() => reject(new Error('Health check timeout')), check.timeout)
            );
            
            const result = await Promise.race([check.check(), timeout]);
            
            return {
                name,
                status: result.status,
                timestamp: Date.now(),
                data: result
            };
        } catch (error) {
            return {
                name,
                status: 'unhealthy',
                timestamp: Date.now(),
                error: error.message
            };
        }
    }
    
    calculateOverallHealth(results) {
        let hasUnhealthy = false;
        let hasCriticalUnhealthy = false;
        let hasWarning = false;
        
        for (const [name, result] of results) {
            const check = this.checks.get(name);
            
            if (result.status === 'unhealthy') {
                hasUnhealthy = true;
                if (check.critical) {
                    hasCriticalUnhealthy = true;
                }
            } else if (result.status === 'warning') {
                hasWarning = true;
            }
        }
        
        if (hasCriticalUnhealthy) return 'critical';
        if (hasUnhealthy) return 'unhealthy';
        if (hasWarning) return 'degraded';
        return 'healthy';
    }
    
    // Health check endpoint
    getHealthEndpoint() {
        return async (req, res) => {
            const health = await this.runHealthChecks();
            
            const statusCode = 
                health.status === 'healthy' ? 200 :
                health.status === 'degraded' ? 200 :
                health.status === 'unhealthy' ? 503 :
                503; // critical
            
            res.status(statusCode).json(health);
        };
    }
}
```

### Log Aggregation
```javascript
class LogAggregationSystem {
    constructor() {
        this.winston = winston.createLogger({
            format: winston.format.combine(
                winston.format.timestamp(),
                winston.format.errors({ stack: true }),
                winston.format.json()
            ),
            defaultMeta: {
                service: 'fabstir-node',
                version: process.env.VERSION,
                environment: process.env.NODE_ENV
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
                    maxsize: 100 * 1024 * 1024, // 100MB
                    maxFiles: 10
                }),
                
                new winston.transports.File({
                    filename: 'logs/combined.log',
                    maxsize: 100 * 1024 * 1024,
                    maxFiles: 30
                }),
                
                // Elasticsearch
                new ElasticsearchTransport({
                    level: 'info',
                    clientOpts: {
                        node: process.env.ELASTICSEARCH_URL,
                        auth: {
                            username: process.env.ELASTIC_USER,
                            password: process.env.ELASTIC_PASS
                        }
                    },
                    index: 'fabstir-logs',
                    pipeline: 'fabstir-pipeline'
                })
            ]
        });
        
        // Structured logging helpers
        this.loggers = {
            job: this.createJobLogger(),
            security: this.createSecurityLogger(),
            performance: this.createPerformanceLogger(),
            audit: this.createAuditLogger()
        };
    }
    
    createJobLogger() {
        return {
            jobStarted: (job) => {
                this.winston.info('Job started', {
                    type: 'job_lifecycle',
                    jobId: job.id,
                    modelId: job.modelId,
                    renter: job.renter,
                    payment: job.payment,
                    timestamp: Date.now()
                });
            },
            
            jobCompleted: (job, result) => {
                this.winston.info('Job completed', {
                    type: 'job_lifecycle',
                    jobId: job.id,
                    duration: result.duration,
                    success: true,
                    gasUsed: result.gasUsed,
                    timestamp: Date.now()
                });
            },
            
            jobFailed: (job, error) => {
                this.winston.error('Job failed', {
                    type: 'job_lifecycle',
                    jobId: job.id,
                    error: error.message,
                    stack: error.stack,
                    timestamp: Date.now()
                });
            }
        };
    }
    
    createSecurityLogger() {
        return {
            authFailure: (attempt) => {
                this.winston.warn('Authentication failure', {
                    type: 'security',
                    subtype: 'auth_failure',
                    ip: attempt.ip,
                    user: attempt.user,
                    reason: attempt.reason,
                    timestamp: Date.now()
                });
            },
            
            suspiciousActivity: (activity) => {
                this.winston.warn('Suspicious activity detected', {
                    type: 'security',
                    subtype: 'suspicious_activity',
                    ...activity,
                    timestamp: Date.now()
                });
            },
            
            accessViolation: (violation) => {
                this.winston.error('Access violation', {
                    type: 'security',
                    subtype: 'access_violation',
                    ...violation,
                    timestamp: Date.now()
                });
            }
        };
    }
    
    createPerformanceLogger() {
        return {
            slowQuery: (query) => {
                this.winston.warn('Slow query detected', {
                    type: 'performance',
                    subtype: 'slow_query',
                    query: query.sql,
                    duration: query.duration,
                    timestamp: Date.now()
                });
            },
            
            highMemoryUsage: (usage) => {
                this.winston.warn('High memory usage', {
                    type: 'performance',
                    subtype: 'high_memory',
                    usage: usage,
                    timestamp: Date.now()
                });
            }
        };
    }
    
    // Log correlation
    correlateLogsWithTraces(traceId) {
        return winston.createLogger({
            ...this.winston.options,
            defaultMeta: {
                ...this.winston.options.defaultMeta,
                traceId
            }
        });
    }
    
    // Log parsing and analysis
    async analyzeLogs(query) {
        const client = new Client({
            node: process.env.ELASTICSEARCH_URL,
            auth: {
                username: process.env.ELASTIC_USER,
                password: process.env.ELASTIC_PASS
            }
        });
        
        const result = await client.search({
            index: 'fabstir-logs-*',
            body: {
                query: {
                    bool: {
                        must: query.must || [],
                        filter: [
                            {
                                range: {
                                    timestamp: {
                                        gte: query.startTime || 'now-1h',
                                        lte: query.endTime || 'now'
                                    }
                                }
                            }
                        ]
                    }
                },
                aggs: query.aggregations || {},
                sort: [{ timestamp: { order: 'desc' } }],
                size: query.size || 100
            }
        });
        
        return result.body;
    }
}
```

## Infrastructure Monitoring

### Blockchain Monitoring
```javascript
class BlockchainMonitor {
    constructor(provider, contracts) {
        this.provider = provider;
        this.contracts = contracts;
        this.lastProcessedBlock = 0;
        this.eventHandlers = new Map();
    }
    
    async startMonitoring() {
        // Get starting block
        this.lastProcessedBlock = await this.getStartingBlock();
        
        // Monitor new blocks
        this.provider.on('block', async (blockNumber) => {
            await this.processBlock(blockNumber);
        });
        
        // Monitor specific events
        this.setupEventMonitoring();
        
        // Monitor gas prices
        this.monitorGasPrices();
        
        // Monitor contract balances
        this.monitorContractBalances();
    }
    
    setupEventMonitoring() {
        // Job events
        this.contracts.jobMarketplace.on('JobPosted', async (...args) => {
            const event = args[args.length - 1];
            await this.handleJobPosted(event);
        });
        
        this.contracts.jobMarketplace.on('JobCompleted', async (...args) => {
            const event = args[args.length - 1];
            await this.handleJobCompleted(event);
        });
        
        // Node events
        this.contracts.nodeRegistry.on('NodeRegistered', async (...args) => {
            const event = args[args.length - 1];
            await this.handleNodeRegistered(event);
        });
        
        // Payment events
        this.contracts.paymentEscrow.on('PaymentReleased', async (...args) => {
            const event = args[args.length - 1];
            await this.handlePaymentReleased(event);
        });
        
        // Monitor for errors
        this.contracts.jobMarketplace.on('error', (error) => {
            console.error('Contract error:', error);
            this.recordMetric('blockchain.contract.errors', 1);
        });
    }
    
    async processBlock(blockNumber) {
        try {
            const block = await this.provider.getBlock(blockNumber);
            
            // Record block metrics
            this.recordMetric('blockchain.block.number', blockNumber);
            this.recordMetric('blockchain.block.gasUsed', block.gasUsed.toString());
            this.recordMetric('blockchain.block.transactions', block.transactions.length);
            
            // Check for reorgs
            if (blockNumber <= this.lastProcessedBlock) {
                console.warn(`Possible reorg detected at block ${blockNumber}`);
                await this.handleReorg(blockNumber);
            }
            
            // Process transactions
            for (const txHash of block.transactions) {
                await this.processTransaction(txHash);
            }
            
            this.lastProcessedBlock = blockNumber;
            
        } catch (error) {
            console.error(`Error processing block ${blockNumber}:`, error);
            this.recordMetric('blockchain.processing.errors', 1);
        }
    }
    
    async processTransaction(txHash) {
        const tx = await this.provider.getTransaction(txHash);
        const receipt = await this.provider.getTransactionReceipt(txHash);
        
        // Check if transaction is related to our contracts
        if (this.isOurContract(tx.to)) {
            // Record transaction metrics
            this.recordMetric('blockchain.transactions.processed', 1, {
                contract: this.getContractName(tx.to),
                status: receipt.status ? 'success' : 'failure'
            });
            
            if (!receipt.status) {
                // Transaction failed
                console.error(`Transaction failed: ${txHash}`);
                await this.analyzeFailedTransaction(tx, receipt);
            }
        }
    }
    
    async monitorGasPrices() {
        setInterval(async () => {
            try {
                const gasPrice = await this.provider.getGasPrice();
                const block = await this.provider.getBlock('latest');
                const baseFee = block.baseFeePerGas;
                
                this.recordMetric('blockchain.gas.price', 
                    parseFloat(ethers.formatUnits(gasPrice, 'gwei'))
                );
                
                if (baseFee) {
                    this.recordMetric('blockchain.gas.baseFee', 
                        parseFloat(ethers.formatUnits(baseFee, 'gwei'))
                    );
                }
                
                // Alert on high gas prices
                if (gasPrice > ethers.parseUnits('100', 'gwei')) {
                    await this.alert({
                        severity: 'warning',
                        title: 'High gas prices detected',
                        message: `Gas price: ${ethers.formatUnits(gasPrice, 'gwei')} gwei`
                    });
                }
                
            } catch (error) {
                console.error('Gas price monitoring error:', error);
            }
        }, 60000); // Every minute
    }
    
    async monitorContractBalances() {
        setInterval(async () => {
            try {
                for (const [name, contract] of Object.entries(this.contracts)) {
                    const balance = await this.provider.getBalance(contract.address);
                    
                    this.recordMetric('blockchain.contract.balance', 
                        parseFloat(ethers.formatEther(balance)),
                        { contract: name }
                    );
                    
                    // Alert on low balance
                    if (balance < ethers.parseEther('1')) {
                        await this.alert({
                            severity: 'warning',
                            title: `Low contract balance: ${name}`,
                            message: `Balance: ${ethers.formatEther(balance)} ETH`
                        });
                    }
                }
            } catch (error) {
                console.error('Balance monitoring error:', error);
            }
        }, 300000); // Every 5 minutes
    }
}
```

## Alerting System

### Alert Configuration
```javascript
class AlertingSystem {
    constructor() {
        this.channels = new Map();
        this.rules = new Map();
        this.activeAlerts = new Map();
        this.alertHistory = [];
    }
    
    // Configure alert channels
    setupChannels() {
        // Email channel
        this.addChannel('email', new EmailChannel({
            smtp: {
                host: process.env.SMTP_HOST,
                port: process.env.SMTP_PORT,
                secure: true,
                auth: {
                    user: process.env.SMTP_USER,
                    pass: process.env.SMTP_PASS
                }
            },
            from: 'alerts@fabstir.com',
            to: ['ops@fabstir.com']
        }));
        
        // Slack channel
        this.addChannel('slack', new SlackChannel({
            webhook: process.env.SLACK_WEBHOOK,
            channel: '#alerts',
            username: 'Fabstir Alerts'
        }));
        
        // PagerDuty channel
        this.addChannel('pagerduty', new PagerDutyChannel({
            routingKey: process.env.PAGERDUTY_KEY,
            client: 'Fabstir Monitoring',
            clientUrl: 'https://monitoring.fabstir.com'
        }));
        
        // Discord channel
        this.addChannel('discord', new DiscordChannel({
            webhook: process.env.DISCORD_WEBHOOK,
            username: 'Fabstir Bot',
            avatarUrl: 'https://fabstir.com/logo.png'
        }));
    }
    
    // Define alert rules
    defineAlertRules() {
        // High CPU usage
        this.addRule({
            name: 'high_cpu_usage',
            condition: 'avg(system.cpu.usage) > 80',
            duration: '5m',
            severity: 'warning',
            channels: ['slack', 'email'],
            message: 'CPU usage above 80% for 5 minutes',
            runbook: 'https://runbooks.fabstir.com/high-cpu'
        });
        
        // Critical CPU usage
        this.addRule({
            name: 'critical_cpu_usage',
            condition: 'avg(system.cpu.usage) > 95',
            duration: '2m',
            severity: 'critical',
            channels: ['pagerduty', 'slack'],
            message: 'CRITICAL: CPU usage above 95%',
            runbook: 'https://runbooks.fabstir.com/critical-cpu'
        });
        
        // Job queue depth
        this.addRule({
            name: 'high_queue_depth',
            condition: 'fabstir.queue.depth > 100',
            duration: '10m',
            severity: 'warning',
            channels: ['slack'],
            message: 'Job queue depth exceeds 100 for 10 minutes'
        });
        
        // Error rate
        this.addRule({
            name: 'high_error_rate',
            condition: 'rate(fabstir.jobs.failed[5m]) > 0.1',
            severity: 'critical',
            channels: ['pagerduty', 'slack', 'email'],
            message: 'Job error rate exceeds 10%'
        });
        
        // Smart contract reverts
        this.addRule({
            name: 'contract_reverts',
            condition: 'sum(blockchain.transactions.reverted[5m]) > 5',
            severity: 'critical',
            channels: ['pagerduty', 'discord'],
            message: 'Multiple smart contract reverts detected'
        });
        
        // Node offline
        this.addRule({
            name: 'node_offline',
            condition: 'up{job="fabstir-node"} == 0',
            duration: '2m',
            severity: 'critical',
            channels: ['pagerduty', 'slack'],
            message: 'Node is offline'
        });
        
        // Disk space
        this.addRule({
            name: 'low_disk_space',
            condition: 'system.disk.available < 10',
            severity: 'warning',
            channels: ['slack', 'email'],
            message: 'Less than 10GB disk space available'
        });
    }
    
    // Evaluate alert rules
    async evaluateRules() {
        for (const [name, rule] of this.rules) {
            try {
                const triggered = await this.evaluateCondition(rule);
                
                if (triggered && !this.activeAlerts.has(name)) {
                    await this.triggerAlert(name, rule);
                } else if (!triggered && this.activeAlerts.has(name)) {
                    await this.resolveAlert(name);
                }
            } catch (error) {
                console.error(`Error evaluating rule ${name}:`, error);
            }
        }
    }
    
    async triggerAlert(name, rule) {
        const alert = {
            id: crypto.randomUUID(),
            name,
            rule,
            triggeredAt: Date.now(),
            severity: rule.severity,
            status: 'active'
        };
        
        this.activeAlerts.set(name, alert);
        this.alertHistory.push(alert);
        
        // Send to configured channels
        for (const channelName of rule.channels) {
            const channel = this.channels.get(channelName);
            if (channel) {
                await channel.send({
                    ...alert,
                    message: rule.message,
                    runbook: rule.runbook,
                    source: 'Fabstir Monitoring'
                });
            }
        }
        
        // Log alert
        console.error(`ALERT: ${rule.message}`);
        
        // Record metric
        this.recordMetric('alerts.triggered', 1, {
            name,
            severity: rule.severity
        });
    }
    
    async resolveAlert(name) {
        const alert = this.activeAlerts.get(name);
        if (!alert) return;
        
        alert.resolvedAt = Date.now();
        alert.status = 'resolved';
        alert.duration = alert.resolvedAt - alert.triggeredAt;
        
        this.activeAlerts.delete(name);
        
        // Notify resolution
        const rule = this.rules.get(name);
        for (const channelName of rule.channels) {
            const channel = this.channels.get(channelName);
            if (channel && channel.sendResolution) {
                await channel.sendResolution({
                    ...alert,
                    message: `RESOLVED: ${rule.message}`,
                    duration: this.formatDuration(alert.duration)
                });
            }
        }
        
        console.log(`Alert resolved: ${name} (duration: ${alert.duration}ms)`);
    }
    
    // Implement alert fatigue prevention
    shouldSuppressAlert(name, rule) {
        const recentAlerts = this.alertHistory.filter(
            a => a.name === name && 
                 a.triggeredAt > Date.now() - 3600000 // Last hour
        );
        
        // Suppress if too many alerts
        if (recentAlerts.length > 5) {
            console.log(`Suppressing alert ${name} due to fatigue`);
            return true;
        }
        
        return false;
    }
}
```

### Alert Channels Implementation
```javascript
class SlackChannel {
    constructor(config) {
        this.webhook = config.webhook;
        this.channel = config.channel;
        this.username = config.username;
    }
    
    async send(alert) {
        const color = 
            alert.severity === 'critical' ? '#FF0000' :
            alert.severity === 'warning' ? '#FFA500' :
            '#00FF00';
        
        const payload = {
            channel: this.channel,
            username: this.username,
            attachments: [{
                color,
                title: `🚨 ${alert.severity.toUpperCase()}: ${alert.message}`,
                fields: [
                    {
                        title: 'Alert',
                        value: alert.name,
                        short: true
                    },
                    {
                        title: 'Time',
                        value: new Date(alert.triggeredAt).toISOString(),
                        short: true
                    },
                    {
                        title: 'Source',
                        value: alert.source || 'Unknown',
                        short: true
                    },
                    {
                        title: 'Environment',
                        value: process.env.NODE_ENV,
                        short: true
                    }
                ],
                footer: 'Fabstir Monitoring',
                ts: Math.floor(alert.triggeredAt / 1000)
            }]
        };
        
        if (alert.runbook) {
            payload.attachments[0].actions = [{
                type: 'button',
                text: 'View Runbook',
                url: alert.runbook
            }];
        }
        
        await fetch(this.webhook, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
    }
    
    async sendResolution(alert) {
        const payload = {
            channel: this.channel,
            username: this.username,
            attachments: [{
                color: '#00FF00',
                title: `✅ RESOLVED: ${alert.message}`,
                fields: [
                    {
                        title: 'Duration',
                        value: alert.duration,
                        short: true
                    },
                    {
                        title: 'Resolved At',
                        value: new Date(alert.resolvedAt).toISOString(),
                        short: true
                    }
                ],
                footer: 'Fabstir Monitoring',
                ts: Math.floor(alert.resolvedAt / 1000)
            }]
        };
        
        await fetch(this.webhook, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
    }
}

class PagerDutyChannel {
    constructor(config) {
        this.routingKey = config.routingKey;
        this.client = config.client;
    }
    
    async send(alert) {
        const payload = {
            routing_key: this.routingKey,
            event_action: 'trigger',
            dedup_key: alert.name,
            payload: {
                summary: alert.message,
                severity: this.mapSeverity(alert.severity),
                source: alert.source || 'fabstir-monitoring',
                component: 'fabstir-node',
                group: alert.rule.group || 'default',
                class: alert.name,
                custom_details: {
                    alert_id: alert.id,
                    environment: process.env.NODE_ENV,
                    region: process.env.AWS_REGION,
                    triggered_at: alert.triggeredAt
                }
            },
            links: alert.runbook ? [{
                href: alert.runbook,
                text: 'Runbook'
            }] : []
        };
        
        await fetch('https://events.pagerduty.com/v2/enqueue', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(payload)
        });
    }
    
    mapSeverity(severity) {
        const map = {
            critical: 'critical',
            warning: 'warning',
            info: 'info'
        };
        return map[severity] || 'error';
    }
}
```

## Dashboard Creation

### Grafana Dashboard Configuration
```json
{
  "dashboard": {
    "title": "Fabstir Node Operations",
    "panels": [
      {
        "title": "Job Processing Rate",
        "targets": [
          {
            "expr": "rate(fabstir_jobs_processed_total[5m])",
            "legendFormat": "{{status}}"
          }
        ],
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 }
      },
      {
        "title": "Active Jobs by Model",
        "targets": [
          {
            "expr": "fabstir_active_jobs",
            "legendFormat": "{{model}}"
          }
        ],
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 }
      },
      {
        "title": "System Resources",
        "targets": [
          {
            "expr": "system_cpu_usage",
            "legendFormat": "CPU %"
          },
          {
            "expr": "system_memory_used / system_memory_total * 100",
            "legendFormat": "Memory %"
          },
          {
            "expr": "system_gpu_utilization",
            "legendFormat": "GPU {{gpu}} %"
          }
        ],
        "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 }
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(fabstir_jobs_failed_total[5m]) / rate(fabstir_jobs_processed_total[5m]) * 100",
            "legendFormat": "Error %"
          }
        ],
        "alert": {
          "conditions": [
            {
              "evaluator": { "params": [5], "type": "gt" },
              "operator": { "type": "and" },
              "query": { "params": ["A", "5m", "now"] },
              "type": "query"
            }
          ]
        },
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 16 }
      }
    ],
    "refresh": "10s",
    "time": { "from": "now-1h", "to": "now" }
  }
}
```

### Custom Dashboard Implementation
```javascript
class MonitoringDashboard {
    constructor() {
        this.metrics = new MetricsStore();
        this.websocket = new WebSocketServer({ port: 8080 });
        this.updateInterval = 5000; // 5 seconds
    }
    
    async initialize() {
        // Setup WebSocket connections
        this.websocket.on('connection', (ws) => {
            console.log('Dashboard client connected');
            
            // Send initial data
            this.sendFullUpdate(ws);
            
            // Setup real-time updates
            const interval = setInterval(() => {
                if (ws.readyState === WebSocket.OPEN) {
                    this.sendUpdate(ws);
                } else {
                    clearInterval(interval);
                }
            }, this.updateInterval);
        });
        
        // Start metrics collection
        this.startMetricsCollection();
    }
    
    async sendFullUpdate(ws) {
        const data = {
            type: 'full_update',
            timestamp: Date.now(),
            metrics: await this.collectAllMetrics(),
            alerts: await this.getActiveAlerts(),
            health: await this.getHealthStatus()
        };
        
        ws.send(JSON.stringify(data));
    }
    
    async sendUpdate(ws) {
        const data = {
            type: 'update',
            timestamp: Date.now(),
            metrics: await this.collectRecentMetrics(),
            alerts: await this.getAlertChanges()
        };
        
        ws.send(JSON.stringify(data));
    }
    
    async collectAllMetrics() {
        return {
            jobs: {
                total: await this.metrics.get('jobs.total'),
                active: await this.metrics.get('jobs.active'),
                completed: await this.metrics.get('jobs.completed'),
                failed: await this.metrics.get('jobs.failed'),
                byModel: await this.metrics.getByLabel('jobs.by_model')
            },
            performance: {
                avgProcessingTime: await this.metrics.avg('job.processing_time'),
                p95ProcessingTime: await this.metrics.percentile('job.processing_time', 95),
                throughput: await this.metrics.rate('jobs.completed', '5m')
            },
            resources: {
                cpu: await this.metrics.get('system.cpu.usage'),
                memory: await this.metrics.get('system.memory.usage'),
                gpu: await this.metrics.getAll('system.gpu.*'),
                disk: await this.metrics.get('system.disk.usage')
            },
            blockchain: {
                gasPrice: await this.metrics.get('blockchain.gas.price'),
                blockNumber: await this.metrics.get('blockchain.block.number'),
                balance: await this.metrics.get('blockchain.contract.balance')
            }
        };
    }
    
    // Dashboard API endpoints
    setupAPI(app) {
        // Metrics endpoint
        app.get('/api/metrics/:metric', async (req, res) => {
            const { metric } = req.params;
            const { start, end, step } = req.query;
            
            const data = await this.metrics.getTimeSeries(metric, {
                start: parseInt(start) || Date.now() - 3600000,
                end: parseInt(end) || Date.now(),
                step: parseInt(step) || 60000
            });
            
            res.json(data);
        });
        
        // Alerts endpoint
        app.get('/api/alerts', async (req, res) => {
            const alerts = await this.getAlerts({
                status: req.query.status,
                severity: req.query.severity,
                limit: parseInt(req.query.limit) || 100
            });
            
            res.json(alerts);
        });
        
        // Health endpoint
        app.get('/api/health', async (req, res) => {
            const health = await healthChecker.runHealthChecks();
            res.status(health.status === 'healthy' ? 200 : 503).json(health);
        });
    }
}
```

## Monitoring Checklist

### Metrics Collection
- [ ] Application metrics instrumented
- [ ] System metrics collected
- [ ] Business metrics tracked
- [ ] Custom metrics defined
- [ ] Metric retention configured
- [ ] Aggregation rules set

### Logging
- [ ] Structured logging implemented
- [ ] Log levels appropriate
- [ ] Log aggregation working
- [ ] Log retention policies set
- [ ] Log parsing configured
- [ ] Security logs isolated

### Health Checks
- [ ] Endpoint exposed
- [ ] All dependencies checked
- [ ] Graceful degradation
- [ ] Health history tracked
- [ ] Integration with load balancer
- [ ] Automated remediation

### Alerting
- [ ] Alert rules defined
- [ ] Severity levels set
- [ ] Escalation paths clear
- [ ] Runbooks linked
- [ ] Alert fatigue prevented
- [ ] Testing procedures

### Dashboards
- [ ] Key metrics visible
- [ ] Real-time updates
- [ ] Historical trends
- [ ] Drill-down capability
- [ ] Mobile responsive
- [ ] Access controlled

## Anti-Patterns to Avoid

### ❌ Monitoring Mistakes
```javascript
// Too many metrics
metrics.record('every.single.function.call');

// Noisy alerts
if (cpu > 50) alert('CPU usage detected!');

// Missing context
logger.error('Error occurred');

// Synchronous metrics
const metrics = fs.readFileSync('metrics.json');

// No rate limiting
stream.on('data', data => metrics.inc('events'));
```

### ✅ Monitoring Best Practices
```javascript
// Meaningful metrics
metrics.record('job.completed', { model, duration });

// Actionable alerts
if (errorRate > 0.1 && duration > '5m') alert('High error rate');

// Contextual logging
logger.error('Job processing failed', { jobId, error, stack });

// Async metrics
await metrics.push('batch_metrics', batch);

// Rate limited collection
const limited = rateLimit(data => metrics.inc('events'), 1000);
```

## Monitoring Tools

### Essential Tools
- **Prometheus**: Time-series metrics
- **Grafana**: Visualization dashboards
- **Elasticsearch**: Log aggregation
- **Kibana**: Log analysis
- **Jaeger**: Distributed tracing
- **Alertmanager**: Alert routing

### Setup Scripts
```bash
# Deploy monitoring stack
docker-compose -f monitoring-stack.yml up -d

# Configure Prometheus
prometheus --config.file=prometheus.yml

# Import Grafana dashboards
curl -X POST http://admin:admin@localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboard.json

# Test alerts
amtool alert add alertname=test severity=warning
```

## Next Steps

1. Set up [Backup & Recovery](backup-recovery.md) procedures
2. Create [Incident Response](incident-response.md) playbooks
3. Review [Risk Management](../economics/risk-management.md) strategies
4. Implement [Pricing Strategies](../economics/pricing-strategies.md)

## Additional Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Dashboard Guide](https://grafana.com/docs/grafana/latest/dashboards/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [SRE Monitoring Guide](https://sre.google/sre-book/monitoring-distributed-systems/)

---

Remember: **You can't improve what you don't measure.** Comprehensive monitoring is the foundation of reliable operations.