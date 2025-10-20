// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function cleanAndRegister() {
  console.log('\n🔧 Clean Registration Script\n');
  console.log('================================\n');

  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  // Setup wallets
  const host1Wallet = new ethers.Wallet(process.env.TEST_HOST_1_PRIVATE_KEY, provider);
  const user2Wallet = new ethers.Wallet(process.env.TEST_USER_2_PRIVATE_KEY, provider);

  const NODE_REGISTRY = '0x87516C13Ea2f99de598665e14cab64E191A0f8c4';
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';

  const nodeRegistryAbi = [
    'function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)',
    'function registerNode(string metadata) external',
    'function unregisterNode() external',
    'function MIN_STAKE() view returns (uint256)',
    'event NodeRegistered(address indexed operator, uint256 stakedAmount, string metadata)',
    'event NodeUnregistered(address indexed operator, uint256 returnedAmount)'
  ];

  const fabTokenAbi = [
    'function balanceOf(address) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function decimals() view returns (uint8)'
  ];

  try {
    // Check initial state
    console.log('📊 Initial State Check:\n');
    
    const registry = new ethers.Contract(NODE_REGISTRY, nodeRegistryAbi, provider);
    const fabToken = new ethers.Contract(FAB_TOKEN, fabTokenAbi, provider);
    const MIN_STAKE = await registry.MIN_STAKE();
    
    const host1Info = await registry.nodes(host1Wallet.address);
    const user2Info = await registry.nodes(user2Wallet.address);
    
    console.log('TEST_HOST_1:', host1Wallet.address);
    console.log('  Operator:', host1Info.operator);
    console.log('  Active:', host1Info.active);
    console.log('  Staked:', ethers.utils.formatUnits(host1Info.stakedAmount, 18), 'FAB');
    
    console.log('\nTEST_USER_2:', user2Wallet.address);
    console.log('  Operator:', user2Info.operator);
    console.log('  Active:', user2Info.active);
    console.log('  Staked:', ethers.utils.formatUnits(user2Info.stakedAmount, 18), 'FAB');
    
    // Check if we need to clean up first
    const host1NeedsCleanup = host1Info.operator !== ethers.constants.AddressZero && !host1Info.active;
    const user2NeedsCleanup = user2Info.operator !== ethers.constants.AddressZero && !user2Info.active;
    
    if (host1NeedsCleanup || user2NeedsCleanup) {
      console.log('\n⚠️  Found hosts in problematic state (registered but inactive with 0 stake)');
      console.log('This unusual state prevents re-registration.');
      console.log('\nThe NodeRegistryFAB contract doesn\'t allow re-registration when:');
      console.log('- operator field is set (even if inactive)');
      console.log('- Previous registration exists in any state');
      console.log('\n❌ Cannot proceed without contract upgrade or owner intervention.');
      return;
    }
    
    // Register TEST_HOST_1
    if (host1Info.operator === ethers.constants.AddressZero) {
      console.log('\n📝 Registering TEST_HOST_1...');
      
      const host1Balance = await fabToken.balanceOf(host1Wallet.address);
      console.log('  Balance:', ethers.utils.formatUnits(host1Balance, 18), 'FAB');
      
      if (host1Balance.lt(MIN_STAKE)) {
        console.log('  ❌ Insufficient FAB tokens');
      } else {
        const registryWithHost1 = registry.connect(host1Wallet);
        const fabWithHost1 = fabToken.connect(host1Wallet);
        
        console.log('  Approving', ethers.utils.formatUnits(MIN_STAKE, 18), 'FAB...');
        const approveTx1 = await fabWithHost1.approve(NODE_REGISTRY, MIN_STAKE, {
          gasLimit: 100000,
          maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
          maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
        });
        await approveTx1.wait();
        
        console.log('  Registering...');
        const registerTx1 = await registryWithHost1.registerNode('llama-2-7b,llama-2-13b,inference,base-sepolia', {
          gasLimit: 300000,
          maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
          maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
        });
        const receipt1 = await registerTx1.wait();
        console.log('  ✅ Registered in block', receipt1.blockNumber);
      }
    } else if (host1Info.active) {
      console.log('\n✅ TEST_HOST_1 already registered and active');
    }
    
    // Register TEST_USER_2
    if (user2Info.operator === ethers.constants.AddressZero) {
      console.log('\n📝 Registering TEST_USER_2...');
      
      const user2Balance = await fabToken.balanceOf(user2Wallet.address);
      console.log('  Balance:', ethers.utils.formatUnits(user2Balance, 18), 'FAB');
      
      if (user2Balance.lt(MIN_STAKE)) {
        console.log('  ❌ Insufficient FAB tokens');
      } else {
        const registryWithUser2 = registry.connect(user2Wallet);
        const fabWithUser2 = fabToken.connect(user2Wallet);
        
        console.log('  Approving', ethers.utils.formatUnits(MIN_STAKE, 18), 'FAB...');
        const approveTx2 = await fabWithUser2.approve(NODE_REGISTRY, MIN_STAKE, {
          gasLimit: 100000,
          maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
          maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
        });
        await approveTx2.wait();
        
        console.log('  Registering...');
        const registerTx2 = await registryWithUser2.registerNode('gpt-4,claude-3,inference,training,base-sepolia', {
          gasLimit: 300000,
          maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
          maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
        });
        const receipt2 = await registerTx2.wait();
        console.log('  ✅ Registered in block', receipt2.blockNumber);
      }
    } else if (user2Info.active) {
      console.log('\n✅ TEST_USER_2 already registered and active');
    }
    
    // Final verification
    console.log('\n================================');
    console.log('FINAL STATUS');
    console.log('================================\n');
    
    const finalHost1 = await registry.nodes(host1Wallet.address);
    const finalUser2 = await registry.nodes(user2Wallet.address);
    
    console.log('TEST_HOST_1:');
    console.log('  Active:', finalHost1.active);
    console.log('  Staked:', ethers.utils.formatUnits(finalHost1.stakedAmount, 18), 'FAB');
    
    console.log('\nTEST_USER_2:');
    console.log('  Active:', finalUser2.active);
    console.log('  Staked:', ethers.utils.formatUnits(finalUser2.stakedAmount, 18), 'FAB');
    
    if (finalHost1.active && finalUser2.active) {
      console.log('\n✅ SUCCESS: Both hosts registered with 1000 FAB staked!');
    }
    
  } catch (error) {
    console.error('\n❌ Error:', error.reason || error.message);
  }
}

cleanAndRegister()
  .then(() => {
    console.log('\nScript completed.\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });