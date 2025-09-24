#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function registerHost(hostName, privateKeyEnv, addressEnv, metadata) {
  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  const hostAddress = process.env[addressEnv];
  const hostPrivateKey = process.env[privateKeyEnv];

  if (!hostAddress || !hostPrivateKey) {
    console.error(`❌ Error: ${addressEnv} and ${privateKeyEnv} must be set in .env`);
    return false;
  }

  const wallet = new ethers.Wallet(hostPrivateKey, provider);
  
  // Contract setup
  const NODE_REGISTRY = '0x87516C13Ea2f99de598665e14cab64E191A0f8c4';
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';

  const nodeRegistryAbi = [
    'function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)',
    'function registerNode(string metadata) external',
    'function MIN_STAKE() view returns (uint256)',
    'event NodeRegistered(address indexed operator, uint256 stakedAmount, string metadata)'
  ];

  const fabTokenAbi = [
    'function balanceOf(address) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function allowance(address owner, address spender) view returns (uint256)',
    'function symbol() view returns (string)',
    'function decimals() view returns (uint8)'
  ];

  const nodeRegistry = new ethers.Contract(NODE_REGISTRY, nodeRegistryAbi, wallet);
  const fabToken = new ethers.Contract(FAB_TOKEN, fabTokenAbi, wallet);

  try {
    console.log(`\n📝 Registering ${hostName}`);
    console.log(`   Address: ${hostAddress}`);
    
    // Check if already registered
    const nodeInfo = await nodeRegistry.nodes(hostAddress);
    if (nodeInfo.active) {
      console.log(`   ✅ Already registered with ${ethers.utils.formatUnits(nodeInfo.stakedAmount, 18)} FAB staked`);
      return true;
    }
    
    // Check FAB balance
    const fabBalance = await fabToken.balanceOf(hostAddress);
    const MIN_STAKE = await nodeRegistry.MIN_STAKE();
    console.log(`   FAB Balance: ${ethers.utils.formatUnits(fabBalance, 18)}`);
    console.log(`   Required Stake: ${ethers.utils.formatUnits(MIN_STAKE, 18)}`);
    
    if (fabBalance.lt(MIN_STAKE)) {
      console.error(`   ❌ Insufficient FAB tokens`);
      return false;
    }
    
    // Check ETH for gas
    const ethBalance = await provider.getBalance(hostAddress);
    console.log(`   ETH Balance: ${ethers.utils.formatEther(ethBalance)}`);
    
    if (ethBalance.lt(ethers.utils.parseEther('0.001'))) {
      console.error(`   ⚠️  Low ETH balance for gas fees`);
    }
    
    // Approve FAB tokens
    console.log(`   Approving ${ethers.utils.formatUnits(MIN_STAKE, 18)} FAB...`);
    const approveTx = await fabToken.approve(NODE_REGISTRY, MIN_STAKE, {
      gasLimit: 100000,
      maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
    });
    await approveTx.wait();
    console.log(`   ✅ Approval confirmed`);
    
    // Register
    console.log(`   Registering with metadata...`);
    const registerTx = await nodeRegistry.registerNode(metadata, {
      gasLimit: 300000,
      maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
    });
    
    console.log(`   Transaction: ${registerTx.hash}`);
    const receipt = await registerTx.wait();
    console.log(`   ✅ Registration confirmed in block ${receipt.blockNumber}`);
    
    // Verify registration
    const newNodeInfo = await nodeRegistry.nodes(hostAddress);
    if (newNodeInfo.active) {
      console.log(`   ✅ Successfully registered with ${ethers.utils.formatUnits(newNodeInfo.stakedAmount, 18)} FAB staked`);
      return true;
    } else {
      console.error(`   ❌ Registration verification failed`);
      return false;
    }
    
  } catch (error) {
    console.error(`   ❌ Error: ${error.reason || error.message}`);
    return false;
  }
}

async function main() {
  console.log('\n🚀 Host Registration Script');
  console.log('================================\n');
  
  // Register TEST_HOST_1
  const host1Success = await registerHost(
    'TEST_HOST_1',
    'TEST_HOST_1_PRIVATE_KEY',
    'TEST_HOST_1_ADDRESS',
    'llama-2-7b,llama-2-13b,inference,base-sepolia'
  );
  
  // Register TEST_USER_2 (acting as a host)
  const user2Success = await registerHost(
    'TEST_USER_2',
    'TEST_USER_2_PRIVATE_KEY',
    'TEST_USER_2_ADDRESS',
    'gpt-4,claude-3,inference,training,base-sepolia'
  );
  
  // Summary
  console.log('\n================================');
  console.log('REGISTRATION SUMMARY');
  console.log('================================\n');
  
  console.log('TEST_HOST_1:', host1Success ? '✅ Registered' : '❌ Failed');
  console.log('TEST_USER_2:', user2Success ? '✅ Registered' : '❌ Failed');
  
  if (host1Success && user2Success) {
    console.log('\n✅ All hosts successfully registered!');
    console.log('   Both hosts have 1000 FAB staked.');
  } else {
    console.log('\n⚠️  Some registrations failed. Check logs above.');
  }
}

main()
  .then(() => {
    console.log('\nScript completed.\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });