const { ethers } = require('ethers');
require('dotenv').config();

/**
 * Correct way to complete session jobs with the deployed contract
 * This addresses the issues your developer is facing
 */

async function completeSessionJob(jobId = 28) {
    const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    
    // Contract address - the fixed deployment
    const MARKETPLACE = '0xc5BACFC1d4399c161034bca106657c0e9A528256';
    
    // Key insight: The contract doesn't have getSessionJob(), use sessions() mapping directly
    const marketplaceAbi = [
        // Session data getter (public mapping)
        'function sessions(uint256) view returns (uint256 depositAmount, uint256 pricePerToken, uint256 maxDuration, uint256 sessionStartTime, address assignedHost, uint8 status, uint256 provenTokens, uint256 lastProofSubmission, bytes32 aggregateProofHash, uint256 checkpointInterval, uint256 lastActivity, uint256 disputeDeadline)',
        
        // Job data getters (these fail for session jobs due to bug)
        'function getJob(uint256) view returns (address renter, uint256 payment, uint8 status, address assignedHost, string promptCID, string responseCID, uint256 deadline)',
        'function getJobStruct(uint256) view returns (tuple(address renter, uint8 status, address assignedHost, uint256 maxPrice, uint256 deadline, uint256 completedAt, address paymentToken, bytes32 escrowId, string modelId, string promptCID, string responseCID))',
        
        // Completion methods
        'function completeSession(uint256 jobId)',  // Host marks complete (no payment)
        'function claimWithProof(uint256 jobId)',   // Host claims payment with proofs
        'function completeSessionJob(uint256 jobId)', // Renter finalizes
        
        // Helper methods
        'function getProvenTokens(uint256) view returns (uint256)',
        
        // Events
        'event SessionCompleted(uint256 indexed jobId, address indexed completedBy, uint256 tokensPaid, uint256 paymentAmount, uint256 refundAmount)',
        'event HostClaimedWithProof(uint256 indexed jobId, address indexed host, uint256 provenTokens, uint256 payment)'
    ];
    
    const marketplace = new ethers.Contract(MARKETPLACE, marketplaceAbi, provider);
    
    console.log(`\n=== Analyzing Session Job ${jobId} ===\n`);
    
    // Step 1: Read session data directly (NOT using non-existent getSessionJob)
    console.log('1. Reading session data from sessions() mapping...');
    try {
        const session = await marketplace.sessions(jobId);
        console.log('   ✅ Session data retrieved:');
        console.log('   - Deposit:', ethers.utils.formatUnits(session.depositAmount, 6), 'USDC');
        console.log('   - Price per token:', ethers.utils.formatUnits(session.pricePerToken, 6), 'USDC');
        console.log('   - Host:', session.assignedHost);
        console.log('   - Status:', ['Active', 'Completed', 'Cancelled'][session.status]);
        console.log('   - Proven tokens:', session.provenTokens.toString());
        
        if (session.status !== 0) {
            console.log('   ⚠️  Session is not active (status:', session.status, ')');
            return;
        }
    } catch (error) {
        console.log('   ❌ Failed to read session:', error.message);
        return;
    }
    
    // Step 2: Try to read job data (this will fail due to bug)
    console.log('\n2. Attempting to read job data (expected to fail)...');
    try {
        const job = await marketplace.getJob(jobId);
        console.log('   ✅ Job data exists (unexpected!):', job);
    } catch (error) {
        console.log('   ❌ Job data not accessible (expected due to bug)');
        console.log('      This is the bug: jobs mapping not initialized for session jobs');
    }
    
    // Step 3: Check proven tokens
    console.log('\n3. Checking proven tokens...');
    const provenTokens = await marketplace.getProvenTokens(jobId);
    console.log('   Proven tokens:', provenTokens.toString());
    
    // Step 4: Determine completion method
    console.log('\n4. Determining correct completion method...');
    const session = await marketplace.sessions(jobId);
    
    if (provenTokens.gt(0)) {
        console.log('   → Proofs submitted, host should use claimWithProof()');
        console.log('   → This triggers payment based on proven tokens');
    } else {
        console.log('   → No proofs, use completeSession() then completeSessionJob()');
    }
    
    // Step 5: Complete the session (demonstrate both flows)
    console.log('\n5. Completion Options:');
    console.log('\n   Option A: Host claims with proof (if proofs submitted)');
    console.log('   ```');
    console.log('   const hostWallet = new ethers.Wallet(HOST_PRIVATE_KEY, provider);');
    console.log('   const marketplaceAsHost = marketplace.connect(hostWallet);');
    console.log('   const tx = await marketplaceAsHost.claimWithProof(jobId);');
    console.log('   ```');
    
    console.log('\n   Option B: Standard completion (no proofs)');
    console.log('   ```');
    console.log('   // Step 1: Host marks complete');
    console.log('   await marketplaceAsHost.completeSession(jobId);');
    console.log('   // Step 2: Renter finalizes payment');
    console.log('   await marketplaceAsRenter.completeSessionJob(jobId);');
    console.log('   ```');
    
    // Demonstrate actual completion (if you want to execute)
    const executeCompletion = false; // Set to true to actually complete
    
    if (executeCompletion && provenTokens.gt(0)) {
        console.log('\n6. Executing completion with claimWithProof...');
        
        // Use the host account
        const hostWallet = new ethers.Wallet(process.env.TEST_HOST_1_PRIVATE_KEY, provider);
        const marketplaceAsHost = marketplace.connect(hostWallet);
        
        try {
            console.log('   Sending transaction as host:', hostWallet.address);
            const tx = await marketplaceAsHost.claimWithProof(jobId);
            console.log('   Transaction sent:', tx.hash);
            
            const receipt = await tx.wait();
            console.log('   ✅ Transaction confirmed in block:', receipt.blockNumber);
            
            // Check for events
            const event = receipt.events?.find(e => e.event === 'HostClaimedWithProof');
            if (event) {
                console.log('   Event emitted:');
                console.log('   - Proven tokens:', event.args.provenTokens.toString());
                console.log('   - Payment:', ethers.utils.formatUnits(event.args.payment, 6), 'USDC');
            }
        } catch (error) {
            console.log('   ❌ Completion failed:', error.message);
            console.log('   Possible reasons:');
            console.log('   - Not calling as host');
            console.log('   - Session already completed');
            console.log('   - No proofs submitted');
        }
    }
    
    // Summary
    console.log('\n=== Summary ===');
    console.log('1. DO NOT use getSessionJob() - it doesn\'t exist');
    console.log('2. Use sessions(jobId) to read session data');
    console.log('3. jobs(jobId) fails due to deployment bug');
    console.log('4. For completion with proofs: host calls claimWithProof()');
    console.log('5. For completion without proofs: completeSession() then completeSessionJob()');
}

// Run the analysis
completeSessionJob(28).catch(console.error);