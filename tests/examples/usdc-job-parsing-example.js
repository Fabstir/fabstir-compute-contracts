// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
const { ethers } = require('ethers');

async function testUSDCWithCorrectParsing() {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    
    // Current working deployment
    const MARKETPLACE = '0xD937c594682Fe74E6e3d06239719805C04BE804A';
    const USDC = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
    const HOST = '0x4594F755F593B517Bb3194F4DeC20C48a3f04504';
    
    // Wallets
    const userWallet = new ethers.Wallet('0x2d5db36770a53811d9a11163a5e6577bb867e19552921bf40f74064308bea952', provider);
    const hostWallet = new ethers.Wallet('0xe7855c0ea54ccca55126d40f97d90868b2a73bad0363e92ccdec0c4fbd6c0ce2', provider);
    
    console.log('USDC Payment Test with Correct Job ID Parsing');
    console.log('==============================================\n');
    
    // Minimal ABI - only what we need
    const marketplaceABI = [
        'function createSessionJobWithToken(address host, address token, uint256 deposit, uint256 pricePerToken, uint256 maxDuration, uint256 proofInterval) returns (uint256)',
        'event SessionJobCreatedWithToken(uint256 indexed jobId, address indexed token, uint256 deposit)'
    ];
    
    const marketplace = new ethers.Contract(MARKETPLACE, marketplaceABI, userWallet);
    
    // Create a USDC session
    console.log('Creating USDC session...');
    const tx = await marketplace.createSessionJobWithToken(
        HOST,
        USDC,
        ethers.parseUnits('1', 6), // 1 USDC
        1000, // price per token
        3600, // 1 hour
        100   // proof interval
    );
    
    console.log('Transaction hash:', tx.hash);
    const receipt = await tx.wait();
    console.log('Transaction mined!\n');
    
    // CORRECT WAY 1: Parse from event logs
    console.log('Method 1: Parsing from Event Logs');
    console.log('----------------------------------');
    let jobIdFromEvent;
    for (const log of receipt.logs) {
        if (log.address.toLowerCase() === MARKETPLACE.toLowerCase()) {
            try {
                const parsed = marketplace.interface.parseLog({
                    topics: log.topics,
                    data: log.data
                });
                if (parsed && parsed.name === 'SessionJobCreatedWithToken') {
                    jobIdFromEvent = parsed.args[0]; // First argument is jobId
                    console.log('✅ Job ID from event:', jobIdFromEvent.toString());
                    break;
                }
            } catch (e) {
                // Not our event
            }
        }
    }
    
    // CORRECT WAY 2: Use static call to simulate first
    console.log('\nMethod 2: Using Static Call (for future transactions)');
    console.log('------------------------------------------------------');
    try {
        // This simulates the transaction and returns the result
        const simulatedJobId = await marketplace.createSessionJobWithToken.staticCall(
            HOST,
            USDC,
            ethers.parseUnits('1', 6),
            1000,
            3600,
            100
        );
        console.log('✅ Job ID from static call:', simulatedJobId.toString());
    } catch (e) {
        console.log('Static call would fail (expected - already created)');
    }
    
    // WRONG WAY: What the failing tests were doing
    console.log('\nWRONG: What Failing Tests Were Doing');
    console.log('-------------------------------------');
    console.log('❌ Trying to decode tx.data as job ID');
    console.log('❌ Using tx.value or other transaction fields');
    console.log('❌ These give you random data, not the job ID!');
    
    // Now test proof submission with the CORRECT job ID
    console.log('\n\nTesting Proof Submission with Correct Job ID');
    console.log('=============================================');
    
    if (jobIdFromEvent) {
        const proofABI = [
            'function submitProofOfWork(uint256 jobId, bytes calldata ekzlProof, uint256 tokensInBatch) returns (bool)'
        ];
        
        const marketplaceHost = new ethers.Contract(MARKETPLACE, proofABI, hostWallet);
        
        console.log('Submitting proof for job ID:', jobIdFromEvent.toString());
        
        try {
            const proof = ethers.randomBytes(64);
            const proofTx = await marketplaceHost.submitProofOfWork(
                jobIdFromEvent, // Use the CORRECT job ID
                proof,
                100
            );
            
            console.log('✅ Proof submission transaction:', proofTx.hash);
            const proofReceipt = await proofTx.wait();
            console.log('✅ Proof submitted successfully!');
            console.log('   Gas used:', proofReceipt.gasUsed.toString());
            
        } catch (e) {
            console.log('❌ Proof submission failed:', e.message);
            if (e.data) {
                console.log('   Error data:', e.data);
            }
        }
    }
    
    console.log('\n📝 SUMMARY');
    console.log('==========');
    console.log('The "job ID" 807201391391077423022502540514138522973679668214 was actually');
    console.log('the user address 0x8D642988E3e7b6DB15b6058461d5563835b04bF6 converted to decimal!');
    console.log('\nAlways parse job IDs from event logs or use staticCall for simulation.');
}

testUSDCWithCorrectParsing().catch(console.error);