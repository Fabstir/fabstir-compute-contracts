const { ethers } = require('ethers');

async function testNewMarketplaceUSDC() {
    const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');
    
    // NEW fresh deployment (not the old one!)
    const MARKETPLACE = '0xD937c594682Fe74E6e3d06239719805C04BE804A';
    const USDC = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
    const HOST = '0x4594F755F593B517Bb3194F4DeC20C48a3f04504';
    
    // Wallets
    const userWallet = new ethers.Wallet('0x2d5db36770a53811d9a11163a5e6577bb867e19552921bf40f74064308bea952', provider);
    const hostWallet = new ethers.Wallet('0xe7855c0ea54ccca55126d40f97d90868b2a73bad0363e92ccdec0c4fbd6c0ce2', provider);
    
    console.log('=================================================');
    console.log('    COMPLETE USDC PAYMENT SETTLEMENT TEST');
    console.log('           NEW MARKETPLACE DEPLOYMENT');
    console.log('=================================================');
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
        'function approve(address spender, uint256 amount) returns (bool)',
        'function balanceOf(address account) view returns (uint256)',
        'function allowance(address owner, address spender) view returns (uint256)'
    ];
    
    const marketplace = new ethers.Contract(MARKETPLACE, marketplaceABI, provider);
    const usdc = new ethers.Contract(USDC, usdcABI, provider);
    
    // Get treasury
    const treasuryAddress = await marketplace.treasuryAddress();
    console.log('Treasury:', treasuryAddress);
    console.log('\n');
    
    // Step 1: Create NEW session
    console.log('STEP 1: CREATE NEW USDC SESSION');
    console.log('================================');
    
    const marketplaceUser = marketplace.connect(userWallet);
    const usdcUser = usdc.connect(userWallet);
    
    // Approve fresh USDC for new marketplace
    console.log('Approving 10 USDC for new marketplace...');
    const approveTx = await usdcUser.approve(MARKETPLACE, ethers.parseUnits('10', 6));
    await approveTx.wait();
    
    // Check allowance
    const allowance = await usdc.allowance(userWallet.address, MARKETPLACE);
    console.log('Allowance confirmed:', ethers.formatUnits(allowance, 6), 'USDC');
    
    // Record balances before
    const userBalanceBefore = await usdc.balanceOf(userWallet.address);
    const contractBalanceBefore = await usdc.balanceOf(MARKETPLACE);
    console.log('User balance before:', ethers.formatUnits(userBalanceBefore, 6), 'USDC');
    console.log('Contract balance before:', ethers.formatUnits(contractBalanceBefore, 6), 'USDC');
    
    // Create session
    console.log('\nCreating session with 2 USDC deposit...');
    const deposit = ethers.parseUnits('2', 6); // 2 USDC
    const pricePerToken = 5000; // 0.005 USDC per token
    const maxDuration = 3600; // 1 hour
    const proofInterval = 100; // 100 tokens
    
    const createTx = await marketplaceUser.createSessionJobWithToken(
        HOST,
        USDC,
        deposit,
        pricePerToken,
        maxDuration,
        proofInterval
    );
    const createReceipt = await createTx.wait();
    console.log('Transaction mined!');
    
    // Get job ID from event
    let jobId;
    for (const log of createReceipt.logs) {
        try {
            const parsed = marketplace.interface.parseLog({
                topics: log.topics,
                data: log.data
            });
            if (parsed && parsed.name === 'SessionJobCreatedWithToken') {
                jobId = parsed.args.jobId;
                console.log('Created job ID:', jobId.toString());
                break;
            }
        } catch {}
    }
    
    // Verify USDC was transferred
    const userBalanceAfterCreate = await usdc.balanceOf(userWallet.address);
    const contractBalanceAfterCreate = await usdc.balanceOf(MARKETPLACE);
    console.log('\nAfter creation:');
    console.log('User balance:', ethers.formatUnits(userBalanceAfterCreate, 6), 'USDC');
    console.log('Contract balance:', ethers.formatUnits(contractBalanceAfterCreate, 6), 'USDC');
    console.log('USDC transferred to contract:', ethers.formatUnits(contractBalanceAfterCreate - contractBalanceBefore, 6), 'USDC');
    
    // Step 2: Submit proofs
    console.log('\n\nSTEP 2: SUBMIT PROOFS');
    console.log('=====================');
    
    const marketplaceHost = marketplace.connect(hostWallet);
    
    // Submit 200 tokens total
    console.log('Submitting proof for 100 tokens...');
    const proof1 = ethers.randomBytes(64);
    const submit1 = await marketplaceHost.submitProofOfWork(jobId, proof1, 100);
    await submit1.wait();
    
    console.log('Submitting proof for 100 more tokens...');
    const proof2 = ethers.randomBytes(64);  
    const submit2 = await marketplaceHost.submitProofOfWork(jobId, proof2, 100);
    await submit2.wait();
    console.log('Total: 200 tokens proven');
    
    // Step 3: Complete session
    console.log('\n\nSTEP 3: COMPLETE SESSION');
    console.log('========================');
    
    // Record balances before completion
    const hostBalanceBefore = await usdc.balanceOf(hostWallet.address);
    const treasuryBalanceBefore = await usdc.balanceOf(treasuryAddress);
    
    console.log('Balances before completion:');
    console.log('- Host:', ethers.formatUnits(hostBalanceBefore, 6), 'USDC');
    console.log('- User:', ethers.formatUnits(userBalanceAfterCreate, 6), 'USDC');
    console.log('- Treasury:', ethers.formatUnits(treasuryBalanceBefore, 6), 'USDC');
    console.log('- Contract:', ethers.formatUnits(contractBalanceAfterCreate, 6), 'USDC');
    
    console.log('\nCompleting session...');
    const completeTx = await marketplaceUser.completeSessionJob(jobId);
    const completeReceipt = await completeTx.wait();
    console.log('Transaction mined!');
    
    // Parse event
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
                console.log('- Payment:', ethers.formatUnits(payment, 6), 'USDC');
                console.log('- Refund:', ethers.formatUnits(refund, 6), 'USDC');
            }
        } catch {}
    }
    
    // Step 4: Verify payments
    console.log('\n\nSTEP 4: VERIFY PAYMENTS');
    console.log('=======================');
    
    const hostBalanceAfter = await usdc.balanceOf(hostWallet.address);
    const userBalanceAfter = await usdc.balanceOf(userWallet.address);
    const treasuryBalanceAfter = await usdc.balanceOf(treasuryAddress);
    const contractBalanceAfter = await usdc.balanceOf(MARKETPLACE);
    
    console.log('Final balances:');
    console.log('- Host:', ethers.formatUnits(hostBalanceAfter, 6), 'USDC');
    console.log('- User:', ethers.formatUnits(userBalanceAfter, 6), 'USDC');
    console.log('- Treasury:', ethers.formatUnits(treasuryBalanceAfter, 6), 'USDC');
    console.log('- Contract:', ethers.formatUnits(contractBalanceAfter, 6), 'USDC');
    
    // Calculate changes
    const hostChange = hostBalanceAfter - hostBalanceBefore;
    const userChange = userBalanceAfter - userBalanceAfterCreate;
    const treasuryChange = treasuryBalanceAfter - treasuryBalanceBefore;
    const contractChange = contractBalanceAfter - contractBalanceAfterCreate;
    
    console.log('\nActual changes:');
    console.log('- Host received:', ethers.formatUnits(hostChange, 6), 'USDC');
    console.log('- User received:', ethers.formatUnits(userChange, 6), 'USDC');
    console.log('- Treasury received:', ethers.formatUnits(treasuryChange, 6), 'USDC');
    console.log('- Contract released:', ethers.formatUnits(-contractChange, 6), 'USDC');
    
    // Verify against expectations
    const totalCost = 200n * 5000n; // 200 tokens * 5000 = 1.0 USDC
    const expectedHost = (totalCost * 90n) / 100n; // 0.9 USDC
    const expectedTreasury = (totalCost * 10n) / 100n; // 0.1 USDC
    const expectedRefund = deposit - totalCost; // 2 - 1 = 1.0 USDC
    
    console.log('\nExpected payments:');
    console.log('- Host (90%):', ethers.formatUnits(expectedHost, 6), 'USDC');
    console.log('- Treasury (10%):', ethers.formatUnits(expectedTreasury, 6), 'USDC');
    console.log('- User refund:', ethers.formatUnits(expectedRefund, 6), 'USDC');
    
    // Final verification
    console.log('\n\n=================================================');
    console.log('                FINAL VERIFICATION');
    console.log('=================================================');
    
    const hostCorrect = hostChange === expectedHost;
    const treasuryCorrect = treasuryChange === expectedTreasury;
    const refundCorrect = userChange === expectedRefund;
    
    console.log('Host payment (90%):', hostCorrect ? '✅ CORRECT' : `❌ Expected ${ethers.formatUnits(expectedHost, 6)} got ${ethers.formatUnits(hostChange, 6)}`);
    console.log('Treasury payment (10%):', treasuryCorrect ? '✅ CORRECT' : `❌ Expected ${ethers.formatUnits(expectedTreasury, 6)} got ${ethers.formatUnits(treasuryChange, 6)}`);
    console.log('User refund:', refundCorrect ? '✅ CORRECT' : `❌ Expected ${ethers.formatUnits(expectedRefund, 6)} got ${ethers.formatUnits(userChange, 6)}`);
    
    if (hostCorrect && treasuryCorrect && refundCorrect) {
        console.log('\n');
        console.log('🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉');
        console.log('    USDC PAYMENT SETTLEMENT FULLY WORKING!');
        console.log('     90% HOST / 10% TREASURY VERIFIED!');
        console.log('          ALL PAYMENTS CORRECT!');
        console.log('🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉');
    }
}

testNewMarketplaceUSDC().catch(console.error);