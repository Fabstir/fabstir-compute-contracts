# Posting Jobs Guide

This comprehensive guide covers how to post AI inference jobs on the Fabstir marketplace, from basic requests to advanced configurations.

## Prerequisites

- Base wallet with ETH for job payments
- Understanding of AI models and parameters
- IPFS access (optional, for large inputs)
- Basic knowledge of Web3 interactions

## Job Posting Overview

```
Prepare Input → Select Model → Set Parameters → Calculate Payment → Post Job → Monitor → Get Results
      ↓              ↓               ↓                ↓               ↓          ↓
   Format      Requirements     Optimization      Fair Price      On-chain    Track
```

## Step 1: Understanding Job Structure

### Basic Job Components
```javascript
const jobStructure = {
    // Core components
    modelId: "gpt-4",              // AI model to use
    inputData: "Your prompt here",  // Input text/data
    payment: "0.01",               // Payment in ETH
    deadline: 3600,                // Time limit in seconds
    
    // Advanced parameters
    maxTokens: 2000,               // Maximum output length
    temperature: 0.7,              // Creativity (0-2)
    seed: 42,                      // For reproducibility
    
    // Requirements
    minGPUMemory: 24,              // Minimum GPU VRAM (GB)
    minReputation: 100,            // Minimum node reputation
    requiresProof: true            // Require proof of computation
};
```

### Payment Calculation
```javascript
class JobPricingCalculator {
    constructor() {
        // Base rates per model (ETH per 1k tokens)
        this.modelRates = {
            "gpt-4": 0.00003,
            "gpt-3.5-turbo": 0.000002,
            "claude-2": 0.00002,
            "llama-2-70b": 0.00001,
            "llama-2-13b": 0.000005,
            "mistral-7b": 0.000003,
            "stable-diffusion-xl": 0.00005
        };
        
        // Urgency multipliers
        this.urgencyMultipliers = {
            standard: 1.0,    // 1 hour deadline
            priority: 1.5,    // 30 min deadline
            urgent: 2.0,      // 15 min deadline
            critical: 3.0     // 5 min deadline
        };
    }
    
    calculateJobPrice(modelId, estimatedTokens, urgency = "standard") {
        const baseRate = this.modelRates[modelId] || 0.00001;
        const tokenCost = (estimatedTokens / 1000) * baseRate;
        const urgencyMultiplier = this.urgencyMultipliers[urgency];
        
        const subtotal = tokenCost * urgencyMultiplier;
        const platformFee = subtotal * 0.025; // 2.5% fee
        
        return {
            basePrice: tokenCost,
            urgencyPremium: tokenCost * (urgencyMultiplier - 1),
            platformFee: platformFee,
            total: subtotal + platformFee,
            breakdown: {
                model: modelId,
                tokens: estimatedTokens,
                urgency: urgency,
                ratePerKToken: baseRate
            }
        };
    }
    
    estimateTokenCount(prompt, expectedOutput = "medium") {
        // Rough estimation
        const promptTokens = prompt.split(' ').length * 1.3;
        
        const outputSizes = {
            short: 100,
            medium: 500,
            long: 1500,
            maximum: 4000
        };
        
        const outputTokens = outputSizes[expectedOutput] || 500;
        
        return promptTokens + outputTokens;
    }
}

// Example usage
const calculator = new JobPricingCalculator();
const pricing = calculator.calculateJobPrice("gpt-4", 2000, "priority");
console.log(`Total cost: ${pricing.total.toFixed(4)} ETH`);
```

## Step 2: Simple Job Posting

### Basic Job Post
```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function postSimpleJob() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    const jobMarketplaceABI = [
        "function createJob(string _modelId, string _inputHash, uint256 _maxPrice, uint256 _deadline) payable returns (uint256)",
        "event JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice)"
    ];
    
    const marketplace = new ethers.Contract(
        process.env.JOB_MARKETPLACE_ADDRESS,
        jobMarketplaceABI,
        wallet
    );
    
    // Job parameters
    const job = {
        modelId: "gpt-4",
        prompt: "Write a comprehensive guide about blockchain consensus mechanisms",
        payment: ethers.parseEther("0.01"),
        deadline: Math.floor(Date.now() / 1000) + 3600 // 1 hour
    };
    
    // Hash the input (for privacy)
    const inputHash = ethers.id(job.prompt);
    
    console.log("Posting job...");
    const tx = await marketplace.createJob(
        job.modelId,
        inputHash,
        job.payment,
        job.deadline,
        { value: job.payment }
    );
    
    const receipt = await tx.wait();
    console.log("Job posted! Transaction:", receipt.hash);
    
    // Get job ID from event
    const event = receipt.logs.find(log => {
        try {
            return marketplace.interface.parseLog(log).name === "JobCreated";
        } catch { return false; }
    });
    
    const jobId = event.args.jobId;
    console.log("Job ID:", jobId.toString());
    
    return jobId;
}
```

### Advanced Job with Parameters
```javascript
async function postAdvancedJob() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    const jobMarketplaceABI = [
        "function postJob(tuple(string modelId, string prompt, uint256 maxTokens, uint256 temperature, uint32 seed, string resultFormat) details, tuple(uint256 minGPUMemory, uint256 minReputationScore, uint256 maxTimeToComplete, bool requiresProof) requirements, uint256 payment) payable returns (uint256)"
    ];
    
    const marketplace = new ethers.Contract(
        process.env.JOB_MARKETPLACE_ADDRESS,
        jobMarketplaceABI,
        wallet
    );
    
    const jobDetails = {
        modelId: "gpt-4",
        prompt: "Analyze the following code and suggest optimizations:\n```solidity\n[code here]\n```",
        maxTokens: 2000,
        temperature: 300, // 0.3 * 1000 for precision
        seed: 42,
        resultFormat: "json"
    };
    
    const requirements = {
        minGPUMemory: 24,        // 24GB VRAM minimum
        minReputationScore: 150, // High reputation nodes only
        maxTimeToComplete: 1800, // 30 minutes
        requiresProof: true      // Require computation proof
    };
    
    const payment = ethers.parseEther("0.02");
    
    console.log("Posting advanced job...");
    const tx = await marketplace.postJob(
        jobDetails,
        requirements,
        payment,
        { 
            value: payment,
            gasLimit: 300000
        }
    );
    
    const receipt = await tx.wait();
    console.log("Advanced job posted!");
    
    return receipt;
}
```

## Step 3: Handling Large Inputs

### IPFS Integration
```javascript
const IPFS = require('ipfs-http-client');

class IPFSJobManager {
    constructor(ipfsUrl = 'http://localhost:5001') {
        this.ipfs = IPFS.create({ url: ipfsUrl });
    }
    
    async uploadLargeInput(data) {
        // For large prompts or datasets
        const file = {
            path: 'job-input.json',
            content: JSON.stringify(data)
        };
        
        const result = await this.ipfs.add(file);
        console.log("Uploaded to IPFS:", result.cid.toString());
        
        return result.cid.toString();
    }
    
    async postJobWithIPFS(jobData) {
        // Upload large input to IPFS
        const inputCID = await this.uploadLargeInput({
            prompt: jobData.prompt,
            context: jobData.context,
            examples: jobData.examples,
            parameters: jobData.parameters
        });
        
        // Post job with IPFS hash
        const job = {
            modelId: jobData.modelId,
            inputHash: inputCID, // IPFS CID instead of hash
            payment: jobData.payment,
            deadline: jobData.deadline
        };
        
        // Continue with normal job posting...
        return await postJobWithHash(job);
    }
    
    async downloadResult(resultCID) {
        const chunks = [];
        for await (const chunk of this.ipfs.cat(resultCID)) {
            chunks.push(chunk);
        }
        
        const data = Buffer.concat(chunks).toString();
        return JSON.parse(data);
    }
}
```

### Structured Data Jobs
```javascript
class StructuredJobPoster {
    async postDataAnalysisJob(dataset, analysisType) {
        const jobInput = {
            type: "data_analysis",
            dataset: dataset,
            analysis: {
                type: analysisType,
                outputFormat: "csv",
                includeVisualization: true
            },
            modelRequirements: {
                capabilities: ["data_analysis", "visualization"],
                minMemory: 32
            }
        };
        
        // Compress if large
        const compressed = await this.compressData(jobInput);
        const inputCID = await this.uploadToIPFS(compressed);
        
        const job = {
            modelId: "claude-2-data",
            inputHash: inputCID,
            payment: this.calculateDataJobPrice(dataset),
            deadline: this.calculateDataJobDeadline(dataset)
        };
        
        return await this.postJob(job);
    }
    
    async postImageGenerationJob(prompt, style, resolution) {
        const jobInput = {
            type: "image_generation",
            prompt: prompt,
            parameters: {
                style: style,
                resolution: resolution,
                steps: 50,
                guidance_scale: 7.5,
                negative_prompt: "blurry, low quality",
                seed: Math.floor(Math.random() * 1000000)
            }
        };
        
        const payment = this.calculateImageJobPrice(resolution);
        
        return await this.postJob({
            modelId: "stable-diffusion-xl",
            inputHash: ethers.id(JSON.stringify(jobInput)),
            payment: payment,
            deadline: Math.floor(Date.now() / 1000) + 600 // 10 minutes
        });
    }
}
```

## Step 4: Batch Job Posting

### Efficient Batch Operations
```javascript
class BatchJobPoster {
    constructor(marketplace, wallet) {
        this.marketplace = marketplace;
        this.wallet = wallet;
    }
    
    async postBatchJobs(jobs) {
        // Prepare batch data
        const details = [];
        const requirements = [];
        const payments = [];
        let totalPayment = ethers.BigNumber.from(0);
        
        for (const job of jobs) {
            details.push({
                modelId: job.modelId,
                prompt: job.prompt,
                maxTokens: job.maxTokens || 1000,
                temperature: job.temperature || 700,
                seed: job.seed || 0,
                resultFormat: job.resultFormat || "text"
            });
            
            requirements.push({
                minGPUMemory: job.minGPUMemory || 8,
                minReputationScore: job.minReputation || 0,
                maxTimeToComplete: job.deadline || 3600,
                requiresProof: job.requiresProof || false
            });
            
            const payment = ethers.parseEther(job.payment.toString());
            payments.push(payment);
            totalPayment = totalPayment.add(payment);
        }
        
        console.log(`Posting ${jobs.length} jobs, total cost: ${ethers.formatEther(totalPayment)} ETH`);
        
        // Post batch
        const tx = await this.marketplace.batchPostJobs(
            details,
            requirements,
            payments,
            { 
                value: totalPayment,
                gasLimit: 150000 * jobs.length // Rough estimate
            }
        );
        
        const receipt = await tx.wait();
        console.log("Batch posted! Gas used:", receipt.gasUsed.toString());
        
        // Extract job IDs
        const jobIds = this.extractJobIds(receipt);
        return jobIds;
    }
    
    extractJobIds(receipt) {
        const jobIds = [];
        
        for (const log of receipt.logs) {
            try {
                const parsed = this.marketplace.interface.parseLog(log);
                if (parsed.name === "JobPosted") {
                    jobIds.push(parsed.args.jobId);
                }
            } catch {}
        }
        
        return jobIds;
    }
}

// Example: Post multiple related jobs
async function postRelatedJobs() {
    const batchPoster = new BatchJobPoster(marketplace, wallet);
    
    const jobs = [
        {
            modelId: "gpt-4",
            prompt: "Summarize this article: [article text]",
            payment: 0.005,
            maxTokens: 500
        },
        {
            modelId: "gpt-4", 
            prompt: "Extract key points from the summary",
            payment: 0.003,
            maxTokens: 200,
            minReputation: 100
        },
        {
            modelId: "stable-diffusion-xl",
            prompt: "Create an infographic of the key points",
            payment: 0.01,
            requiresProof: true
        }
    ];
    
    const jobIds = await batchPoster.postBatchJobs(jobs);
    console.log("Created jobs:", jobIds);
}
```

## Step 5: Job Monitoring

### Real-time Job Tracking
```javascript
class JobMonitor {
    constructor(marketplace, jobId) {
        this.marketplace = marketplace;
        this.jobId = jobId;
        this.events = new EventEmitter();
    }
    
    async startMonitoring() {
        console.log(`Monitoring job ${this.jobId}...`);
        
        // Initial status
        await this.checkStatus();
        
        // Listen for events
        this.marketplace.on("JobClaimed", (jobId, host) => {
            if (jobId.eq(this.jobId)) {
                console.log(`Job claimed by ${host}`);
                this.events.emit("claimed", { host });
            }
        });
        
        this.marketplace.on("JobCompleted", (jobId, resultCID) => {
            if (jobId.eq(this.jobId)) {
                console.log(`Job completed! Result: ${resultCID}`);
                this.events.emit("completed", { resultCID });
                this.stopMonitoring();
            }
        });
        
        // Periodic status checks
        this.interval = setInterval(() => this.checkStatus(), 30000);
    }
    
    async checkStatus() {
        const job = await this.marketplace.getJob(this.jobId);
        const status = ["Posted", "Claimed", "Completed"][job.status];
        
        console.log(`Job ${this.jobId} status: ${status}`);
        
        if (job.status === 1) { // Claimed
            const timeLeft = job.deadline - Math.floor(Date.now() / 1000);
            console.log(`Time remaining: ${Math.floor(timeLeft / 60)} minutes`);
            
            if (timeLeft < 0) {
                console.warn("Job deadline passed!");
                this.events.emit("expired");
            }
        }
    }
    
    stopMonitoring() {
        if (this.interval) {
            clearInterval(this.interval);
        }
        this.marketplace.removeAllListeners();
    }
}
```

### Automated Result Retrieval
```javascript
class AutoResultRetriever {
    constructor(marketplace, ipfs) {
        this.marketplace = marketplace;
        this.ipfs = ipfs;
        this.pendingJobs = new Map();
    }
    
    async trackJob(jobId, callback) {
        this.pendingJobs.set(jobId, callback);
        
        const monitor = new JobMonitor(this.marketplace, jobId);
        
        monitor.events.on("completed", async ({ resultCID }) => {
            try {
                const result = await this.retrieveResult(resultCID);
                callback(null, result);
            } catch (error) {
                callback(error);
            }
            
            this.pendingJobs.delete(jobId);
        });
        
        monitor.events.on("expired", () => {
            callback(new Error("Job expired"));
            this.pendingJobs.delete(jobId);
        });
        
        await monitor.startMonitoring();
    }
    
    async retrieveResult(resultCID) {
        console.log(`Retrieving result from IPFS: ${resultCID}`);
        
        // Download from IPFS
        const chunks = [];
        for await (const chunk of this.ipfs.cat(resultCID)) {
            chunks.push(chunk);
        }
        
        const data = Buffer.concat(chunks).toString();
        
        try {
            return JSON.parse(data);
        } catch {
            return data; // Plain text result
        }
    }
    
    async waitForCompletion(jobId, timeout = 3600000) {
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                reject(new Error("Timeout waiting for job completion"));
            }, timeout);
            
            this.trackJob(jobId, (error, result) => {
                clearTimeout(timer);
                if (error) reject(error);
                else resolve(result);
            });
        });
    }
}
```

## Common Issues & Solutions

### Issue: Job Not Getting Claimed
```javascript
// Solution: Adjust pricing and requirements
async function diagnoseUnclaimedJob(jobId) {
    const job = await marketplace.getJob(jobId);
    const avgPrice = await getAveragePrice(job.modelId);
    
    console.log("Diagnostics:");
    console.log("- Your price:", ethers.formatEther(job.payment));
    console.log("- Average price:", ethers.formatEther(avgPrice));
    console.log("- Time until deadline:", job.deadline - Date.now() / 1000);
    
    if (job.payment < avgPrice * 0.8) {
        console.log("⚠️ Price too low - increase by 20%");
    }
    
    if (job.deadline - Date.now() / 1000 < 600) {
        console.log("⚠️ Deadline too short - allow at least 30 minutes");
    }
}
```

### Issue: Results Not Matching Expectations
```javascript
// Solution: Improve prompt engineering
class PromptOptimizer {
    improvePrompt(originalPrompt, modelId) {
        const improvements = {
            "gpt-4": {
                prefix: "You are an expert assistant. ",
                suffix: "\n\nProvide a detailed response with examples.",
                format: "Format your response with clear sections."
            },
            "llama-2-70b": {
                prefix: "### Instruction:\n",
                suffix: "\n\n### Response:",
                format: "Use markdown formatting."
            }
        };
        
        const config = improvements[modelId] || improvements["gpt-4"];
        
        return `${config.prefix}${originalPrompt} ${config.format}${config.suffix}`;
    }
}
```

### Issue: High Costs
```javascript
// Solution: Optimize token usage
class CostOptimizer {
    async optimizeJob(job) {
        // 1. Compress prompt
        const compressed = this.compressPrompt(job.prompt);
        
        // 2. Use cheaper models for simple tasks
        const optimalModel = this.selectOptimalModel(job.task);
        
        // 3. Reduce max tokens if possible
        const estimatedOutput = this.estimateOutputLength(job.task);
        
        return {
            ...job,
            prompt: compressed,
            modelId: optimalModel,
            maxTokens: Math.min(job.maxTokens, estimatedOutput * 1.2)
        };
    }
    
    compressPrompt(prompt) {
        // Remove redundancy, use abbreviations
        return prompt
            .replace(/\s+/g, ' ')
            .replace(/please|could you|would you mind/gi, '')
            .trim();
    }
}
```

## Best Practices

### 1. Pricing Strategy
```javascript
const pricingStrategy = {
    // Base pricing on:
    baseFactors: [
        "Model complexity",
        "Token count", 
        "Urgency",
        "Market rates"
    ],
    
    // Add premium for:
    premiumFactors: [
        "High reputation requirement",
        "Proof requirement",
        "Special models",
        "Peak hours"
    ],
    
    // Reduce price for:
    discountFactors: [
        "Batch jobs",
        "Flexible deadline",
        "Simple prompts",
        "Off-peak hours"
    ]
};
```

### 2. Input Preparation
```javascript
// Always validate and sanitize inputs
function prepareInput(rawInput) {
    return {
        // Remove sensitive data
        sanitized: rawInput.replace(/api[_-]?key[\s:=]+[\w-]+/gi, '[REDACTED]'),
        
        // Ensure proper formatting
        formatted: rawInput.trim().replace(/\r\n/g, '\n'),
        
        // Add clear instructions
        enhanced: `Instructions: ${rawInput}\n\nRequirements: Be concise and accurate.`
    };
}
```

### 3. Error Handling
```javascript
async function robustJobPosting(job) {
    const maxRetries = 3;
    let attempt = 0;
    
    while (attempt < maxRetries) {
        try {
            return await postJob(job);
        } catch (error) {
            attempt++;
            
            if (error.message.includes("insufficient funds")) {
                throw error; // Don't retry
            }
            
            if (error.message.includes("gas")) {
                // Increase gas and retry
                job.gasLimit = job.gasLimit * 1.2;
            }
            
            await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
        }
    }
    
    throw new Error("Failed to post job after retries");
}
```

## Next Steps

1. **[Model Selection Guide](model-selection.md)** - Choose the right model
2. **[Result Verification](result-verification.md)** - Validate outputs
3. **[SDK Usage](../developers/sdk-usage.md)** - Automate job posting

## Resources

- [Model Comparison Chart](https://fabstir.com/models)
- [Pricing Calculator](https://fabstir.com/calculator)
- [Prompt Engineering Guide](https://platform.openai.com/docs/guides/prompt-engineering)
- [IPFS Documentation](https://docs.ipfs.io/)

---

Need help? Join our [Job Creators Discord](https://discord.gg/fabstir-jobs) →