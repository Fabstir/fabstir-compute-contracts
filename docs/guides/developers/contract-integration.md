# Contract Integration Guide

This guide covers how to integrate Fabstir smart contracts into your dApps and services, with detailed examples and best practices.

## Prerequisites

- Solidity knowledge
- ethers.js or web3.js familiarity
- Base network RPC access
- Contract ABIs and addresses

## Integration Overview

### Contract Architecture
```
Your dApp
    ↓
Contract Interfaces → Fabstir Contracts → Events & State
    ↓                        ↓
Error Handling         State Management
```

## Core Contract Addresses

### Mainnet (Base)
```javascript
const MAINNET_CONTRACTS = {
    nodeRegistry: "0x...",        // TBD
    jobMarketplace: "0x...",      // TBD
    paymentEscrow: "0x...",       // TBD
    reputationSystem: "0x...",    // TBD
    proofSystem: "0x...",         // TBD
    governance: "0x...",          // TBD
    governanceToken: "0x..."      // TBD
};
```

### Testnet (Base Sepolia)
```javascript
const TESTNET_CONTRACTS = {
    nodeRegistry: "0x1234...abcd",
    jobMarketplace: "0x2345...bcde",
    paymentEscrow: "0x3456...cdef",
    reputationSystem: "0x4567...def0",
    proofSystem: "0x5678...ef01",
    governance: "0x6789...f012",
    governanceToken: "0x789a...0123"
};
```

## Setting Up Contract Interfaces

### Basic Setup with ethers.js
```javascript
const { ethers } = require("ethers");

class FabstirContracts {
    constructor(providerUrl, signerKey = null) {
        this.provider = new ethers.JsonRpcProvider(providerUrl);
        this.signer = signerKey 
            ? new ethers.Wallet(signerKey, this.provider)
            : null;
            
        this.contracts = {};
        this.initializeContracts();
    }
    
    initializeContracts() {
        const network = this.provider.network.chainId === 8453 
            ? MAINNET_CONTRACTS 
            : TESTNET_CONTRACTS;
            
        // Initialize each contract
        this.contracts.nodeRegistry = new ethers.Contract(
            network.nodeRegistry,
            NodeRegistryABI,
            this.signer || this.provider
        );
        
        this.contracts.jobMarketplace = new ethers.Contract(
            network.jobMarketplace,
            JobMarketplaceABI,
            this.signer || this.provider
        );
        
        // ... initialize other contracts
    }
    
    // Helper to switch between read/write modes
    connect(signer) {
        this.signer = signer;
        this.initializeContracts();
        return this;
    }
}
```

### Contract ABIs
```javascript
// Minimal ABIs for common operations
const NodeRegistryABI = [
    "function registerNode(string _peerId, string[] _models, string _region) payable",
    "function updateNode(string[] _models, string _region)",
    "function deactivateNode()",
    "function getNode(address) view returns (tuple(address operator, string peerId, uint256 stake, bool active, string[] models, string region))",
    "event NodeRegistered(address indexed node, string metadata)",
    "event NodeUpdated(address indexed node, string metadata)",
    "event NodeDeactivated(address indexed node)"
];

const JobMarketplaceABI = [
    "function postJob(tuple(string modelId, string prompt, uint256 maxTokens, uint256 temperature, uint32 seed, string resultFormat) details, tuple(uint256 minGPUMemory, uint256 minReputationScore, uint256 maxTimeToComplete, bool requiresProof) requirements, uint256 payment) payable returns (uint256)",
    "function claimJob(uint256 _jobId)",
    "function completeJob(uint256 _jobId, string _resultCID, bytes _proof)",
    "function getJob(uint256) view returns (tuple(address renter, address assignedHost, uint256 payment, uint8 status, string modelId, string inputHash, uint256 deadline, string resultHash, uint256 completedAt))",
    "event JobPosted(uint256 indexed jobId, address indexed renter, string modelId, uint256 payment)",
    "event JobClaimed(uint256 indexed jobId, address indexed host)",
    "event JobCompleted(uint256 indexed jobId, string resultCID)"
];

// ... more ABIs
```

## Read Operations

### Query Node Information
```javascript
class NodeReader {
    constructor(contracts) {
        this.contracts = contracts;
    }
    
    async getNodeInfo(address) {
        try {
            const node = await this.contracts.nodeRegistry.getNode(address);
            
            return {
                operator: node.operator,
                peerId: node.peerId,
                stake: ethers.formatEther(node.stake),
                active: node.active,
                models: node.models,
                region: node.region
            };
        } catch (error) {
            console.error("Error fetching node:", error);
            return null;
        }
    }
    
    async getNodeStats(address) {
        // Get reputation
        const reputation = await this.contracts.reputationSystem.getReputation(address);
        
        // Get job history
        const completedJobs = await this.queryNodeJobs(address);
        
        return {
            reputation: reputation.toNumber(),
            totalJobs: completedJobs.length,
            successRate: await this.calculateSuccessRate(address),
            earnings: await this.calculateEarnings(address)
        };
    }
    
    async queryNodeJobs(nodeAddress) {
        // Query events for job history
        const claimedFilter = this.contracts.jobMarketplace.filters.JobClaimed(null, nodeAddress);
        const claimedEvents = await this.contracts.jobMarketplace.queryFilter(claimedFilter);
        
        const completedJobs = [];
        for (const event of claimedEvents) {
            const job = await this.contracts.jobMarketplace.getJob(event.args.jobId);
            if (job.status === 2) { // Completed
                completedJobs.push({
                    jobId: event.args.jobId,
                    payment: ethers.formatEther(job.payment),
                    completedAt: new Date(job.completedAt * 1000)
                });
            }
        }
        
        return completedJobs;
    }
}
```

### Query Available Jobs
```javascript
class JobReader {
    constructor(contracts) {
        this.contracts = contracts;
    }
    
    async getAvailableJobs(filters = {}) {
        const jobs = [];
        
        // Get recent JobPosted events
        const eventFilter = this.contracts.jobMarketplace.filters.JobPosted();
        const events = await this.contracts.jobMarketplace.queryFilter(
            eventFilter,
            -1000 // Last 1000 blocks
        );
        
        for (const event of events) {
            const job = await this.contracts.jobMarketplace.getJob(event.args.jobId);
            
            // Filter for available jobs
            if (job.status === 0) { // Posted
                if (this.matchesFilters(job, filters)) {
                    jobs.push({
                        jobId: event.args.jobId,
                        renter: job.renter,
                        modelId: job.modelId,
                        payment: ethers.formatEther(job.payment),
                        deadline: new Date(job.deadline * 1000)
                    });
                }
            }
        }
        
        return jobs;
    }
    
    matchesFilters(job, filters) {
        if (filters.modelId && job.modelId !== filters.modelId) return false;
        if (filters.minPayment && job.payment < ethers.parseEther(filters.minPayment)) return false;
        if (filters.maxDeadline && job.deadline > filters.maxDeadline) return false;
        
        return true;
    }
    
    async getJobDetails(jobId) {
        const job = await this.contracts.jobMarketplace.getJob(jobId);
        
        return {
            jobId,
            renter: job.renter,
            assignedHost: job.assignedHost,
            payment: ethers.formatEther(job.payment),
            status: ['Posted', 'Claimed', 'Completed'][job.status],
            modelId: job.modelId,
            inputHash: job.inputHash,
            deadline: new Date(job.deadline * 1000),
            resultHash: job.resultHash,
            completedAt: job.completedAt > 0 ? new Date(job.completedAt * 1000) : null
        };
    }
}
```

## Write Operations

### Node Registration
```javascript
class NodeManager {
    constructor(contracts) {
        this.contracts = contracts;
    }
    
    async registerNode(peerId, models, region, stakeAmount) {
        // Validate inputs
        if (!peerId || !models.length || !region) {
            throw new Error("Invalid registration parameters");
        }
        
        // Check minimum stake
        const minStake = await this.contracts.nodeRegistry.MIN_STAKE();
        const stake = ethers.parseEther(stakeAmount.toString());
        
        if (stake < minStake) {
            throw new Error(`Minimum stake is ${ethers.formatEther(minStake)} ETH`);
        }
        
        // Estimate gas
        const gasEstimate = await this.contracts.nodeRegistry.registerNode.estimateGas(
            peerId,
            models,
            region,
            { value: stake }
        );
        
        // Add 10% buffer
        const gasLimit = gasEstimate * 110n / 100n;
        
        // Send transaction
        const tx = await this.contracts.nodeRegistry.registerNode(
            peerId,
            models,
            region,
            { 
                value: stake,
                gasLimit
            }
        );
        
        console.log("Registration TX:", tx.hash);
        
        // Wait for confirmation
        const receipt = await tx.wait();
        
        // Extract node address from event
        const event = receipt.logs.find(log => {
            try {
                const parsed = this.contracts.nodeRegistry.interface.parseLog(log);
                return parsed.name === "NodeRegistered";
            } catch { return false; }
        });
        
        return {
            success: true,
            transactionHash: receipt.hash,
            nodeAddress: event.args.node,
            gasUsed: receipt.gasUsed.toString()
        };
    }
    
    async updateNode(models, region) {
        const tx = await this.contracts.nodeRegistry.updateNode(models, region);
        const receipt = await tx.wait();
        
        return {
            success: true,
            transactionHash: receipt.hash
        };
    }
}
```

### Job Posting
```javascript
class JobPoster {
    constructor(contracts) {
        this.contracts = contracts;
    }
    
    async postJob(jobConfig) {
        const {
            modelId,
            prompt,
            maxTokens = 1000,
            temperature = 0.7,
            seed = 0,
            resultFormat = "text",
            minGPUMemory = 8,
            minReputationScore = 0,
            maxTimeToComplete = 3600,
            requiresProof = false,
            payment
        } = jobConfig;
        
        // Prepare job details
        const details = {
            modelId,
            prompt: ethers.id(prompt), // Hash for privacy
            maxTokens,
            temperature: Math.floor(temperature * 1000), // Scale for precision
            seed,
            resultFormat
        };
        
        const requirements = {
            minGPUMemory,
            minReputationScore,
            maxTimeToComplete,
            requiresProof
        };
        
        const paymentAmount = ethers.parseEther(payment.toString());
        
        // Post job
        const tx = await this.contracts.jobMarketplace.postJob(
            details,
            requirements,
            paymentAmount,
            { value: paymentAmount }
        );
        
        const receipt = await tx.wait();
        
        // Get job ID
        const event = receipt.logs.find(log => {
            try {
                const parsed = this.contracts.jobMarketplace.interface.parseLog(log);
                return parsed.name === "JobPosted";
            } catch { return false; }
        });
        
        return {
            success: true,
            jobId: event.args.jobId.toString(),
            transactionHash: receipt.hash
        };
    }
    
    async postBatchJobs(jobs) {
        // Batch posting for efficiency
        const multicallData = [];
        let totalPayment = 0n;
        
        for (const job of jobs) {
            const payment = ethers.parseEther(job.payment.toString());
            totalPayment += payment;
            
            const callData = this.contracts.jobMarketplace.interface.encodeFunctionData(
                "postJob",
                [job.details, job.requirements, payment]
            );
            
            multicallData.push(callData);
        }
        
        // Use multicall if available
        if (this.contracts.jobMarketplace.multicall) {
            const tx = await this.contracts.jobMarketplace.multicall(
                multicallData,
                { value: totalPayment }
            );
            
            return await tx.wait();
        }
        
        // Fallback to individual transactions
        const results = [];
        for (const job of jobs) {
            results.push(await this.postJob(job));
        }
        
        return results;
    }
}
```

## Event Listening

### Real-time Event Monitoring
```javascript
class EventMonitor {
    constructor(contracts) {
        this.contracts = contracts;
        this.listeners = new Map();
    }
    
    // Monitor job lifecycle
    async monitorJobs(callbacks) {
        // New jobs
        this.contracts.jobMarketplace.on("JobPosted", (jobId, renter, modelId, payment) => {
            if (callbacks.onJobPosted) {
                callbacks.onJobPosted({
                    jobId: jobId.toString(),
                    renter,
                    modelId,
                    payment: ethers.formatEther(payment)
                });
            }
        });
        
        // Job claims
        this.contracts.jobMarketplace.on("JobClaimed", (jobId, host) => {
            if (callbacks.onJobClaimed) {
                callbacks.onJobClaimed({
                    jobId: jobId.toString(),
                    host
                });
            }
        });
        
        // Job completions
        this.contracts.jobMarketplace.on("JobCompleted", (jobId, resultCID) => {
            if (callbacks.onJobCompleted) {
                callbacks.onJobCompleted({
                    jobId: jobId.toString(),
                    resultCID
                });
            }
        });
    }
    
    // Monitor node events
    async monitorNodes(callbacks) {
        // Node registrations
        this.contracts.nodeRegistry.on("NodeRegistered", (node, metadata) => {
            if (callbacks.onNodeRegistered) {
                callbacks.onNodeRegistered({ node, metadata });
            }
        });
        
        // Node updates
        this.contracts.nodeRegistry.on("NodeUpdated", (node, metadata) => {
            if (callbacks.onNodeUpdated) {
                callbacks.onNodeUpdated({ node, metadata });
            }
        });
        
        // Node slashing
        this.contracts.nodeRegistry.on("NodeSlashed", (node, amount, reason) => {
            if (callbacks.onNodeSlashed) {
                callbacks.onNodeSlashed({
                    node,
                    amount: ethers.formatEther(amount),
                    reason
                });
            }
        });
    }
    
    // Stop all listeners
    stopAll() {
        this.contracts.jobMarketplace.removeAllListeners();
        this.contracts.nodeRegistry.removeAllListeners();
        // ... remove other listeners
    }
}
```

### Historical Event Queries
```javascript
class EventQuerier {
    constructor(contracts) {
        this.contracts = contracts;
    }
    
    async getJobHistory(address, role = 'renter') {
        const jobs = [];
        
        if (role === 'renter') {
            // Get jobs posted by address
            const filter = this.contracts.jobMarketplace.filters.JobPosted(null, address);
            const events = await this.contracts.jobMarketplace.queryFilter(filter);
            
            for (const event of events) {
                const job = await this.contracts.jobMarketplace.getJob(event.args.jobId);
                jobs.push({
                    jobId: event.args.jobId.toString(),
                    timestamp: await this.getBlockTimestamp(event.blockNumber),
                    ...this.formatJob(job)
                });
            }
        } else if (role === 'host') {
            // Get jobs claimed by address
            const filter = this.contracts.jobMarketplace.filters.JobClaimed(null, address);
            const events = await this.contracts.jobMarketplace.queryFilter(filter);
            
            for (const event of events) {
                const job = await this.contracts.jobMarketplace.getJob(event.args.jobId);
                jobs.push({
                    jobId: event.args.jobId.toString(),
                    claimedAt: await this.getBlockTimestamp(event.blockNumber),
                    ...this.formatJob(job)
                });
            }
        }
        
        return jobs;
    }
    
    async getNodeActivity(nodeAddress, fromBlock = 0) {
        const activity = {
            registrations: [],
            updates: [],
            slashes: [],
            jobsClaimed: [],
            jobsCompleted: []
        };
        
        // Registration events
        const regFilter = this.contracts.nodeRegistry.filters.NodeRegistered(nodeAddress);
        const regEvents = await this.contracts.nodeRegistry.queryFilter(regFilter, fromBlock);
        
        for (const event of regEvents) {
            activity.registrations.push({
                blockNumber: event.blockNumber,
                timestamp: await this.getBlockTimestamp(event.blockNumber),
                metadata: event.args.metadata
            });
        }
        
        // ... query other events
        
        return activity;
    }
    
    async getBlockTimestamp(blockNumber) {
        const block = await this.contracts.nodeRegistry.provider.getBlock(blockNumber);
        return new Date(block.timestamp * 1000);
    }
}
```

## Error Handling

### Common Errors and Solutions
```javascript
class ErrorHandler {
    handleContractError(error) {
        // Parse revert reasons
        if (error.reason) {
            return this.parseRevertReason(error.reason);
        }
        
        // Handle specific error codes
        if (error.code === 'UNPREDICTABLE_GAS_LIMIT') {
            return {
                type: 'GAS_ESTIMATION_FAILED',
                message: 'Transaction would fail. Check parameters.',
                solution: 'Verify contract state and input parameters'
            };
        }
        
        if (error.code === 'INSUFFICIENT_FUNDS') {
            return {
                type: 'INSUFFICIENT_BALANCE',
                message: 'Insufficient ETH balance',
                solution: 'Add more ETH to your wallet'
            };
        }
        
        // Generic error
        return {
            type: 'UNKNOWN_ERROR',
            message: error.message,
            solution: 'Check transaction parameters and try again'
        };
    }
    
    parseRevertReason(reason) {
        const errorMap = {
            'Node already registered': {
                type: 'ALREADY_REGISTERED',
                solution: 'Use updateNode() instead'
            },
            'Insufficient stake': {
                type: 'INSUFFICIENT_STAKE',
                solution: 'Increase stake amount to minimum'
            },
            'Job already claimed': {
                type: 'JOB_CLAIMED',
                solution: 'Try claiming a different job'
            },
            'Not authorized': {
                type: 'UNAUTHORIZED',
                solution: 'Check wallet address permissions'
            }
        };
        
        for (const [key, value] of Object.entries(errorMap)) {
            if (reason.includes(key)) {
                return {
                    ...value,
                    message: reason
                };
            }
        }
        
        return {
            type: 'CONTRACT_REVERT',
            message: reason,
            solution: 'Check contract requirements'
        };
    }
}

// Usage in contract calls
async function safeContractCall(contractCall) {
    const errorHandler = new ErrorHandler();
    
    try {
        return await contractCall();
    } catch (error) {
        const parsed = errorHandler.handleContractError(error);
        console.error('Contract Error:', parsed);
        
        // Could also show user-friendly message
        if (parsed.type === 'INSUFFICIENT_STAKE') {
            alert(`Please stake at least ${MIN_STAKE} ETH to register`);
        }
        
        throw parsed;
    }
}
```

## Gas Optimization

### Efficient Contract Interactions
```javascript
class GasOptimizer {
    constructor(provider) {
        this.provider = provider;
    }
    
    async getOptimalGasPrice() {
        const feeData = await this.provider.getFeeData();
        
        return {
            standard: feeData.gasPrice,
            fast: feeData.gasPrice * 110n / 100n, // 10% higher
            instant: feeData.gasPrice * 125n / 100n // 25% higher
        };
    }
    
    async estimateWithBuffer(contract, method, params, value = 0n) {
        // Estimate gas
        const estimate = await contract[method].estimateGas(...params, { value });
        
        // Add buffer based on method
        const buffers = {
            registerNode: 1.2,    // 20% buffer
            postJob: 1.15,        // 15% buffer
            claimJob: 1.3,        // 30% buffer (competitive)
            completeJob: 1.1      // 10% buffer
        };
        
        const buffer = buffers[method] || 1.1;
        return estimate * BigInt(Math.floor(buffer * 100)) / 100n;
    }
    
    // Batch operations to save gas
    async batchOperations(operations) {
        // Check if multicall is available
        const multicall = new ethers.Contract(
            MULTICALL_ADDRESS,
            MulticallABI,
            this.provider
        );
        
        const calls = operations.map(op => ({
            target: op.contract.address,
            callData: op.contract.interface.encodeFunctionData(op.method, op.params)
        }));
        
        return await multicall.aggregate(calls);
    }
}
```

## State Management

### Caching Contract State
```javascript
class ContractStateCache {
    constructor(contracts, ttl = 60000) { // 1 minute TTL
        this.contracts = contracts;
        this.cache = new Map();
        this.ttl = ttl;
    }
    
    async getNode(address, forceRefresh = false) {
        const key = `node:${address}`;
        
        if (!forceRefresh && this.cache.has(key)) {
            const cached = this.cache.get(key);
            if (Date.now() - cached.timestamp < this.ttl) {
                return cached.data;
            }
        }
        
        const node = await this.contracts.nodeRegistry.getNode(address);
        this.cache.set(key, {
            data: node,
            timestamp: Date.now()
        });
        
        return node;
    }
    
    async getJob(jobId, forceRefresh = false) {
        const key = `job:${jobId}`;
        
        if (!forceRefresh && this.cache.has(key)) {
            const cached = this.cache.get(key);
            if (Date.now() - cached.timestamp < this.ttl) {
                return cached.data;
            }
        }
        
        const job = await this.contracts.jobMarketplace.getJob(jobId);
        
        // Don't cache active jobs
        if (job.status === 1) { // Claimed but not completed
            return job;
        }
        
        this.cache.set(key, {
            data: job,
            timestamp: Date.now()
        });
        
        return job;
    }
    
    invalidate(pattern) {
        for (const key of this.cache.keys()) {
            if (key.includes(pattern)) {
                this.cache.delete(key);
            }
        }
    }
}
```

## Testing Integration

### Mock Contracts for Testing
```javascript
const { MockContract } = require('@ethereum-waffle/mock-contract');

async function setupMockContracts() {
    const mockNodeRegistry = await MockContract.deploy(NodeRegistryABI);
    const mockJobMarketplace = await MockContract.deploy(JobMarketplaceABI);
    
    // Mock specific responses
    await mockNodeRegistry.mock.getNode.returns({
        operator: "0x123...",
        peerId: "QmTest...",
        stake: ethers.parseEther("100"),
        active: true,
        models: ["gpt-4"],
        region: "us-east-1"
    });
    
    return {
        nodeRegistry: mockNodeRegistry,
        jobMarketplace: mockJobMarketplace
    };
}

// Test your integration
describe("Contract Integration", () => {
    it("should register node", async () => {
        const mocks = await setupMockContracts();
        const integration = new FabstirContracts(mocks);
        
        // Test registration
        const result = await integration.registerNode(...);
        expect(result.success).to.be.true;
    });
});
```

## Production Best Practices

### 1. Connection Management
```javascript
class ConnectionManager {
    constructor() {
        this.providers = new Map();
        this.fallbackProviders = [];
    }
    
    addProvider(name, url, priority = 0) {
        const provider = new ethers.JsonRpcProvider(url);
        this.providers.set(name, { provider, priority });
    }
    
    async getHealthyProvider() {
        for (const [name, config] of this.providers) {
            try {
                await config.provider.getBlockNumber();
                return config.provider;
            } catch {
                console.warn(`Provider ${name} is unhealthy`);
            }
        }
        
        throw new Error("No healthy providers available");
    }
}
```

### 2. Transaction Management
```javascript
class TransactionManager {
    constructor(signer) {
        this.signer = signer;
        this.nonce = null;
        this.pending = new Map();
    }
    
    async sendTransaction(tx) {
        // Manage nonce
        if (this.nonce === null) {
            this.nonce = await this.signer.getTransactionCount();
        }
        
        tx.nonce = this.nonce++;
        
        // Send and track
        const sentTx = await this.signer.sendTransaction(tx);
        this.pending.set(sentTx.hash, sentTx);
        
        // Wait for confirmation
        const receipt = await sentTx.wait();
        this.pending.delete(sentTx.hash);
        
        return receipt;
    }
    
    async cancelTransaction(txHash, gasPrice) {
        const tx = this.pending.get(txHash);
        if (!tx) throw new Error("Transaction not found");
        
        // Send replacement with same nonce
        return await this.sendTransaction({
            to: this.signer.address,
            value: 0,
            nonce: tx.nonce,
            gasPrice: gasPrice // Higher gas price
        });
    }
}
```

### 3. Security Considerations
```javascript
// Input validation
function validateJobInput(input) {
    const errors = [];
    
    if (!input.modelId || !SUPPORTED_MODELS.includes(input.modelId)) {
        errors.push("Invalid model ID");
    }
    
    if (!input.prompt || input.prompt.length > MAX_PROMPT_LENGTH) {
        errors.push("Invalid prompt");
    }
    
    if (input.payment < MIN_JOB_PAYMENT) {
        errors.push("Payment too low");
    }
    
    if (errors.length > 0) {
        throw new ValidationError(errors);
    }
}

// Rate limiting
class RateLimiter {
    constructor(maxCalls, windowMs) {
        this.maxCalls = maxCalls;
        this.windowMs = windowMs;
        this.calls = new Map();
    }
    
    canCall(address) {
        const now = Date.now();
        const calls = this.calls.get(address) || [];
        
        // Remove old calls
        const recent = calls.filter(time => now - time < this.windowMs);
        
        if (recent.length >= this.maxCalls) {
            return false;
        }
        
        recent.push(now);
        this.calls.set(address, recent);
        return true;
    }
}
```

## Next Steps

1. **[SDK Usage](sdk-usage.md)** - High-level SDK for easier integration
2. **[Building on Fabstir](building-on-fabstir.md)** - Build complete applications
3. **[API Reference](../../technical/README.md)** - Detailed contract documentation

## Resources

- [Contract Source Code](https://github.com/fabstir/fabstir-contracts)
- [Base Documentation](https://docs.base.org)
- [ethers.js Documentation](https://docs.ethers.org)
- [Example Integrations](https://github.com/fabstir/examples)

---

Questions? Join our [Developer Discord](https://discord.gg/fabstir-dev) →