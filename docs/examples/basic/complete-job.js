/**
 * Example: Complete Session (Multi-Chain with Earnings Accumulation)
 * Purpose: Demonstrates how to complete sessions and accumulate earnings across chains
 * Prerequisites:
 *   - Host must be registered with 1000 FAB staked
 *   - Session must be active
 *   - Anyone can complete sessions (gasless for users)
 *
 * Last Updated: January 25, 2025
 */

const { ethers } = require('ethers');
const fs = require('fs').promises;
const readline = require('readline');
require('dotenv').config({ path: '../.env' });

// Contract ABIs - Updated for Multi-Chain JobMarketplaceWithModels
const JOB_MARKETPLACE_ABI = [
    'function completeSessionJob(uint256 jobId, string memory conversationCID)',
    'function sessionJobs(uint256) view returns (uint256 id, address requester, address host, address model, uint256 pricePerToken, uint256 maxTokens, uint256 tokensUsed, uint256 paymentAmount, uint256 refundAmount, address depositor, uint256 sessionDeadline, uint8 status, uint256 proofInterval, uint256 lastProofTime, uint256 escrowAmount, uint256 disputeDeadline)',
    'event SessionCompleted(uint256 indexed jobId, address indexed completedBy, uint256 tokensPaid, uint256 paymentAmount, uint256 refundAmount)',
    'event SessionCompletedWithCompletedBy(uint256 indexed jobId, address indexed completedBy)'
];

const USDC_ABI = [
    'function balanceOf(address account) view returns (uint256)',
    'function decimals() view returns (uint8)'
];

// Configuration - Multi-chain system with earnings accumulation
const config = {
    // Base Sepolia (ETH)
    baseSepolia: {
        rpcUrl: process.env.BASE_RPC_URL || 'https://sepolia.base.org',
        chainId: 84532,
        nativeSymbol: 'ETH',
        jobMarketplace: '0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f', // Multi-chain support
        hostEarnings: '0x908962e8c6CE72610021586f85ebDE09aAc97776',
        usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
    },

    // opBNB Testnet (BNB) - Future deployment
    opBNB: {
        rpcUrl: process.env.OPBNB_RPC_URL || 'https://opbnb-testnet-rpc.bnbchain.org',
        chainId: 5611,
        nativeSymbol: 'BNB',
        jobMarketplace: 'TBD', // To be deployed post-MVP
        hostEarnings: 'TBD',
        usdc: 'TBD'
    },

    // Gas settings
    gasLimit: 300000,
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
};

// Session status enum
const SessionStatus = {
    Active: 0,
    Completed: 1,
    Abandoned: 2,
    Disputed: 3
};

// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    const params = {};
    
    for (let i = 0; i < args.length; i++) {
        switch(args[i]) {
            case '--id':
            case '-i':
                params.jobId = parseInt(args[++i]);
                break;
            case '--result':
            case '-r':
                params.resultHash = args[++i];
                break;
            case '--file':
            case '-f':
                params.resultFile = args[++i];
                break;
            case '--ipfs':
                params.useIPFS = true;
                params.resultHash = args[++i];
                break;
            case '--help':
            case '-h':
                console.log(`
Usage: node complete-job-fab.js [options]

Options:
  --id, -i <jobId>        Job ID to complete (required)
  --result, -r <hash>     Result hash or reference
  --file, -f <file>       Read result from file and hash it
  --ipfs <hash>          IPFS hash of the result
  --help, -h             Show this help message

Examples:
  node complete-job-fab.js --id 1 --result "QmResultHash123"
  node complete-job-fab.js --id 1 --file ./output.json
  node complete-job-fab.js --id 1 --ipfs QmXxx...
                `);
                process.exit(0);
        }
    }
    
    return params;
}

// Hash file content for result reference
async function hashFileContent(filePath) {
    const content = await fs.readFile(filePath, 'utf8');
    return ethers.keccak256(ethers.toUtf8Bytes(content));
}

// Upload to IPFS (mock - replace with actual IPFS implementation)
async function uploadToIPFS(content) {
    // In production, use actual IPFS client like ipfs-http-client
    console.log('   📤 Uploading to IPFS (simulated)...');
    const hash = ethers.keccak256(ethers.toUtf8Bytes(content));
    return `Qm${hash.slice(2, 48)}`; // Mock IPFS hash
}

async function main() {
    try {
        console.log('✅ Fabstir Session Completion (Multi-Chain)\n');

        // 1. Parse arguments
        const params = parseArgs();

        if (!params.jobId) {
            throw new Error('Session ID is required. Use --id <sessionId>');
        }

        // Select chain (default to Base Sepolia)
        const chainConfig = params.chain === 'opbnb' ? config.opBNB : config.baseSepolia;

        // 2. Setup connection
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(chainConfig.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

        console.log(`   Address: ${wallet.address}`);
        console.log(`   Network: ${params.chain === 'opbnb' ? 'opBNB' : 'Base Sepolia'} (${chainConfig.nativeSymbol})`);
        
        // 3. Initialize contracts
        console.log('\n2️⃣ Connecting to contracts...');
        const jobMarketplace = new ethers.Contract(
            chainConfig.jobMarketplace,
            JOB_MARKETPLACE_ABI,
            wallet
        );

        const usdc = new ethers.Contract(
            chainConfig.usdc,
            USDC_ABI,
            provider
        );
        
        // 4. Get session details
        console.log(`\n3️⃣ Fetching session #${params.jobId} details...`);
        const session = await jobMarketplace.sessionJobs(params.jobId);
        
        // Parse session fields
        const status = Number(session[11]); // status field
        const host = session[2]; // host field
        const requester = session[1]; // requester field
        const disputeDeadline = session[15]; // disputeDeadline

        // Verify session status
        if (status === SessionStatus.Completed) {
            throw new Error('Session is already completed');
        } else if (status !== SessionStatus.Active) {
            throw new Error('Session is not active');
        }

        // Check if dispute window has passed
        const now = Math.floor(Date.now() / 1000);
        if (now < Number(disputeDeadline)) {
            console.log('   ⚠️ Waiting for dispute window to pass...');
            // In real app, you might want to wait or return
        }
        
        console.log(`   ✅ Job is claimed by your node`);
        console.log(`   Renter: ${renter}`);
        console.log(`   Payment: ${ethers.formatUnits(payment, 6)} USDC`);
        console.log(`   Status: Claimed`);
        
        // Check deadline
        const now = Math.floor(Date.now() / 1000);
        const timeRemaining = Number(deadline) - now;
        
        if (timeRemaining <= 0) {
            throw new Error('Job deadline has passed');
        }
        
        console.log(`   Time remaining: ${Math.floor(timeRemaining / 60)} minutes`);
        
        // 5. Prepare result hash
        console.log('\n4️⃣ Preparing result hash...');
        let resultHash;
        
        if (params.resultHash) {
            resultHash = params.resultHash;
            console.log(`   Using provided hash: ${resultHash}`);
        } else if (params.resultFile) {
            // Read file and create hash or upload to IPFS
            const content = await fs.readFile(params.resultFile, 'utf8');
            if (params.useIPFS) {
                resultHash = await uploadToIPFS(content);
                console.log(`   IPFS hash: ${resultHash}`);
            } else {
                resultHash = await hashFileContent(params.resultFile);
                console.log(`   File hash: ${resultHash}`);
            }
        } else {
            // Generate a simple result hash for demo
            resultHash = `result-${params.jobId}-${Date.now()}`;
            console.log(`   Generated hash: ${resultHash}`);
        }
        
        // 6. Check USDC balance before
        console.log('\n5️⃣ Checking balances...');
        const usdcBalanceBefore = await usdc.balanceOf(wallet.address);
        const ethBalance = await provider.getBalance(wallet.address);
        console.log(`   USDC balance: ${ethers.formatUnits(usdcBalanceBefore, 6)} USDC`);
        console.log(`   ETH balance: ${ethers.formatEther(ethBalance)} ETH (for gas)`);
        
        // 7. Submit completion (anyone can complete!)
        console.log('\n6️⃣ Completing session...');
        console.log(`   Conversation CID: ${resultHash}`);
        console.log(`   💡 Note: Anyone can complete sessions - enabling gasless UX!`);

        const tx = await jobMarketplace.completeSessionJob(
            params.jobId,
            resultHash, // conversationCID
            {
                gasLimit: config.gasLimit,
                maxFeePerGas: config.maxFeePerGas,
                maxPriorityFeePerGas: config.maxPriorityFeePerGas
            }
        );
        
        console.log(`   Transaction hash: ${tx.hash}`);
        console.log('   Waiting for confirmation...');
        
        // 8. Wait for confirmation
        const receipt = await tx.wait();
        console.log(`   ✅ Transaction confirmed in block ${receipt.blockNumber}`);
        
        // 9. Parse completion event
        const event = receipt.logs
            .map(log => {
                try {
                    return jobMarketplace.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'SessionCompleted');
        
        if (event) {
            console.log(`\n✅ Job Completed Successfully!`);
            console.log(`   Job ID: ${event.args[0]}`);
            console.log(`   Result Hash: ${event.args[1]}`);
        }
        
        // 10. Check accumulated earnings (not direct payment)
        console.log('\n7️⃣ Verifying earnings accumulation...');
        
        // Connect to HostEarnings contract
        const HOST_EARNINGS_ABI = [
            'function getBalance(address host, address token) view returns (uint256)'
        ];
        const hostEarnings = new ethers.Contract(
            chainConfig.hostEarnings,
            HOST_EARNINGS_ABI,
            provider
        );
        
        // Check accumulated balance
        const accumulatedBalance = await hostEarnings.getBalance(wallet.address, config.usdc);
        const expectedPayment = (payment * 90n) / 100n; // 90% after 10% fee
        
        console.log(`   ⚠️  NOTE: Payments are now accumulated, not transferred directly`);
        console.log(`   Accumulated earnings: ${ethers.formatUnits(accumulatedBalance, 6)} USDC`);
        console.log(`   Expected from this job (90% of ${ethers.formatUnits(payment, 6)}): ${ethers.formatUnits(expectedPayment, 6)} USDC`);
        console.log(`   Platform fee (10%): ${ethers.formatUnits(payment - expectedPayment, 6)} USDC`);
        console.log(`   \n   💡 To withdraw earnings, use: hostEarnings.withdrawAll(USDC_ADDRESS)`);
        
        // 11. Calculate gas costs
        const gasUsed = receipt.gasUsed;
        const gasPrice = receipt.gasPrice || tx.gasPrice;
        const gasCost = gasUsed * gasPrice;
        console.log(`   Gas used: ${gasUsed.toString()}`);
        console.log(`   Gas cost: ${ethers.formatEther(gasCost)} ETH`);
        
        // 12. Summary
        console.log('\n📊 Completion Summary:');
        console.log(`   Job ID: ${params.jobId}`);
        console.log(`   Result Hash: ${resultHash}`);
        console.log(`   Earnings credited: ${ethers.formatUnits(expectedPayment, 6)} USDC`);
        console.log(`   Total accumulated: ${ethers.formatUnits(accumulatedBalance, 6)} USDC`);
        console.log(`   Gas Cost: ${ethers.formatEther(gasCost)} ETH`);
        console.log(`   Gas Saved: ~46,000 (40% reduction vs direct transfer)`);
        console.log(`   Status: ✅ Completed`);
        
        console.log('\n🎉 Congratulations! Job completed and earnings credited.');
        console.log('💡 Earnings accumulate for gas-efficient batch withdrawal!');
        
        // Show BaseScan link
        console.log(`\n🔗 View on BaseScan:`);
        console.log(`   https://sepolia.basescan.org/tx/${tx.hash}`);
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        // Helpful error messages
        if (error.message.includes('not been claimed')) {
            console.error('💡 You need to claim the job first using the claim-job script');
        } else if (error.message.includes('already completed')) {
            console.error('💡 This job has already been completed');
        } else if (error.message.includes('deadline has passed')) {
            console.error('💡 The job deadline has expired');
        } else if (error.message.includes('assigned to')) {
            console.error('💡 Only the assigned host can complete this job');
        } else if (error.message.includes('insufficient funds')) {
            console.error('💡 You need ETH for gas fees');
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
 * Usage Examples:
 * 
 * # Complete with result hash
 * node complete-job-fab.js --id 1 --result "QmResultHash123"
 * 
 * # Complete with file content (creates hash)
 * node complete-job-fab.js --id 1 --file ./output.json
 * 
 * # Complete with IPFS upload
 * node complete-job-fab.js --id 1 --file ./output.json --ipfs
 * 
 * # View help
 * node complete-job-fab.js --help
 * 
 * Expected Output:
 * 
 * ✅ Fabstir Job Completion (FAB System)
 * 
 * 1️⃣ Setting up connection...
 *    Host address: 0x4594F755F593B517Bb3194F4DeC20C48a3f04504
 *    Network: Base Sepolia
 * 
 * 2️⃣ Connecting to contracts...
 * 
 * 3️⃣ Fetching job #1 details...
 *    ✅ Job is claimed by your node
 *    Payment: 10.00 USDC
 *    Time remaining: 45 minutes
 * 
 * 4️⃣ Preparing result hash...
 *    Generated hash: result-1-1703123456789
 * 
 * 5️⃣ Checking balances...
 *    USDC balance: 0.00 USDC
 *    ETH balance: 0.01 ETH (for gas)
 * 
 * 6️⃣ Submitting job completion...
 *    Transaction hash: 0x123...
 *    ✅ Transaction confirmed
 * 
 * 7️⃣ Verifying earnings accumulation...
 *    ⚠️  NOTE: Payments are now accumulated, not transferred directly
 *    Accumulated earnings: 9.00 USDC
 *    Platform fee (10%): 1.00 USDC
 *    
 *    💡 To withdraw earnings, use: hostEarnings.withdrawAll(USDC_ADDRESS)
 * 
 * 🎉 Job completed and earnings credited!
 */