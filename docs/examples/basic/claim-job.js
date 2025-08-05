/**
 * Example: Claim Job
 * Purpose: Demonstrates how a registered node claims and starts working on a job
 * Prerequisites:
 *   - Registered as a node with stake
 *   - Node supports the requested model
 *   - Job is in "Posted" status
 */

const { ethers } = require('ethers');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const JOB_MARKETPLACE_ABI = [
    'function claimJob(uint256 jobId)',
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))',
    'function getActiveJobs() view returns (uint256[])',
    'event JobClaimed(uint256 indexed jobId, address indexed host)'
];

const NODE_REGISTRY_ABI = [
    'function getNode(address nodeAddress) view returns (tuple(address owner, uint256 stake, string[] supportedModels, string[] regions, bool isActive, uint256 registeredAt))'
];

const REPUTATION_SYSTEM_ABI = [
    'function getNodeStats(address node) view returns (tuple(uint256 jobsCompleted, uint256 jobsFailed, uint256 totalEarned, uint256 avgCompletionTime, uint256 lastJobTimestamp, uint256 reputationScore))'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    jobMarketplace: process.env.JOB_MARKETPLACE || '0x...',
    nodeRegistry: process.env.NODE_REGISTRY || '0x...',
    reputationSystem: process.env.REPUTATION_SYSTEM || '0x...',
    
    // Gas settings
    gasLimit: 200000,
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
    
    // Node settings
    autoSelectJob: true, // Automatically select best job
    minPayment: ethers.parseEther('0.05'), // Minimum acceptable payment
    preferredModels: ['gpt-4', 'claude-2'], // Preferred models to work on
};

// Job statuses
const JobStatus = {
    Posted: 0,
    Claimed: 1,
    Completed: 2,
    Cancelled: 3
};

// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    let jobId = null;
    
    for (let i = 0; i < args.length; i += 2) {
        if (args[i] === '--id') {
            jobId = args[i + 1];
        }
    }
    
    return { jobId };
}

// Decode job input data
function decodeInputData(inputData) {
    try {
        const [prompt, maxTokens, version] = ethers.AbiCoder.defaultAbiCoder().decode(
            ['string', 'uint256', 'string'],
            inputData
        );
        return { prompt, maxTokens, version };
    } catch {
        return { prompt: 'Unable to decode', maxTokens: 0, version: 'unknown' };
    }
}

// Find best available job
async function findBestJob(jobMarketplace, nodeCapabilities) {
    console.log('\n🔍 Searching for suitable jobs...');
    
    const activeJobs = await jobMarketplace.getActiveJobs();
    console.log(`   Found ${activeJobs.length} active jobs`);
    
    const suitableJobs = [];
    
    for (const jobId of activeJobs) {
        const job = await jobMarketplace.getJob(jobId);
        
        // Check if job is posted (not claimed)
        if (job.status !== JobStatus.Posted) continue;
        
        // Check if node supports the model
        if (!nodeCapabilities.supportedModels.includes(job.modelId)) continue;
        
        // Check minimum payment
        if (job.payment < config.minPayment) continue;
        
        // Check deadline is reasonable
        const timeRemaining = Number(job.postedAt) + Number(job.deadline) - Math.floor(Date.now() / 1000);
        if (timeRemaining < 300) continue; // Need at least 5 minutes
        
        const inputData = decodeInputData(job.inputData);
        
        suitableJobs.push({
            id: jobId,
            modelId: job.modelId,
            payment: job.payment,
            maxTokens: job.maxTokens,
            timeRemaining,
            paymentPerToken: job.payment / job.maxTokens,
            prompt: inputData.prompt,
            poster: job.poster
        });
    }
    
    if (suitableJobs.length === 0) {
        return null;
    }
    
    // Sort by payment per token (highest first)
    suitableJobs.sort((a, b) => Number(b.paymentPerToken - a.paymentPerToken));
    
    console.log('\n📊 Suitable jobs found:');
    suitableJobs.slice(0, 5).forEach((job, index) => {
        console.log(`   ${index + 1}. Job #${job.id}`);
        console.log(`      Model: ${job.modelId}`);
        console.log(`      Payment: ${ethers.formatEther(job.payment)} ETH`);
        console.log(`      Tokens: ${job.maxTokens}`);
        console.log(`      Rate: ${ethers.formatEther(job.paymentPerToken)} ETH/token`);
        console.log(`      Time remaining: ${Math.floor(job.timeRemaining / 60)} minutes`);
    });
    
    return suitableJobs[0];
}

async function main() {
    try {
        console.log('🔨 Fabstir Job Claim Example\n');
        
        // 1. Parse arguments
        const { jobId: specificJobId } = parseArgs();
        
        // 2. Setup connection
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`   Node address: ${wallet.address}`);
        console.log(`   Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        
        // 3. Initialize contracts
        console.log('\n2️⃣ Connecting to contracts...');
        const jobMarketplace = new ethers.Contract(
            config.jobMarketplace,
            JOB_MARKETPLACE_ABI,
            wallet
        );
        
        const nodeRegistry = new ethers.Contract(
            config.nodeRegistry,
            NODE_REGISTRY_ABI,
            wallet
        );
        
        const reputationSystem = new ethers.Contract(
            config.reputationSystem,
            REPUTATION_SYSTEM_ABI,
            wallet
        );
        
        // 4. Check node registration
        console.log('\n3️⃣ Verifying node registration...');
        const nodeInfo = await nodeRegistry.getNode(wallet.address);
        
        if (!nodeInfo.isActive) {
            throw new Error('Node is not registered or inactive');
        }
        
        console.log(`   ✅ Node is active`);
        console.log(`   Stake: ${ethers.formatEther(nodeInfo.stake)} ETH`);
        console.log(`   Supported models: ${nodeInfo.supportedModels.join(', ')}`);
        
        // 5. Check reputation
        const reputation = await reputationSystem.getNodeStats(wallet.address);
        console.log(`   Jobs completed: ${reputation.jobsCompleted}`);
        console.log(`   Reputation score: ${reputation.reputationScore}/1000`);
        
        // 6. Find or verify job
        let jobToClaim;
        
        if (specificJobId) {
            // Claim specific job
            console.log(`\n4️⃣ Checking job #${specificJobId}...`);
            const job = await jobMarketplace.getJob(specificJobId);
            
            if (job.status !== JobStatus.Posted) {
                throw new Error(`Job #${specificJobId} is not available (status: ${['Posted', 'Claimed', 'Completed', 'Cancelled'][job.status]})`);
            }
            
            if (!nodeInfo.supportedModels.includes(job.modelId)) {
                throw new Error(`Node does not support model: ${job.modelId}`);
            }
            
            const inputData = decodeInputData(job.inputData);
            
            jobToClaim = {
                id: specificJobId,
                modelId: job.modelId,
                payment: job.payment,
                maxTokens: job.maxTokens,
                prompt: inputData.prompt,
                poster: job.poster
            };
            
            console.log(`   Model: ${job.modelId}`);
            console.log(`   Payment: ${ethers.formatEther(job.payment)} ETH`);
            console.log(`   Max tokens: ${job.maxTokens}`);
            console.log(`   Prompt: "${inputData.prompt.substring(0, 50)}${inputData.prompt.length > 50 ? '...' : ''}"`);
            
        } else if (config.autoSelectJob) {
            // Auto-select best job
            console.log('\n4️⃣ Auto-selecting best available job...');
            jobToClaim = await findBestJob(jobMarketplace, nodeInfo);
            
            if (!jobToClaim) {
                throw new Error('No suitable jobs available');
            }
            
            console.log(`\n   Selected Job #${jobToClaim.id}`);
            
        } else {
            throw new Error('No job ID specified and auto-select is disabled');
        }
        
        // 7. Estimate gas
        console.log('\n5️⃣ Estimating transaction cost...');
        const estimatedGas = await jobMarketplace.claimJob.estimateGas(jobToClaim.id);
        
        const gasPrice = (config.maxFeePerGas + config.maxPriorityFeePerGas) / 2n;
        const estimatedCost = estimatedGas * gasPrice;
        
        console.log(`   Estimated gas: ${estimatedGas.toString()} units`);
        console.log(`   Gas cost: ${ethers.formatEther(estimatedCost)} ETH`);
        
        // 8. Claim the job
        console.log('\n6️⃣ Claiming job...');
        const tx = await jobMarketplace.claimJob(
            jobToClaim.id,
            {
                gasLimit: config.gasLimit,
                maxFeePerGas: config.maxFeePerGas,
                maxPriorityFeePerGas: config.maxPriorityFeePerGas
            }
        );
        
        console.log(`   Transaction hash: ${tx.hash}`);
        console.log('   Waiting for confirmation...');
        
        // 9. Wait for confirmation
        const receipt = await tx.wait();
        console.log(`   ✅ Transaction confirmed in block ${receipt.blockNumber}`);
        
        // 10. Parse event
        const event = receipt.logs
            .map(log => {
                try {
                    return jobMarketplace.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'JobClaimed');
        
        if (event) {
            console.log(`\n✅ Job Claimed Successfully!`);
            console.log(`   Job ID: ${event.args[0]}`);
            console.log(`   Host: ${event.args[1]}`);
        }
        
        // 11. Verify claim
        console.log('\n7️⃣ Verifying claim...');
        const claimedJob = await jobMarketplace.getJob(jobToClaim.id);
        console.log(`   Status: ${['Posted', 'Claimed', 'Completed', 'Cancelled'][claimedJob.status]}`);
        console.log(`   Assigned to: ${claimedJob.assignedHost}`);
        
        const deadline = Number(claimedJob.postedAt) + Number(claimedJob.deadline);
        const timeRemaining = deadline - Math.floor(Date.now() / 1000);
        console.log(`   Time to complete: ${Math.floor(timeRemaining / 60)} minutes`);
        
        // 12. Processing instructions
        console.log('\n📋 Next Steps:');
        console.log('   1. Process the inference request');
        console.log(`   2. Complete within ${Math.floor(timeRemaining / 60)} minutes`);
        console.log(`   3. Submit results: node complete-job.js --id ${jobToClaim.id} --output "result"`);
        console.log('\n🚀 Job Details for Processing:');
        console.log(`   Model: ${jobToClaim.modelId}`);
        console.log(`   Max tokens: ${jobToClaim.maxTokens}`);
        console.log(`   Prompt: "${jobToClaim.prompt}"`);
        console.log('\n💡 Start processing immediately to maximize completion time!');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        // Helpful error messages
        if (error.message.includes('not registered')) {
            console.error('💡 Register your node first: node register-node.js');
        } else if (error.message.includes('not available')) {
            console.error('💡 Job may already be claimed or completed');
        } else if (error.message.includes('not support model')) {
            console.error('💡 Update your node to support this model');
        } else if (error.message.includes('No suitable jobs')) {
            console.error('💡 Try again later or adjust your minimum payment requirements');
        }
        
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = { main, config, findBestJob };

/**
 * Usage Examples:
 * 
 * # Claim a specific job
 * node claim-job.js --id 42
 * 
 * # Auto-select best available job
 * node claim-job.js
 * 
 * Expected Output:
 * 
 * 🔨 Fabstir Job Claim Example
 * 
 * 1️⃣ Setting up connection...
 *    Node address: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 * 
 * 2️⃣ Connecting to contracts...
 * 
 * 3️⃣ Verifying node registration...
 *    ✅ Node is active
 *    Stake: 100.0 ETH
 *    Supported models: gpt-3.5-turbo, gpt-4, claude-2, llama-2-70b
 *    Jobs completed: 156
 *    Reputation score: 950/1000
 * 
 * 4️⃣ Auto-selecting best available job...
 * 
 * 🔍 Searching for suitable jobs...
 *    Found 8 active jobs
 * 
 * 📊 Suitable jobs found:
 *    1. Job #42
 *       Model: gpt-4
 *       Payment: 0.2 ETH
 *       Tokens: 2000
 *       Rate: 0.0001 ETH/token
 *       Time remaining: 45 minutes
 *    2. Job #38
 *       Model: claude-2
 *       Payment: 0.15 ETH
 *       Tokens: 1500
 *       Rate: 0.0001 ETH/token
 *       Time remaining: 30 minutes
 * 
 *    Selected Job #42
 * 
 * 5️⃣ Estimating transaction cost...
 *    Estimated gas: 150000 units
 *    Gas cost: 0.0075 ETH
 * 
 * 6️⃣ Claiming job...
 *    Transaction hash: 0xdef456...
 *    Waiting for confirmation...
 *    ✅ Transaction confirmed in block 12345680
 * 
 * ✅ Job Claimed Successfully!
 *    Job ID: 42
 *    Host: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 * 
 * 7️⃣ Verifying claim...
 *    Status: Claimed
 *    Assigned to: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Time to complete: 44 minutes
 * 
 * 📋 Next Steps:
 *    1. Process the inference request
 *    2. Complete within 44 minutes
 *    3. Submit results: node complete-job.js --id 42 --output "result"
 * 
 * 🚀 Job Details for Processing:
 *    Model: gpt-4
 *    Max tokens: 2000
 *    Prompt: "Explain how blockchain works"
 * 
 * 💡 Start processing immediately to maximize completion time!
 */