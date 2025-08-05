/**
 * Example: Automated Node Operator
 * Purpose: Fully automated node operation with job selection, processing, and optimization
 * Prerequisites:
 *   - Registered node with stake
 *   - AI model inference capability
 *   - Sufficient resources for continuous operation
 */

const { ethers } = require('ethers');
const EventEmitter = require('events');
const fs = require('fs').promises;
const path = require('path');
require('dotenv').config({ path: '../.env' });

// Import contract ABIs
const NODE_REGISTRY_ABI = require('../contracts/NodeRegistry.json').abi;
const JOB_MARKETPLACE_ABI = require('../contracts/JobMarketplace.json').abi;
const REPUTATION_SYSTEM_ABI = require('../contracts/ReputationSystem.json').abi;
const PROOF_SYSTEM_ABI = require('../contracts/ProofSystem.json').abi;

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    contracts: {
        nodeRegistry: process.env.NODE_REGISTRY,
        jobMarketplace: process.env.JOB_MARKETPLACE,
        reputationSystem: process.env.REPUTATION_SYSTEM,
        proofSystem: process.env.PROOF_SYSTEM
    },
    
    // Operator settings
    operator: {
        maxConcurrentJobs: 3,
        jobCheckInterval: 30000, // 30 seconds
        healthCheckInterval: 60000, // 1 minute
        maintenanceWindow: { hour: 3, duration: 1 }, // 3 AM for 1 hour
        
        // Job selection criteria
        minPayment: ethers.parseEther('0.05'),
        maxProcessingTime: 1800, // 30 minutes
        preferredModels: ['gpt-4', 'claude-2', 'llama-2-70b'],
        
        // Resource management
        cpuThreshold: 80, // Max CPU usage %
        memoryThreshold: 85, // Max memory usage %
        gpuThreshold: 90, // Max GPU usage %
        
        // Performance optimization
        cacheSize: 1000, // Number of cached responses
        batchSize: 5, // Jobs to claim in batch
        
        // Risk management
        maxDailyLoss: ethers.parseEther('0.1'),
        minReputationScore: 700,
        emergencyShutdownScore: 500
    },
    
    // Logging
    logDir: './operator-logs',
    metricsFile: './operator-metrics.json'
};

// Job processor interface
class JobProcessor {
    constructor(modelId) {
        this.modelId = modelId;
        this.cache = new Map();
    }
    
    async process(input) {
        // Check cache first
        const cacheKey = ethers.keccak256(ethers.toUtf8Bytes(input));
        if (this.cache.has(cacheKey)) {
            console.log('   📦 Cache hit!');
            return this.cache.get(cacheKey);
        }
        
        // Simulate AI inference
        console.log(`   🤖 Processing with ${this.modelId}...`);
        const processingTime = Math.random() * 10000 + 5000; // 5-15 seconds
        
        await new Promise(resolve => setTimeout(resolve, processingTime));
        
        // Generate mock output
        const output = this.generateMockOutput(input);
        
        // Cache result
        if (this.cache.size >= config.operator.cacheSize) {
            const firstKey = this.cache.keys().next().value;
            this.cache.delete(firstKey);
        }
        this.cache.set(cacheKey, output);
        
        return output;
    }
    
    generateMockOutput(input) {
        // In production, this would call actual AI model
        const responses = [
            "Based on my analysis, the key factors to consider are...",
            "The solution involves implementing a multi-step approach...",
            "According to the latest research, the best practice is...",
            "Let me break this down into manageable components..."
        ];
        
        return responses[Math.floor(Math.random() * responses.length)] + 
               ` [Processed: ${input.substring(0, 50)}...]`;
    }
}

// Resource monitor
class ResourceMonitor extends EventEmitter {
    constructor() {
        super();
        this.metrics = {
            cpu: 0,
            memory: 0,
            gpu: 0,
            activeJobs: 0,
            queuedJobs: 0
        };
    }
    
    async checkResources() {
        // Simulate resource checking
        this.metrics.cpu = Math.random() * 100;
        this.metrics.memory = Math.random() * 100;
        this.metrics.gpu = Math.random() * 100;
        
        // Check thresholds
        if (this.metrics.cpu > config.operator.cpuThreshold) {
            this.emit('highCPU', this.metrics.cpu);
        }
        if (this.metrics.memory > config.operator.memoryThreshold) {
            this.emit('highMemory', this.metrics.memory);
        }
        if (this.metrics.gpu > config.operator.gpuThreshold) {
            this.emit('highGPU', this.metrics.gpu);
        }
        
        return this.metrics;
    }
    
    canAcceptJob() {
        return this.metrics.cpu < config.operator.cpuThreshold &&
               this.metrics.memory < config.operator.memoryThreshold &&
               this.metrics.gpu < config.operator.gpuThreshold &&
               this.metrics.activeJobs < config.operator.maxConcurrentJobs;
    }
}

// Performance tracker
class PerformanceTracker {
    constructor() {
        this.metrics = {
            jobsCompleted: 0,
            jobsFailed: 0,
            totalEarnings: ethers.parseEther('0'),
            averageProcessingTime: 0,
            successRate: 100,
            dailyStats: new Map()
        };
    }
    
    async recordJob(job, success, earnings, processingTime) {
        if (success) {
            this.metrics.jobsCompleted++;
            this.metrics.totalEarnings = this.metrics.totalEarnings + earnings;
        } else {
            this.metrics.jobsFailed++;
        }
        
        // Update average processing time
        const total = this.metrics.jobsCompleted + this.metrics.jobsFailed;
        this.metrics.averageProcessingTime = 
            (this.metrics.averageProcessingTime * (total - 1) + processingTime) / total;
        
        // Update success rate
        this.metrics.successRate = 
            (this.metrics.jobsCompleted / total) * 100;
        
        // Update daily stats
        const today = new Date().toISOString().split('T')[0];
        if (!this.metrics.dailyStats.has(today)) {
            this.metrics.dailyStats.set(today, {
                jobs: 0,
                earnings: ethers.parseEther('0'),
                failures: 0
            });
        }
        
        const dailyStats = this.metrics.dailyStats.get(today);
        dailyStats.jobs++;
        if (success) {
            dailyStats.earnings = dailyStats.earnings + earnings;
        } else {
            dailyStats.failures++;
        }
        
        await this.saveMetrics();
    }
    
    async saveMetrics() {
        try {
            await fs.writeFile(
                config.metricsFile,
                JSON.stringify({
                    ...this.metrics,
                    totalEarnings: this.metrics.totalEarnings.toString(),
                    dailyStats: Array.from(this.metrics.dailyStats.entries())
                }, null, 2)
            );
        } catch (error) {
            console.error('Failed to save metrics:', error);
        }
    }
    
    async loadMetrics() {
        try {
            const data = await fs.readFile(config.metricsFile, 'utf8');
            const saved = JSON.parse(data);
            this.metrics = {
                ...saved,
                totalEarnings: ethers.parseEther(saved.totalEarnings),
                dailyStats: new Map(saved.dailyStats)
            };
        } catch {
            // File doesn't exist yet
        }
    }
}

// Main automated node operator
class AutomatedNodeOperator extends EventEmitter {
    constructor(contracts, wallet) {
        super();
        this.contracts = contracts;
        this.wallet = wallet;
        this.processors = new Map();
        this.resourceMonitor = new ResourceMonitor();
        this.performanceTracker = new PerformanceTracker();
        this.activeJobs = new Map();
        this.isRunning = false;
        this.isPaused = false;
    }
    
    async initialize() {
        console.log('🚀 Initializing Automated Node Operator...');
        
        // Load performance metrics
        await this.performanceTracker.loadMetrics();
        
        // Verify node registration
        const nodeInfo = await this.contracts.nodeRegistry.getNode(this.wallet.address);
        if (!nodeInfo.isActive) {
            throw new Error('Node is not registered or inactive');
        }
        
        console.log('   ✅ Node verified');
        console.log(`   • Models: ${nodeInfo.supportedModels.join(', ')}`);
        console.log(`   • Stake: ${ethers.formatEther(nodeInfo.stake)} ETH`);
        
        // Initialize processors for supported models
        for (const model of nodeInfo.supportedModels) {
            this.processors.set(model, new JobProcessor(model));
        }
        
        // Check reputation
        const reputation = await this.contracts.reputationSystem.getNodeStats(this.wallet.address);
        console.log(`   • Reputation: ${reputation.reputationScore}/1000`);
        
        if (reputation.reputationScore < config.operator.emergencyShutdownScore) {
            throw new Error('Reputation too low for automated operation');
        }
        
        // Set up resource monitoring
        this.resourceMonitor.on('highCPU', cpu => {
            console.log(`   ⚠️  High CPU usage: ${cpu.toFixed(1)}%`);
            this.pauseNewJobs();
        });
        
        this.resourceMonitor.on('highMemory', memory => {
            console.log(`   ⚠️  High memory usage: ${memory.toFixed(1)}%`);
            this.pauseNewJobs();
        });
        
        console.log('   ✅ Initialization complete');
        
        // Display current metrics
        console.log('\n📊 Current Performance:');
        console.log(`   • Jobs completed: ${this.performanceTracker.metrics.jobsCompleted}`);
        console.log(`   • Success rate: ${this.performanceTracker.metrics.successRate.toFixed(1)}%`);
        console.log(`   • Total earnings: ${ethers.formatEther(this.performanceTracker.metrics.totalEarnings)} ETH`);
    }
    
    async start() {
        console.log('\n▶️  Starting automated operation...');
        this.isRunning = true;
        
        // Start job scanner
        this.jobScanInterval = setInterval(() => {
            if (this.isRunning && !this.isPaused) {
                this.scanForJobs();
            }
        }, config.operator.jobCheckInterval);
        
        // Start health checker
        this.healthCheckInterval = setInterval(() => {
            this.performHealthCheck();
        }, config.operator.healthCheckInterval);
        
        // Start resource monitor
        this.resourceCheckInterval = setInterval(() => {
            this.resourceMonitor.checkResources();
        }, 5000);
        
        // Listen for events
        this.setupEventListeners();
        
        console.log('   ✅ Automated operation started');
        console.log('   📡 Scanning for jobs...\n');
        
        // Initial scan
        await this.scanForJobs();
    }
    
    async scanForJobs() {
        try {
            const resources = await this.resourceMonitor.checkResources();
            
            if (!this.resourceMonitor.canAcceptJob()) {
                return;
            }
            
            // Get available jobs
            const activeJobIds = await this.contracts.jobMarketplace.getActiveJobs();
            const suitableJobs = [];
            
            for (const jobId of activeJobIds) {
                if (this.activeJobs.has(jobId.toString())) continue;
                
                const job = await this.contracts.jobMarketplace.getJob(jobId);
                
                if (this.isJobSuitable(job)) {
                    suitableJobs.push({
                        id: jobId,
                        job,
                        score: this.scoreJob(job)
                    });
                }
            }
            
            if (suitableJobs.length === 0) return;
            
            // Sort by score and take best jobs
            suitableJobs.sort((a, b) => b.score - a.score);
            const jobsToClaim = suitableJobs.slice(0, 
                Math.min(config.operator.batchSize, config.operator.maxConcurrentJobs - this.activeJobs.size)
            );
            
            // Claim jobs
            for (const { id, job } of jobsToClaim) {
                await this.claimAndProcessJob(id, job);
            }
            
        } catch (error) {
            console.error('❌ Job scan error:', error.message);
        }
    }
    
    isJobSuitable(job) {
        // Check basic criteria
        if (job.status !== 0) return false; // Not posted
        if (job.payment < config.operator.minPayment) return false;
        if (!this.processors.has(job.modelId)) return false;
        
        // Check deadline
        const timeRemaining = Number(job.postedAt) + Number(job.deadline) - Math.floor(Date.now() / 1000);
        if (timeRemaining < 300) return false; // Less than 5 minutes
        
        return true;
    }
    
    scoreJob(job) {
        let score = 0;
        
        // Payment score (normalized to 0-100)
        const paymentScore = Number(job.payment / ethers.parseEther('1')) * 100;
        score += paymentScore * 0.4;
        
        // Model preference score
        const modelIndex = config.operator.preferredModels.indexOf(job.modelId);
        const modelScore = modelIndex >= 0 ? (100 - modelIndex * 20) : 50;
        score += modelScore * 0.3;
        
        // Time score (more time = better)
        const deadline = Number(job.deadline);
        const timeScore = Math.min(deadline / 3600, 1) * 100;
        score += timeScore * 0.2;
        
        // Random factor for diversity
        score += Math.random() * 10;
        
        return score;
    }
    
    async claimAndProcessJob(jobId, job) {
        console.log(`\n🎯 Claiming job #${jobId}`);
        console.log(`   • Model: ${job.modelId}`);
        console.log(`   • Payment: ${ethers.formatEther(job.payment)} ETH`);
        
        try {
            // Claim job
            const claimTx = await this.contracts.jobMarketplace.claimJob(jobId);
            await claimTx.wait();
            console.log('   ✅ Job claimed');
            
            // Add to active jobs
            this.activeJobs.set(jobId.toString(), {
                job,
                claimedAt: Date.now(),
                status: 'processing'
            });
            
            // Process job asynchronously
            this.processJob(jobId, job);
            
        } catch (error) {
            console.error(`   ❌ Failed to claim: ${error.message}`);
        }
    }
    
    async processJob(jobId, job) {
        const startTime = Date.now();
        
        try {
            // Decode input
            const [prompt] = ethers.AbiCoder.defaultAbiCoder().decode(
                ['string', 'uint256', 'string'],
                job.inputData
            );
            
            console.log(`\n🔄 Processing job #${jobId}`);
            console.log(`   • Prompt: "${prompt.substring(0, 50)}..."`);
            
            // Get processor
            const processor = this.processors.get(job.modelId);
            if (!processor) {
                throw new Error('No processor for model');
            }
            
            // Process
            const output = await processor.process(prompt);
            const processingTime = Date.now() - startTime;
            
            console.log(`   ✅ Processing complete (${(processingTime / 1000).toFixed(1)}s)`);
            
            // Encode output
            const outputData = ethers.AbiCoder.defaultAbiCoder().encode(
                ['string', 'uint256', 'uint256', 'string'],
                [output, prompt.length + output.length, Date.now(), 'v1']
            );
            
            // Submit completion
            console.log('   📤 Submitting completion...');
            const completeTx = await this.contracts.jobMarketplace.completeJob(
                jobId,
                outputData
            );
            await completeTx.wait();
            
            console.log(`   ✅ Job #${jobId} completed successfully!`);
            
            // Update metrics
            await this.performanceTracker.recordJob(
                job,
                true,
                job.payment,
                processingTime
            );
            
            // Remove from active jobs
            this.activeJobs.delete(jobId.toString());
            
            // Emit success event
            this.emit('jobCompleted', { jobId, payment: job.payment, processingTime });
            
        } catch (error) {
            console.error(`   ❌ Job #${jobId} failed: ${error.message}`);
            
            // Update metrics
            await this.performanceTracker.recordJob(
                job,
                false,
                ethers.parseEther('0'),
                Date.now() - startTime
            );
            
            // Remove from active jobs
            this.activeJobs.delete(jobId.toString());
            
            // Emit failure event
            this.emit('jobFailed', { jobId, error: error.message });
        }
    }
    
    async performHealthCheck() {
        try {
            // Check reputation
            const reputation = await this.contracts.reputationSystem.getNodeStats(this.wallet.address);
            
            if (reputation.reputationScore < config.operator.emergencyShutdownScore) {
                console.error('\n🚨 EMERGENCY: Reputation critically low!');
                await this.emergencyShutdown();
                return;
            }
            
            if (reputation.reputationScore < config.operator.minReputationScore) {
                console.log('\n⚠️  Warning: Reputation below threshold');
                this.pauseNewJobs();
            }
            
            // Check daily loss limit
            const today = new Date().toISOString().split('T')[0];
            const dailyStats = this.performanceTracker.metrics.dailyStats.get(today);
            
            if (dailyStats && dailyStats.failures > 5) {
                console.log('\n⚠️  Warning: High failure rate today');
                this.pauseNewJobs();
            }
            
            // Check maintenance window
            const now = new Date();
            if (now.getHours() === config.operator.maintenanceWindow.hour) {
                console.log('\n🔧 Entering maintenance window...');
                await this.performMaintenance();
            }
            
        } catch (error) {
            console.error('Health check error:', error);
        }
    }
    
    pauseNewJobs() {
        if (!this.isPaused) {
            console.log('\n⏸️  Pausing new job claims...');
            this.isPaused = true;
            
            // Resume after 5 minutes
            setTimeout(() => {
                console.log('\n▶️  Resuming job claims...');
                this.isPaused = false;
            }, 300000);
        }
    }
    
    async performMaintenance() {
        console.log('   • Clearing old cache entries...');
        for (const processor of this.processors.values()) {
            processor.cache.clear();
        }
        
        console.log('   • Compacting metrics...');
        await this.performanceTracker.saveMetrics();
        
        console.log('   • Running garbage collection...');
        if (global.gc) {
            global.gc();
        }
        
        console.log('   ✅ Maintenance complete');
    }
    
    async emergencyShutdown() {
        console.log('\n🛑 EMERGENCY SHUTDOWN INITIATED');
        this.isRunning = false;
        
        // Stop all intervals
        clearInterval(this.jobScanInterval);
        clearInterval(this.healthCheckInterval);
        clearInterval(this.resourceCheckInterval);
        
        // Wait for active jobs to complete
        console.log(`   Waiting for ${this.activeJobs.size} active jobs...`);
        
        const timeout = setTimeout(() => {
            console.log('   ⚠️  Timeout waiting for jobs');
            process.exit(1);
        }, 60000);
        
        while (this.activeJobs.size > 0) {
            await new Promise(resolve => setTimeout(resolve, 1000));
        }
        
        clearTimeout(timeout);
        
        console.log('   ✅ All jobs completed');
        console.log('   📊 Final metrics saved');
        
        await this.performanceTracker.saveMetrics();
        
        process.exit(0);
    }
    
    setupEventListeners() {
        // Job events
        this.contracts.jobMarketplace.on('JobPosted', (jobId, poster, modelId, payment) => {
            if (this.processors.has(modelId)) {
                console.log(`\n🔔 New job posted: #${jobId} (${modelId})`);
            }
        });
        
        // Handle process termination
        process.on('SIGINT', async () => {
            console.log('\n\n👋 Graceful shutdown requested...');
            await this.emergencyShutdown();
        });
        
        process.on('SIGTERM', async () => {
            console.log('\n\n👋 Graceful shutdown requested...');
            await this.emergencyShutdown();
        });
    }
    
    getStatus() {
        return {
            isRunning: this.isRunning,
            isPaused: this.isPaused,
            activeJobs: this.activeJobs.size,
            performance: {
                jobsCompleted: this.performanceTracker.metrics.jobsCompleted,
                successRate: this.performanceTracker.metrics.successRate,
                totalEarnings: ethers.formatEther(this.performanceTracker.metrics.totalEarnings),
                averageProcessingTime: this.performanceTracker.metrics.averageProcessingTime
            },
            resources: this.resourceMonitor.metrics
        };
    }
}

// Main function
async function main() {
    try {
        console.log('🤖 Fabstir Automated Node Operator\n');
        console.log('━'.repeat(50));
        
        // Setup
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`Node Address: ${wallet.address}`);
        console.log(`Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        console.log('━'.repeat(50) + '\n');
        
        // Initialize contracts
        const contracts = {
            nodeRegistry: new ethers.Contract(
                config.contracts.nodeRegistry,
                NODE_REGISTRY_ABI,
                wallet
            ),
            jobMarketplace: new ethers.Contract(
                config.contracts.jobMarketplace,
                JOB_MARKETPLACE_ABI,
                wallet
            ),
            reputationSystem: new ethers.Contract(
                config.contracts.reputationSystem,
                REPUTATION_SYSTEM_ABI,
                provider
            ),
            proofSystem: new ethers.Contract(
                config.contracts.proofSystem,
                PROOF_SYSTEM_ABI,
                wallet
            )
        };
        
        // Create and initialize operator
        const operator = new AutomatedNodeOperator(contracts, wallet);
        await operator.initialize();
        
        // Set up status display
        const displayStatus = () => {
            const status = operator.getStatus();
            console.log('\n📊 Status Update ' + new Date().toLocaleTimeString());
            console.log('━'.repeat(50));
            console.log(`Active Jobs: ${status.activeJobs}/${config.operator.maxConcurrentJobs}`);
            console.log(`Jobs Completed: ${status.performance.jobsCompleted}`);
            console.log(`Success Rate: ${status.performance.successRate.toFixed(1)}%`);
            console.log(`Total Earnings: ${status.performance.totalEarnings} ETH`);
            console.log(`Resources - CPU: ${status.resources.cpu.toFixed(1)}% | Memory: ${status.resources.memory.toFixed(1)}% | GPU: ${status.resources.gpu.toFixed(1)}%`);
            console.log('━'.repeat(50));
        };
        
        // Display status every minute
        setInterval(displayStatus, 60000);
        
        // Handle operator events
        operator.on('jobCompleted', ({ jobId, payment, processingTime }) => {
            console.log(`\n💰 Payment received: ${ethers.formatEther(payment)} ETH`);
        });
        
        operator.on('jobFailed', ({ jobId, error }) => {
            console.log(`\n⚠️  Job ${jobId} failed: ${error}`);
        });
        
        // Start automated operation
        await operator.start();
        
        console.log('\n🚀 Automated node operator is running!');
        console.log('   • Max concurrent jobs:', config.operator.maxConcurrentJobs);
        console.log('   • Min payment:', ethers.formatEther(config.operator.minPayment), 'ETH');
        console.log('   • Preferred models:', config.operator.preferredModels.join(', '));
        console.log('\nPress Ctrl+C for graceful shutdown\n');
        
        // Keep running
        await new Promise(() => {});
        
    } catch (error) {
        console.error('\n❌ Fatal error:', error.message);
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = { 
    AutomatedNodeOperator,
    JobProcessor,
    ResourceMonitor,
    PerformanceTracker,
    config
};

/**
 * Expected Output:
 * 
 * 🤖 Fabstir Automated Node Operator
 * ══════════════════════════════════════════════════
 * Node Address: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 * Network: Base Mainnet
 * ══════════════════════════════════════════════════
 * 
 * 🚀 Initializing Automated Node Operator...
 *    ✅ Node verified
 *    • Models: gpt-4, claude-2, llama-2-70b
 *    • Stake: 100.0 ETH
 *    • Reputation: 875/1000
 *    ✅ Initialization complete
 * 
 * 📊 Current Performance:
 *    • Jobs completed: 1247
 *    • Success rate: 98.5%
 *    • Total earnings: 245.75 ETH
 * 
 * ▶️  Starting automated operation...
 *    ✅ Automated operation started
 *    📡 Scanning for jobs...
 * 
 * 🎯 Claiming job #142
 *    • Model: gpt-4
 *    • Payment: 0.15 ETH
 *    ✅ Job claimed
 * 
 * 🔄 Processing job #142
 *    • Prompt: "Explain the benefits of decentralized AI..."
 *    🤖 Processing with gpt-4...
 *    ✅ Processing complete (8.3s)
 *    📤 Submitting completion...
 *    ✅ Job #142 completed successfully!
 * 
 * 💰 Payment received: 0.15 ETH
 * 
 * 🔔 New job posted: #143 (claude-2)
 * 
 * 🎯 Claiming job #143
 *    • Model: claude-2
 *    • Payment: 0.12 ETH
 *    ✅ Job claimed
 * 
 * 📊 Status Update 10:45:23 AM
 * ══════════════════════════════════════════════════
 * Active Jobs: 1/3
 * Jobs Completed: 1248
 * Success Rate: 98.5%
 * Total Earnings: 245.87 ETH
 * Resources - CPU: 45.2% | Memory: 62.1% | GPU: 78.5%
 * ══════════════════════════════════════════════════
 * 
 * 🚀 Automated node operator is running!
 *    • Max concurrent jobs: 3
 *    • Min payment: 0.05 ETH
 *    • Preferred models: gpt-4, claude-2, llama-2-70b
 * 
 * Press Ctrl+C for graceful shutdown
 * 
 * [Continues running and processing jobs automatically...]
 */