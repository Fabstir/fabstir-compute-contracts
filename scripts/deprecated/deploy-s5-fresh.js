// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

async function main() {
    console.log('🚀 FRESH S5 DEPLOYMENT WITH FULL CONFIGURATION\n');
    console.log('==============================================\n');
    
    // Configuration
    const RPC_URL = 'https://sepolia.base.org';
    const PRIVATE_KEY = '0xe7231a57c89df087f0291bf20b952199c1d4575206d256397c02ba6383dedc97';
    
    // Existing contracts to integrate with
    const NODE_REGISTRY_FAB = '0x87516C13Ea2f99de598665e14cab64E191A0f8c4';
    const TREASURY = '0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078';
    const FEE_BASIS_POINTS = 1000; // 10%
    
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    console.log('💼 Deployer:', wallet.address);
    const balance = await provider.getBalance(wallet.address);
    console.log('💎 Balance:', ethers.formatEther(balance), 'ETH\n');
    
    try {
        // Load contract artifacts
        console.log('📦 Loading contract artifacts...');
        const hostEarningsArtifact = JSON.parse(
            fs.readFileSync(path.join(__dirname, 'out/HostEarnings.sol/HostEarnings.json'))
        );
        const paymentEscrowArtifact = JSON.parse(
            fs.readFileSync(path.join(__dirname, 'out/PaymentEscrowWithEarnings.sol/PaymentEscrowWithEarnings.json'))
        );
        const jobMarketplaceArtifact = JSON.parse(
            fs.readFileSync(path.join(__dirname, 'out/JobMarketplaceFABWithS5.sol/JobMarketplaceFABWithS5.json'))
        );
        
        // Deploy contracts
        console.log('\n🏗️  DEPLOYMENT PHASE\n');
        
        // 1. Deploy HostEarnings
        console.log('1️⃣  Deploying HostEarnings...');
        const HostEarningsFactory = new ethers.ContractFactory(
            hostEarningsArtifact.abi,
            hostEarningsArtifact.bytecode.object,
            wallet
        );
        const hostEarnings = await HostEarningsFactory.deploy();
        await hostEarnings.waitForDeployment();
        const hostEarningsAddr = await hostEarnings.getAddress();
        console.log('   ✅ HostEarnings deployed:', hostEarningsAddr);
        
        // 2. Deploy PaymentEscrowWithEarnings
        console.log('\n2️⃣  Deploying PaymentEscrowWithEarnings...');
        const PaymentEscrowFactory = new ethers.ContractFactory(
            paymentEscrowArtifact.abi,
            paymentEscrowArtifact.bytecode.object,
            wallet
        );
        const paymentEscrow = await PaymentEscrowFactory.deploy(TREASURY, FEE_BASIS_POINTS);
        await paymentEscrow.waitForDeployment();
        const paymentEscrowAddr = await paymentEscrow.getAddress();
        console.log('   ✅ PaymentEscrowWithEarnings deployed:', paymentEscrowAddr);
        
        // 3. Deploy JobMarketplaceFABWithS5
        console.log('\n3️⃣  Deploying JobMarketplaceFABWithS5...');
        const JobMarketplaceFactory = new ethers.ContractFactory(
            jobMarketplaceArtifact.abi,
            jobMarketplaceArtifact.bytecode.object,
            wallet
        );
        const jobMarketplace = await JobMarketplaceFactory.deploy(NODE_REGISTRY_FAB, hostEarningsAddr);
        await jobMarketplace.waitForDeployment();
        const jobMarketplaceAddr = await jobMarketplace.getAddress();
        console.log('   ✅ JobMarketplaceFABWithS5 deployed:', jobMarketplaceAddr);
        
        // Configure contracts
        console.log('\n⚙️  CONFIGURATION PHASE\n');
        
        // Configure HostEarnings
        console.log('4️⃣  Configuring HostEarnings...');
        const txAuth = await hostEarnings.setAuthorizedCaller(paymentEscrowAddr, true);
        await txAuth.wait();
        console.log('   ✅ PaymentEscrow authorized');
        
        // Configure PaymentEscrow
        console.log('\n5️⃣  Configuring PaymentEscrowWithEarnings...');
        const txJM = await paymentEscrow.setJobMarketplace(jobMarketplaceAddr);
        await txJM.wait();
        console.log('   ✅ JobMarketplace set');
        
        // Configure JobMarketplace
        console.log('\n6️⃣  Configuring JobMarketplaceFABWithS5...');
        const txPE = await jobMarketplace.setPaymentEscrow(paymentEscrowAddr);
        await txPE.wait();
        console.log('   ✅ PaymentEscrow set');
        
        // Verification
        console.log('\n✅ DEPLOYMENT COMPLETE!\n');
        console.log('==============================================');
        console.log('📝 NEW S5-ENABLED CONTRACT ADDRESSES:');
        console.log('==============================================');
        console.log(`JOB_MARKETPLACE_FAB_WITH_S5_ADDRESS="${jobMarketplaceAddr}"`);
        console.log(`HOST_EARNINGS_ADDRESS="${hostEarningsAddr}"`);
        console.log(`PAYMENT_ESCROW_WITH_EARNINGS_ADDRESS="${paymentEscrowAddr}"`);
        console.log('==============================================\n');
        
        // Test the deployment
        console.log('🧪 Testing deployment...');
        const nodeReg = await jobMarketplace.nodeRegistry();
        const hostEarn = await jobMarketplace.hostEarnings();
        const payEsc = await jobMarketplace.paymentEscrow();
        
        console.log('   NodeRegistry:', nodeReg === NODE_REGISTRY_FAB ? '✅' : '❌');
        console.log('   HostEarnings:', hostEarn === hostEarningsAddr ? '✅' : '❌');
        console.log('   PaymentEscrow:', payEsc === paymentEscrowAddr ? '✅' : '❌');
        
        console.log('\n🎉 All contracts deployed and configured successfully!');
        
        // Save to file for reference
        const deploymentInfo = {
            timestamp: new Date().toISOString(),
            network: 'Base Sepolia',
            contracts: {
                JobMarketplaceFABWithS5: jobMarketplaceAddr,
                HostEarnings: hostEarningsAddr,
                PaymentEscrowWithEarnings: paymentEscrowAddr,
                NodeRegistryFAB: NODE_REGISTRY_FAB,
                Treasury: TREASURY
            }
        };
        
        fs.writeFileSync('s5-deployment.json', JSON.stringify(deploymentInfo, null, 2));
        console.log('\n📄 Deployment info saved to s5-deployment.json');
        
    } catch (error) {
        console.error('\n❌ Deployment failed:', error.message);
        process.exit(1);
    }
}

main().catch(console.error);