const { ethers } = require('ethers');

async function testFullUSDCFlow() {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    
    // NEW fresh deployment
    const MARKETPLACE = '0xD937c594682Fe74E6e3d06239719805C04BE804A';
    const USDC = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
    const HOST = '0x4594F755F593B517Bb3194F4DeC20C48a3f04504';
    
    // Wallets
    const userWallet = new ethers.Wallet('0x2d5db36770a53811d9a11163a5e6577bb867e19552921bf40f74064308bea952', provider);
    const hostWallet = new ethers.Wallet('0xe7855c0ea54ccca55126d40f97d90868b2a73bad0363e92ccdec0c4fbd6c0ce2', provider);
    
    console.log('Full USDC Payment Settlement Test');
    console.log('==================================');
    console.log('Marketplace:', MARKETPLACE);
    console.log('User:', userWallet.address);
    console.log('Host:', hostWallet.address);
    
    // ABIs
    const marketplaceABI = [
        'function createSessionJobWithToken(address host, address token, uint256 deposit, uint256 pricePerToken, uint256 maxDuration, uint256 proofInterval) returns (uint256)',
        'function submitProofOfWork(uint256 jobId, bytes calldata ekzlProof, uint256 tokensInBatch) returns (bool)',
        'function completeSessionJob(uint256 jobId) external',
        'function treasuryAddress() view returns (address)',
        'event SessionJobCreatedWithToken(uint256 indexed jobId, address indexed token, uint256 deposit)',
        'event SessionCompleted(uint256 indexed jobId, address indexed completer, uint256 totalTokens, uint256 payment, uint256 refund)'
    ];
    
    const usdcABI = [
        'function balanceOf(address account) view returns (uint256)'
    ];
    
    const marketplace = new ethers.Contract(MARKETPLACE, marketplaceABI, provider);
    const usdc = new ethers.Contract(USDC, usdcABI, provider);
    
    // Get treasury
    const treasuryAddress = await marketplace.treasuryAddress();
    console.log('Treasury:', treasuryAddress);
    
    // Record initial balances
    console.log('\n1. Initial USDC Balances:');
    const userBalanceBefore = await usdc.balanceOf(userWallet.address);
    const hostBalanceBefore = await usdc.balanceOf(hostWallet.address);
    const treasuryBalanceBefore = await usdc.balanceOf(treasuryAddress);
    const contractBalanceBefore = await usdc.balanceOf(MARKETPLACE);
    
    console.log('- User:', ethers.formatUnits(userBalanceBefore, 6));
    console.log('- Host:', ethers.formatUnits(hostBalanceBefore, 6));
    console.log('- Treasury:', ethers.formatUnits(treasuryBalanceBefore, 6));
    console.log('- Contract:', ethers.formatUnits(contractBalanceBefore, 6));
    
    // We already created a session in the previous test, let's find the job ID
    // From the previous test, we know a job was created. Let's use job ID 1
    const jobId = 1;
    console.log('\n2. Using Job ID:', jobId);
    
    // Submit proof as host (200 tokens total)
    console.log('\n3. Submitting proofs as host...');
    const marketplaceHost = marketplace.connect(hostWallet);
    
    // First proof: 100 tokens
    const proof1 = ethers.randomBytes(64);
    const submit1 = await marketplaceHost.submitProofOfWork(jobId, proof1, 100);
    await submit1.wait();
    console.log('- Submitted 100 tokens');
    
    // Second proof: 100 more tokens
    const proof2 = ethers.randomBytes(64);
    const submit2 = await marketplaceHost.submitProofOfWork(jobId, proof2, 100);
    await submit2.wait();
    console.log('- Submitted 100 more tokens (200 total)');
    
    // Complete session as user
    console.log('\n4. Completing session as user...');
    const marketplaceUser = marketplace.connect(userWallet);
    const completeTx = await marketplaceUser.completeSessionJob(jobId);
    const completeReceipt = await completeTx.wait();
    console.log('Transaction mined!');
    console.log('Gas used:', completeReceipt.gasUsed.toString());
    
    // Parse completion event
    let totalTokens, payment, refund;
    for (const log of completeReceipt.logs) {
        try {
            const parsed = marketplace.interface.parseLog({
                topics: log.topics,
                data: log.data
            });
            if (parsed && parsed.name === 'SessionCompleted') {
                totalTokens = parsed.args[2];
                payment = parsed.args[3];
                refund = parsed.args[4];
                
                console.log('\nSessionCompleted Event:');
                console.log('- Total Tokens:', totalTokens.toString());
                console.log('- Payment to host:', ethers.formatUnits(payment, 6), 'USDC');
                console.log('- Refund to user:', ethers.formatUnits(refund, 6), 'USDC');
            }
        } catch {}
    }
    
    // Check final balances
    console.log('\n5. Final USDC Balances:');
    const userBalanceAfter = await usdc.balanceOf(userWallet.address);
    const hostBalanceAfter = await usdc.balanceOf(hostWallet.address);
    const treasuryBalanceAfter = await usdc.balanceOf(treasuryAddress);
    const contractBalanceAfter = await usdc.balanceOf(MARKETPLACE);
    
    console.log('- User:', ethers.formatUnits(userBalanceAfter, 6));
    console.log('- Host:', ethers.formatUnits(hostBalanceAfter, 6));
    console.log('- Treasury:', ethers.formatUnits(treasuryBalanceAfter, 6));
    console.log('- Contract:', ethers.formatUnits(contractBalanceAfter, 6));
    
    // Calculate actual changes
    const userChange = userBalanceAfter - userBalanceBefore;
    const hostChange = hostBalanceAfter - hostBalanceBefore;
    const treasuryChange = treasuryBalanceAfter - treasuryBalanceBefore;
    const contractChange = contractBalanceAfter - contractBalanceBefore;
    
    console.log('\n6. Actual Balance Changes:');
    console.log('- User:', ethers.formatUnits(userChange, 6), 'USDC');
    console.log('- Host:', ethers.formatUnits(hostChange, 6), 'USDC');
    console.log('- Treasury:', ethers.formatUnits(treasuryChange, 6), 'USDC');
    console.log('- Contract:', ethers.formatUnits(contractChange, 6), 'USDC');
    
    // Verify payments (200 tokens at 1000 price = 0.2 USDC)
    const totalCost = 200n * 1000n; // 0.2 USDC
    const expectedHost = (totalCost * 90n) / 100n; // 0.18 USDC
    const expectedTreasury = (totalCost * 10n) / 100n; // 0.02 USDC
    const deposit = 1000000n; // 1 USDC
    const expectedRefund = deposit - totalCost; // 0.8 USDC
    
    console.log('\n7. Payment Verification:');
    console.log('Expected payments:');
    console.log('- Host (90%):', ethers.formatUnits(expectedHost, 6), 'USDC');
    console.log('- Treasury (10%):', ethers.formatUnits(expectedTreasury, 6), 'USDC');
    console.log('- User refund:', ethers.formatUnits(expectedRefund, 6), 'USDC');
    
    console.log('\nVerification:');
    const hostCorrect = hostChange === expectedHost;
    const treasuryCorrect = treasuryChange === expectedTreasury;
    const refundCorrect = userChange === -deposit + expectedRefund;
    
    console.log('- Host payment:', hostCorrect ? '✅ CORRECT' : `❌ Got ${ethers.formatUnits(hostChange, 6)}`);
    console.log('- Treasury payment:', treasuryCorrect ? '✅ CORRECT' : `❌ Got ${ethers.formatUnits(treasuryChange, 6)}`);
    console.log('- User refund:', refundCorrect ? '✅ CORRECT' : `❌ Got ${ethers.formatUnits(userChange, 6)}`);
    
    if (hostCorrect && treasuryCorrect && refundCorrect) {
        console.log('\n');
        console.log('===============================================');
        console.log('🎉 USDC PAYMENT SETTLEMENT FULLY WORKING! 🎉');
        console.log('✅ 90% HOST / 10% TREASURY VERIFIED!');
        console.log('✅ USER REFUND VERIFIED!');
        console.log('===============================================');
    }
}

testFullUSDCFlow().catch(console.error);