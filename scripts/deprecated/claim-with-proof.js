// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
const { ethers } = require('ethers');
require('dotenv').config();

/**
 * Complete session job 28 using claimWithProof
 * This is the correct method when proofs have been submitted
 */
async function claimSessionPayment(jobId = 28) {
    const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    
    const MARKETPLACE = '0xc5BACFC1d4399c161034bca106657c0e9A528256';
    
    const marketplaceAbi = [
        'function sessions(uint256) view returns (uint256,uint256,uint256,uint256,address,uint8,uint256,uint256,bytes32,uint256,uint256,uint256)',
        'function claimWithProof(uint256 jobId)',
        'function getProvenTokens(uint256) view returns (uint256)',
        'event HostClaimedWithProof(uint256 indexed jobId, address indexed host, uint256 provenTokens, uint256 payment)'
    ];
    
    // Use the host account (TEST_HOST_1)
    const hostWallet = new ethers.Wallet(process.env.TEST_HOST_1_PRIVATE_KEY, provider);
    const marketplace = new ethers.Contract(MARKETPLACE, marketplaceAbi, hostWallet);
    
    console.log('Host address:', hostWallet.address);
    console.log('Claiming payment for job:', jobId);
    
    // Check current state
    const session = await marketplace.sessions(jobId);
    const provenTokens = await marketplace.getProvenTokens(jobId);
    
    console.log('Session status:', ['Active', 'Completed', 'Cancelled'][session[5]]);
    console.log('Proven tokens:', provenTokens.toString());
    console.log('Expected payment:', (provenTokens * 2000 * 0.9 / 1000000).toFixed(6), 'USDC (after 10% fee)');
    
    if (session[5] !== 0) {
        console.log('Session is not active, cannot claim');
        return;
    }
    
    if (provenTokens.eq(0)) {
        console.log('No proofs submitted, cannot claim');
        return;
    }
    
    // Execute claim
    console.log('\nSending claimWithProof transaction...');
    try {
        const tx = await marketplace.claimWithProof(jobId);
        console.log('Transaction sent:', tx.hash);
        
        const receipt = await tx.wait();
        console.log('Transaction confirmed in block:', receipt.blockNumber);
        console.log('Gas used:', receipt.gasUsed.toString());
        
        // Check events
        const event = receipt.events?.find(e => e.event === 'HostClaimedWithProof');
        if (event) {
            console.log('\n✅ SUCCESS! Payment claimed:');
            console.log('  Proven tokens:', event.args.provenTokens.toString());
            console.log('  Payment received:', ethers.utils.formatUnits(event.args.payment, 6), 'USDC');
        }
        
        // Verify final state
        const finalSession = await marketplace.sessions(jobId);
        console.log('\nFinal session status:', ['Active', 'Completed', 'Cancelled'][finalSession[5]]);
        
    } catch (error) {
        console.log('\n❌ Transaction failed:', error.message);
        if (error.data) {
            console.log('Error data:', error.data);
        }
        console.log('\nPossible reasons:');
        console.log('- Not calling as the assigned host');
        console.log('- Session already completed');
        console.log('- Contract state issue');
    }
}

// Execute the claim
claimSessionPayment(28).catch(console.error);