# Node Optimization Best Practices

This guide covers performance optimization strategies for running Fabstir nodes efficiently.

## Why It Matters

Node optimization impacts:
- **Job throughput** - Process more jobs per unit time
- **Resource efficiency** - Lower infrastructure costs
- **Response time** - Better user experience
- **Reliability** - Fewer failures and timeouts
- **Profitability** - Higher earnings with lower costs

## System Requirements Optimization

### Hardware Selection
```yaml
# Minimum Production Specifications
minimum:
  cpu: 8 cores @ 3.0GHz
  ram: 32GB DDR4
  storage: 1TB NVMe SSD
  network: 1Gbps dedicated
  gpu: NVIDIA RTX 3090 (24GB VRAM)

# Recommended Production Specifications  
recommended:
  cpu: 16 cores @ 3.5GHz (AMD EPYC or Intel Xeon)
  ram: 64GB DDR4 ECC
  storage: 2TB NVMe SSD (Samsung 980 Pro)
  network: 10Gbps dedicated
  gpu: NVIDIA A100 (40GB) or 2x RTX 4090

# High-Performance Specifications
enterprise:
  cpu: 32 cores @ 4.0GHz
  ram: 128GB DDR5
  storage: 4TB NVMe RAID 0
  network: 25Gbps dedicated
  gpu: 4x NVIDIA A100 (80GB) with NVLink
```

### Operating System Tuning
```bash
#!/bin/bash
# Ubuntu 22.04 performance tuning

# CPU Governor
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Disable CPU frequency scaling
systemctl disable ondemand

# Memory settings
cat >> /etc/sysctl.conf << EOF
# Increase system memory limits
vm.max_map_count = 262144
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Network optimizations
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# File descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152
EOF

# Apply settings
sysctl -p

# Increase ulimits
cat >> /etc/security/limits.conf << EOF
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
EOF

# NUMA optimization
numactl --hardware # Check NUMA topology
# Run node with NUMA binding
numactl --cpunodebind=0 --membind=0 ./fabstir-node

# Huge pages for better memory performance
echo 'vm.nr_hugepages = 1024' >> /etc/sysctl.conf
sysctl -p

# I/O scheduler optimization for NVMe
echo 'none' > /sys/block/nvme0n1/queue/scheduler

# GPU optimization
nvidia-smi -pm ENABLED
nvidia-smi -pl 350  # Set power limit
nvidia-smi -ac 1593,1708  # Set application clocks
```

## Node Software Optimization

### Configuration Tuning
```javascript
// optimized-config.js
module.exports = {
    // Connection pool settings
    connectionPool: {
        min: 10,
        max: 100,
        acquireTimeout: 30000,
        idleTimeout: 60000,
        reapInterval: 1000
    },
    
    // Worker settings
    workers: {
        // Use all available cores minus one for system
        count: require('os').cpus().length - 1,
        restartDelay: 5000,
        maxRestarts: 10,
        killTimeout: 30000
    },
    
    // Cache configuration
    cache: {
        // In-memory cache
        memory: {
            max: 10000,
            ttl: 300000, // 5 minutes
            updateAgeOnGet: true,
            checkperiod: 60000
        },
        
        // Redis cache
        redis: {
            host: 'localhost',
            port: 6379,
            db: 0,
            keyPrefix: 'fabstir:',
            enableOfflineQueue: true,
            connectTimeout: 10000,
            maxRetriesPerRequest: 3
        }
    },
    
    // Model loading
    models: {
        preload: ['gpt-4', 'llama-2-70b'], // Preload popular models
        maxLoaded: 5,
        unloadTimeout: 600000, // 10 minutes idle
        loadConcurrency: 2
    },
    
    // Request handling
    requests: {
        maxConcurrent: 20,
        queueSize: 100,
        timeout: 300000, // 5 minutes
        retries: 3,
        backoffMultiplier: 2
    }
};
```

### Memory Management
```javascript
class MemoryOptimizer {
    constructor() {
        this.heapSnapshots = [];
        this.gcStats = [];
        this.threshold = 0.85; // 85% memory usage threshold
    }
    
    startMonitoring() {
        // Monitor memory usage
        setInterval(() => {
            const usage = process.memoryUsage();
            const heapUsed = usage.heapUsed / usage.heapTotal;
            
            if (heapUsed > this.threshold) {
                this.handleHighMemory(usage);
            }
            
            // Collect GC stats
            const gcStats = {
                timestamp: Date.now(),
                heapUsed: usage.heapUsed,
                heapTotal: usage.heapTotal,
                external: usage.external,
                arrayBuffers: usage.arrayBuffers
            };
            
            this.gcStats.push(gcStats);
            
            // Keep only last hour
            const hourAgo = Date.now() - 3600000;
            this.gcStats = this.gcStats.filter(s => s.timestamp > hourAgo);
            
        }, 10000); // Every 10 seconds
        
        // Force GC periodically if available
        if (global.gc) {
            setInterval(() => {
                const before = process.memoryUsage().heapUsed;
                global.gc();
                const after = process.memoryUsage().heapUsed;
                
                console.log(`GC freed ${(before - after) / 1048576}MB`);
            }, 300000); // Every 5 minutes
        }
    }
    
    handleHighMemory(usage) {
        console.warn('High memory usage detected:', usage);
        
        // Clear caches
        this.clearCaches();
        
        // Unload unused models
        this.unloadIdleModels();
        
        // Force garbage collection
        if (global.gc) {
            global.gc();
        }
        
        // Take heap snapshot for analysis
        if (process.env.NODE_ENV === 'development') {
            this.takeHeapSnapshot();
        }
    }
    
    clearCaches() {
        // Clear various caches
        if (global.modelCache) {
            const cleared = global.modelCache.clear();
            console.log(`Cleared ${cleared} cached models`);
        }
        
        if (global.resultCache) {
            const cleared = global.resultCache.prune();
            console.log(`Cleared ${cleared} cached results`);
        }
    }
    
    async unloadIdleModels() {
        const models = await global.modelManager.getLoadedModels();
        const now = Date.now();
        
        for (const model of models) {
            if (now - model.lastUsed > 600000) { // 10 minutes idle
                await global.modelManager.unload(model.id);
                console.log(`Unloaded idle model: ${model.id}`);
            }
        }
    }
}

// Start with optimized V8 flags
// node --max-old-space-size=8192 --optimize-for-size --gc-interval=100 server.js
```

### GPU Optimization
```javascript
class GPUOptimizer {
    constructor() {
        this.cuda = require('cuda-runtime-api');
        this.devices = this.cuda.getDeviceCount();
        this.allocations = new Map();
    }
    
    async initialize() {
        console.log(`Found ${this.devices} GPU devices`);
        
        for (let i = 0; i < this.devices; i++) {
            const props = this.cuda.getDeviceProperties(i);
            console.log(`GPU ${i}: ${props.name}`);
            console.log(`  Memory: ${props.totalGlobalMem / 1e9}GB`);
            console.log(`  Compute: ${props.major}.${props.minor}`);
            
            // Set optimal configuration
            this.cuda.setDevice(i);
            this.cuda.setDeviceFlags(this.cuda.deviceScheduleBlockingSync);
            
            // Pre-allocate memory pools
            await this.createMemoryPool(i, props.totalGlobalMem * 0.8);
        }
    }
    
    async createMemoryPool(device, size) {
        // Memory pool for efficient allocation
        const pool = {
            device,
            total: size,
            allocated: 0,
            blocks: []
        };
        
        // Pre-allocate large blocks
        const blockSize = 1e9; // 1GB blocks
        const numBlocks = Math.floor(size / blockSize);
        
        for (let i = 0; i < numBlocks; i++) {
            const block = await this.cuda.mallocAsync(blockSize, device);
            pool.blocks.push({
                ptr: block,
                size: blockSize,
                used: false
            });
        }
        
        this.allocations.set(device, pool);
    }
    
    async allocateForModel(modelSize, device = 0) {
        const pool = this.allocations.get(device);
        
        // Find suitable block
        for (const block of pool.blocks) {
            if (!block.used && block.size >= modelSize) {
                block.used = true;
                pool.allocated += modelSize;
                return block.ptr;
            }
        }
        
        throw new Error('Insufficient GPU memory');
    }
    
    optimizeBatchSize(modelConfig) {
        // Calculate optimal batch size based on available memory
        const device = modelConfig.device || 0;
        const props = this.cuda.getDeviceProperties(device);
        const availableMemory = props.totalGlobalMem - this.getAllocated(device);
        
        // Model memory requirements
        const paramsMemory = modelConfig.parameters * 4; // 4 bytes per param
        const activationMemory = modelConfig.activationSize;
        const perSampleMemory = activationMemory * modelConfig.sequenceLength;
        
        // Calculate max batch size
        const maxBatchSize = Math.floor(
            (availableMemory - paramsMemory) / perSampleMemory
        );
        
        // Round down to power of 2 for efficiency
        return Math.pow(2, Math.floor(Math.log2(maxBatchSize)));
    }
}
```

## Request Processing Optimization

### Efficient Job Queue
```javascript
class OptimizedJobQueue {
    constructor() {
        this.queues = new Map(); // Priority queues
        this.processing = new Set();
        this.workers = [];
        this.stats = new StatsCollector();
    }
    
    async initialize(workerCount) {
        // Create worker pool
        for (let i = 0; i < workerCount; i++) {
            const worker = new Worker('./job-worker.js', {
                workerData: { id: i }
            });
            
            worker.on('message', this.handleWorkerMessage.bind(this));
            worker.on('error', this.handleWorkerError.bind(this));
            
            this.workers.push({
                id: i,
                worker,
                busy: false,
                jobsProcessed: 0
            });
        }
        
        // Start job distribution
        this.startDistribution();
    }
    
    async addJob(job) {
        // Calculate priority
        const priority = this.calculatePriority(job);
        
        // Get or create priority queue
        if (!this.queues.has(priority)) {
            this.queues.set(priority, []);
        }
        
        // Add to appropriate queue
        this.queues.get(priority).push(job);
        
        // Track metrics
        this.stats.increment('jobs_queued');
        this.stats.gauge('queue_depth', this.getTotalQueued());
    }
    
    calculatePriority(job) {
        let priority = 0;
        
        // Payment amount (higher payment = higher priority)
        priority += Math.log10(parseFloat(job.payment)) * 10;
        
        // Deadline urgency
        const timeUntilDeadline = job.deadline - Date.now();
        priority += Math.max(0, 100 - timeUntilDeadline / 60000);
        
        // Model availability
        if (this.isModelLoaded(job.modelId)) {
            priority += 20;
        }
        
        // Reputation boost
        priority += job.renterReputation / 10;
        
        return Math.floor(priority);
    }
    
    async startDistribution() {
        setInterval(() => {
            this.distributeJobs();
        }, 100); // Check every 100ms
    }
    
    async distributeJobs() {
        // Find available workers
        const availableWorkers = this.workers.filter(w => !w.busy);
        
        if (availableWorkers.length === 0) return;
        
        // Get highest priority jobs
        const jobs = this.getHighestPriorityJobs(availableWorkers.length);
        
        // Assign jobs to workers
        for (let i = 0; i < jobs.length; i++) {
            const worker = availableWorkers[i];
            const job = jobs[i];
            
            worker.busy = true;
            worker.worker.postMessage({ type: 'process', job });
            
            this.processing.add(job.id);
            this.stats.increment('jobs_started');
        }
    }
    
    getHighestPriorityJobs(count) {
        const jobs = [];
        
        // Get priorities in descending order
        const priorities = Array.from(this.queues.keys()).sort((a, b) => b - a);
        
        for (const priority of priorities) {
            const queue = this.queues.get(priority);
            
            while (queue.length > 0 && jobs.length < count) {
                jobs.push(queue.shift());
            }
            
            // Remove empty queue
            if (queue.length === 0) {
                this.queues.delete(priority);
            }
            
            if (jobs.length >= count) break;
        }
        
        return jobs;
    }
}
```

### Model Loading Strategy
```javascript
class ModelLoadingOptimizer {
    constructor() {
        this.loadedModels = new Map();
        this.loadingModels = new Map();
        this.modelStats = new Map();
        this.maxLoadedModels = 5;
    }
    
    async getModel(modelId) {
        // Check if already loaded
        if (this.loadedModels.has(modelId)) {
            const model = this.loadedModels.get(modelId);
            model.lastUsed = Date.now();
            this.updateStats(modelId, 'hit');
            return model;
        }
        
        // Check if currently loading
        if (this.loadingModels.has(modelId)) {
            this.updateStats(modelId, 'wait');
            return await this.loadingModels.get(modelId);
        }
        
        // Load model
        this.updateStats(modelId, 'miss');
        const loadPromise = this.loadModel(modelId);
        this.loadingModels.set(modelId, loadPromise);
        
        try {
            const model = await loadPromise;
            return model;
        } finally {
            this.loadingModels.delete(modelId);
        }
    }
    
    async loadModel(modelId) {
        console.log(`Loading model: ${modelId}`);
        const startTime = Date.now();
        
        // Check if we need to evict a model
        if (this.loadedModels.size >= this.maxLoadedModels) {
            await this.evictLRUModel();
        }
        
        // Load model based on type
        let model;
        if (modelId.startsWith('gpt')) {
            model = await this.loadOpenAIModel(modelId);
        } else if (modelId.startsWith('llama')) {
            model = await this.loadLlamaModel(modelId);
        } else {
            model = await this.loadGenericModel(modelId);
        }
        
        // Optimize model for inference
        model = await this.optimizeForInference(model);
        
        // Cache loaded model
        this.loadedModels.set(modelId, {
            id: modelId,
            model: model,
            loadedAt: Date.now(),
            lastUsed: Date.now(),
            memoryUsage: this.getModelMemoryUsage(model)
        });
        
        const loadTime = Date.now() - startTime;
        console.log(`Model ${modelId} loaded in ${loadTime}ms`);
        
        return model;
    }
    
    async evictLRUModel() {
        let lruModel = null;
        let lruTime = Infinity;
        
        // Find least recently used model
        for (const [id, info] of this.loadedModels) {
            if (info.lastUsed < lruTime) {
                lruTime = info.lastUsed;
                lruModel = id;
            }
        }
        
        if (lruModel) {
            console.log(`Evicting model: ${lruModel}`);
            const info = this.loadedModels.get(lruModel);
            
            // Free GPU memory
            if (info.model.dispose) {
                await info.model.dispose();
            }
            
            this.loadedModels.delete(lruModel);
        }
    }
    
    async optimizeForInference(model) {
        // Quantization for faster inference
        if (model.quantize) {
            model = await model.quantize({
                bits: 8,
                strategy: 'dynamic'
            });
        }
        
        // Compile for specific hardware
        if (model.compile) {
            model = await model.compile({
                backend: 'tensorrt', // For NVIDIA GPUs
                precision: 'fp16',
                maxBatchSize: 32
            });
        }
        
        // Enable Flash Attention if available
        if (model.enableFlashAttention) {
            model.enableFlashAttention();
        }
        
        return model;
    }
    
    updateStats(modelId, event) {
        if (!this.modelStats.has(modelId)) {
            this.modelStats.set(modelId, {
                hits: 0,
                misses: 0,
                waits: 0,
                totalInferences: 0
            });
        }
        
        const stats = this.modelStats.get(modelId);
        stats[event + 's']++;
    }
    
    getModelPriority(modelId) {
        const stats = this.modelStats.get(modelId);
        if (!stats) return 0;
        
        // Calculate priority based on usage patterns
        const hitRate = stats.hits / (stats.hits + stats.misses + stats.waits);
        const frequency = stats.totalInferences;
        
        return hitRate * Math.log(frequency + 1);
    }
}
```

### Network Optimization
```javascript
class NetworkOptimizer {
    constructor() {
        this.connections = new Map();
        this.bandwidthMonitor = new BandwidthMonitor();
        this.compressionEnabled = true;
    }
    
    async createOptimizedServer() {
        const server = http2.createSecureServer({
            key: fs.readFileSync('server.key'),
            cert: fs.readFileSync('server.crt'),
            
            // HTTP/2 settings
            settings: {
                headerTableSize: 4096,
                enablePush: true,
                initialWindowSize: 1048576,
                maxFrameSize: 16384,
                maxConcurrentStreams: 1000,
                maxHeaderListSize: 8192
            },
            
            // TLS settings
            minVersion: 'TLSv1.3',
            ciphers: 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
            
            // Connection settings
            allowHTTP1: false,
            maxSessionMemory: 100
        });
        
        // Enable compression
        server.on('stream', (stream, headers) => {
            if (this.shouldCompress(headers)) {
                stream.respond({
                    ':status': 200,
                    'content-encoding': 'br' // Brotli compression
                });
            }
        });
        
        return server;
    }
    
    async optimizeConnection(socket) {
        // TCP optimizations
        socket.setNoDelay(true); // Disable Nagle's algorithm
        socket.setKeepAlive(true, 60000); // Keep-alive every minute
        
        // Buffer sizes
        socket.bufferSize = 1048576; // 1MB
        
        // Monitor connection
        this.connections.set(socket.remoteAddress, {
            socket,
            bandwidth: new BandwidthTracker(),
            startTime: Date.now()
        });
        
        socket.on('close', () => {
            this.connections.delete(socket.remoteAddress);
        });
    }
    
    async sendOptimized(socket, data) {
        const connection = this.connections.get(socket.remoteAddress);
        
        // Compress if beneficial
        if (this.compressionEnabled && data.length > 1024) {
            data = await this.compress(data);
        }
        
        // Chunk large data
        if (data.length > 65536) {
            return await this.sendChunked(socket, data);
        }
        
        // Track bandwidth
        connection.bandwidth.addBytes(data.length);
        
        return socket.write(data);
    }
    
    async compress(data) {
        return new Promise((resolve, reject) => {
            zlib.brotliCompress(data, {
                params: {
                    [zlib.constants.BROTLI_PARAM_QUALITY]: 4
                }
            }, (err, compressed) => {
                if (err) reject(err);
                else resolve(compressed);
            });
        });
    }
}
```

## Monitoring and Profiling

### Performance Monitoring
```javascript
class PerformanceMonitor {
    constructor() {
        this.metrics = new MetricsRegistry();
        this.profiler = new Profiler();
    }
    
    setupMonitoring() {
        // CPU monitoring
        setInterval(() => {
            const cpuUsage = process.cpuUsage();
            this.metrics.gauge('cpu.user', cpuUsage.user);
            this.metrics.gauge('cpu.system', cpuUsage.system);
        }, 1000);
        
        // Memory monitoring
        setInterval(() => {
            const mem = process.memoryUsage();
            this.metrics.gauge('memory.heap.used', mem.heapUsed);
            this.metrics.gauge('memory.heap.total', mem.heapTotal);
            this.metrics.gauge('memory.rss', mem.rss);
            this.metrics.gauge('memory.external', mem.external);
        }, 5000);
        
        // Event loop monitoring
        this.monitorEventLoop();
        
        // GPU monitoring
        this.monitorGPU();
    }
    
    monitorEventLoop() {
        let lastCheck = process.hrtime.bigint();
        
        setInterval(() => {
            const now = process.hrtime.bigint();
            const delay = Number(now - lastCheck - 1000000000n) / 1000000;
            
            this.metrics.histogram('eventloop.delay', delay);
            
            if (delay > 100) {
                console.warn(`Event loop blocked for ${delay}ms`);
            }
            
            lastCheck = now;
        }, 1000);
    }
    
    async monitorGPU() {
        setInterval(async () => {
            try {
                const gpuStats = await this.getGPUStats();
                
                for (const gpu of gpuStats) {
                    this.metrics.gauge(`gpu.${gpu.index}.utilization`, gpu.utilization);
                    this.metrics.gauge(`gpu.${gpu.index}.memory.used`, gpu.memoryUsed);
                    this.metrics.gauge(`gpu.${gpu.index}.memory.total`, gpu.memoryTotal);
                    this.metrics.gauge(`gpu.${gpu.index}.temperature`, gpu.temperature);
                    this.metrics.gauge(`gpu.${gpu.index}.power`, gpu.power);
                }
            } catch (error) {
                console.error('GPU monitoring error:', error);
            }
        }, 5000);
    }
    
    async profileFunction(name, fn) {
        const start = process.hrtime.bigint();
        const startMem = process.memoryUsage();
        
        try {
            const result = await fn();
            
            const duration = Number(process.hrtime.bigint() - start) / 1000000;
            const memDelta = process.memoryUsage().heapUsed - startMem.heapUsed;
            
            this.metrics.histogram(`function.${name}.duration`, duration);
            this.metrics.histogram(`function.${name}.memory`, memDelta);
            
            return result;
        } catch (error) {
            this.metrics.increment(`function.${name}.errors`);
            throw error;
        }
    }
}
```

## Optimization Checklist

### System Level
- [ ] CPU governor set to performance
- [ ] NUMA configuration optimized
- [ ] Huge pages enabled
- [ ] I/O scheduler optimized
- [ ] Network stack tuned
- [ ] GPU drivers updated

### Application Level
- [ ] Worker pool sized correctly
- [ ] Connection pooling configured
- [ ] Memory limits set appropriately
- [ ] Garbage collection tuned
- [ ] Model preloading enabled
- [ ] Request queuing optimized

### Monitoring
- [ ] Performance metrics collected
- [ ] Resource usage tracked
- [ ] Bottlenecks identified
- [ ] Profiling automated
- [ ] Alerts configured
- [ ] Dashboards created

## Anti-Patterns to Avoid

### ❌ Performance Killers
```javascript
// Synchronous operations
const data = fs.readFileSync('large-file.json');

// Unbounded concurrency
for (const job of jobs) {
    processJob(job); // No limit!
}

// Memory leaks
global.cache[key] = value; // Never cleaned

// Blocking event loop
while (Date.now() < deadline) {
    // Busy wait
}
```

### ✅ Performance Best Practices
```javascript
// Asynchronous operations
const data = await fs.promises.readFile('large-file.json');

// Controlled concurrency
const pLimit = require('p-limit');
const limit = pLimit(10);
await Promise.all(jobs.map(job => limit(() => processJob(job))));

// Managed cache
const LRU = require('lru-cache');
const cache = new LRU({ max: 500, ttl: 1000 * 60 * 5 });

// Non-blocking delays
await new Promise(resolve => setTimeout(resolve, delay));
```

## Performance Testing

### Load Testing Script
```javascript
const loadTest = async () => {
    const scenarios = [
        {
            name: 'Normal Load',
            vus: 10,
            duration: '5m',
            rps: 100
        },
        {
            name: 'Peak Load',
            vus: 100,
            duration: '10m',
            rps: 1000
        },
        {
            name: 'Stress Test',
            vus: 500,
            duration: '30m',
            rps: 5000
        }
    ];
    
    for (const scenario of scenarios) {
        console.log(`Running ${scenario.name}`);
        const results = await runScenario(scenario);
        console.log(results.summary());
    }
};
```

## Next Steps

1. Implement [Scalability Patterns](scalability-patterns.md)
2. Set up [Monitoring & Alerting](../operations/monitoring-alerting.md)
3. Review [Gas Optimization](gas-optimization.md) techniques
4. Study [Staking Economics](../economics/staking-economics.md)

## Additional Resources

- [Node.js Performance Best Practices](https://nodejs.org/en/docs/guides/simple-profiling/)
- [V8 Optimization Tips](https://v8.dev/docs)
- [NVIDIA GPU Optimization Guide](https://docs.nvidia.com/deeplearning/performance/index.html)
- [Linux Performance Tuning](https://www.kernel.org/doc/html/latest/admin-guide/kernel-per-CPU-kthreads.html)

---

Remember: **Measure, don't guess.** Always profile and benchmark before and after optimizations to ensure improvements.