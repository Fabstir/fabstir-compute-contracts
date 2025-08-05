# Claiming Jobs Guide

This guide covers strategies and best practices for efficiently claiming and processing jobs as a Fabstir node operator.

## Prerequisites

- Registered node with active stake
- Node software running (see [Running a Node](running-a-node.md))
- Understanding of supported models
- Monitoring system in place

## Job Claiming Overview

```
Available Jobs → Filter by Criteria → Claim Job → Process → Submit Result → Get Paid
       ↓              ↓                    ↓          ↓            ↓
    Monitor      Profitability      Race Condition  Timeout    Proof Required
```

## Step 1: Monitor Available Jobs

### Basic Job Monitor
```javascript
const { ethers } = require("ethers");
const EventEmitter = require("events");

class JobMonitor extends EventEmitter {
    constructor(config) {
        super();
        this.provider = new ethers.JsonRpcProvider(config.rpcUrl);
        this.marketplace = new ethers.Contract(
            config.marketplaceAddress,
            config.marketplaceABI,
            this.provider
        );
        this.supportedModels = config.supportedModels;
    }
    
    async start() {
        console.log("Starting job monitor...");
        
        // Listen for new jobs
        this.marketplace.on("JobCreated", async (jobId, renter, modelId, maxPrice) => {
            console.log(`New job #${jobId}: ${modelId} for ${ethers.formatEther(maxPrice)} ETH`);
            
            if (this.shouldClaimJob(modelId, maxPrice)) {
                this.emit("jobAvailable", { jobId, modelId, maxPrice });
            }
        });
        
        // Scan existing jobs
        await this.scanExistingJobs();
    }
    
    shouldClaimJob(modelId, maxPrice) {
        // Check if we support the model
        if (!this.supportedModels.includes(modelId)) {
            return false;
        }
        
        // Check minimum payment threshold
        const minPayment = ethers.parseEther("0.001");
        if (maxPrice < minPayment) {
            return false;
        }
        
        return true;
    }
    
    async scanExistingJobs() {
        const events = await this.marketplace.queryFilter("JobCreated", -1000);
        
        for (const event of events) {
            const jobId = event.args.jobId;
            const job = await this.getJobDetails(jobId);
            
            if (job.status === 0 && this.shouldClaimJob(job.modelId, job.payment)) {
                this.emit("jobAvailable", job);
            }
        }
    }
    
    async getJobDetails(jobId) {
        const job = await this.marketplace.getJob(jobId);
        return {
            jobId,
            renter: job[0],
            payment: job[1],
            status: job[2],
            modelId: job[3],
            deadline: job[5]
        };
    }
}
```

### Advanced Job Scanner with Filtering
```javascript
class AdvancedJobScanner {
    constructor(config) {
        this.config = config;
        this.filters = {
            minPayment: ethers.parseEther(config.minPayment || "0.001"),
            maxConcurrent: config.maxConcurrent || 10,
            preferredModels: config.preferredModels || [],
            regionMatch: config.regionMatch || false,
            minReputation: config.minReputation || 0
        };
        this.activeJobs = new Map();
    }
    
    async evaluateJob(job) {
        const score = await this.calculateJobScore(job);
        
        return {
            jobId: job.jobId,
            score,
            profitable: score > this.config.minProfitScore,
            estimatedProfit: await this.estimateProfit(job),
            estimatedTime: await this.estimateProcessingTime(job),
            recommendation: this.getRecommendation(score)
        };
    }
    
    async calculateJobScore(job) {
        let score = 0;
        
        // Payment score (0-40 points)
        const paymentScore = Math.min(40, 
            (Number(ethers.formatEther(job.payment)) / 0.1) * 40
        );
        score += paymentScore;
        
        // Model preference score (0-20 points)
        const modelIndex = this.filters.preferredModels.indexOf(job.modelId);
        if (modelIndex >= 0) {
            score += 20 - (modelIndex * 2);
        }
        
        // Deadline score (0-20 points)
        const timeUntilDeadline = job.deadline - Date.now() / 1000;
        const deadlineScore = Math.min(20, (timeUntilDeadline / 3600) * 5);
        score += deadlineScore;
        
        // Competition score (0-20 points)
        const competition = await this.estimateCompetition(job);
        score += 20 - (competition * 4);
        
        return score;
    }
    
    async estimateProfit(job) {
        const payment = Number(ethers.formatEther(job.payment));
        const platformFee = payment * 0.025; // 2.5%
        
        // Estimate costs
        const computeCost = await this.estimateComputeCost(job);
        const gasCost = await this.estimateGasCost();
        
        const profit = payment - platformFee - computeCost - gasCost;
        
        return {
            gross: payment,
            platformFee,
            computeCost,
            gasCost,
            net: profit,
            margin: (profit / payment) * 100
        };
    }
    
    async estimateComputeCost(job) {
        const modelCosts = {
            "gpt-4": 0.0001,      // $ per 1k tokens
            "gpt-3.5-turbo": 0.00002,
            "llama-2-70b": 0.00005,
            "mistral-7b": 0.00001
        };
        
        const baseCost = modelCosts[job.modelId] || 0.00005;
        const estimatedTokens = 2000; // Average job size
        
        return (baseCost * estimatedTokens) / 1000;
    }
    
    async estimateCompetition(job) {
        // Check how many nodes support this model
        const activeNodes = await this.getActiveNodesForModel(job.modelId);
        const jobsPerNode = await this.getAverageJobsPerNode();
        
        return Math.min(5, activeNodes / jobsPerNode);
    }
    
    getRecommendation(score) {
        if (score >= 80) return "CLAIM_IMMEDIATELY";
        if (score >= 60) return "CLAIM_IF_AVAILABLE";
        if (score >= 40) return "CONSIDER";
        return "SKIP";
    }
}
```

## Step 2: Optimize Job Selection

### Profit Maximization Strategy
```javascript
class ProfitOptimizer {
    constructor(nodeCapabilities) {
        this.capabilities = nodeCapabilities;
        this.performanceHistory = new Map();
    }
    
    async selectBestJobs(availableJobs) {
        // Score and rank all jobs
        const scoredJobs = await Promise.all(
            availableJobs.map(job => this.scoreJob(job))
        );
        
        // Sort by profitability
        scoredJobs.sort((a, b) => b.profitPerHour - a.profitPerHour);
        
        // Select jobs that maximize profit within constraints
        const selectedJobs = [];
        let totalGPUUsage = 0;
        let totalMemoryUsage = 0;
        
        for (const job of scoredJobs) {
            if (this.canHandleJob(job, totalGPUUsage, totalMemoryUsage)) {
                selectedJobs.push(job);
                totalGPUUsage += job.estimatedGPUUsage;
                totalMemoryUsage += job.estimatedMemoryUsage;
                
                if (selectedJobs.length >= this.capabilities.maxConcurrentJobs) {
                    break;
                }
            }
        }
        
        return selectedJobs;
    }
    
    async scoreJob(job) {
        const processingTime = await this.estimateProcessingTime(job);
        const profit = await this.calculateNetProfit(job);
        
        return {
            ...job,
            processingTime,
            profit,
            profitPerHour: (profit / processingTime) * 3600,
            estimatedGPUUsage: this.estimateGPUUsage(job),
            estimatedMemoryUsage: this.estimateMemoryUsage(job)
        };
    }
    
    canHandleJob(job, currentGPUUsage, currentMemoryUsage) {
        const totalGPU = currentGPUUsage + job.estimatedGPUUsage;
        const totalMemory = currentMemoryUsage + job.estimatedMemoryUsage;
        
        return (
            totalGPU <= this.capabilities.totalGPUCapacity &&
            totalMemory <= this.capabilities.totalMemoryCapacity &&
            this.capabilities.supportedModels.includes(job.modelId)
        );
    }
    
    async estimateProcessingTime(job) {
        // Use historical data if available
        const history = this.performanceHistory.get(job.modelId);
        if (history) {
            return history.averageTime * (job.estimatedTokens / 1000);
        }
        
        // Default estimates
        const baseTime = {
            "gpt-4": 30,
            "gpt-3.5-turbo": 10,
            "llama-2-70b": 45,
            "mistral-7b": 8
        };
        
        return baseTime[job.modelId] || 20;
    }
}
```

### Batch Claiming Strategy
```javascript
class BatchJobClaimer {
    constructor(wallet, marketplace) {
        this.wallet = wallet;
        this.marketplace = marketplace;
        this.claimQueue = [];
        this.processing = false;
    }
    
    addToQueue(job) {
        this.claimQueue.push(job);
        if (!this.processing) {
            this.processClaims();
        }
    }
    
    async processClaims() {
        this.processing = true;
        
        while (this.claimQueue.length > 0) {
            const batch = this.claimQueue.splice(0, 5); // Process 5 at a time
            
            try {
                await this.claimBatch(batch);
            } catch (error) {
                console.error("Batch claim failed:", error);
                // Re-queue failed jobs
                this.claimQueue.unshift(...batch);
            }
            
            // Small delay between batches
            await new Promise(resolve => setTimeout(resolve, 1000));
        }
        
        this.processing = false;
    }
    
    async claimBatch(jobs) {
        // Try to claim multiple jobs in one transaction
        const multicallData = jobs.map(job => 
            this.marketplace.interface.encodeFunctionData("claimJob", [job.jobId])
        );
        
        // Use multicall if available
        if (this.marketplace.multicall) {
            const tx = await this.marketplace.multicall(multicallData);
            await tx.wait();
        } else {
            // Fall back to individual claims
            for (const job of jobs) {
                await this.claimSingleJob(job);
            }
        }
    }
    
    async claimSingleJob(job) {
        const maxRetries = 3;
        let attempt = 0;
        
        while (attempt < maxRetries) {
            try {
                const tx = await this.marketplace.claimJob(job.jobId, {
                    gasLimit: 200000,
                    maxFeePerGas: await this.getOptimalGasPrice(),
                    maxPriorityFeePerGas: ethers.parseUnits("2", "gwei")
                });
                
                const receipt = await tx.wait();
                console.log(`Claimed job ${job.jobId} in block ${receipt.blockNumber}`);
                return receipt;
                
            } catch (error) {
                attempt++;
                if (error.message.includes("Job already claimed")) {
                    console.log(`Job ${job.jobId} was claimed by another node`);
                    break;
                }
                
                if (attempt < maxRetries) {
                    await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
                }
            }
        }
    }
    
    async getOptimalGasPrice() {
        const feeData = await this.wallet.provider.getFeeData();
        const baseGasPrice = feeData.gasPrice;
        
        // Add 10% buffer for competitive claiming
        return baseGasPrice * 110n / 100n;
    }
}
```

## Step 3: Efficient Job Processing

### Job Processing Pipeline
```javascript
class JobProcessor {
    constructor(config) {
        this.config = config;
        this.jobQueue = [];
        this.activeJobs = new Map();
        this.modelRunners = new Map();
        
        this.initializeModelRunners();
    }
    
    initializeModelRunners() {
        // Initialize model-specific runners
        this.modelRunners.set("gpt-4", new GPT4Runner(this.config));
        this.modelRunners.set("llama-2-70b", new LlamaRunner(this.config));
        // Add more models...
    }
    
    async processJob(job) {
        const startTime = Date.now();
        
        try {
            // 1. Fetch job details
            const jobDetails = await this.fetchJobDetails(job.jobId);
            
            // 2. Download input data
            const input = await this.downloadInput(jobDetails.inputHash);
            
            // 3. Select appropriate model runner
            const runner = this.modelRunners.get(jobDetails.modelId);
            if (!runner) {
                throw new Error(`Unsupported model: ${jobDetails.modelId}`);
            }
            
            // 4. Process the job
            const result = await runner.process(input, jobDetails.parameters);
            
            // 5. Upload result to IPFS
            const resultCID = await this.uploadResult(result);
            
            // 6. Generate proof
            const proof = await this.generateProof(
                jobDetails.modelId,
                jobDetails.inputHash,
                resultCID
            );
            
            // 7. Submit completion
            await this.submitCompletion(job.jobId, resultCID, proof);
            
            // Record performance metrics
            this.recordPerformance(job.jobId, startTime);
            
        } catch (error) {
            console.error(`Failed to process job ${job.jobId}:`, error);
            await this.handleJobFailure(job.jobId, error);
        }
    }
    
    async downloadInput(inputHash) {
        // Download from IPFS
        const response = await fetch(`${this.config.ipfsGateway}/${inputHash}`);
        return await response.text();
    }
    
    async uploadResult(result) {
        const ipfs = this.config.ipfsClient;
        const { cid } = await ipfs.add(JSON.stringify(result));
        return cid.toString();
    }
    
    async generateProof(modelId, inputHash, outputHash) {
        // Generate EZKL proof
        const proof = {
            modelCommitment: ethers.id(modelId),
            inputHash: inputHash,
            outputHash: ethers.id(outputHash),
            timestamp: Date.now(),
            nodeSignature: await this.signProof(outputHash)
        };
        
        return ethers.AbiCoder.defaultAbiCoder().encode(
            ["bytes32", "bytes32", "bytes32", "uint256", "bytes"],
            Object.values(proof)
        );
    }
    
    async submitCompletion(jobId, resultCID, proof) {
        const tx = await this.marketplace.completeJob(jobId, resultCID, proof, {
            gasLimit: 300000
        });
        
        await tx.wait();
        console.log(`Job ${jobId} completed successfully`);
    }
    
    recordPerformance(jobId, startTime) {
        const duration = Date.now() - startTime;
        const job = this.activeJobs.get(jobId);
        
        // Update performance history
        this.performanceHistory.record({
            jobId,
            modelId: job.modelId,
            duration,
            tokensProcessed: job.estimatedTokens,
            success: true
        });
    }
}
```

### Parallel Processing
```javascript
class ParallelJobProcessor {
    constructor(maxConcurrent = 5) {
        this.maxConcurrent = maxConcurrent;
        this.activeCount = 0;
        this.queue = [];
    }
    
    async addJob(job) {
        if (this.activeCount < this.maxConcurrent) {
            this.processJob(job);
        } else {
            this.queue.push(job);
        }
    }
    
    async processJob(job) {
        this.activeCount++;
        
        try {
            await this.runJob(job);
        } finally {
            this.activeCount--;
            
            // Process next job in queue
            if (this.queue.length > 0) {
                const nextJob = this.queue.shift();
                this.processJob(nextJob);
            }
        }
    }
    
    async runJob(job) {
        // Allocate resources
        const resources = await this.allocateResources(job);
        
        try {
            // Run in isolated environment
            const result = await this.runInContainer(job, resources);
            await this.submitResult(job.jobId, result);
        } finally {
            // Release resources
            await this.releaseResources(resources);
        }
    }
    
    async allocateResources(job) {
        // GPU allocation logic
        const requiredGPUs = this.getRequiredGPUs(job.modelId);
        const availableGPUs = await this.getAvailableGPUs();
        
        if (availableGPUs.length < requiredGPUs) {
            throw new Error("Insufficient GPU resources");
        }
        
        return {
            gpus: availableGPUs.slice(0, requiredGPUs),
            memory: this.getRequiredMemory(job.modelId),
            container: await this.createContainer(job)
        };
    }
}
```

## Step 4: Monitoring and Analytics

### Performance Dashboard
```javascript
class NodeDashboard {
    constructor() {
        this.metrics = {
            jobsCompleted: 0,
            jobsFailed: 0,
            totalEarnings: 0,
            averageProcessingTime: 0,
            successRate: 0,
            reputationScore: 0
        };
    }
    
    async updateMetrics() {
        // Fetch on-chain data
        const node = await nodeRegistry.getNode(this.nodeAddress);
        const reputation = await reputationSystem.getReputation(this.nodeAddress);
        
        this.metrics.reputationScore = reputation;
        
        // Calculate success rate
        const total = this.metrics.jobsCompleted + this.metrics.jobsFailed;
        this.metrics.successRate = total > 0 
            ? (this.metrics.jobsCompleted / total) * 100 
            : 0;
            
        // Update dashboard
        this.renderDashboard();
    }
    
    renderDashboard() {
        console.clear();
        console.log("=== Fabstir Node Dashboard ===");
        console.log(`Jobs Completed: ${this.metrics.jobsCompleted}`);
        console.log(`Success Rate: ${this.metrics.successRate.toFixed(2)}%`);
        console.log(`Total Earnings: ${this.metrics.totalEarnings.toFixed(4)} ETH`);
        console.log(`Avg Processing Time: ${this.metrics.averageProcessingTime}s`);
        console.log(`Reputation Score: ${this.metrics.reputationScore}`);
        console.log("\nActive Jobs:");
        this.renderActiveJobs();
    }
}
```

## Common Issues & Solutions

### Issue: Losing Job Claims to Other Nodes
```javascript
// Solution: Implement MEV protection
async function claimWithMEVProtection(job) {
    // Use flashbots or similar
    const flashbotsProvider = new ethers.providers.JsonRpcProvider(
        "https://rpc.flashbots.net"
    );
    
    // Submit private transaction
    const signedTx = await wallet.signTransaction({
        to: MARKETPLACE_ADDRESS,
        data: marketplace.interface.encodeFunctionData("claimJob", [job.jobId]),
        gasLimit: 200000,
        maxFeePerGas: ethers.parseUnits("50", "gwei"),
        maxPriorityFeePerGas: ethers.parseUnits("5", "gwei")
    });
    
    const result = await flashbotsProvider.send(
        "eth_sendPrivateTransaction",
        [signedTx]
    );
}
```

### Issue: Job Processing Timeout
```javascript
// Solution: Implement job estimation and filtering
function canCompleteInTime(job, estimatedProcessingTime) {
    const currentTime = Math.floor(Date.now() / 1000);
    const timeRemaining = job.deadline - currentTime;
    const buffer = 300; // 5 minute buffer
    
    return timeRemaining > (estimatedProcessingTime + buffer);
}
```

### Issue: Resource Contention
```javascript
// Solution: Implement resource scheduler
class ResourceScheduler {
    scheduleJob(job) {
        const resources = this.estimateResources(job);
        
        if (this.canAllocate(resources)) {
            return this.allocate(resources);
        }
        
        // Queue job for later
        return this.queueForResources(job, resources);
    }
}
```

## Best Practices

### 1. Job Selection
- Set minimum profitability thresholds
- Prioritize jobs you can complete quickly
- Consider reputation impact
- Monitor gas prices

### 2. Processing Efficiency
- Use GPU batching where possible
- Cache common model outputs
- Implement result compression
- Monitor resource usage

### 3. Risk Management
- Don't claim jobs near deadline
- Maintain processing redundancy
- Monitor failure rates
- Keep reputation high

### 4. Optimization Tips
```javascript
// Pre-load models for faster processing
const preloadModels = async () => {
    const commonModels = ["gpt-4", "llama-2-70b"];
    for (const model of commonModels) {
        await modelLoader.preload(model);
    }
};

// Implement smart caching
const cache = new LRUCache({
    max: 100,
    ttl: 1000 * 60 * 60 // 1 hour
});

// Use connection pooling
const connectionPool = new ConnectionPool({
    max: 10,
    idleTimeout: 30000
});
```

## Next Steps

1. **[Advanced Monitoring](../advanced/monitoring-setup.md)** - Track performance
2. **[Building Applications](../developers/building-on-fabstir.md)** - Automate operations
3. **[Governance](../advanced/governance-participation.md)** - Influence job parameters

## Resources

- [GPU Optimization Guide](https://docs.nvidia.com/datacenter/)
- [IPFS Best Practices](https://docs.ipfs.io/how-to/best-practices/)
- [Base Network Gas Tracker](https://basescan.org/gastracker)
- [Model Performance Benchmarks](https://huggingface.co/spaces/optimum/llm-perf-leaderboard)

---

Questions? Join our [Node Operators Channel](https://discord.gg/fabstir-nodes) →