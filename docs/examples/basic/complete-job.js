/**
 * Example: Complete Job
 * Purpose: Demonstrates how to submit job results and receive payment
 * Prerequisites:
 *   - Job must be claimed by your node
 *   - Results must be ready before deadline
 *   - Optional: proof of computation
 */

const { ethers } = require('ethers');
const fs = require('fs').promises;
const readline = require('readline');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const JOB_MARKETPLACE_ABI = [
    'function completeJob(uint256 jobId, bytes outputData)',
    'function completeJobWithProof(uint256 jobId, bytes outputData, bytes proof)',
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))',
    'event JobCompleted(uint256 indexed jobId, address indexed host, uint256 payment)'
];

const PAYMENT_ESCROW_ABI = [
    'function getBalance(address account) view returns (uint256)'
];

const REPUTATION_SYSTEM_ABI = [
    'function getNodeStats(address node) view returns (tuple(uint256 jobsCompleted, uint256 jobsFailed, uint256 totalEarned, uint256 avgCompletionTime, uint256 lastJobTimestamp, uint256 reputationScore))'
];

const PROOF_SYSTEM_ABI = [
    'function verifyProof(bytes proof, bytes publicInputs) view returns (bool)'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    jobMarketplace: process.env.JOB_MARKETPLACE || '0x...',
    paymentEscrow: process.env.PAYMENT_ESCROW || '0x...',
    reputationSystem: process.env.REPUTATION_SYSTEM || '0x...',
    proofSystem: process.env.PROOF_SYSTEM || '0x...',
    
    // Gas settings
    gasLimit: 300000,
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
    
    // Completion settings
    includeProof: false, // Set to true if proof system is available
    outputFormat: 'v1'
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
    const params = {
        jobId: null,
        output: null,
        outputFile: null,
        proof: null
    };
    
    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace('--', '');
        const value = args[i + 1];
        
        switch (key) {
            case 'id':
                params.jobId = value;
                break;
            case 'output':
                params.output = value;
                break;
            case 'file':
                params.outputFile = value;
                break;
            case 'proof':
                params.proof = value;
                break;
        }
    }
    
    return params;
}

// Get output from user
async function getOutput() {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });
    
    return new Promise(resolve => {
        console.log('Enter the job output (press Enter twice when done):');
        let lines = [];
        let emptyLineCount = 0;
        
        rl.on('line', line => {
            if (line === '') {
                emptyLineCount++;
                if (emptyLineCount >= 2) {
                    rl.close();
                    resolve(lines.join('\n'));
                }
            } else {
                emptyLineCount = 0;
                lines.push(line);
            }
        });
    });
}

// Generate mock proof (for demonstration)
function generateMockProof(jobId, output) {
    // In production, this would use actual EZKL or similar proof system
    return ethers.hexlify(ethers.toUtf8Bytes(
        JSON.stringify({
            jobId,
            outputHash: ethers.keccak256(ethers.toUtf8Bytes(output)),
            timestamp: Date.now(),
            version: '1.0.0'
        })
    ));
}

// Calculate token usage (mock implementation)
function calculateTokenUsage(prompt, output) {
    // Simplified token counting - in production use proper tokenizer
    const promptTokens = Math.ceil(prompt.split(' ').length * 1.3);
    const outputTokens = Math.ceil(output.split(' ').length * 1.3);
    return promptTokens + outputTokens;
}

async function main() {
    try {
        console.log('✅ Fabstir Job Completion Example\n');
        
        // 1. Parse arguments
        const params = parseArgs();
        
        if (!params.jobId) {
            throw new Error('Job ID is required. Use --id <jobId>');
        }
        
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
        
        const paymentEscrow = new ethers.Contract(
            config.paymentEscrow,
            PAYMENT_ESCROW_ABI,
            provider
        );
        
        const reputationSystem = new ethers.Contract(
            config.reputationSystem,
            REPUTATION_SYSTEM_ABI,
            provider
        );
        
        // 4. Get job details
        console.log(`\n3️⃣ Fetching job #${params.jobId} details...`);
        const job = await jobMarketplace.getJob(params.jobId);
        
        // Verify job status
        if (job.status === JobStatus.Completed) {
            throw new Error('Job is already completed');
        } else if (job.status === JobStatus.Cancelled) {
            throw new Error('Job has been cancelled');
        } else if (job.status === JobStatus.Posted) {
            throw new Error('Job has not been claimed yet');
        }
        
        // Verify we are the assigned host
        if (job.assignedHost.toLowerCase() !== wallet.address.toLowerCase()) {
            throw new Error(`Job is assigned to ${job.assignedHost}, not ${wallet.address}`);
        }
        
        console.log(`   ✅ Job is claimed by your node`);
        console.log(`   Model: ${job.modelId}`);
        console.log(`   Payment: ${ethers.formatEther(job.payment)} ETH`);
        console.log(`   Max tokens: ${job.maxTokens}`);
        
        // Check deadline
        const now = Math.floor(Date.now() / 1000);
        const deadline = Number(job.postedAt) + Number(job.deadline);
        const timeRemaining = deadline - now;
        
        if (timeRemaining <= 0) {
            throw new Error('Job deadline has passed');
        }
        
        console.log(`   Time remaining: ${Math.floor(timeRemaining / 60)} minutes`);
        
        // 5. Get output data
        console.log('\n4️⃣ Preparing output data...');
        let output;
        
        if (params.output) {
            output = params.output;
        } else if (params.outputFile) {
            output = await fs.readFile(params.outputFile, 'utf8');
        } else {
            output = await getOutput();
        }
        
        console.log(`   Output length: ${output.length} characters`);
        
        // Decode input to calculate token usage
        let tokenUsage;
        try {
            const [prompt] = ethers.AbiCoder.defaultAbiCoder().decode(
                ['string', 'uint256', 'string'],
                job.inputData
            );
            tokenUsage = calculateTokenUsage(prompt, output);
            console.log(`   Estimated token usage: ${tokenUsage}`);
            
            if (tokenUsage > job.maxTokens) {
                console.log(`   ⚠️  Warning: Token usage (${tokenUsage}) exceeds limit (${job.maxTokens})`);
            }
        } catch {
            tokenUsage = 0;
        }
        
        // 6. Encode output data
        const outputData = ethers.AbiCoder.defaultAbiCoder().encode(
            ['string', 'uint256', 'uint256', 'string'],
            [output, tokenUsage, Date.now(), config.outputFormat]
        );
        
        // 7. Generate proof if required
        let proof = null;
        if (config.includeProof || params.proof) {
            console.log('\n5️⃣ Generating proof of computation...');
            proof = params.proof || generateMockProof(params.jobId, output);
            console.log(`   Proof generated (${proof.length} bytes)`);
        }
        
        // 8. Check balances before
        console.log('\n6️⃣ Checking balances...');
        const balanceBefore = await provider.getBalance(wallet.address);
        const escrowBefore = await paymentEscrow.getBalance(wallet.address);
        console.log(`   ETH balance: ${ethers.formatEther(balanceBefore)} ETH`);
        console.log(`   Escrow balance: ${ethers.formatEther(escrowBefore)} ETH`);
        
        // 9. Submit completion
        console.log('\n7️⃣ Submitting job completion...');
        let tx;
        
        if (proof) {
            tx = await jobMarketplace.completeJobWithProof(
                params.jobId,
                outputData,
                proof,
                {
                    gasLimit: config.gasLimit,
                    maxFeePerGas: config.maxFeePerGas,
                    maxPriorityFeePerGas: config.maxPriorityFeePerGas
                }
            );
        } else {
            tx = await jobMarketplace.completeJob(
                params.jobId,
                outputData,
                {
                    gasLimit: config.gasLimit,
                    maxFeePerGas: config.maxFeePerGas,
                    maxPriorityFeePerGas: config.maxPriorityFeePerGas
                }
            );
        }
        
        console.log(`   Transaction hash: ${tx.hash}`);
        console.log('   Waiting for confirmation...');
        
        // 10. Wait for confirmation
        const receipt = await tx.wait();
        console.log(`   ✅ Transaction confirmed in block ${receipt.blockNumber}`);
        
        // 11. Parse completion event
        const event = receipt.logs
            .map(log => {
                try {
                    return jobMarketplace.interface.parseLog(log);
                } catch {
                    return null;
                }
            })
            .find(e => e && e.name === 'JobCompleted');
        
        if (event) {
            console.log(`\n✅ Job Completed Successfully!`);
            console.log(`   Job ID: ${event.args[0]}`);
            console.log(`   Payment: ${ethers.formatEther(event.args[2])} ETH`);
        }
        
        // 12. Check balances after
        console.log('\n8️⃣ Verifying payment...');
        const balanceAfter = await provider.getBalance(wallet.address);
        const escrowAfter = await paymentEscrow.getBalance(wallet.address);
        
        const gasUsed = receipt.gasUsed * receipt.gasPrice;
        const netPayment = balanceAfter - balanceBefore + gasUsed;
        
        console.log(`   Payment received: ${ethers.formatEther(job.payment)} ETH`);
        console.log(`   Gas spent: ${ethers.formatEther(gasUsed)} ETH`);
        console.log(`   Net earnings: ${ethers.formatEther(netPayment)} ETH`);
        
        // 13. Check reputation update
        console.log('\n9️⃣ Checking reputation update...');
        const reputation = await reputationSystem.getNodeStats(wallet.address);
        console.log(`   Jobs completed: ${reputation.jobsCompleted}`);
        console.log(`   Total earned: ${ethers.formatEther(reputation.totalEarned)} ETH`);
        console.log(`   Reputation score: ${reputation.reputationScore}/1000`);
        
        // 14. Summary
        console.log('\n📊 Completion Summary:');
        console.log(`   Job ID: ${params.jobId}`);
        console.log(`   Model: ${job.modelId}`);
        console.log(`   Completion time: ${Math.floor((now - Number(job.postedAt)) / 60)} minutes`);
        console.log(`   Token usage: ${tokenUsage}/${job.maxTokens}`);
        console.log(`   Payment: ${ethers.formatEther(job.payment)} ETH`);
        console.log(`   Status: ✅ Completed`);
        
        console.log('\n🎉 Congratulations! Job completed and payment received.');
        console.log('💡 Keep your reputation high by completing jobs on time with quality results!');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        
        // Helpful error messages
        if (error.message.includes('not been claimed')) {
            console.error('💡 You need to claim the job first: node claim-job.js --id <jobId>');
        } else if (error.message.includes('already completed')) {
            console.error('💡 This job has already been completed');
        } else if (error.message.includes('deadline has passed')) {
            console.error('💡 The job deadline has expired');
        } else if (error.message.includes('assigned to')) {
            console.error('💡 Only the assigned host can complete this job');
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
 * # Complete with inline output
 * node complete-job.js --id 42 --output "Blockchain is a distributed ledger technology..."
 * 
 * # Complete with output from file
 * node complete-job.js --id 42 --file output.txt
 * 
 * # Complete with interactive input
 * node complete-job.js --id 42
 * 
 * # Complete with proof
 * node complete-job.js --id 42 --output "Result" --proof 0x123abc...
 * 
 * Expected Output:
 * 
 * ✅ Fabstir Job Completion Example
 * 
 * 1️⃣ Setting up connection...
 *    Node address: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 * 
 * 2️⃣ Connecting to contracts...
 * 
 * 3️⃣ Fetching job #42 details...
 *    ✅ Job is claimed by your node
 *    Model: gpt-4
 *    Payment: 0.2 ETH
 *    Max tokens: 2000
 *    Time remaining: 35 minutes
 * 
 * 4️⃣ Preparing output data...
 * Enter the job output (press Enter twice when done):
 * Blockchain is a distributed ledger technology that maintains a continuously growing list of records, called blocks. Each block contains a cryptographic hash of the previous block, a timestamp, and transaction data. This structure makes it extremely difficult to alter historical records, providing security and transparency.
 * 
 *    Output length: 287 characters
 *    Estimated token usage: 65
 * 
 * 5️⃣ Generating proof of computation...
 *    Proof generated (256 bytes)
 * 
 * 6️⃣ Checking balances...
 *    ETH balance: 5.25 ETH
 *    Escrow balance: 0.0 ETH
 * 
 * 7️⃣ Submitting job completion...
 *    Transaction hash: 0x789def...
 *    Waiting for confirmation...
 *    ✅ Transaction confirmed in block 12345681
 * 
 * ✅ Job Completed Successfully!
 *    Job ID: 42
 *    Payment: 0.2 ETH
 * 
 * 8️⃣ Verifying payment...
 *    Payment received: 0.2 ETH
 *    Gas spent: 0.0087 ETH
 *    Net earnings: 0.1913 ETH
 * 
 * 9️⃣ Checking reputation update...
 *    Jobs completed: 157
 *    Total earned: 28.45 ETH
 *    Reputation score: 952/1000
 * 
 * 📊 Completion Summary:
 *    Job ID: 42
 *    Model: gpt-4
 *    Completion time: 10 minutes
 *    Token usage: 65/2000
 *    Payment: 0.2 ETH
 *    Status: ✅ Completed
 * 
 * 🎉 Congratulations! Job completed and payment received.
 * 💡 Keep your reputation high by completing jobs on time with quality results!
 */