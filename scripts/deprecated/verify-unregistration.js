#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function verify() {
  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );
  
  const hostAddress = process.env.TEST_USER_2_ADDRESS || process.env.TEST_HOST_2_ADDRESS;
  const NODE_REGISTRY = '0x87516C13Ea2f99de598665e14cab64E191A0f8c4';
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';
  
  const nodeRegistryAbi = [
    'function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)'
  ];
  
  const fabTokenAbi = [
    'function balanceOf(address) view returns (uint256)'
  ];
  
  const nodeRegistry = new ethers.Contract(NODE_REGISTRY, nodeRegistryAbi, provider);
  const fabToken = new ethers.Contract(FAB_TOKEN, fabTokenAbi, provider);
  
  const nodeInfo = await nodeRegistry.nodes(hostAddress);
  const fabBalance = await fabToken.balanceOf(hostAddress);
  
  console.log('\n====================================');
  console.log('HOST UNREGISTRATION VERIFICATION');
  console.log('====================================\n');
  
  console.log('Host Address:', hostAddress);
  console.log('\nRegistry Status:');
  console.log('  Active:', nodeInfo.active);
  console.log('  Staked:', ethers.utils.formatUnits(nodeInfo.stakedAmount, 18), 'FAB');
  console.log('  Operator:', nodeInfo.operator);
  
  console.log('\nCurrent Balances:');
  console.log('  FAB Balance:', ethers.utils.formatUnits(fabBalance, 18), 'FAB');
  
  console.log('\n====================================');
  
  if (!nodeInfo.active && nodeInfo.stakedAmount.eq(0)) {
    console.log('✅ VERIFICATION PASSED!');
    console.log('====================================\n');
    console.log('The host has been successfully unregistered:');
    console.log('  • No longer active in registry');
    console.log('  • All staked FAB returned (0 remaining)');
    console.log('  • Ready for re-registration in tests');
    console.log('\nYour test should now be able to register this host.');
  } else {
    console.log('⚠️ UNEXPECTED STATE!');
    console.log('====================================\n');
    if (nodeInfo.active) {
      console.log('  • Host is still marked as active');
    }
    if (!nodeInfo.stakedAmount.eq(0)) {
      console.log('  • Host still has', ethers.utils.formatUnits(nodeInfo.stakedAmount, 18), 'FAB staked');
    }
    console.log('\nThis may prevent test execution.');
  }
  
  console.log('\n');
}

verify()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Error:', error.message);
    process.exit(1);
  });