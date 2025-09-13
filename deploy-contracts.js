#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// Configuration
const config = {
  rpcUrl: 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR',
  privateKey: '0xe7231a57c89df087f0291bf20b952199c1d4575206d256397c02ba6383dedc97',
  etherscanApiKey: 'ZZTDTGE9HAKK7ZZC8T6SMBV4ZKIJACGZBJ',
  
  // Contract addresses
  hostEarnings: '0x4050FaDdd250dB75B0B4242B0748EB8681C72F41', // Already deployed
  treasury: '0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078',
  nodeRegistry: '0xb212F4e62a2F3BA36048054Fe75e3d0b0d61EB44', // Latest NodeRegistry with API URL support
  jobMarketplace: '0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0', // Latest JobMarketplace
  usdcAddress: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  
  // Constructor args
  feeBasisPoints: 1000, // 10%
};

// Contract ABIs and Bytecode (you'll need to compile these)
const contracts = {
  PaymentEscrowWithEarnings: {
    // This would normally come from your compiled contracts
    // For now, we'll use forge to compile and get the artifacts
    bytecode: null, // Will be loaded from forge artifacts
    abi: null
  },
  JobMarketplaceFABWithEarnings: {
    bytecode: null,
    abi: null
  },
  HostEarnings: {
    // For configuration calls
    abi: [
      "function setAuthorizedCaller(address caller, bool authorized) external",
      "function owner() external view returns (address)"
    ]
  }
};

async function loadCompiledContracts() {
  console.log('📦 Loading compiled contract artifacts...');
  
  try {
    // Load PaymentEscrowWithEarnings
    const escrowPath = path.join(__dirname, 'out/PaymentEscrowWithEarnings.sol/PaymentEscrowWithEarnings.json');
    if (fs.existsSync(escrowPath)) {
      const escrowArtifact = JSON.parse(fs.readFileSync(escrowPath, 'utf8'));
      contracts.PaymentEscrowWithEarnings.bytecode = escrowArtifact.bytecode.object;
      contracts.PaymentEscrowWithEarnings.abi = escrowArtifact.abi;
      console.log('   ✓ PaymentEscrowWithEarnings loaded');
    } else {
      throw new Error('PaymentEscrowWithEarnings artifact not found. Run `forge build` first.');
    }

    // Load JobMarketplaceFABWithEarnings  
    const marketplacePath = path.join(__dirname, 'out/JobMarketplaceFABWithEarnings.sol/JobMarketplaceFABWithEarnings.json');
    if (fs.existsSync(marketplacePath)) {
      const marketplaceArtifact = JSON.parse(fs.readFileSync(marketplacePath, 'utf8'));
      contracts.JobMarketplaceFABWithEarnings.bytecode = marketplaceArtifact.bytecode.object;
      contracts.JobMarketplaceFABWithEarnings.abi = marketplaceArtifact.abi;
      console.log('   ✓ JobMarketplaceFABWithEarnings loaded');
    } else {
      throw new Error('JobMarketplaceFABWithEarnings artifact not found. Run `forge build` first.');
    }

    console.log('');
  } catch (error) {
    console.error('❌ Error loading contracts:', error.message);
    console.log('\n💡 Make sure to run `forge build` first to compile contracts.');
    process.exit(1);
  }
}

async function deployContract(name, contractData, constructorArgs = [], wallet) {
  console.log(`🚀 Deploying ${name}...`);
  
  try {
    const factory = new ethers.ContractFactory(contractData.abi, contractData.bytecode, wallet);
    
    console.log(`   - Constructor args: [${constructorArgs.join(', ')}]`);
    console.log('   - Sending transaction...');
    
    const contract = await factory.deploy(...constructorArgs, {
      gasLimit: 3000000, // Adjust as needed
    });
    
    console.log(`   - Transaction hash: ${contract.deploymentTransaction().hash}`);
    console.log('   - Waiting for confirmation...');
    
    await contract.waitForDeployment();
    const address = await contract.getAddress();
    
    console.log(`   ✅ ${name} deployed to: ${address}`);
    console.log('');
    
    return { contract, address };
  } catch (error) {
    console.error(`   ❌ Failed to deploy ${name}:`, error.message);
    throw error;
  }
}

async function configureContracts(hostEarningsAddr, paymentEscrowAddr, jobMarketplaceAddr, wallet) {
  console.log('⚙️  Configuring contracts...');
  
  try {
    // Create contract instances
    const hostEarnings = new ethers.Contract(hostEarningsAddr, contracts.HostEarnings.abi, wallet);
    
    // 1. Authorize PaymentEscrow in HostEarnings
    console.log('   - Authorizing PaymentEscrow in HostEarnings...');
    const tx1 = await hostEarnings.setAuthorizedCaller(paymentEscrowAddr, true);
    await tx1.wait();
    console.log(`     ✓ Transaction: ${tx1.hash}`);

    // 2. Set JobMarketplace in PaymentEscrow
    console.log('   - Setting JobMarketplace in PaymentEscrow...');
    const paymentEscrow = new ethers.Contract(paymentEscrowAddr, [
      "function setJobMarketplace(address _jobMarketplace) external"
    ], wallet);
    const tx2 = await paymentEscrow.setJobMarketplace(jobMarketplaceAddr);
    await tx2.wait();
    console.log(`     ✓ Transaction: ${tx2.hash}`);

    // 3. Set PaymentEscrow in JobMarketplace
    console.log('   - Setting PaymentEscrow in JobMarketplace...');
    const jobMarketplace = new ethers.Contract(jobMarketplaceAddr, [
      "function setPaymentEscrow(address _paymentEscrow) external"
    ], wallet);
    const tx3 = await jobMarketplace.setPaymentEscrow(paymentEscrowAddr);
    await tx3.wait();
    console.log(`     ✓ Transaction: ${tx3.hash}`);

    // 4. Set USDC address in JobMarketplace
    console.log('   - Setting USDC address in JobMarketplace...');
    const jobMarketplaceWithUsdc = new ethers.Contract(jobMarketplaceAddr, [
      "function setUsdcAddress(address _usdcAddress) external"
    ], wallet);
    const tx4 = await jobMarketplaceWithUsdc.setUsdcAddress(config.usdcAddress);
    await tx4.wait();
    console.log(`     ✓ Transaction: ${tx4.hash}`);

    console.log('   ✅ All contracts configured successfully!');
    console.log('');
    
  } catch (error) {
    console.error('   ❌ Configuration failed:', error.message);
    throw error;
  }
}

async function verifyContract(address, contractName, constructorArgs = []) {
  console.log(`🔍 Contract verification for ${contractName}:`);
  console.log(`   📍 Address: ${address}`);
  console.log(`   🔗 View on BaseScan: https://sepolia.basescan.org/address/${address}`);
  console.log(`   💡 To verify manually, use:`);
  console.log(`   forge verify-contract ${address} src/${contractName}.sol:${contractName.split('With')[0]} --etherscan-api-key ${config.etherscanApiKey} --chain base-sepolia`);
  console.log('');
}

async function main() {
  console.log('🎯 FABSTIR FRESH TEST ENVIRONMENT DEPLOYMENT');
  console.log('============================================');
  console.log('');
  
  console.log('📋 Configuration:');
  console.log(`   🌐 Network: Base Sepolia`);
  console.log(`   🔑 Deployer: ${config.privateKey.substring(0, 10)}...`);
  console.log(`   🏦 Treasury: ${config.treasury}`);
  console.log(`   💰 Platform Fee: ${config.feeBasisPoints / 100}%`);
  console.log('');

  try {
    // Setup provider and wallet
    const provider = new ethers.JsonRpcProvider(config.rpcUrl);
    const wallet = new ethers.Wallet(config.privateKey, provider);
    
    console.log(`💼 Deployer address: ${wallet.address}`);
    const balance = await provider.getBalance(wallet.address);
    console.log(`💎 Balance: ${ethers.formatEther(balance)} ETH`);
    console.log('');
    
    // Load compiled contracts
    await loadCompiledContracts();
    
    // Deploy contracts
    console.log('🏗️  Starting deployment...');
    console.log(`   ✅ HostEarnings (already deployed): ${config.hostEarnings}`);
    console.log('');
    
    // Deploy PaymentEscrowWithEarnings
    const escrowResult = await deployContract(
      'PaymentEscrowWithEarnings',
      contracts.PaymentEscrowWithEarnings,
      [config.treasury, config.feeBasisPoints],
      wallet
    );
    
    // Deploy JobMarketplaceFABWithEarnings
    const marketplaceResult = await deployContract(
      'JobMarketplaceFABWithEarnings', 
      contracts.JobMarketplaceFABWithEarnings,
      [config.nodeRegistry, config.hostEarnings],
      wallet
    );
    
    // Configure all contracts
    await configureContracts(
      config.hostEarnings,
      escrowResult.address,
      marketplaceResult.address,
      wallet
    );
    
    // Display final results
    console.log('🎉 DEPLOYMENT COMPLETE!');
    console.log('========================');
    console.log('');
    console.log('📍 Contract Addresses:');
    console.log(`   HostEarnings:                   ${config.hostEarnings}`);
    console.log(`   PaymentEscrowWithEarnings:      ${escrowResult.address}`);
    console.log(`   JobMarketplaceFABWithEarnings:  ${marketplaceResult.address}`);
    console.log('');
    console.log('🔗 Existing Contracts:');
    console.log(`   NodeRegistry:                   ${config.nodeRegistry}`);
    console.log(`   JobMarketplace (existing):      ${config.jobMarketplace}`);
    console.log(`   USDC Token:                     ${config.usdcAddress}`);
    console.log(`   FAB Token:                      0x6Bd8C52a1ceC5a00Df973FD60143EFaC13d30E42`);
    console.log('');
    
    // Contract verification info
    await verifyContract(escrowResult.address, 'PaymentEscrowWithEarnings', [config.treasury, config.feeBasisPoints]);
    await verifyContract(marketplaceResult.address, 'JobMarketplaceFABWithEarnings', [config.nodeRegistry, config.hostEarnings]);
    
    console.log('✅ Fresh test environment deployed successfully!');
    console.log('💡 Job IDs will start from 1 (clean state)');
    console.log('🚀 Update your client with the new contract addresses above.');
    
  } catch (error) {
    console.error('❌ Deployment failed:', error.message);
    process.exit(1);
  }
}

// Handle script execution
if (require.main === module) {
  main().catch((error) => {
    console.error('Unhandled error:', error);
    process.exit(1);
  });
}

module.exports = { main };