# Scalability Patterns Best Practices

This guide covers architectural patterns and strategies for building scalable Fabstir infrastructure.

## Why It Matters

Scalability enables:
- **Growth handling** - Support increasing user demand
- **Cost efficiency** - Scale resources with demand
- **Performance consistency** - Maintain SLAs under load
- **Competitive advantage** - Handle more volume than competitors
- **Future-proofing** - Adapt to changing requirements

## Horizontal Scaling Patterns

### Node Fleet Architecture
```yaml
# Multi-region node deployment
architecture:
  regions:
    us-east-1:
      zones: [a, b, c]
      nodes_per_zone: 10
      models: ["gpt-4", "llama-2", "stable-diffusion"]
    eu-west-1:
      zones: [a, b]
      nodes_per_zone: 8
      models: ["gpt-4", "claude-2"]
    ap-southeast-1:
      zones: [a, b]
      nodes_per_zone: 5
      models: ["gpt-4", "llama-2"]
  
  load_balancing:
    strategy: "geo-proximity"
    health_check_interval: 10s
    failover_threshold: 3
  
  auto_scaling:
    min_nodes: 3
    max_nodes: 50
    target_utilization: 70%
    scale_up_cooldown: 300s
    scale_down_cooldown: 600s
```

### Load Balancer Implementation
```javascript
class DistributedLoadBalancer {
    constructor(config) {
        this.nodes = new Map();
        this.healthChecker = new HealthChecker();
        this.strategy = config.strategy || 'weighted-round-robin';
        this.geoIP = new GeoIPService();
    }
    
    async registerNode(nodeInfo) {
        const node = {
            id: nodeInfo.id,
            address: nodeInfo.address,
            region: nodeInfo.region,
            capacity: nodeInfo.capacity,
            models: new Set(nodeInfo.models),
            currentLoad: 0,
            healthy: true,
            performance: {
                latency: [],
                successRate: 1.0,
                throughput: 0
            }
        };
        
        this.nodes.set(node.id, node);
        
        // Start health monitoring
        this.healthChecker.monitor(node);
        
        console.log(`Node ${node.id} registered in ${node.region}`);
    }
    
    async selectNode(job) {
        const eligibleNodes = this.getEligibleNodes(job);
        
        if (eligibleNodes.length === 0) {
            throw new Error('No available nodes for job');
        }
        
        // Select based on strategy
        let selected;
        switch (this.strategy) {
            case 'geo-proximity':
                selected = await this.selectByGeoProximity(eligibleNodes, job);
                break;
            case 'least-loaded':
                selected = this.selectLeastLoaded(eligibleNodes);
                break;
            case 'weighted-round-robin':
                selected = this.selectWeightedRoundRobin(eligibleNodes);
                break;
            case 'performance-based':
                selected = this.selectByPerformance(eligibleNodes);
                break;
            default:
                selected = eligibleNodes[0];
        }
        
        // Update load
        selected.currentLoad++;
        
        return selected;
    }
    
    getEligibleNodes(job) {
        const eligible = [];
        
        for (const node of this.nodes.values()) {
            if (node.healthy &&
                node.models.has(job.modelId) &&
                node.currentLoad < node.capacity) {
                eligible.push(node);
            }
        }
        
        return eligible;
    }
    
    async selectByGeoProximity(nodes, job) {
        const clientLocation = await this.geoIP.locate(job.clientIP);
        
        // Calculate distances
        const nodesWithDistance = nodes.map(node => ({
            node,
            distance: this.calculateDistance(clientLocation, node.region)
        }));
        
        // Sort by distance
        nodesWithDistance.sort((a, b) => a.distance - b.distance);
        
        // Return closest node with capacity
        return nodesWithDistance[0].node;
    }
    
    selectLeastLoaded(nodes) {
        return nodes.reduce((least, node) => {
            const loadRatio = node.currentLoad / node.capacity;
            const leastRatio = least.currentLoad / least.capacity;
            return loadRatio < leastRatio ? node : least;
        });
    }
    
    selectByPerformance(nodes) {
        // Score nodes based on performance metrics
        const scored = nodes.map(node => ({
            node,
            score: this.calculatePerformanceScore(node)
        }));
        
        // Sort by score
        scored.sort((a, b) => b.score - a.score);
        
        return scored[0].node;
    }
    
    calculatePerformanceScore(node) {
        const { latency, successRate, throughput } = node.performance;
        
        // Average latency (lower is better)
        const avgLatency = latency.length > 0
            ? latency.reduce((a, b) => a + b) / latency.length
            : 100;
        
        // Normalize metrics
        const latencyScore = Math.max(0, 1 - avgLatency / 1000);
        const successScore = successRate;
        const throughputScore = Math.min(1, throughput / 100);
        
        // Weighted score
        return latencyScore * 0.4 + successScore * 0.4 + throughputScore * 0.2;
    }
}
```

### Auto-Scaling Implementation
```javascript
class AutoScaler {
    constructor(config) {
        this.config = config;
        this.metrics = new MetricsCollector();
        this.orchestrator = new NodeOrchestrator();
        this.predictor = new LoadPredictor();
    }
    
    async startAutoScaling() {
        // Monitor metrics
        setInterval(() => this.evaluateScaling(), 30000); // Every 30s
        
        // Predictive scaling
        setInterval(() => this.predictiveScale(), 300000); // Every 5m
    }
    
    async evaluateScaling() {
        const metrics = await this.collectMetrics();
        const decision = this.makeScalingDecision(metrics);
        
        if (decision.action !== 'none') {
            await this.executeScaling(decision);
        }
    }
    
    async collectMetrics() {
        return {
            avgCPU: await this.metrics.getAverageCPU(),
            avgMemory: await this.metrics.getAverageMemory(),
            avgGPU: await this.metrics.getAverageGPU(),
            queueDepth: await this.metrics.getQueueDepth(),
            responseTime: await this.metrics.getResponseTime(),
            errorRate: await this.metrics.getErrorRate(),
            activeNodes: await this.orchestrator.getActiveNodeCount()
        };
    }
    
    makeScalingDecision(metrics) {
        const { activeNodes } = metrics;
        const utilization = this.calculateUtilization(metrics);
        
        // Scale up conditions
        if (utilization > this.config.target_utilization * 1.1 ||
            metrics.queueDepth > 100 ||
            metrics.responseTime > 5000) {
            
            const newNodes = this.calculateScaleUpCount(metrics);
            if (activeNodes + newNodes <= this.config.max_nodes) {
                return {
                    action: 'scale-up',
                    count: newNodes,
                    reason: this.getScaleUpReason(metrics)
                };
            }
        }
        
        // Scale down conditions
        if (utilization < this.config.target_utilization * 0.5 &&
            metrics.queueDepth < 10 &&
            activeNodes > this.config.min_nodes) {
            
            const nodesToRemove = this.calculateScaleDownCount(metrics);
            return {
                action: 'scale-down',
                count: nodesToRemove,
                reason: 'Low utilization'
            };
        }
        
        return { action: 'none' };
    }
    
    calculateScaleUpCount(metrics) {
        // Base calculation on queue depth and response time
        let additionalNodes = 0;
        
        if (metrics.queueDepth > 100) {
            additionalNodes = Math.ceil(metrics.queueDepth / 50);
        }
        
        if (metrics.responseTime > 5000) {
            additionalNodes = Math.max(additionalNodes, 3);
        }
        
        // Apply scaling factor
        return Math.min(additionalNodes, 10); // Max 10 at a time
    }
    
    async executeScaling(decision) {
        console.log(`Executing ${decision.action}: ${decision.count} nodes`);
        console.log(`Reason: ${decision.reason}`);
        
        if (decision.action === 'scale-up') {
            await this.scaleUp(decision.count);
        } else if (decision.action === 'scale-down') {
            await this.scaleDown(decision.count);
        }
        
        // Record scaling event
        await this.recordScalingEvent(decision);
    }
    
    async scaleUp(count) {
        const instances = [];
        
        for (let i = 0; i < count; i++) {
            const instance = await this.orchestrator.launchNode({
                type: 'gpu.large',
                region: this.selectRegion(),
                models: this.selectModels()
            });
            
            instances.push(instance);
        }
        
        // Wait for nodes to be ready
        await this.waitForNodesReady(instances);
        
        return instances;
    }
    
    async predictiveScale() {
        // Use historical data to predict future load
        const prediction = await this.predictor.predictLoad(60); // 60 min ahead
        
        if (prediction.confidence > 0.8) {
            const currentCapacity = await this.getCurrentCapacity();
            const requiredCapacity = prediction.expectedLoad * 1.2; // 20% buffer
            
            if (requiredCapacity > currentCapacity) {
                const additionalCapacity = requiredCapacity - currentCapacity;
                const nodesToAdd = Math.ceil(additionalCapacity / this.config.node_capacity);
                
                console.log(`Predictive scaling: Adding ${nodesToAdd} nodes`);
                await this.scaleUp(nodesToAdd);
            }
        }
    }
}
```

## Data Scalability Patterns

### Sharding Strategy
```javascript
class DataShardingManager {
    constructor(shardCount = 16) {
        this.shardCount = shardCount;
        this.shards = new Map();
        this.replicaCount = 3;
        
        this.initializeShards();
    }
    
    initializeShards() {
        for (let i = 0; i < this.shardCount; i++) {
            this.shards.set(i, {
                id: i,
                primary: null,
                replicas: [],
                keyRange: this.calculateKeyRange(i),
                size: 0,
                operations: 0
            });
        }
    }
    
    calculateKeyRange(shardId) {
        const range = BigInt(2 ** 256) / BigInt(this.shardCount);
        return {
            start: range * BigInt(shardId),
            end: range * BigInt(shardId + 1) - 1n
        };
    }
    
    getShardForKey(key) {
        // Hash key to determine shard
        const hash = this.hashKey(key);
        const shardId = Number(hash % BigInt(this.shardCount));
        return this.shards.get(shardId);
    }
    
    hashKey(key) {
        const hash = crypto.createHash('sha256');
        hash.update(key);
        return BigInt('0x' + hash.digest('hex'));
    }
    
    async write(key, value) {
        const shard = this.getShardForKey(key);
        
        // Write to primary
        await this.writeToNode(shard.primary, key, value);
        
        // Replicate to replicas asynchronously
        const replicationPromises = shard.replicas.map(replica =>
            this.writeToNode(replica, key, value).catch(err => {
                console.error(`Replication failed to ${replica}:`, err);
                this.handleReplicationFailure(shard, replica);
            })
        );
        
        // Don't wait for replications
        Promise.all(replicationPromises);
        
        // Update metrics
        shard.operations++;
        shard.size += this.estimateSize(value);
        
        // Check if rebalancing needed
        if (shard.size > this.config.maxShardSize) {
            this.scheduleRebalancing(shard);
        }
    }
    
    async read(key, consistency = 'eventual') {
        const shard = this.getShardForKey(key);
        
        if (consistency === 'strong') {
            // Read from primary
            return await this.readFromNode(shard.primary, key);
        } else {
            // Read from any replica
            const nodes = [shard.primary, ...shard.replicas];
            const node = this.selectReadNode(nodes);
            return await this.readFromNode(node, key);
        }
    }
    
    async rebalanceShards() {
        console.log('Starting shard rebalancing...');
        
        // Calculate average shard size
        const totalSize = Array.from(this.shards.values())
            .reduce((sum, shard) => sum + shard.size, 0);
        const avgSize = totalSize / this.shardCount;
        
        // Find over/under loaded shards
        const overloaded = [];
        const underloaded = [];
        
        for (const shard of this.shards.values()) {
            if (shard.size > avgSize * 1.2) {
                overloaded.push(shard);
            } else if (shard.size < avgSize * 0.8) {
                underloaded.push(shard);
            }
        }
        
        // Migrate data
        for (const source of overloaded) {
            const target = underloaded.shift();
            if (!target) break;
            
            await this.migrateData(source, target, avgSize - target.size);
        }
    }
    
    async splitShard(shardId) {
        const shard = this.shards.get(shardId);
        console.log(`Splitting shard ${shardId}`);
        
        // Create new shard
        const newShardId = this.shardCount++;
        const newShard = {
            id: newShardId,
            primary: await this.allocateNode(),
            replicas: await this.allocateReplicas(),
            keyRange: this.splitKeyRange(shard.keyRange),
            size: 0,
            operations: 0
        };
        
        // Update original shard range
        shard.keyRange.end = newShard.keyRange.start - 1n;
        
        // Migrate half the data
        await this.migrateKeyRange(shard, newShard, newShard.keyRange);
        
        // Add new shard
        this.shards.set(newShardId, newShard);
        
        console.log(`Shard ${shardId} split into ${shardId} and ${newShardId}`);
    }
}
```

### Caching Layer
```javascript
class DistributedCache {
    constructor() {
        this.localCache = new LRU({ max: 10000, ttl: 300000 });
        this.redisCluster = new RedisCluster({
            nodes: [
                { host: 'redis-1', port: 6379 },
                { host: 'redis-2', port: 6379 },
                { host: 'redis-3', port: 6379 }
            ],
            redisOptions: {
                password: process.env.REDIS_PASSWORD,
                enableReadyCheck: true,
                maxRetriesPerRequest: 3
            }
        });
        this.cacheStats = new CacheStatistics();
    }
    
    async get(key, options = {}) {
        const startTime = Date.now();
        
        // L1: Local cache
        const local = this.localCache.get(key);
        if (local) {
            this.cacheStats.hit('local');
            return local;
        }
        
        // L2: Redis cluster
        try {
            const value = await this.redisCluster.get(key);
            if (value) {
                this.cacheStats.hit('redis');
                
                // Populate local cache
                this.localCache.set(key, value);
                
                return JSON.parse(value);
            }
        } catch (error) {
            console.error('Redis error:', error);
            this.cacheStats.error('redis');
        }
        
        // Cache miss
        this.cacheStats.miss();
        
        // Fetch from source if loader provided
        if (options.loader) {
            const value = await options.loader();
            await this.set(key, value, options.ttl);
            return value;
        }
        
        return null;
    }
    
    async set(key, value, ttl = 300) {
        // Set in both caches
        this.localCache.set(key, value);
        
        try {
            await this.redisCluster.setex(
                key,
                ttl,
                JSON.stringify(value)
            );
        } catch (error) {
            console.error('Redis set error:', error);
        }
    }
    
    async invalidate(pattern) {
        // Clear local cache
        for (const [key] of this.localCache.entries()) {
            if (key.match(pattern)) {
                this.localCache.delete(key);
            }
        }
        
        // Clear Redis
        const stream = this.redisCluster.scanStream({
            match: pattern,
            count: 100
        });
        
        stream.on('data', async (keys) => {
            if (keys.length) {
                await this.redisCluster.del(keys);
            }
        });
        
        return new Promise((resolve, reject) => {
            stream.on('end', resolve);
            stream.on('error', reject);
        });
    }
    
    async warmCache(keys) {
        console.log(`Warming cache with ${keys.length} keys`);
        
        const chunks = this.chunkArray(keys, 100);
        
        for (const chunk of chunks) {
            await Promise.all(
                chunk.map(key => this.get(key, {
                    loader: () => this.fetchFromSource(key)
                }))
            );
        }
    }
}
```

### Event-Driven Architecture
```javascript
class EventDrivenScalability {
    constructor() {
        this.eventBus = new EventBus();
        this.messageQueue = new MessageQueue();
        this.workflows = new Map();
    }
    
    async setupEventHandlers() {
        // Job events
        this.eventBus.on('job.posted', this.handleJobPosted.bind(this));
        this.eventBus.on('job.claimed', this.handleJobClaimed.bind(this));
        this.eventBus.on('job.completed', this.handleJobCompleted.bind(this));
        
        // Node events
        this.eventBus.on('node.registered', this.handleNodeRegistered.bind(this));
        this.eventBus.on('node.offline', this.handleNodeOffline.bind(this));
        
        // System events
        this.eventBus.on('system.overload', this.handleSystemOverload.bind(this));
    }
    
    async handleJobPosted(event) {
        // Fanout to multiple handlers asynchronously
        await Promise.all([
            this.notifyAvailableNodes(event),
            this.updateJobMetrics(event),
            this.checkAutoScaling(event),
            this.logAuditTrail(event)
        ]);
    }
    
    async notifyAvailableNodes(jobEvent) {
        const eligibleNodes = await this.findEligibleNodes(jobEvent.job);
        
        // Create notification tasks
        const notifications = eligibleNodes.map(node => ({
            type: 'job.available',
            nodeId: node.id,
            jobId: jobEvent.job.id,
            priority: this.calculatePriority(jobEvent.job, node)
        }));
        
        // Queue notifications
        await this.messageQueue.publishBatch('node-notifications', notifications);
    }
    
    defineWorkflow(name, steps) {
        const workflow = {
            name,
            steps: steps.map(step => ({
                ...step,
                retries: step.retries || 3,
                timeout: step.timeout || 30000,
                compensation: step.compensation || null
            }))
        };
        
        this.workflows.set(name, workflow);
    }
    
    async executeWorkflow(workflowName, context) {
        const workflow = this.workflows.get(workflowName);
        if (!workflow) {
            throw new Error(`Workflow ${workflowName} not found`);
        }
        
        const execution = {
            id: crypto.randomUUID(),
            workflow: workflowName,
            startTime: Date.now(),
            context,
            completedSteps: [],
            status: 'running'
        };
        
        try {
            for (const step of workflow.steps) {
                await this.executeStep(step, execution);
                execution.completedSteps.push(step.name);
            }
            
            execution.status = 'completed';
        } catch (error) {
            execution.status = 'failed';
            execution.error = error.message;
            
            // Run compensations
            await this.runCompensations(execution);
            
            throw error;
        }
        
        return execution;
    }
    
    async executeStep(step, execution) {
        let attempts = 0;
        
        while (attempts < step.retries) {
            try {
                const timeout = new Promise((_, reject) =>
                    setTimeout(() => reject(new Error('Step timeout')), step.timeout)
                );
                
                const result = await Promise.race([
                    step.handler(execution.context),
                    timeout
                ]);
                
                execution.context[step.name] = result;
                return result;
                
            } catch (error) {
                attempts++;
                if (attempts >= step.retries) {
                    throw error;
                }
                
                // Exponential backoff
                await new Promise(resolve =>
                    setTimeout(resolve, Math.pow(2, attempts) * 1000)
                );
            }
        }
    }
}
```

## Database Scalability

### Read Replica Pattern
```javascript
class DatabaseScaling {
    constructor() {
        this.master = null;
        this.readReplicas = [];
        this.connectionPool = new Map();
        this.loadBalancer = new ReadReplicaBalancer();
    }
    
    async initialize(config) {
        // Setup master
        this.master = await this.createConnection(config.master);
        
        // Setup read replicas
        for (const replicaConfig of config.replicas) {
            const replica = await this.createConnection(replicaConfig);
            this.readReplicas.push(replica);
        }
        
        // Setup replication monitoring
        this.startReplicationMonitoring();
    }
    
    async executeQuery(query, options = {}) {
        const isWrite = this.isWriteQuery(query);
        
        if (isWrite || options.consistency === 'strong') {
            // All writes go to master
            return await this.executeOnMaster(query);
        } else {
            // Reads can go to replicas
            const connection = await this.selectReadConnection(options);
            return await this.executeOnConnection(connection, query);
        }
    }
    
    isWriteQuery(query) {
        const writeKeywords = ['INSERT', 'UPDATE', 'DELETE', 'CREATE', 'ALTER', 'DROP'];
        const normalizedQuery = query.trim().toUpperCase();
        
        return writeKeywords.some(keyword => 
            normalizedQuery.startsWith(keyword)
        );
    }
    
    async selectReadConnection(options) {
        if (options.preferMaster) {
            return this.master;
        }
        
        // Filter healthy replicas
        const healthyReplicas = await this.getHealthyReplicas();
        
        if (healthyReplicas.length === 0) {
            console.warn('No healthy replicas, falling back to master');
            return this.master;
        }
        
        // Select based on load and lag
        return this.loadBalancer.select(healthyReplicas, {
            maxLag: options.maxLag || 1000, // 1 second default
            strategy: options.strategy || 'least-connections'
        });
    }
    
    async getHealthyReplicas() {
        const healthChecks = await Promise.all(
            this.readReplicas.map(async replica => ({
                replica,
                healthy: await this.checkReplicaHealth(replica),
                lag: await this.getReplicationLag(replica)
            }))
        );
        
        return healthChecks
            .filter(check => check.healthy && check.lag < 5000) // 5s max lag
            .map(check => check.replica);
    }
    
    async checkReplicaHealth(replica) {
        try {
            const result = await replica.query('SELECT 1');
            return result.rows.length === 1;
        } catch {
            return false;
        }
    }
    
    async getReplicationLag(replica) {
        try {
            const result = await replica.query(`
                SELECT EXTRACT(EPOCH FROM (NOW() - pg_last_xact_replay_timestamp())) * 1000 as lag_ms
            `);
            return result.rows[0].lag_ms || 0;
        } catch {
            return Infinity;
        }
    }
    
    startReplicationMonitoring() {
        setInterval(async () => {
            for (const replica of this.readReplicas) {
                const lag = await this.getReplicationLag(replica);
                
                if (lag > 10000) { // 10 seconds
                    console.error(`High replication lag on ${replica.host}: ${lag}ms`);
                    await this.handleHighLag(replica, lag);
                }
            }
        }, 10000); // Check every 10 seconds
    }
}
```

## Microservices Patterns

### Service Mesh Implementation
```javascript
class ServiceMesh {
    constructor() {
        this.services = new Map();
        this.circuitBreakers = new Map();
        this.rateLimiters = new Map();
        this.traces = new TraceCollector();
    }
    
    registerService(name, config) {
        const service = {
            name,
            instances: [],
            healthCheck: config.healthCheck,
            timeout: config.timeout || 30000,
            retries: config.retries || 3,
            circuitBreaker: new CircuitBreaker({
                threshold: 5,
                timeout: 60000
            }),
            rateLimiter: new RateLimiter({
                points: config.rateLimit || 1000,
                duration: 60
            })
        };
        
        this.services.set(name, service);
        this.setupServiceDiscovery(service);
    }
    
    async call(serviceName, method, params, options = {}) {
        const service = this.services.get(serviceName);
        if (!service) {
            throw new Error(`Service ${serviceName} not found`);
        }
        
        // Start trace
        const span = this.traces.startSpan(`${serviceName}.${method}`);
        
        try {
            // Check circuit breaker
            if (service.circuitBreaker.isOpen()) {
                throw new Error('Circuit breaker open');
            }
            
            // Rate limiting
            await service.rateLimiter.consume(options.clientId || 'default');
            
            // Select instance
            const instance = await this.selectInstance(service);
            
            // Execute with retry
            const result = await this.executeWithRetry(
                () => this.invokeService(instance, method, params),
                service.retries
            );
            
            service.circuitBreaker.success();
            span.finish();
            
            return result;
            
        } catch (error) {
            service.circuitBreaker.failure();
            span.setTag('error', true);
            span.log({ event: 'error', message: error.message });
            span.finish();
            
            throw error;
        }
    }
    
    async selectInstance(service) {
        // Get healthy instances
        const healthyInstances = [];
        
        for (const instance of service.instances) {
            if (await this.isHealthy(instance, service.healthCheck)) {
                healthyInstances.push(instance);
            }
        }
        
        if (healthyInstances.length === 0) {
            throw new Error('No healthy instances available');
        }
        
        // Load balance using power of two choices
        const choice1 = healthyInstances[Math.floor(Math.random() * healthyInstances.length)];
        const choice2 = healthyInstances[Math.floor(Math.random() * healthyInstances.length)];
        
        return choice1.load < choice2.load ? choice1 : choice2;
    }
    
    async executeWithRetry(fn, retries) {
        let lastError;
        
        for (let i = 0; i < retries; i++) {
            try {
                return await fn();
            } catch (error) {
                lastError = error;
                
                // Don't retry on client errors
                if (error.statusCode >= 400 && error.statusCode < 500) {
                    throw error;
                }
                
                // Exponential backoff
                if (i < retries - 1) {
                    await new Promise(resolve =>
                        setTimeout(resolve, Math.pow(2, i) * 100)
                    );
                }
            }
        }
        
        throw lastError;
    }
    
    setupServiceDiscovery(service) {
        // Watch for instance changes
        const watcher = this.consul.watch({
            method: this.consul.health.service,
            options: {
                service: service.name,
                passing: true
            }
        });
        
        watcher.on('change', (data) => {
            service.instances = data.map(entry => ({
                id: entry.Service.ID,
                address: entry.Service.Address,
                port: entry.Service.Port,
                load: 0
            }));
        });
        
        watcher.on('error', (err) => {
            console.error('Service discovery error:', err);
        });
    }
}
```

## Performance Patterns

### Resource Pooling
```javascript
class ResourcePool {
    constructor(factory, options = {}) {
        this.factory = factory;
        this.options = {
            min: options.min || 2,
            max: options.max || 10,
            acquireTimeout: options.acquireTimeout || 30000,
            idleTimeout: options.idleTimeout || 300000,
            evictionInterval: options.evictionInterval || 60000,
            ...options
        };
        
        this.available = [];
        this.inUse = new Set();
        this.waiting = [];
        this.creating = 0;
        
        this.initialize();
    }
    
    async initialize() {
        // Create minimum resources
        const promises = [];
        for (let i = 0; i < this.options.min; i++) {
            promises.push(this.createResource());
        }
        
        await Promise.all(promises);
        
        // Start eviction timer
        setInterval(() => this.evictIdle(), this.options.evictionInterval);
    }
    
    async acquire() {
        const startTime = Date.now();
        
        while (true) {
            // Try to get available resource
            const resource = this.available.shift();
            if (resource && !resource.destroyed) {
                resource.lastUsed = Date.now();
                this.inUse.add(resource);
                return resource;
            }
            
            // Check if we can create new resource
            if (this.canCreate()) {
                this.creating++;
                try {
                    const resource = await this.createResource();
                    resource.lastUsed = Date.now();
                    this.inUse.add(resource);
                    return resource;
                } finally {
                    this.creating--;
                }
            }
            
            // Check timeout
            if (Date.now() - startTime > this.options.acquireTimeout) {
                throw new Error('Resource acquisition timeout');
            }
            
            // Wait for resource
            await new Promise(resolve => {
                this.waiting.push(resolve);
            });
        }
    }
    
    release(resource) {
        this.inUse.delete(resource);
        
        if (resource.destroyed) {
            return;
        }
        
        // Notify waiting requests
        const waiter = this.waiting.shift();
        if (waiter) {
            waiter();
        }
        
        // Return to pool
        this.available.push(resource);
    }
    
    async destroy(resource) {
        resource.destroyed = true;
        this.inUse.delete(resource);
        
        const index = this.available.indexOf(resource);
        if (index !== -1) {
            this.available.splice(index, 1);
        }
        
        if (resource.cleanup) {
            await resource.cleanup();
        }
    }
    
    canCreate() {
        const total = this.available.length + this.inUse.size + this.creating;
        return total < this.options.max;
    }
    
    async createResource() {
        const resource = await this.factory();
        resource.createdAt = Date.now();
        resource.lastUsed = Date.now();
        resource.destroyed = false;
        
        return resource;
    }
    
    async evictIdle() {
        const now = Date.now();
        const toEvict = [];
        
        for (const resource of this.available) {
            if (now - resource.lastUsed > this.options.idleTimeout &&
                this.available.length + this.inUse.size > this.options.min) {
                toEvict.push(resource);
            }
        }
        
        for (const resource of toEvict) {
            await this.destroy(resource);
        }
    }
}
```

## Scalability Checklist

### Architecture
- [ ] Stateless services design
- [ ] Horizontal scaling capability
- [ ] Load balancing implemented
- [ ] Auto-scaling configured
- [ ] Service discovery setup
- [ ] Circuit breakers in place

### Data Layer
- [ ] Database sharding strategy
- [ ] Read replicas configured
- [ ] Caching layer implemented
- [ ] Event sourcing for audit
- [ ] Message queuing for async
- [ ] Data partitioning strategy

### Performance
- [ ] Resource pooling active
- [ ] Connection pooling configured
- [ ] Request batching implemented
- [ ] Async processing patterns
- [ ] Rate limiting in place
- [ ] CDN for static assets

### Monitoring
- [ ] Distributed tracing setup
- [ ] Metrics aggregation active
- [ ] Log centralization working
- [ ] Performance baselines set
- [ ] Capacity planning tools
- [ ] Alerting thresholds defined

## Anti-Patterns to Avoid

### ❌ Scalability Mistakes
```javascript
// Stateful services
class StatefulService {
    constructor() {
        this.sessions = {}; // In-memory state
    }
}

// Synchronous fanout
for (const service of services) {
    await service.process(data); // Sequential
}

// Unbounded queries
const allUsers = await db.query('SELECT * FROM users'); // No limit

// Single point of failure
const cache = new SingleNodeCache(); // Not distributed
```

### ✅ Scalable Patterns
```javascript
// Stateless services
class StatelessService {
    async process(data, sessionId) {
        const session = await redis.get(sessionId); // External state
    }
}

// Parallel processing
await Promise.all(
    services.map(service => service.process(data))
);

// Paginated queries
const users = await db.query(
    'SELECT * FROM users LIMIT $1 OFFSET $2',
    [pageSize, offset]
);

// Distributed systems
const cache = new RedisCluster(); // Distributed
```

## Testing Scalability

### Load Testing Framework
```javascript
class ScalabilityTest {
    async runTest(scenario) {
        const results = {
            throughput: [],
            latency: [],
            errors: [],
            resources: []
        };
        
        // Gradually increase load
        for (const stage of scenario.stages) {
            console.log(`Stage: ${stage.users} users for ${stage.duration}s`);
            
            const stageResults = await this.runStage(stage);
            results.throughput.push(stageResults.rps);
            results.latency.push(stageResults.p95);
            results.errors.push(stageResults.errorRate);
            results.resources.push(await this.getResourceUsage());
        }
        
        // Analyze results
        return this.analyzeScalability(results);
    }
    
    analyzeScalability(results) {
        // Check linear scalability
        const scalabilityIndex = this.calculateScalabilityIndex(
            results.throughput
        );
        
        // Find breaking point
        const breakingPoint = this.findBreakingPoint(
            results.latency,
            results.errors
        );
        
        return {
            scalabilityIndex,
            breakingPoint,
            maxThroughput: Math.max(...results.throughput),
            recommendations: this.generateRecommendations(results)
        };
    }
}
```

## Next Steps

1. Implement [Monitoring & Alerting](../operations/monitoring-alerting.md)
2. Review [Incident Response](../operations/incident-response.md) procedures
3. Study [Pricing Strategies](../economics/pricing-strategies.md) for scale
4. Set up [Backup & Recovery](../operations/backup-recovery.md) for resilience

## Additional Resources

- [Designing Data-Intensive Applications](https://dataintensive.net/)
- [Site Reliability Engineering](https://sre.google/books/)
- [Kubernetes Patterns](https://www.oreilly.com/library/view/kubernetes-patterns/9781492050278/)
- [Microservices Patterns](https://microservices.io/patterns/)

---

Remember: **Scale horizontally, fail gracefully.** Design for 10x growth from day one.