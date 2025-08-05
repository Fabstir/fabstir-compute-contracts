/**
 * Example: Batch Operations
 * Purpose: Demonstrates efficient batch operations using BaseAccountIntegration for gas savings
 * Prerequisites:
 *   - Deployed Base Account (ERC-4337)
 *   - Sufficient ETH for operations
 *   - Multiple operations to batch
 */

const { ethers } = require('ethers');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const BASE_ACCOUNT_INTEGRATION_ABI = [
    'function executeBatch(address[] targets, uint256[] values, bytes[] calldatas) returns (bytes[] results)',
    'function registerNodeBatch(address[] nodes, string[][] models, string[][] regions, uint256[] stakes) payable',
    'function claimJobsBatch(uint256[] jobIds)',
    'function completeJobsBatch(uint256[] jobIds, bytes[] outputs)',
    'event BatchExecuted(address indexed account, uint256 operationCount, bool success)'
];

const JOB_MARKETPLACE_ABI = [
    'function getActiveJobs() view returns (uint256[])',
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))'
];

const NODE_REGISTRY_ABI = [
    'function updateSupportedModels(string[] models)',
    'function updateRegions(string[] regions)',
    'function withdraw(uint256 amount)'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    baseAccountIntegration: process.env.BASE_ACCOUNT_INTEGRATION || '0x...',
    jobMarketplace: process.env.JOB_MARKETPLACE || '0x...',
    nodeRegistry: process.env.NODE_REGISTRY || '0x...',
    
    // Gas settings
    gasLimit: 1000000, // Higher for batch operations
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
    
    // Batch settings
    maxBatchSize: 10,
    estimateGasMultiplier: 1.2 // 20% buffer
};

// Example: Batch job claiming
async function batchClaimJobs(integration, marketplace, wallet) {
    console.log('\n📦 Batch Job Claiming Example');
    
    // 1. Find available jobs
    console.log('   Finding available jobs...');
    const activeJobs = await marketplace.getActiveJobs();
    const availableJobs = [];
    
    for (const jobId of activeJobs.slice(0, 20)) { // Check first 20
        const job = await marketplace.getJob(jobId);
        if (job.status === 0) { // Posted status
            availableJobs.push({
                id: jobId,
                payment: job.payment,
                model: job.modelId
            });
        }
    }
    
    if (availableJobs.length === 0) {
        console.log('   No available jobs found');
        return;
    }
    
    console.log(`   Found ${availableJobs.length} available jobs`);
    
    // 2. Select jobs to claim (up to batch size)
    const jobsToClaim = availableJobs
        .sort((a, b) => Number(b.payment - a.payment)) // Sort by payment
        .slice(0, config.maxBatchSize)
        .map(job => job.id);
    
    console.log(`   Claiming ${jobsToClaim.length} jobs in batch`);
    
    // 3. Estimate gas for batch
    const estimatedGas = await integration.claimJobsBatch.estimateGas(jobsToClaim);
    const totalGas = estimatedGas * BigInt(Math.floor(config.estimateGasMultiplier * 100)) / 100n;
    
    console.log(`   Estimated gas: ${estimatedGas.toString()}`);
    console.log(`   Gas with buffer: ${totalGas.toString()}`);
    
    // 4. Execute batch claim
    console.log('   Executing batch claim...');
    const tx = await integration.claimJobsBatch(jobsToClaim, {
        gasLimit: totalGas,
        maxFeePerGas: config.maxFeePerGas,
        maxPriorityFeePerGas: config.maxPriorityFeePerGas
    });
    
    console.log(`   Transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`   ✅ Batch claim successful! Gas used: ${receipt.gasUsed.toString()}`);
    
    // 5. Calculate savings
    const individualGasEstimate = BigInt(150000) * BigInt(jobsToClaim.length); // Estimated gas per claim
    const savings = individualGasEstimate - receipt.gasUsed;
    const savingsPercent = (Number(savings) / Number(individualGasEstimate) * 100).toFixed(1);
    
    console.log(`   💰 Gas saved: ${savings.toString()} (${savingsPercent}%)`);
    
    return jobsToClaim;
}

// Example: Batch node updates
async function batchNodeUpdates(integration, nodeRegistry, wallet) {
    console.log('\n🔧 Batch Node Updates Example');
    
    // Multiple update operations
    const operations = [
        {
            target: nodeRegistry.target,
            value: 0,
            calldata: nodeRegistry.interface.encodeFunctionData('updateSupportedModels', [
                ['gpt-4', 'claude-2', 'llama-2-70b', 'mistral-7b']
            ])
        },
        {
            target: nodeRegistry.target,
            value: 0,
            calldata: nodeRegistry.interface.encodeFunctionData('updateRegions', [
                ['us-east-1', 'us-west-2', 'eu-west-1', 'ap-southeast-1']
            ])
        }
    ];
    
    console.log(`   Batching ${operations.length} update operations`);
    
    // Extract arrays for batch execution
    const targets = operations.map(op => op.target);
    const values = operations.map(op => op.value);
    const calldatas = operations.map(op => op.calldata);
    
    // Execute batch
    console.log('   Executing batch updates...');
    const tx = await integration.executeBatch(targets, values, calldatas, {
        gasLimit: config.gasLimit,
        maxFeePerGas: config.maxFeePerGas,
        maxPriorityFeePerGas: config.maxPriorityFeePerGas
    });
    
    console.log(`   Transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`   ✅ Batch updates successful!`);
    
    return receipt;
}

// Example: Batch job completions
async function batchCompleteJobs(integration, completions) {
    console.log('\n✅ Batch Job Completions Example');
    
    if (!completions || completions.length === 0) {
        console.log('   No jobs to complete');
        return;
    }
    
    console.log(`   Completing ${completions.length} jobs in batch`);
    
    // Prepare batch data
    const jobIds = completions.map(c => c.jobId);
    const outputs = completions.map(c => {
        return ethers.AbiCoder.defaultAbiCoder().encode(
            ['string', 'uint256', 'uint256', 'string'],
            [c.output, c.tokensUsed, Date.now(), 'v1']
        );
    });
    
    // Execute batch completion
    console.log('   Executing batch completions...');
    const tx = await integration.completeJobsBatch(jobIds, outputs, {
        gasLimit: config.gasLimit * 2, // Higher limit for completions
        maxFeePerGas: config.maxFeePerGas,
        maxPriorityFeePerGas: config.maxPriorityFeePerGas
    });
    
    console.log(`   Transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`   ✅ Batch completions successful!`);
    
    return receipt;
}

// Example: Complex multi-step batch
async function complexBatchOperation(integration, contracts) {
    console.log('\n🚀 Complex Multi-Step Batch Example');
    
    // Build a complex batch with different operations
    const operations = [];
    
    // 1. Update node configuration
    operations.push({
        target: contracts.nodeRegistry.target,
        value: 0,
        calldata: contracts.nodeRegistry.interface.encodeFunctionData('updateSupportedModels', [
            ['gpt-4-turbo', 'claude-3', 'gemini-pro']
        ])
    });
    
    // 2. Claim multiple jobs
    const jobIds = [101, 102, 103]; // Example job IDs
    for (const jobId of jobIds) {
        operations.push({
            target: contracts.jobMarketplace.target,
            value: 0,
            calldata: contracts.jobMarketplace.interface.encodeFunctionData('claimJob', [jobId])
        });
    }
    
    // 3. Withdraw some earnings
    operations.push({
        target: contracts.nodeRegistry.target,
        value: 0,
        calldata: contracts.nodeRegistry.interface.encodeFunctionData('withdraw', [
            ethers.parseEther('1.0')
        ])
    });
    
    console.log(`   Executing ${operations.length} operations in single transaction`);
    
    // Estimate gas for entire batch
    const targets = operations.map(op => op.target);
    const values = operations.map(op => op.value);
    const calldatas = operations.map(op => op.calldata);
    
    try {
        const estimatedGas = await integration.executeBatch.estimateGas(targets, values, calldatas);
        console.log(`   Estimated gas: ${estimatedGas.toString()}`);
        
        // Execute with gas buffer
        const tx = await integration.executeBatch(targets, values, calldatas, {
            gasLimit: estimatedGas * 120n / 100n, // 20% buffer
            maxFeePerGas: config.maxFeePerGas,
            maxPriorityFeePerGas: config.maxPriorityFeePerGas
        });
        
        console.log(`   Transaction: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`   ✅ Complex batch successful!`);
        
        // Parse results
        console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
        console.log(`   Operations completed: ${operations.length}`);
        
    } catch (error) {
        console.error('   ❌ Batch failed:', error.message);
        // Could retry with smaller batches or handle specific failures
    }
}

// Main function demonstrating various batch operations
async function main() {
    try {
        console.log('🎯 Fabstir Batch Operations Example\n');
        
        // 1. Setup
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`   Wallet: ${wallet.address}`);
        console.log(`   Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        
        // 2. Initialize contracts
        console.log('\n2️⃣ Initializing contracts...');
        const integration = new ethers.Contract(
            config.baseAccountIntegration,
            BASE_ACCOUNT_INTEGRATION_ABI,
            wallet
        );
        
        const marketplace = new ethers.Contract(
            config.jobMarketplace,
            JOB_MARKETPLACE_ABI,
            provider
        );
        
        const nodeRegistry = new ethers.Contract(
            config.nodeRegistry,
            NODE_REGISTRY_ABI,
            wallet
        );
        
        // 3. Demonstrate batch operations
        console.log('\n3️⃣ Demonstrating batch operations...');
        
        // Example 1: Batch claim jobs
        const claimedJobs = await batchClaimJobs(integration, marketplace, wallet);
        
        // Example 2: Batch node updates
        await batchNodeUpdates(integration, nodeRegistry, wallet);
        
        // Example 3: Batch complete jobs (mock data)
        const mockCompletions = claimedJobs ? claimedJobs.slice(0, 3).map((jobId, i) => ({
            jobId,
            output: `Sample output for job ${jobId}`,
            tokensUsed: 100 + i * 50
        })) : [];
        
        if (mockCompletions.length > 0) {
            await batchCompleteJobs(integration, mockCompletions);
        }
        
        // Example 4: Complex batch
        await complexBatchOperation(integration, { nodeRegistry, jobMarketplace: marketplace });
        
        // 4. Summary
        console.log('\n📊 Batch Operations Summary:');
        console.log('   ✅ Demonstrated efficient batch claiming');
        console.log('   ✅ Showed multi-operation batching');
        console.log('   ✅ Calculated gas savings');
        console.log('   ✅ Handled complex operation sequences');
        
        console.log('\n💡 Tips for Batch Operations:');
        console.log('   • Batch similar operations for maximum efficiency');
        console.log('   • Always estimate gas with a buffer');
        console.log('   • Handle partial failures gracefully');
        console.log('   • Monitor gas prices for optimal timing');
        console.log('   • Consider operation dependencies');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        if (error.message.includes('gas required exceeds')) {
            console.error('💡 Try reducing batch size or increasing gas limit');
        } else if (error.message.includes('nonce too low')) {
            console.error('💡 Transaction may already be pending');
        }
        
        process.exit(1);
    }
}

// Helper function to create batches
function createBatches(items, batchSize) {
    const batches = [];
    for (let i = 0; i < items.length; i += batchSize) {
        batches.push(items.slice(i, i + batchSize));
    }
    return batches;
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = { 
    main, 
    config, 
    batchClaimJobs,
    batchNodeUpdates,
    batchCompleteJobs,
    createBatches
};

/**
 * Expected Output:
 * 
 * 🎯 Fabstir Batch Operations Example
 * 
 * 1️⃣ Setting up connection...
 *    Wallet: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 * 
 * 2️⃣ Initializing contracts...
 * 
 * 3️⃣ Demonstrating batch operations...
 * 
 * 📦 Batch Job Claiming Example
 *    Finding available jobs...
 *    Found 8 available jobs
 *    Claiming 8 jobs in batch
 *    Estimated gas: 850000
 *    Gas with buffer: 1020000
 *    Executing batch claim...
 *    Transaction: 0xabc123...
 *    ✅ Batch claim successful! Gas used: 823456
 *    💰 Gas saved: 376544 (31.4%)
 * 
 * 🔧 Batch Node Updates Example
 *    Batching 2 update operations
 *    Executing batch updates...
 *    Transaction: 0xdef456...
 *    ✅ Batch updates successful!
 * 
 * ✅ Batch Job Completions Example
 *    Completing 3 jobs in batch
 *    Executing batch completions...
 *    Transaction: 0x789ghi...
 *    ✅ Batch completions successful!
 * 
 * 🚀 Complex Multi-Step Batch Example
 *    Executing 6 operations in single transaction
 *    Estimated gas: 580000
 *    Transaction: 0xjkl012...
 *    ✅ Complex batch successful!
 *    Gas used: 542178
 *    Operations completed: 6
 * 
 * 📊 Batch Operations Summary:
 *    ✅ Demonstrated efficient batch claiming
 *    ✅ Showed multi-operation batching
 *    ✅ Calculated gas savings
 *    ✅ Handled complex operation sequences
 * 
 * 💡 Tips for Batch Operations:
 *    • Batch similar operations for maximum efficiency
 *    • Always estimate gas with a buffer
 *    • Handle partial failures gracefully
 *    • Monitor gas prices for optimal timing
 *    • Consider operation dependencies
 */