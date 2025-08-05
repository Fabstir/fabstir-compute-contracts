# SDK Usage Guide

This guide covers how to use the Fabstir SDK for JavaScript/TypeScript to interact with the marketplace without dealing with low-level contract calls.

## Prerequisites

- Node.js 16+ or browser environment
- TypeScript (optional but recommended)
- Base network RPC endpoint
- Wallet private key or provider

## Installation

```bash
# npm
npm install @fabstir/sdk ethers@6

# yarn
yarn add @fabstir/sdk ethers@6

# pnpm
pnpm add @fabstir/sdk ethers@6
```

## Quick Start

### Initialize the SDK
```javascript
import { FabstirSDK, Network } from '@fabstir/sdk';
import { ethers } from 'ethers';

// For Node.js
const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET,
    privateKey: process.env.PRIVATE_KEY,
    rpcUrl: process.env.RPC_URL // Optional custom RPC
});

// For browser with injected provider
const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();

const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET,
    signer: signer
});

// For read-only access
const readOnlySDK = new FabstirSDK({
    network: Network.BASE_MAINNET
});
```

### Basic Job Creation
```javascript
// Simple job posting
const job = await sdk.jobs.create({
    modelId: 'gpt-4',
    prompt: 'Write a poem about blockchain',
    payment: '0.01' // ETH
});

console.log('Job created:', job.id);

// Wait for completion
const result = await sdk.jobs.waitForResult(job.id);
console.log('Result:', result);
```

## Core SDK Features

### Job Management

#### Creating Jobs
```javascript
// Advanced job with all options
const job = await sdk.jobs.create({
    // Required
    modelId: 'gpt-4',
    prompt: 'Analyze this code for security vulnerabilities:\n```solidity\n...\n```',
    payment: '0.02',
    
    // Optional parameters
    maxTokens: 2000,
    temperature: 0.3,
    seed: 42,
    resultFormat: 'json',
    
    // Requirements
    requirements: {
        minGPUMemory: 24,
        minReputationScore: 150,
        maxTimeToComplete: 1800, // 30 minutes
        requiresProof: true
    },
    
    // Metadata
    metadata: {
        category: 'code-analysis',
        priority: 'high'
    }
});

// Batch job creation
const jobs = await sdk.jobs.createBatch([
    {
        modelId: 'gpt-4',
        prompt: 'Task 1',
        payment: '0.01'
    },
    {
        modelId: 'llama-2-70b',
        prompt: 'Task 2',
        payment: '0.008'
    }
]);

console.log('Created jobs:', jobs.map(j => j.id));
```

#### Querying Jobs
```javascript
// Get job details
const job = await sdk.jobs.get('123');
console.log('Job status:', job.status);

// Query jobs with filters
const availableJobs = await sdk.jobs.query({
    status: 'posted',
    modelId: 'gpt-4',
    minPayment: '0.01',
    maxDeadline: Date.now() + 3600000 // 1 hour
});

// Get user's jobs
const myJobs = await sdk.jobs.getMyJobs({
    role: 'renter', // or 'host'
    status: ['completed', 'posted'],
    limit: 50
});

// Monitor job status
sdk.jobs.watch(job.id, (update) => {
    console.log('Job update:', update.status);
    if (update.status === 'completed') {
        console.log('Result:', update.result);
    }
});
```

#### Job Results
```javascript
// Get result
const result = await sdk.jobs.getResult(job.id);
console.log('Result:', result.data);

// Verify result
const verification = await sdk.jobs.verifyResult(job.id);
console.log('Quality score:', verification.qualityScore);
console.log('Proof valid:', verification.proofValid);

// Accept or dispute
if (verification.qualityScore > 0.8) {
    await sdk.jobs.acceptResult(job.id);
} else {
    await sdk.jobs.disputeResult(job.id, {
        reason: 'Low quality output',
        evidence: verification
    });
}
```

### Node Operations

#### Node Registration
```javascript
// Register as a node operator
const node = await sdk.nodes.register({
    peerId: 'QmYourIPFSPeerId',
    models: ['gpt-4', 'llama-2-70b', 'stable-diffusion-xl'],
    region: 'us-east-1',
    stake: '100' // ETH
});

console.log('Node registered:', node.address);

// Update node configuration
await sdk.nodes.update({
    models: ['gpt-4', 'claude-2'], // New model list
    region: 'eu-west-1'
});

// Monitor node performance
const stats = await sdk.nodes.getStats();
console.log('Jobs completed:', stats.jobsCompleted);
console.log('Success rate:', stats.successRate);
console.log('Total earnings:', stats.totalEarnings);
```

#### Job Processing
```javascript
// Auto-claim and process jobs
const processor = sdk.nodes.createProcessor({
    models: ['gpt-4', 'llama-2-70b'],
    maxConcurrent: 5,
    minPayment: '0.005',
    
    // Custom job filter
    filter: (job) => {
        return job.payment >= '0.01' && 
               job.requirements.minReputationScore <= myReputation;
    },
    
    // Job handler
    onJob: async (job) => {
        console.log('Processing job:', job.id);
        
        // Your ML inference logic here
        const result = await runInference(job.modelId, job.prompt);
        
        return {
            data: result,
            metadata: {
                processingTime: Date.now() - job.claimedAt,
                modelVersion: '1.0.0'
            }
        };
    },
    
    // Error handler
    onError: (job, error) => {
        console.error('Job failed:', job.id, error);
    }
});

// Start processing
processor.start();

// Stop when needed
processor.stop();
```

### Payment & Escrow

#### Payment Management
```javascript
// Check escrow balance
const escrowBalance = await sdk.payments.getEscrowBalance();
console.log('Total in escrow:', escrowBalance);

// Withdraw completed payments (for hosts)
const withdrawn = await sdk.payments.withdraw();
console.log('Withdrawn:', withdrawn.amount);

// Get payment history
const payments = await sdk.payments.getHistory({
    type: 'received', // or 'sent'
    from: Date.now() - 30 * 24 * 60 * 60 * 1000, // Last 30 days
    to: Date.now()
});

// Calculate earnings
const earnings = await sdk.payments.calculateEarnings({
    period: 'month',
    includesPending: false
});
```

#### Multi-token Support
```javascript
// Post job with ERC20 token
const job = await sdk.jobs.create({
    modelId: 'gpt-4',
    prompt: 'Hello world',
    payment: {
        amount: '100',
        token: '0x...', // USDC address
        decimals: 6
    }
});

// Check supported tokens
const tokens = await sdk.payments.getSupportedTokens();
console.log('Supported tokens:', tokens);
```

### Reputation System

```javascript
// Get reputation
const reputation = await sdk.reputation.get(nodeAddress);
console.log('Reputation score:', reputation.score);
console.log('Total jobs:', reputation.totalJobs);
console.log('Success rate:', reputation.successRate);

// Get reputation history
const history = await sdk.reputation.getHistory(nodeAddress);
history.forEach(entry => {
    console.log(`${entry.date}: ${entry.score} (${entry.change})`);
});

// Rate a host (after job completion)
await sdk.reputation.rateHost(job.assignedHost, {
    rating: 5,
    jobId: job.id,
    feedback: 'Excellent quality and fast delivery'
});
```

### Governance

```javascript
// Get governance token balance
const balance = await sdk.governance.getTokenBalance();
console.log('Voting power:', balance);

// Create proposal
const proposal = await sdk.governance.createProposal({
    title: 'Reduce minimum stake to 50 ETH',
    description: 'This proposal aims to...',
    actions: [
        {
            target: NODE_REGISTRY_ADDRESS,
            method: 'setMinimumStake',
            params: [ethers.parseEther('50')]
        }
    ]
});

// Vote on proposal
await sdk.governance.vote(proposal.id, 'for'); // or 'against', 'abstain'

// Get proposal details
const proposalDetails = await sdk.governance.getProposal(proposal.id);
console.log('Current votes:', proposalDetails.votes);
console.log('Status:', proposalDetails.status);

// Execute passed proposal
if (proposalDetails.status === 'passed') {
    await sdk.governance.execute(proposal.id);
}
```

## Advanced Usage

### Custom Providers & Signers
```javascript
// Use with custom provider
import { JsonRpcProvider } from 'ethers';

const customProvider = new JsonRpcProvider({
    url: 'https://your-rpc.com',
    headers: {
        'Authorization': 'Bearer YOUR_TOKEN'
    }
});

const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET,
    provider: customProvider
});

// Use with hardware wallet
import { LedgerSigner } from '@ethersproject/hardware-wallets';

const ledger = new LedgerSigner(provider, "m/44'/60'/0'/0/0");
const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET,
    signer: ledger
});
```

### Event Subscriptions
```javascript
// Subscribe to all events
const unsubscribe = sdk.events.subscribe({
    onJobPosted: (job) => {
        console.log('New job:', job);
    },
    onJobClaimed: ({ jobId, host }) => {
        console.log(`Job ${jobId} claimed by ${host}`);
    },
    onJobCompleted: ({ jobId, result }) => {
        console.log(`Job ${jobId} completed`);
    },
    onNodeRegistered: (node) => {
        console.log('New node:', node);
    },
    onNodeSlashed: ({ node, amount, reason }) => {
        console.log(`Node ${node} slashed: ${amount} ETH`);
    }
});

// Unsubscribe when done
unsubscribe();

// Filter events
sdk.events.subscribe({
    filters: {
        jobPosted: {
            modelId: 'gpt-4',
            minPayment: '0.01'
        }
    },
    onJobPosted: (job) => {
        console.log('High-value GPT-4 job:', job);
    }
});
```

### Caching & Performance
```javascript
// Enable caching
const sdk = new FabstirSDK({
    network: Network.BASE_MAINNET,
    cache: {
        enabled: true,
        ttl: 60000, // 1 minute
        maxSize: 1000
    }
});

// Manual cache control
sdk.cache.clear();
sdk.cache.invalidate('job:123');

// Batch queries for performance
const results = await sdk.batch([
    sdk.jobs.get('123'),
    sdk.jobs.get('124'),
    sdk.nodes.get('0x...'),
    sdk.reputation.get('0x...')
]);
```

### Error Handling
```javascript
import { FabstirError, ErrorCode } from '@fabstir/sdk';

try {
    await sdk.jobs.create({
        modelId: 'gpt-4',
        prompt: 'Hello',
        payment: '0.001'
    });
} catch (error) {
    if (error instanceof FabstirError) {
        switch (error.code) {
            case ErrorCode.INSUFFICIENT_FUNDS:
                console.error('Not enough ETH');
                break;
            case ErrorCode.PAYMENT_TOO_LOW:
                console.error('Payment below minimum');
                break;
            case ErrorCode.MODEL_NOT_AVAILABLE:
                console.error('No nodes support this model');
                break;
            default:
                console.error('SDK Error:', error.message);
        }
    } else {
        console.error('Unknown error:', error);
    }
}

// Global error handler
sdk.on('error', (error) => {
    console.error('SDK Error:', error);
    // Send to monitoring service
});
```

### Testing & Mocking
```javascript
import { MockFabstirSDK } from '@fabstir/sdk/testing';

// Create mock SDK for testing
const mockSDK = new MockFabstirSDK();

// Set mock responses
mockSDK.jobs.setMockResponse('create', {
    id: 'mock-job-123',
    status: 'posted',
    payment: '0.01'
});

// Use in tests
describe('My App', () => {
    it('should create job', async () => {
        const job = await mockSDK.jobs.create({
            modelId: 'gpt-4',
            prompt: 'Test',
            payment: '0.01'
        });
        
        expect(job.id).toBe('mock-job-123');
    });
});

// Simulate events
mockSDK.simulateEvent('jobCompleted', {
    jobId: 'mock-job-123',
    result: 'Test result'
});
```

## SDK Configuration

### Full Configuration Options
```javascript
const sdk = new FabstirSDK({
    // Network
    network: Network.BASE_MAINNET,
    
    // Authentication
    privateKey: process.env.PRIVATE_KEY,
    signer: customSigner,
    provider: customProvider,
    
    // RPC
    rpcUrl: 'https://base-mainnet.infura.io/v3/YOUR_KEY',
    rpcTimeout: 30000,
    
    // Caching
    cache: {
        enabled: true,
        ttl: 60000,
        maxSize: 1000,
        storage: 'memory' // or 'localStorage' in browser
    },
    
    // Retry logic
    retry: {
        maxAttempts: 3,
        delay: 1000,
        backoff: 'exponential'
    },
    
    // Gas settings
    gas: {
        maxFeePerGas: '50', // gwei
        maxPriorityFeePerGas: '2',
        estimateMultiplier: 1.1
    },
    
    // Event polling
    polling: {
        interval: 12000, // 12 seconds
        timeout: 120000
    },
    
    // Debug mode
    debug: process.env.NODE_ENV === 'development'
});
```

### Environment Variables
```bash
# .env file
FABSTIR_NETWORK=mainnet
FABSTIR_RPC_URL=https://base-mainnet.infura.io/v3/YOUR_KEY
FABSTIR_PRIVATE_KEY=0x...
FABSTIR_DEBUG=true

# SDK will auto-detect these
const sdk = new FabstirSDK();
```

## TypeScript Support

### Type Definitions
```typescript
import { 
    FabstirSDK, 
    Job, 
    Node, 
    JobStatus,
    ModelId,
    PaymentToken 
} from '@fabstir/sdk';

// Typed job creation
const job: Job = await sdk.jobs.create({
    modelId: ModelId.GPT4,
    prompt: 'Hello',
    payment: '0.01',
    requirements: {
        minGPUMemory: 24,
        requiresProof: true
    }
});

// Type guards
if (job.status === JobStatus.Completed) {
    const result = await sdk.jobs.getResult(job.id);
    console.log(result.data);
}

// Custom types
interface MyJobMetadata {
    category: string;
    priority: 'low' | 'medium' | 'high';
}

const typedJob = await sdk.jobs.create<MyJobMetadata>({
    modelId: ModelId.GPT4,
    prompt: 'Test',
    payment: '0.01',
    metadata: {
        category: 'test',
        priority: 'high'
    }
});
```

### Generics and Interfaces
```typescript
// Generic result types
interface CodeAnalysisResult {
    vulnerabilities: Array<{
        severity: 'low' | 'medium' | 'high' | 'critical';
        line: number;
        description: string;
    }>;
    suggestions: string[];
}

const result = await sdk.jobs.getResult<CodeAnalysisResult>(job.id);
result.data.vulnerabilities.forEach(vuln => {
    console.log(`${vuln.severity}: ${vuln.description} (line ${vuln.line})`);
});

// Extend SDK types
interface ExtendedJob extends Job {
    customField: string;
}
```

## Common Patterns

### Job Queue Manager
```javascript
class JobQueueManager {
    constructor(sdk, options = {}) {
        this.sdk = sdk;
        this.queue = [];
        this.processing = false;
        this.options = {
            batchSize: 5,
            delayBetweenBatches: 1000,
            ...options
        };
    }
    
    async addJob(jobConfig) {
        this.queue.push(jobConfig);
        if (!this.processing) {
            this.processQueue();
        }
    }
    
    async processQueue() {
        this.processing = true;
        
        while (this.queue.length > 0) {
            const batch = this.queue.splice(0, this.options.batchSize);
            
            try {
                const jobs = await this.sdk.jobs.createBatch(batch);
                console.log(`Created ${jobs.length} jobs`);
                
                // Wait for results
                const results = await Promise.all(
                    jobs.map(job => this.sdk.jobs.waitForResult(job.id))
                );
                
                this.onBatchComplete(results);
            } catch (error) {
                this.onBatchError(batch, error);
            }
            
            if (this.queue.length > 0) {
                await new Promise(resolve => 
                    setTimeout(resolve, this.options.delayBetweenBatches)
                );
            }
        }
        
        this.processing = false;
    }
    
    onBatchComplete(results) {
        // Override in subclass
    }
    
    onBatchError(batch, error) {
        // Override in subclass
    }
}
```

### Result Aggregator
```javascript
class ResultAggregator {
    constructor(sdk) {
        this.sdk = sdk;
        this.results = new Map();
    }
    
    async aggregateResults(jobIds, options = {}) {
        const { format = 'json', quality = 0.8 } = options;
        
        // Fetch all results
        const results = await Promise.all(
            jobIds.map(async (id) => {
                const result = await this.sdk.jobs.getResult(id);
                const verification = await this.sdk.jobs.verifyResult(id);
                
                return {
                    jobId: id,
                    data: result.data,
                    quality: verification.qualityScore
                };
            })
        );
        
        // Filter by quality
        const validResults = results.filter(r => r.quality >= quality);
        
        // Aggregate based on format
        if (format === 'json') {
            return this.aggregateJSON(validResults);
        } else if (format === 'text') {
            return this.aggregateText(validResults);
        }
        
        return validResults;
    }
    
    aggregateJSON(results) {
        // Merge JSON results
        return results.reduce((acc, result) => {
            if (typeof result.data === 'object') {
                return { ...acc, ...result.data };
            }
            return acc;
        }, {});
    }
    
    aggregateText(results) {
        // Concatenate text results
        return results.map(r => r.data).join('\n\n');
    }
}
```

## Migration Guide

### From Direct Contract Calls
```javascript
// Before: Direct contract interaction
const contract = new ethers.Contract(JOB_MARKETPLACE_ADDRESS, ABI, signer);
const tx = await contract.postJob(details, requirements, payment, { value: payment });
const receipt = await tx.wait();

// After: Using SDK
const job = await sdk.jobs.create({
    modelId: details.modelId,
    prompt: details.prompt,
    payment: ethers.formatEther(payment),
    requirements
});
```

### From Web3.js
```javascript
// Before: Web3.js
const web3 = new Web3(provider);
const contract = new web3.eth.Contract(ABI, ADDRESS);
const result = await contract.methods.getJob(jobId).call();

// After: Fabstir SDK
const job = await sdk.jobs.get(jobId);
```

## Troubleshooting

### Common Issues

#### SDK Not Connecting
```javascript
// Check network
console.log('Network:', await sdk.getNetwork());
console.log('Block number:', await sdk.provider.getBlockNumber());

// Test connection
try {
    await sdk.provider.getNetwork();
    console.log('Connected successfully');
} catch (error) {
    console.error('Connection failed:', error);
}
```

#### Transaction Failures
```javascript
// Enable debug mode
const sdk = new FabstirSDK({ debug: true });

// Check gas estimation
sdk.on('gasEstimate', (estimate) => {
    console.log('Gas estimate:', estimate);
});

// Monitor transactions
sdk.on('transactionSent', (tx) => {
    console.log('TX sent:', tx.hash);
});

sdk.on('transactionConfirmed', (receipt) => {
    console.log('TX confirmed:', receipt.transactionHash);
});
```

## Best Practices

1. **Always handle errors gracefully**
2. **Use TypeScript for better type safety**
3. **Enable caching for better performance**
4. **Monitor events for real-time updates**
5. **Batch operations when possible**
6. **Set appropriate gas limits**
7. **Validate inputs before sending**
8. **Use read-only SDK when write access not needed**

## Next Steps

1. **[Building on Fabstir](building-on-fabstir.md)** - Build complete applications
2. **[Contract Integration](contract-integration.md)** - Low-level contract access
3. **[API Reference](https://docs.fabstir.com/sdk)** - Complete SDK documentation

## Resources

- [SDK GitHub Repository](https://github.com/fabstir/fabstir-sdk)
- [SDK Examples](https://github.com/fabstir/sdk-examples)
- [API Documentation](https://docs.fabstir.com/sdk)
- [TypeScript Definitions](https://github.com/fabstir/fabstir-sdk/blob/main/types)

---

Need help? Join our [Developer Discord](https://discord.gg/fabstir-dev) →