// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function registerHosts() {
  console.log('\n🚀 Registering Hosts in New Registry');
  console.log('================================\n');

  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  // New registry address
  const NODE_REGISTRY = '0x039AB5d5e8D5426f9963140202F506A2Ce6988F9';
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';
  
  console.log('Using NEW NodeRegistryFAB:', NODE_REGISTRY);
  console.log('FAB Token:', FAB_TOKEN, '\n');

  // Setup wallets
  const host1Wallet = new ethers.Wallet(process.env.TEST_HOST_1_PRIVATE_KEY, provider);
  const user2Wallet = new ethers.Wallet(process.env.TEST_USER_2_PRIVATE_KEY, provider);

  const nodeRegistryAbi = [
    'function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)',
    'function registerNode(string metadata) external',
    'function MIN_STAKE() view returns (uint256)',
    'event NodeRegistered(address indexed operator, uint256 stakedAmount, string metadata)'
  ];

  const fabTokenAbi = [
    'function balanceOf(address) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function allowance(address owner, address spender) view returns (uint256)'
  ];

  const nodeRegistry = new ethers.Contract(NODE_REGISTRY, nodeRegistryAbi, provider);
  const fabToken = new ethers.Contract(FAB_TOKEN, fabTokenAbi, provider);
  const MIN_STAKE = await nodeRegistry.MIN_STAKE();

  async function registerHost(name, wallet, metadata) {
    console.log(`📝 Registering ${name}`);
    console.log(`   Address: ${wallet.address}`);
    
    try {
      // Check current status
      const nodeInfo = await nodeRegistry.nodes(wallet.address);
      if (nodeInfo.active) {
        console.log(`   ✅ Already registered with ${ethers.utils.formatUnits(nodeInfo.stakedAmount, 18)} FAB`);
        return true;
      }
      
      // Check balances
      const fabBalance = await fabToken.balanceOf(wallet.address);
      const ethBalance = await provider.getBalance(wallet.address);
      
      console.log(`   FAB Balance: ${ethers.utils.formatUnits(fabBalance, 18)}`);
      console.log(`   ETH Balance: ${ethers.utils.formatEther(ethBalance)}`);
      
      if (fabBalance.lt(MIN_STAKE)) {
        console.log(`   ❌ Insufficient FAB (need ${ethers.utils.formatUnits(MIN_STAKE, 18)})`);
        return false;
      }
      
      if (ethBalance.lt(ethers.utils.parseEther('0.001'))) {
        console.log(`   ⚠️  Low ETH for gas`);
      }
      
      // Check existing allowance
      const currentAllowance = await fabToken.allowance(wallet.address, NODE_REGISTRY);
      if (currentAllowance.lt(MIN_STAKE)) {
        // Approve tokens
        console.log(`   Approving ${ethers.utils.formatUnits(MIN_STAKE, 18)} FAB...`);
        const fabWithSigner = fabToken.connect(wallet);
        const approveTx = await fabWithSigner.approve(NODE_REGISTRY, MIN_STAKE, {
          gasLimit: 100000,
          maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
          maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
        });
        await approveTx.wait();
        console.log(`   ✅ Approval confirmed`);
      }
      
      // Register
      console.log(`   Registering with metadata...`);
      const registryWithSigner = nodeRegistry.connect(wallet);
      const registerTx = await registryWithSigner.registerNode(metadata, {
        gasLimit: 300000,
        maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
        maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
      });
      
      console.log(`   Transaction: ${registerTx.hash}`);
      const receipt = await registerTx.wait();
      
      // Check for event
      const event = receipt.events?.find(e => e.event === 'NodeRegistered');
      if (event) {
        console.log(`   ✅ Registered with ${ethers.utils.formatUnits(event.args.stakedAmount, 18)} FAB staked`);
      }
      
      // Verify
      const finalInfo = await nodeRegistry.nodes(wallet.address);
      if (finalInfo.active && finalInfo.stakedAmount.gte(MIN_STAKE)) {
        console.log(`   ✅ Verified: Active with ${ethers.utils.formatUnits(finalInfo.stakedAmount, 18)} FAB\n`);
        return true;
      }
      
      return false;
      
    } catch (error) {
      console.log(`   ❌ Error: ${error.reason || error.message}\n`);
      return false;
    }
  }

  // Register both hosts
  const host1Success = await registerHost(
    'TEST_HOST_1',
    host1Wallet,
    'llama-2-7b,llama-2-13b,inference,base-sepolia'
  );
  
  const user2Success = await registerHost(
    'TEST_USER_2',
    user2Wallet,
    'gpt-4,claude-3,inference,training,base-sepolia'
  );

  // Summary
  console.log('================================');
  console.log('REGISTRATION SUMMARY');
  console.log('================================\n');
  
  console.log('TEST_HOST_1:', host1Success ? '✅ Registered' : '❌ Failed');
  console.log('TEST_USER_2:', user2Success ? '✅ Registered' : '❌ Failed');
  
  if (host1Success && user2Success) {
    console.log('\n✅ SUCCESS: Both hosts registered with 1000 FAB each!');
    console.log('\n📝 Update your .env file:');
    console.log(`NODE_REGISTRY_ADDRESS="${NODE_REGISTRY}"`);
  } else {
    console.log('\n⚠️  Some registrations failed. Check logs above.');
  }
}

registerHosts()
  .then(() => {
    console.log('\nScript completed.\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });