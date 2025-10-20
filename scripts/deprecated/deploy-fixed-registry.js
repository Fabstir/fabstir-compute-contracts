// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

async function deployFixedRegistry() {
  console.log('\n🚀 Deploying Fixed NodeRegistryFAB Contract');
  console.log('================================\n');

  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  // Use TEST_USER_1 as deployer
  const deployerPrivateKey = process.env.TEST_USER_1_PRIVATE_KEY;
  const deployerAddress = process.env.TEST_USER_1_ADDRESS;
  
  if (!deployerPrivateKey || !deployerAddress) {
    console.error('❌ TEST_USER_1_PRIVATE_KEY and TEST_USER_1_ADDRESS must be set');
    process.exit(1);
  }

  const deployer = new ethers.Wallet(deployerPrivateKey, provider);
  console.log('Deployer:', deployerAddress);
  
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';
  
  // Check deployer balance
  const ethBalance = await provider.getBalance(deployerAddress);
  console.log('ETH Balance:', ethers.utils.formatEther(ethBalance), 'ETH');
  
  if (ethBalance.lt(ethers.utils.parseEther('0.01'))) {
    console.error('❌ Insufficient ETH for deployment (need at least 0.01 ETH)');
    process.exit(1);
  }

  try {
    // Read the compiled contract
    const contractJson = JSON.parse(
      fs.readFileSync('/workspace/out/NodeRegistryFAB.sol/NodeRegistryFAB.json', 'utf8')
    );
    
    const abi = contractJson.abi;
    const bytecode = contractJson.bytecode.object;
    
    console.log('Contract bytecode loaded');
    console.log('Bytecode length:', bytecode.length);
    
    // Deploy the contract
    const ContractFactory = new ethers.ContractFactory(abi, bytecode, deployer);
    
    console.log('\nDeploying NodeRegistryFAB with FAB token:', FAB_TOKEN);
    console.log('Estimated deployment cost: ~0.003 ETH\n');
    
    const contract = await ContractFactory.deploy(FAB_TOKEN, {
      gasLimit: 2000000,
      maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
    });
    
    console.log('Transaction hash:', contract.deployTransaction.hash);
    console.log('Waiting for confirmation...');
    
    await contract.deployed();
    
    console.log('\n✅ Contract deployed successfully!');
    console.log('================================');
    console.log('New NodeRegistryFAB Address:', contract.address);
    console.log('================================\n');
    
    // Verify deployment
    const code = await provider.getCode(contract.address);
    if (code === '0x') {
      console.error('❌ Contract deployment verification failed');
      process.exit(1);
    }
    
    // Test the contract
    console.log('Verifying contract functions...');
    const MIN_STAKE = await contract.MIN_STAKE();
    const fabTokenAddress = await contract.fabToken();
    
    console.log('  MIN_STAKE:', ethers.utils.formatUnits(MIN_STAKE, 18), 'FAB');
    console.log('  FAB Token:', fabTokenAddress);
    console.log('  ✅ Contract verified!\n');
    
    // Update .env file
    console.log('📝 Update your .env file:');
    console.log(`NODE_REGISTRY_ADDRESS="${contract.address}"`);
    console.log('\nOr run:');
    console.log(`export NODE_REGISTRY_ADDRESS="${contract.address}"`);
    
    return contract.address;
    
  } catch (error) {
    console.error('\n❌ Deployment failed:', error.message);
    if (error.reason) console.error('Reason:', error.reason);
    if (error.data) console.error('Data:', error.data);
    process.exit(1);
  }
}

deployFixedRegistry()
  .then(address => {
    console.log('\n✅ Deployment complete!');
    console.log('Next steps:');
    console.log('1. Update NODE_REGISTRY_ADDRESS in .env');
    console.log('2. Register TEST_HOST_1 and TEST_USER_2');
    process.exit(0);
  })
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });