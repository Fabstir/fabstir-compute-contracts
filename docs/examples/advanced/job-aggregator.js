/**
 * Example: Job Aggregator
 * Purpose: Aggregate jobs from multiple sources and route to optimal nodes
 * Prerequisites:
 *   - Understanding of job marketplace dynamics
 *   - Access to multiple job sources
 *   - Routing optimization knowledge
 */

const { ethers } = require('ethers');
const express = require('express');
const WebSocket = require('ws');
const EventEmitter = require('events');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const JOB_MARKETPLACE_ABI = require('../contracts/JobMarketplace.json').abi;
const NODE_REGISTRY_ABI = require('../contracts/NodeRegistry.json').abi;
const REPUTATION_SYSTEM_ABI = require('../contracts/ReputationSystem.json').abi;

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    contracts: {
        jobMarketplace: process.env.JOB_MARKETPLACE,
        nodeRegistry: process.env.NODE_REGISTRY,
        reputationSystem: process.env.REPUTATION_SYSTEM
    },
    
    // Aggregator settings
    aggregator: {
        port: 3000,
        wsPort: 3001,
        
        // Job collection
        scanInterval: 10000, // 10 seconds
        maxJobAge: 3600, // 1 hour
        
        // Routing optimization
        routingAlgorithm: 'weighted', // 'weighted', 'round-robin', 'cheapest'
        loadBalancing: true,
        
        // Node scoring weights
        scoring: {
            reputation: 0.3,
            successRate: 0.2,
            avgCompletionTime: 0.2,
            price: 0.2,
            availability: 0.1
        },
        
        // Caching
        cacheExpiry: 300, // 5 minutes
        maxCacheSize: 1000
    },
    
    // External job sources (mock)
    externalSources: [
        {
            name: 'OpenAI Bridge',
            url: 'https://api.bridge.example/jobs',
            apiKey: process.env.OPENAI_BRIDGE_KEY
        },
        {
            name: 'HuggingFace Queue',
            url: 'https://api.hf-queue.example/pending',
            apiKey: process.env.HF_QUEUE_KEY
        }
    ]
};

// Job aggregator engine
class JobAggregator extends EventEmitter {
    constructor(contracts) {
        super();
        this.contracts = contracts;
        this.jobs = new Map(); // jobId -> job details
        this.nodes = new Map(); // nodeAddress -> node info
        this.routes = new Map(); // jobId -> assigned node
        this.stats = {
            totalJobs: 0,
            routedJobs: 0,
            completedJobs: 0,
            avgRoutingTime: 0,
            nodeUtilization: new Map()
        };
    }
    
    async initialize() {
        console.log('🔄 Initializing Job Aggregator...');
        
        // Load active nodes
        await this.refreshNodeList();
        
        // Start job scanner
        this.startJobScanner();
        
        // Start external source polling
        this.startExternalPolling();
        
        console.log(`   ✅ Initialized with ${this.nodes.size} active nodes`);
    }
    
    async refreshNodeList() {
        // In production, this would query all registered nodes
        // For demo, we'll simulate a few nodes
        const mockNodes = [
            {
                address: '0x1234567890123456789012345678901234567890',
                models: ['gpt-4', 'claude-2'],
                reputation: 950,
                successRate: 98.5,
                avgCompletionTime: 300,
                priceMultiplier: 1.1
            },
            {
                address: '0x2345678901234567890123456789012345678901',
                models: ['llama-2-70b', 'mistral-7b'],
                reputation: 875,
                successRate: 96.2,
                avgCompletionTime: 420,
                priceMultiplier: 0.9
            },
            {
                address: '0x3456789012345678901234567890123456789012',
                models: ['gpt-4', 'llama-2-70b', 'stable-diffusion-xl'],
                reputation: 820,
                successRate: 94.8,
                avgCompletionTime: 360,
                priceMultiplier: 1.0
            }
        ];
        
        for (const node of mockNodes) {
            this.nodes.set(node.address, {
                ...node,
                currentLoad: 0,
                maxLoad: 5,
                isAvailable: true,
                lastSeen: Date.now()
            });
        }
    }
    
    startJobScanner() {
        setInterval(async () => {
            try {
                await this.scanForJobs();
            } catch (error) {
                console.error('Job scan error:', error);
            }
        }, config.aggregator.scanInterval);
    }
    
    async scanForJobs() {
        // Get jobs from marketplace
        const activeJobIds = await this.contracts.jobMarketplace.getActiveJobs();
        
        for (const jobId of activeJobIds) {
            const jobIdStr = jobId.toString();
            
            if (this.jobs.has(jobIdStr)) continue;
            
            const job = await this.contracts.jobMarketplace.getJob(jobId);
            
            if (job.status === 0) { // Posted
                this.addJob({
                    id: jobIdStr,
                    source: 'marketplace',
                    ...this.parseJob(job),
                    addedAt: Date.now()
                });
            }
        }
    }
    
    parseJob(job) {
        return {
            poster: job.poster,
            modelId: job.modelId,
            payment: job.payment,
            maxTokens: job.maxTokens,
            deadline: Number(job.deadline),
            postedAt: Number(job.postedAt),
            inputData: job.inputData
        };
    }
    
    startExternalPolling() {
        // Mock external source polling
        setInterval(() => {
            // Simulate external jobs
            if (Math.random() > 0.7) {
                this.addExternalJob();
            }
        }, 15000);
    }
    
    addExternalJob() {
        const models = ['gpt-4', 'claude-2', 'llama-2-70b'];
        const job = {
            id: `ext-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            source: config.externalSources[Math.floor(Math.random() * config.externalSources.length)].name,
            modelId: models[Math.floor(Math.random() * models.length)],
            payment: ethers.parseEther((Math.random() * 0.3 + 0.05).toFixed(3)),
            maxTokens: Math.floor(Math.random() * 2000 + 500),
            deadline: 3600,
            postedAt: Math.floor(Date.now() / 1000),
            inputData: ethers.hexlify(ethers.toUtf8Bytes('External job input')),
            addedAt: Date.now()
        };
        
        this.addJob(job);
    }
    
    addJob(job) {
        this.jobs.set(job.id, job);
        this.stats.totalJobs++;
        
        // Emit event
        this.emit('jobAdded', job);
        
        // Try to route immediately
        this.routeJob(job);
    }
    
    async routeJob(job) {
        const startTime = Date.now();
        
        // Find suitable nodes
        const suitableNodes = this.findSuitableNodes(job);
        
        if (suitableNodes.length === 0) {
            console.log(`   ⚠️  No suitable nodes for job ${job.id}`);
            this.emit('jobUnroutable', job);
            return;
        }
        
        // Score and rank nodes
        const scoredNodes = this.scoreNodes(suitableNodes, job);
        
        // Select best node based on algorithm
        const selectedNode = this.selectNode(scoredNodes, job);
        
        if (!selectedNode) {
            console.log(`   ⚠️  Failed to select node for job ${job.id}`);
            return;
        }
        
        // Assign job to node
        this.routes.set(job.id, selectedNode.address);
        selectedNode.currentLoad++;
        
        // Update stats
        this.stats.routedJobs++;
        const routingTime = Date.now() - startTime;
        this.stats.avgRoutingTime = 
            (this.stats.avgRoutingTime * (this.stats.routedJobs - 1) + routingTime) / this.stats.routedJobs;
        
        // Update node utilization
        const utilization = (selectedNode.currentLoad / selectedNode.maxLoad) * 100;
        this.stats.nodeUtilization.set(selectedNode.address, utilization);
        
        console.log(`   ✅ Routed job ${job.id} to node ${selectedNode.address.slice(0, 10)}...`);
        console.log(`      Model: ${job.modelId}, Payment: ${ethers.formatEther(job.payment)} ETH`);
        
        // Emit routing event
        this.emit('jobRouted', {
            job,
            node: selectedNode,
            routingTime
        });
    }
    
    findSuitableNodes(job) {
        const suitable = [];
        
        for (const [address, node] of this.nodes) {
            if (!node.isAvailable) continue;
            if (node.currentLoad >= node.maxLoad) continue;
            if (!node.models.includes(job.modelId)) continue;
            
            // Check if node is still active (last seen < 5 minutes ago)
            if (Date.now() - node.lastSeen > 300000) continue;
            
            suitable.push(node);
        }
        
        return suitable;
    }
    
    scoreNodes(nodes, job) {
        return nodes.map(node => {
            let score = 0;
            
            // Reputation score
            score += (node.reputation / 1000) * config.aggregator.scoring.reputation;
            
            // Success rate score
            score += (node.successRate / 100) * config.aggregator.scoring.successRate;
            
            // Completion time score (inverse - faster is better)
            const timeScore = 1 - (node.avgCompletionTime / 600); // Normalize to 10 minutes
            score += Math.max(0, timeScore) * config.aggregator.scoring.avgCompletionTime;
            
            // Price score (inverse - cheaper is better)
            const priceScore = 1 - (node.priceMultiplier - 0.8) / 0.4; // Normalize 0.8-1.2
            score += Math.max(0, priceScore) * config.aggregator.scoring.price;
            
            // Availability score
            const availabilityScore = 1 - (node.currentLoad / node.maxLoad);
            score += availabilityScore * config.aggregator.scoring.availability;
            
            return {
                ...node,
                score,
                estimatedCost: job.payment * node.priceMultiplier
            };
        }).sort((a, b) => b.score - a.score);
    }
    
    selectNode(scoredNodes, job) {
        switch (config.aggregator.routingAlgorithm) {
            case 'weighted':
                // Weighted random selection based on scores
                const totalScore = scoredNodes.reduce((sum, node) => sum + node.score, 0);
                let random = Math.random() * totalScore;
                
                for (const node of scoredNodes) {
                    random -= node.score;
                    if (random <= 0) {
                        return node;
                    }
                }
                return scoredNodes[0];
                
            case 'round-robin':
                // Simple round-robin
                return scoredNodes.find(node => node.currentLoad === Math.min(...scoredNodes.map(n => n.currentLoad)));
                
            case 'cheapest':
                // Select cheapest option
                return scoredNodes.reduce((cheapest, node) => 
                    node.estimatedCost < cheapest.estimatedCost ? node : cheapest
                );
                
            default:
                // Default to highest score
                return scoredNodes[0];
        }
    }
    
    getStats() {
        return {
            ...this.stats,
            activeJobs: this.jobs.size,
            activeNodes: Array.from(this.nodes.values()).filter(n => n.isAvailable).length,
            nodeUtilization: Array.from(this.stats.nodeUtilization.entries())
        };
    }
    
    getJobs(filter = {}) {
        let jobs = Array.from(this.jobs.values());
        
        if (filter.modelId) {
            jobs = jobs.filter(j => j.modelId === filter.modelId);
        }
        
        if (filter.source) {
            jobs = jobs.filter(j => j.source === filter.source);
        }
        
        if (filter.minPayment) {
            jobs = jobs.filter(j => j.payment >= ethers.parseEther(filter.minPayment));
        }
        
        return jobs;
    }
}

// REST API for job aggregator
class AggregatorAPI {
    constructor(aggregator) {
        this.aggregator = aggregator;
        this.app = express();
        this.setupRoutes();
    }
    
    setupRoutes() {
        this.app.use(express.json());
        
        // Get aggregator stats
        this.app.get('/stats', (req, res) => {
            res.json(this.aggregator.getStats());
        });
        
        // Get jobs
        this.app.get('/jobs', (req, res) => {
            const jobs = this.aggregator.getJobs(req.query);
            res.json({
                count: jobs.length,
                jobs: jobs.map(j => ({
                    id: j.id,
                    source: j.source,
                    modelId: j.modelId,
                    payment: ethers.formatEther(j.payment),
                    maxTokens: j.maxTokens,
                    deadline: j.deadline,
                    age: Math.floor((Date.now() - j.addedAt) / 1000)
                }))
            });
        });
        
        // Get nodes
        this.app.get('/nodes', (req, res) => {
            const nodes = Array.from(this.aggregator.nodes.values());
            res.json({
                count: nodes.length,
                nodes: nodes.map(n => ({
                    address: n.address,
                    models: n.models,
                    reputation: n.reputation,
                    currentLoad: n.currentLoad,
                    maxLoad: n.maxLoad,
                    utilization: ((n.currentLoad / n.maxLoad) * 100).toFixed(1) + '%'
                }))
            });
        });
        
        // Get routing for a job
        this.app.get('/routing/:jobId', (req, res) => {
            const nodeAddress = this.aggregator.routes.get(req.params.jobId);
            if (!nodeAddress) {
                return res.status(404).json({ error: 'Job not found or not routed' });
            }
            
            const node = this.aggregator.nodes.get(nodeAddress);
            res.json({
                jobId: req.params.jobId,
                assignedNode: nodeAddress,
                nodeDetails: node
            });
        });
        
        // Submit external job
        this.app.post('/jobs', (req, res) => {
            try {
                const job = {
                    id: `api-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
                    source: 'API',
                    modelId: req.body.model,
                    payment: ethers.parseEther(req.body.payment || '0.1'),
                    maxTokens: req.body.maxTokens || 1000,
                    deadline: req.body.deadline || 3600,
                    postedAt: Math.floor(Date.now() / 1000),
                    inputData: ethers.hexlify(ethers.toUtf8Bytes(req.body.input || '')),
                    addedAt: Date.now()
                };
                
                this.aggregator.addJob(job);
                
                res.json({
                    success: true,
                    jobId: job.id
                });
            } catch (error) {
                res.status(400).json({ error: error.message });
            }
        });
    }
    
    start(port) {
        this.app.listen(port, () => {
            console.log(`   📡 API server listening on port ${port}`);
        });
    }
}

// WebSocket server for real-time updates
class AggregatorWebSocket {
    constructor(aggregator) {
        this.aggregator = aggregator;
        this.wss = new WebSocket.Server({ port: config.aggregator.wsPort });
        this.clients = new Set();
        
        this.setupWebSocket();
        this.setupEventHandlers();
    }
    
    setupWebSocket() {
        this.wss.on('connection', (ws) => {
            console.log('   🔌 New WebSocket client connected');
            this.clients.add(ws);
            
            // Send initial stats
            ws.send(JSON.stringify({
                type: 'stats',
                data: this.aggregator.getStats()
            }));
            
            ws.on('close', () => {
                this.clients.delete(ws);
            });
            
            ws.on('error', (error) => {
                console.error('WebSocket error:', error);
                this.clients.delete(ws);
            });
        });
        
        console.log(`   🔌 WebSocket server listening on port ${config.aggregator.wsPort}`);
    }
    
    setupEventHandlers() {
        // Forward aggregator events to WebSocket clients
        this.aggregator.on('jobAdded', (job) => {
            this.broadcast({
                type: 'jobAdded',
                data: {
                    id: job.id,
                    source: job.source,
                    modelId: job.modelId,
                    payment: ethers.formatEther(job.payment)
                }
            });
        });
        
        this.aggregator.on('jobRouted', ({ job, node, routingTime }) => {
            this.broadcast({
                type: 'jobRouted',
                data: {
                    jobId: job.id,
                    nodeAddress: node.address,
                    routingTime
                }
            });
        });
        
        // Send periodic stats updates
        setInterval(() => {
            this.broadcast({
                type: 'stats',
                data: this.aggregator.getStats()
            });
        }, 5000);
    }
    
    broadcast(message) {
        const data = JSON.stringify(message);
        this.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(data);
            }
        });
    }
}

// Monitoring dashboard (simple HTML)
function createDashboardHTML() {
    return `
<!DOCTYPE html>
<html>
<head>
    <title>Fabstir Job Aggregator Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .stat-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat-value { font-size: 2em; font-weight: bold; color: #2563eb; }
        .stat-label { color: #666; margin-top: 5px; }
        .log { background: white; padding: 20px; border-radius: 8px; height: 400px; overflow-y: auto; }
        .log-entry { padding: 5px; border-bottom: 1px solid #eee; }
        .job-added { color: #10b981; }
        .job-routed { color: #2563eb; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Fabstir Job Aggregator Dashboard</h1>
        
        <div class="stats">
            <div class="stat-box">
                <div class="stat-value" id="totalJobs">0</div>
                <div class="stat-label">Total Jobs</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="activeJobs">0</div>
                <div class="stat-label">Active Jobs</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="routedJobs">0</div>
                <div class="stat-label">Routed Jobs</div>
            </div>
            <div class="stat-box">
                <div class="stat-value" id="activeNodes">0</div>
                <div class="stat-label">Active Nodes</div>
            </div>
        </div>
        
        <h2>Real-time Activity</h2>
        <div class="log" id="activityLog"></div>
    </div>
    
    <script>
        const ws = new WebSocket('ws://localhost:3001');
        const log = document.getElementById('activityLog');
        
        function addLogEntry(message, className = '') {
            const entry = document.createElement('div');
            entry.className = 'log-entry ' + className;
            entry.textContent = new Date().toLocaleTimeString() + ' - ' + message;
            log.insertBefore(entry, log.firstChild);
            
            // Keep only last 50 entries
            while (log.children.length > 50) {
                log.removeChild(log.lastChild);
            }
        }
        
        ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            
            switch (message.type) {
                case 'stats':
                    document.getElementById('totalJobs').textContent = message.data.totalJobs;
                    document.getElementById('activeJobs').textContent = message.data.activeJobs;
                    document.getElementById('routedJobs').textContent = message.data.routedJobs;
                    document.getElementById('activeNodes').textContent = message.data.activeNodes;
                    break;
                    
                case 'jobAdded':
                    addLogEntry(
                        'New job added: ' + message.data.id + ' (' + message.data.modelId + ', ' + message.data.payment + ' ETH)',
                        'job-added'
                    );
                    break;
                    
                case 'jobRouted':
                    addLogEntry(
                        'Job ' + message.data.jobId + ' routed to ' + message.data.nodeAddress.slice(0, 10) + '... (routing time: ' + message.data.routingTime + 'ms)',
                        'job-routed'
                    );
                    break;
            }
        };
        
        ws.onopen = () => {
            addLogEntry('Connected to aggregator');
        };
        
        ws.onerror = () => {
            addLogEntry('Connection error', 'error');
        };
        
        ws.onclose = () => {
            addLogEntry('Disconnected from aggregator', 'error');
        };
    </script>
</body>
</html>
    `;
}

// Main function
async function main() {
    try {
        console.log('🚀 Fabstir Job Aggregator\n');
        console.log('━'.repeat(50));
        
        // Setup
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        
        // Initialize contracts (read-only for aggregator)
        const contracts = {
            jobMarketplace: new ethers.Contract(
                config.contracts.jobMarketplace,
                JOB_MARKETPLACE_ABI,
                provider
            ),
            nodeRegistry: new ethers.Contract(
                config.contracts.nodeRegistry,
                NODE_REGISTRY_ABI,
                provider
            ),
            reputationSystem: new ethers.Contract(
                config.contracts.reputationSystem,
                REPUTATION_SYSTEM_ABI,
                provider
            )
        };
        
        // Create aggregator
        const aggregator = new JobAggregator(contracts);
        await aggregator.initialize();
        
        // Start API server
        const api = new AggregatorAPI(aggregator);
        api.start(config.aggregator.port);
        
        // Start WebSocket server
        const ws = new AggregatorWebSocket(aggregator);
        
        // Serve dashboard
        api.app.get('/', (req, res) => {
            res.send(createDashboardHTML());
        });
        
        console.log('\n✅ Job Aggregator is running!');
        console.log(`   🌐 Dashboard: http://localhost:${config.aggregator.port}`);
        console.log(`   📡 API: http://localhost:${config.aggregator.port}/stats`);
        console.log(`   🔌 WebSocket: ws://localhost:${config.aggregator.wsPort}`);
        console.log('\n📊 Routing Configuration:');
        console.log(`   • Algorithm: ${config.aggregator.routingAlgorithm}`);
        console.log(`   • Load balancing: ${config.aggregator.loadBalancing ? 'Enabled' : 'Disabled'}`);
        console.log(`   • Scan interval: ${config.aggregator.scanInterval / 1000}s`);
        
        // Display periodic stats
        setInterval(() => {
            const stats = aggregator.getStats();
            console.log(`\n📈 Stats Update - ${new Date().toLocaleTimeString()}`);
            console.log(`   Jobs: ${stats.activeJobs} active, ${stats.routedJobs} routed`);
            console.log(`   Nodes: ${stats.activeNodes} active`);
            console.log(`   Avg routing time: ${stats.avgRoutingTime.toFixed(2)}ms`);
        }, 30000);
        
        console.log('\nPress Ctrl+C to stop\n');
        
    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = {
    JobAggregator,
    AggregatorAPI,
    AggregatorWebSocket,
    config
};

/**
 * Expected Output:
 * 
 * 🚀 Fabstir Job Aggregator
 * ══════════════════════════════════════════════════
 * 🔄 Initializing Job Aggregator...
 *    ✅ Initialized with 3 active nodes
 *    📡 API server listening on port 3000
 *    🔌 WebSocket server listening on port 3001
 * 
 * ✅ Job Aggregator is running!
 *    🌐 Dashboard: http://localhost:3000
 *    📡 API: http://localhost:3000/stats
 *    🔌 WebSocket: ws://localhost:3001
 * 
 * 📊 Routing Configuration:
 *    • Algorithm: weighted
 *    • Load balancing: Enabled
 *    • Scan interval: 10s
 * 
 *    ✅ Routed job 42 to node 0x12345678...
 *       Model: gpt-4, Payment: 0.15 ETH
 *    ✅ Routed job ext-1234567890-abc123 to node 0x23456789...
 *       Model: claude-2, Payment: 0.087 ETH
 *    🔌 New WebSocket client connected
 * 
 * 📈 Stats Update - 10:45:30 AM
 *    Jobs: 8 active, 156 routed
 *    Nodes: 3 active
 *    Avg routing time: 12.45ms
 * 
 * Press Ctrl+C to stop
 * 
 * [Dashboard shows real-time job routing visualization]
 */