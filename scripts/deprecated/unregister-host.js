// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function unregisterHost() {
  console.log('\n🔧 Host Unregistration Script\n');
  console.log('================================\n');

  // Setup
  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  // Get TEST_USER_2 credentials from env
  const hostAddress = process.env.TEST_USER_2_ADDRESS || process.env.TEST_HOST_2_ADDRESS;
  const hostPrivateKey = process.env.TEST_USER_2_PRIVATE_KEY || process.env.TEST_HOST_2_PRIVATE_KEY;

  if (!hostAddress || !hostPrivateKey) {
    console.error('❌ Error: TEST_USER_2_ADDRESS and TEST_USER_2_PRIVATE_KEY must be set in .env');
    process.exit(1);
  }

  const wallet = new ethers.Wallet(hostPrivateKey, provider);
  console.log(`Host Address: ${hostAddress}`);
  console.log(`Using wallet: ${wallet.address}\n`);

  // Contract setup
  const NODE_REGISTRY = '0x87516C13Ea2f99de598665e14cab64E191A0f8c4';
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';

  const nodeRegistryAbi = [
    'function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)',
    'function unregisterNode() external',
    'event NodeUnregistered(address indexed operator, uint256 returnedAmount)'
  ];

  const fabTokenAbi = [
    'function balanceOf(address) view returns (uint256)',
    'function symbol() view returns (string)',
    'function decimals() view returns (uint8)'
  ];

  const nodeRegistry = new ethers.Contract(NODE_REGISTRY, nodeRegistryAbi, wallet);
  const fabToken = new ethers.Contract(FAB_TOKEN, fabTokenAbi, provider);

  try {
    // Check current registration status
    console.log('📊 Checking current registration status...\n');
    const nodeInfo = await nodeRegistry.nodes(hostAddress);
    
    const isRegistered = nodeInfo.operator !== ethers.constants.AddressZero;
    
    if (!isRegistered) {
      console.log('✅ Host is already unregistered!');
      console.log('   No action needed.\n');
      return;
    }

    console.log('Current Node Info:');
    console.log(`  Operator: ${nodeInfo.operator}`);
    console.log(`  Staked: ${ethers.utils.formatUnits(nodeInfo.stakedAmount, 18)} FAB`);
    console.log(`  Active: ${nodeInfo.active}`);
    console.log(`  Metadata: ${nodeInfo.metadata || '(empty)'}\n`);

    // Check balances before
    const fabBalanceBefore = await fabToken.balanceOf(hostAddress);
    const ethBalance = await provider.getBalance(hostAddress);
    
    console.log('Current Balances:');
    console.log(`  FAB: ${ethers.utils.formatUnits(fabBalanceBefore, 18)}`);
    console.log(`  ETH: ${ethers.utils.formatEther(ethBalance)}\n`);

    if (ethBalance.lt(ethers.utils.parseEther('0.001'))) {
      console.error('⚠️  Warning: Low ETH balance for gas fees');
      console.error(`   Current: ${ethers.utils.formatEther(ethBalance)} ETH`);
      console.error('   Recommended: At least 0.001 ETH\n');
    }

    // Unregister
    console.log('🚀 Unregistering host...\n');
    
    const gasPrice = await provider.getGasPrice();
    console.log(`Gas Price: ${ethers.utils.formatUnits(gasPrice, 'gwei')} gwei`);
    
    const tx = await nodeRegistry.unregisterNode({
      gasLimit: 150000,
      maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
    });
    
    console.log(`Transaction sent: ${tx.hash}`);
    console.log('Waiting for confirmation...\n');
    
    const receipt = await tx.wait();
    
    console.log('✅ Transaction confirmed!');
    console.log(`  Block: ${receipt.blockNumber}`);
    console.log(`  Gas Used: ${receipt.gasUsed.toString()}`);
    console.log(`  Status: ${receipt.status === 1 ? 'Success' : 'Failed'}\n`);

    // Check for NodeUnregistered event
    const event = receipt.events?.find(e => e.event === 'NodeUnregistered');
    if (event) {
      console.log('📋 Event Details:');
      console.log(`  Operator: ${event.args.operator}`);
      console.log(`  Returned Amount: ${ethers.utils.formatUnits(event.args.returnedAmount, 18)} FAB\n`);
    }

    // Check final status
    console.log('📊 Verifying unregistration...\n');
    
    const newNodeInfo = await nodeRegistry.nodes(hostAddress);
    const stillActive = newNodeInfo.active;
    
    if (!stillActive) {
      console.log('✅ SUCCESS: Host has been unregistered!');
      
      // Check FAB balance after
      const fabBalanceAfter = await fabToken.balanceOf(hostAddress);
      const fabReturned = fabBalanceAfter.sub(fabBalanceBefore);
      
      if (fabReturned.gt(0)) {
        console.log(`   Returned: ${ethers.utils.formatUnits(fabReturned, 18)} FAB`);
      }
      
      console.log('\nThe host can now be registered again with your test.\n');
    } else {
      console.error('❌ ERROR: Host is still active!');
      console.error('   Something went wrong with the unregistration.\n');
    }

  } catch (error) {
    console.error('❌ Error during unregistration:');
    
    if (error.reason) {
      console.error(`   Reason: ${error.reason}`);
    }
    
    if (error.message?.includes('Not registered')) {
      console.error('   The host is not registered or already unregistered.');
    } else if (error.message?.includes('insufficient funds')) {
      console.error('   Insufficient ETH for gas fees.');
    } else {
      console.error(`   ${error.message || error}`);
    }
    
    console.error('\nTroubleshooting:');
    console.error('1. Ensure TEST_USER_2_PRIVATE_KEY is correct in .env');
    console.error('2. Ensure the account has ETH for gas fees');
    console.error('3. Check if the host is actually registered\n');
    
    process.exit(1);
  }
}

// Run the script
unregisterHost()
  .then(() => {
    console.log('Script completed successfully.');
    process.exit(0);
  })
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });