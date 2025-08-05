/**
 * Example: Register Node
 * Purpose: Demonstrates how to register as a compute node provider in the Fabstir network
 * Prerequisites: 
 *   - 100 ETH for staking (minimum requirement)
 *   - Wallet with sufficient ETH for gas
 *   - Node with GPU capabilities
 */

const { ethers } = require('ethers');
const readline = require('readline');
require('dotenv').config({ path: '../.env' });

// Contract ABI (minimal for this example)
const NODE_REGISTRY_ABI = [
    'function registerNode(string[] supportedModels, string[] regions) payable',
    'function getNode(address nodeAddress) view returns (tuple(address owner, uint256 stake, string[] supportedModels, string[] regions, bool isActive, uint256 registeredAt))',
    'function MIN_STAKE() view returns (uint256)',
    'event NodeRegistered(address indexed node, uint256 stake, string[] models, string[] regions)'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    nodeRegistry: process.env.NODE_REGISTRY || '0x...', // Replace with actual address
    
    // Node configuration
    supportedModels: [
        'gpt-3.5-turbo',
        'gpt-4',
        'claude-2',
        'llama-2-70b',
        'stable-diffusion-xl'
    ],
    regions: ['us-east-1', 'eu-west-1'],
    
    // Gas settings
    gasLimit: 500000,
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
};

// Helper function to confirm action
async function confirm(question) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });
    
    return new Promise(resolve => {
        rl.question(question + ' (y/n): ', answer => {
            rl.close();
            resolve(answer.toLowerCase() === 'y');
        });
    });
}

async function main() {
    try {
        console.log('🚀 Fabstir Node Registration Example\n');
        
        // 1. Setup provider and wallet
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`   Wallet address: ${wallet.address}`);
        console.log(`   Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        
        // 2. Check wallet balance
        const balance = await provider.getBalance(wallet.address);
        console.log(`   Balance: ${ethers.formatEther(balance)} ETH`);
        
        // 3. Initialize contract
        console.log('\n2️⃣ Connecting to NodeRegistry contract...');
        const nodeRegistry = new ethers.Contract(
            config.nodeRegistry,
            NODE_REGISTRY_ABI,
            wallet
        );
        
        // 4. Check minimum stake requirement
        const minStake = await nodeRegistry.MIN_STAKE();
        console.log(`   Minimum stake required: ${ethers.formatEther(minStake)} ETH`);
        
        // 5. Check if already registered
        console.log('\n3️⃣ Checking registration status...');
        const existingNode = await nodeRegistry.getNode(wallet.address);
        
        if (existingNode.isActive) {
            console.log('   ⚠️  You are already registered as a node!');
            console.log(`   Stake: ${ethers.formatEther(existingNode.stake)} ETH`);
            console.log(`   Models: ${existingNode.supportedModels.join(', ')}`);
            console.log(`   Regions: ${existingNode.regions.join(', ')}`);
            return;
        }
        
        // 6. Verify sufficient balance
        if (balance < minStake) {
            throw new Error(`Insufficient balance. Need at least ${ethers.formatEther(minStake)} ETH`);
        }
        
        // 7. Display registration details
        console.log('\n4️⃣ Registration Details:');
        console.log(`   Stake amount: ${ethers.formatEther(minStake)} ETH`);
        console.log(`   Supported models: ${config.supportedModels.join(', ')}`);
        console.log(`   Regions: ${config.regions.join(', ')}`);
        
        // 8. Estimate gas
        console.log('\n5️⃣ Estimating transaction cost...');
        const estimatedGas = await nodeRegistry.registerNode.estimateGas(
            config.supportedModels,
            config.regions,
            { value: minStake }
        );
        
        const gasPrice = (config.maxFeePerGas + config.maxPriorityFeePerGas) / 2n;
        const estimatedCost = estimatedGas * gasPrice;
        
        console.log(`   Estimated gas: ${estimatedGas.toString()} units`);
        console.log(`   Estimated cost: ${ethers.formatEther(estimatedCost)} ETH`);
        console.log(`   Total required: ${ethers.formatEther(minStake + estimatedCost)} ETH`);
        
        // 9. Confirm registration
        const proceed = await confirm('\n❓ Do you want to proceed with registration?');
        if (!proceed) {
            console.log('❌ Registration cancelled');
            return;
        }
        
        // 10. Execute registration
        console.log('\n6️⃣ Submitting registration transaction...');
        const tx = await nodeRegistry.registerNode(
            config.supportedModels,
            config.regions,
            {
                value: minStake,
                gasLimit: config.gasLimit,
                maxFeePerGas: config.maxFeePerGas,
                maxPriorityFeePerGas: config.maxPriorityFeePerGas
            }
        );
        
        console.log(`   Transaction hash: ${tx.hash}`);
        console.log('   Waiting for confirmation...');
        
        // 11. Wait for confirmation
        const receipt = await tx.wait();
        console.log(`   ✅ Transaction confirmed in block ${receipt.blockNumber}`);
        
        // 12. Parse events
        const event = receipt.logs
            .map(log => {
                try {
                    return nodeRegistry.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'NodeRegistered');
        
        if (event) {
            console.log('\n✅ Node Registration Successful!');
            console.log(`   Node address: ${event.args[0]}`);
            console.log(`   Stake: ${ethers.formatEther(event.args[1])} ETH`);
            console.log(`   Models: ${event.args[2].join(', ')}`);
            console.log(`   Regions: ${event.args[3].join(', ')}`);
        }
        
        // 13. Verify registration
        console.log('\n7️⃣ Verifying registration...');
        const newNode = await nodeRegistry.getNode(wallet.address);
        console.log(`   Active: ${newNode.isActive}`);
        console.log(`   Registered at: ${new Date(Number(newNode.registeredAt) * 1000).toLocaleString()}`);
        
        // 14. Next steps
        console.log('\n📋 Next Steps:');
        console.log('   1. Configure your node software');
        console.log('   2. Start accepting jobs');
        console.log('   3. Monitor your reputation');
        console.log('   4. Join the governance community');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        // Provide helpful error messages
        if (error.message.includes('insufficient funds')) {
            console.error('💡 Make sure you have enough ETH for staking + gas fees');
        } else if (error.message.includes('already registered')) {
            console.error('💡 This address is already registered as a node');
        } else if (error.message.includes('user rejected')) {
            console.error('💡 Transaction was cancelled');
        }
        
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = { main, config };

/**
 * Expected Output:
 * 
 * 🚀 Fabstir Node Registration Example
 * 
 * 1️⃣ Setting up connection...
 *    Wallet address: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 *    Balance: 125.5 ETH
 * 
 * 2️⃣ Connecting to NodeRegistry contract...
 *    Minimum stake required: 100.0 ETH
 * 
 * 3️⃣ Checking registration status...
 * 
 * 4️⃣ Registration Details:
 *    Stake amount: 100.0 ETH
 *    Supported models: gpt-3.5-turbo, gpt-4, claude-2, llama-2-70b, stable-diffusion-xl
 *    Regions: us-east-1, eu-west-1
 * 
 * 5️⃣ Estimating transaction cost...
 *    Estimated gas: 285000 units
 *    Estimated cost: 0.0143 ETH
 *    Total required: 100.0143 ETH
 * 
 * ❓ Do you want to proceed with registration? (y/n): y
 * 
 * 6️⃣ Submitting registration transaction...
 *    Transaction hash: 0x123abc...
 *    Waiting for confirmation...
 *    ✅ Transaction confirmed in block 12345678
 * 
 * ✅ Node Registration Successful!
 *    Node address: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Stake: 100.0 ETH
 *    Models: gpt-3.5-turbo, gpt-4, claude-2, llama-2-70b, stable-diffusion-xl
 *    Regions: us-east-1, eu-west-1
 * 
 * 7️⃣ Verifying registration...
 *    Active: true
 *    Registered at: 12/25/2024, 10:30:45 AM
 * 
 * 📋 Next Steps:
 *    1. Configure your node software
 *    2. Start accepting jobs
 *    3. Monitor your reputation
 *    4. Join the governance community
 */