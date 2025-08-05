/**
 * Example: Post Job
 * Purpose: Demonstrates how to post an AI inference job to the Fabstir marketplace
 * Prerequisites:
 *   - Wallet with ETH for payment + gas
 *   - Access to JobMarketplace contract
 *   - Knowledge of model requirements
 */

const { ethers } = require('ethers');
const readline = require('readline');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const JOB_MARKETPLACE_ABI = [
    'function postJob(string modelId, uint256 maxTokens, uint256 deadline, bytes inputData) payable returns (uint256)',
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))',
    'function MIN_JOB_PAYMENT() view returns (uint256)',
    'event JobPosted(uint256 indexed jobId, address indexed poster, string modelId, uint256 payment, uint256 maxTokens)'
];

const PAYMENT_ESCROW_ABI = [
    'function approve(address spender, uint256 amount) returns (bool)'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    jobMarketplace: process.env.JOB_MARKETPLACE || '0x...',
    paymentEscrow: process.env.PAYMENT_ESCROW || '0x...',
    
    // Default job parameters
    defaultModel: 'gpt-4',
    defaultMaxTokens: 1000,
    defaultPayment: ethers.parseEther('0.1'), // 0.1 ETH
    defaultDeadline: 3600, // 1 hour in seconds
    
    // Gas settings
    gasLimit: 300000,
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
};

// Model configurations
const MODELS = {
    'gpt-3.5-turbo': {
        id: 'gpt-3.5-turbo',
        costPerToken: ethers.parseEther('0.00001'),
        maxTokens: 4096,
        description: 'Fast, efficient general-purpose model'
    },
    'gpt-4': {
        id: 'gpt-4',
        costPerToken: ethers.parseEther('0.00003'),
        maxTokens: 8192,
        description: 'Advanced reasoning and analysis'
    },
    'claude-2': {
        id: 'claude-2',
        costPerToken: ethers.parseEther('0.00002'),
        maxTokens: 100000,
        description: 'Long context, helpful assistant'
    },
    'llama-2-70b': {
        id: 'llama-2-70b',
        costPerToken: ethers.parseEther('0.00001'),
        maxTokens: 4096,
        description: 'Open-source large language model'
    },
    'stable-diffusion-xl': {
        id: 'stable-diffusion-xl',
        costPerToken: ethers.parseEther('0.0001'),
        maxTokens: 77, // For image generation prompts
        description: 'High-quality image generation'
    }
};

// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    const params = {
        model: config.defaultModel,
        maxTokens: config.defaultMaxTokens,
        payment: config.defaultPayment,
        deadline: config.defaultDeadline,
        prompt: null
    };
    
    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace('--', '');
        const value = args[i + 1];
        
        switch (key) {
            case 'model':
                params.model = value;
                break;
            case 'tokens':
                params.maxTokens = parseInt(value);
                break;
            case 'payment':
                params.payment = ethers.parseEther(value);
                break;
            case 'deadline':
                params.deadline = parseInt(value);
                break;
            case 'prompt':
                params.prompt = value;
                break;
        }
    }
    
    return params;
}

// Get prompt from user
async function getPrompt() {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });
    
    return new Promise(resolve => {
        rl.question('Enter your prompt (or press Enter for default): ', answer => {
            rl.close();
            resolve(answer || 'Explain quantum computing in simple terms.');
        });
    });
}

// Calculate recommended payment
function calculateRecommendedPayment(model, maxTokens) {
    const modelConfig = MODELS[model];
    if (!modelConfig) {
        throw new Error(`Unknown model: ${model}`);
    }
    
    const baseCost = modelConfig.costPerToken * BigInt(maxTokens);
    const overhead = baseCost / 10n; // 10% overhead
    const gasCushion = ethers.parseEther('0.01'); // Extra for gas
    
    return baseCost + overhead + gasCushion;
}

async function main() {
    try {
        console.log('📝 Fabstir Job Posting Example\n');
        
        // 1. Parse arguments
        const params = parseArgs();
        
        // 2. Setup connection
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`   Wallet address: ${wallet.address}`);
        console.log(`   Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        
        // 3. Check balance
        const balance = await provider.getBalance(wallet.address);
        console.log(`   Balance: ${ethers.formatEther(balance)} ETH`);
        
        // 4. Get prompt
        console.log('\n2️⃣ Preparing job details...');
        if (!params.prompt) {
            params.prompt = await getPrompt();
        }
        console.log(`   Prompt: "${params.prompt.substring(0, 50)}${params.prompt.length > 50 ? '...' : ''}"`);
        
        // 5. Validate model
        const modelConfig = MODELS[params.model];
        if (!modelConfig) {
            console.log('\n❌ Unknown model. Available models:');
            Object.entries(MODELS).forEach(([key, model]) => {
                console.log(`   ${key}: ${model.description}`);
            });
            throw new Error(`Invalid model: ${params.model}`);
        }
        
        console.log(`   Model: ${params.model} (${modelConfig.description})`);
        console.log(`   Max tokens: ${params.maxTokens}`);
        
        // 6. Calculate payment
        const recommendedPayment = calculateRecommendedPayment(params.model, params.maxTokens);
        if (params.payment < recommendedPayment) {
            console.log(`   ⚠️  Warning: Payment may be too low`);
            console.log(`   Recommended: ${ethers.formatEther(recommendedPayment)} ETH`);
        }
        console.log(`   Payment: ${ethers.formatEther(params.payment)} ETH`);
        console.log(`   Deadline: ${params.deadline} seconds`);
        
        // 7. Initialize contracts
        console.log('\n3️⃣ Connecting to contracts...');
        const jobMarketplace = new ethers.Contract(
            config.jobMarketplace,
            JOB_MARKETPLACE_ABI,
            wallet
        );
        
        // 8. Check minimum payment
        const minPayment = await jobMarketplace.MIN_JOB_PAYMENT();
        if (params.payment < minPayment) {
            throw new Error(`Payment too low. Minimum: ${ethers.formatEther(minPayment)} ETH`);
        }
        
        // 9. Encode input data
        const inputData = ethers.AbiCoder.defaultAbiCoder().encode(
            ['string', 'uint256', 'string'],
            [params.prompt, params.maxTokens, 'v1']
        );
        
        // 10. Estimate gas
        console.log('\n4️⃣ Estimating transaction cost...');
        const estimatedGas = await jobMarketplace.postJob.estimateGas(
            params.model,
            params.maxTokens,
            params.deadline,
            inputData,
            { value: params.payment }
        );
        
        const gasPrice = (config.maxFeePerGas + config.maxPriorityFeePerGas) / 2n;
        const estimatedCost = estimatedGas * gasPrice;
        
        console.log(`   Estimated gas: ${estimatedGas.toString()} units`);
        console.log(`   Gas cost: ${ethers.formatEther(estimatedCost)} ETH`);
        console.log(`   Total cost: ${ethers.formatEther(params.payment + estimatedCost)} ETH`);
        
        // 11. Verify sufficient balance
        if (balance < params.payment + estimatedCost) {
            throw new Error('Insufficient balance for payment + gas');
        }
        
        // 12. Post job
        console.log('\n5️⃣ Posting job to marketplace...');
        const tx = await jobMarketplace.postJob(
            params.model,
            params.maxTokens,
            params.deadline,
            inputData,
            {
                value: params.payment,
                gasLimit: config.gasLimit,
                maxFeePerGas: config.maxFeePerGas,
                maxPriorityFeePerGas: config.maxPriorityFeePerGas
            }
        );
        
        console.log(`   Transaction hash: ${tx.hash}`);
        console.log('   Waiting for confirmation...');
        
        // 13. Wait for confirmation
        const receipt = await tx.wait();
        console.log(`   ✅ Transaction confirmed in block ${receipt.blockNumber}`);
        
        // 14. Parse event to get job ID
        const event = receipt.logs
            .map(log => {
                try {
                    return jobMarketplace.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'JobPosted');
        
        if (!event) {
            throw new Error('JobPosted event not found');
        }
        
        const jobId = event.args[0];
        console.log(`\n✅ Job Posted Successfully!`);
        console.log(`   Job ID: ${jobId}`);
        console.log(`   Model: ${event.args[2]}`);
        console.log(`   Payment: ${ethers.formatEther(event.args[3])} ETH`);
        console.log(`   Max tokens: ${event.args[4]}`);
        
        // 15. Verify job details
        console.log('\n6️⃣ Verifying job details...');
        const job = await jobMarketplace.getJob(jobId);
        console.log(`   Status: ${['Posted', 'Claimed', 'Completed', 'Cancelled'][job.status]}`);
        console.log(`   Posted at: ${new Date(Number(job.postedAt) * 1000).toLocaleString()}`);
        console.log(`   Deadline: ${new Date((Number(job.postedAt) + Number(job.deadline)) * 1000).toLocaleString()}`);
        
        // 16. Monitor job
        console.log('\n📋 Next Steps:');
        console.log(`   1. Monitor job status: node ../intermediate/job-monitor.js --id ${jobId}`);
        console.log(`   2. Check for results: node check-results.js --id ${jobId}`);
        console.log(`   3. View in dashboard: https://app.fabstir.com/jobs/${jobId}`);
        console.log('\n💡 Your job is now available for nodes to claim and process!');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        // Helpful error messages
        if (error.message.includes('insufficient funds')) {
            console.error('💡 Make sure you have enough ETH for payment + gas');
        } else if (error.message.includes('user rejected')) {
            console.error('💡 Transaction was cancelled');
        } else if (error.message.includes('MIN_JOB_PAYMENT')) {
            console.error('💡 Payment amount is below minimum requirement');
        }
        
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = { main, config, MODELS };

/**
 * Usage Examples:
 * 
 * # Basic usage (interactive prompt)
 * node post-job.js
 * 
 * # Specify all parameters
 * node post-job.js --model gpt-4 --tokens 2000 --payment 0.2 --deadline 7200 --prompt "Write a story about AI"
 * 
 * # Use a cheaper model
 * node post-job.js --model llama-2-70b --tokens 500 --payment 0.05
 * 
 * # Image generation
 * node post-job.js --model stable-diffusion-xl --tokens 77 --payment 0.1 --prompt "A futuristic city at sunset"
 * 
 * Expected Output:
 * 
 * 📝 Fabstir Job Posting Example
 * 
 * 1️⃣ Setting up connection...
 *    Wallet address: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 *    Balance: 5.5 ETH
 * 
 * 2️⃣ Preparing job details...
 * Enter your prompt (or press Enter for default): Explain how blockchain works
 *    Prompt: "Explain how blockchain works"
 *    Model: gpt-4 (Advanced reasoning and analysis)
 *    Max tokens: 1000
 *    Payment: 0.1 ETH
 *    Deadline: 3600 seconds
 * 
 * 3️⃣ Connecting to contracts...
 * 
 * 4️⃣ Estimating transaction cost...
 *    Estimated gas: 185000 units
 *    Gas cost: 0.00925 ETH
 *    Total cost: 0.10925 ETH
 * 
 * 5️⃣ Posting job to marketplace...
 *    Transaction hash: 0xabc123...
 *    Waiting for confirmation...
 *    ✅ Transaction confirmed in block 12345679
 * 
 * ✅ Job Posted Successfully!
 *    Job ID: 42
 *    Model: gpt-4
 *    Payment: 0.1 ETH
 *    Max tokens: 1000
 * 
 * 6️⃣ Verifying job details...
 *    Status: Posted
 *    Posted at: 12/25/2024, 11:30:45 AM
 *    Deadline: 12/25/2024, 12:30:45 PM
 * 
 * 📋 Next Steps:
 *    1. Monitor job status: node ../intermediate/job-monitor.js --id 42
 *    2. Check for results: node check-results.js --id 42
 *    3. View in dashboard: https://app.fabstir.com/jobs/42
 * 
 * 💡 Your job is now available for nodes to claim and process!
 */