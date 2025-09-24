#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function fixStuckHost(name, privateKeyEnv, addressEnv) {
  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  const hostAddress = process.env[addressEnv];
  const hostPrivateKey = process.env[privateKeyEnv];
  
  if (!hostAddress || !hostPrivateKey) {
    console.error(`❌ ${addressEnv} and ${privateKeyEnv} must be set`);
    return false;
  }

  const wallet = new ethers.Wallet(hostPrivateKey, provider);
  
  const NODE_REGISTRY = '0x87516C13Ea2f99de598665e14cab64E191A0f8c4';
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';

  const nodeRegistryAbi = [
    'function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)',
    'function registerNode(string metadata) external',
    'function unregisterNode() external',
    'function stake(uint256 amount) external',
    'function MIN_STAKE() view returns (uint256)'
  ];

  const fabTokenAbi = [
    'function balanceOf(address) view returns (uint256)',
    'function approve(address spender, uint256 amount) returns (bool)'
  ];

  const nodeRegistry = new ethers.Contract(NODE_REGISTRY, nodeRegistryAbi, wallet);
  const fabToken = new ethers.Contract(FAB_TOKEN, fabTokenAbi, wallet);

  try {
    console.log(`\n📝 Processing ${name} (${hostAddress}):`);
    
    // Check current state
    const nodeInfo = await nodeRegistry.nodes(hostAddress);
    const MIN_STAKE = await nodeRegistry.MIN_STAKE();
    
    console.log('  Current state:');
    console.log('    Operator:', nodeInfo.operator);
    console.log('    Active:', nodeInfo.active);
    console.log('    Staked:', ethers.utils.formatUnits(nodeInfo.stakedAmount, 18), 'FAB');
    
    // If stuck (registered but inactive with 0 stake), try to stake to activate
    if (nodeInfo.operator !== ethers.constants.AddressZero && !nodeInfo.active && nodeInfo.stakedAmount.eq(0)) {
      console.log('  ⚠️  Found in stuck state (registered but inactive with 0 stake)');
      console.log('  Attempting to activate by staking...');
      
      // Try staking to see if it activates the node
      const fabBalance = await fabToken.balanceOf(hostAddress);
      console.log('  FAB Balance:', ethers.utils.formatUnits(fabBalance, 18));
      
      if (fabBalance.gte(MIN_STAKE)) {
        console.log('  Approving', ethers.utils.formatUnits(MIN_STAKE, 18), 'FAB...');
        const approveTx = await fabToken.approve(NODE_REGISTRY, MIN_STAKE, {
          gasLimit: 100000,
          maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
          maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
        });
        await approveTx.wait();
        
        console.log('  Attempting to stake...');
        try {
          const stakeTx = await nodeRegistry.stake(MIN_STAKE, {
            gasLimit: 200000,
            maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
            maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
          });
          await stakeTx.wait();
          console.log('  ✅ Staking successful!');
          
          // Check if now active
          const newInfo = await nodeRegistry.nodes(hostAddress);
          if (newInfo.active) {
            console.log('  ✅ Node is now active with', ethers.utils.formatUnits(newInfo.stakedAmount, 18), 'FAB staked');
            return true;
          }
        } catch (stakeError) {
          console.log('  ❌ Staking failed:', stakeError.reason || 'Node not active');
        }
      }
    }
    
    // If already active with stake, we're good
    if (nodeInfo.active && nodeInfo.stakedAmount.gte(MIN_STAKE)) {
      console.log('  ✅ Already properly registered with', ethers.utils.formatUnits(nodeInfo.stakedAmount, 18), 'FAB');
      return true;
    }
    
    // If not registered at all, register fresh
    if (nodeInfo.operator === ethers.constants.AddressZero) {
      console.log('  Not registered, proceeding with fresh registration...');
      
      const fabBalance = await fabToken.balanceOf(hostAddress);
      if (fabBalance.lt(MIN_STAKE)) {
        console.log('  ❌ Insufficient FAB tokens');
        return false;
      }
      
      console.log('  Approving', ethers.utils.formatUnits(MIN_STAKE, 18), 'FAB...');
      const approveTx = await fabToken.approve(NODE_REGISTRY, MIN_STAKE, {
        gasLimit: 100000,
        maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
        maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
      });
      await approveTx.wait();
      
      const metadata = name === 'TEST_HOST_1' 
        ? 'llama-2-7b,llama-2-13b,inference,base-sepolia'
        : 'gpt-4,claude-3,inference,training,base-sepolia';
      
      console.log('  Registering with metadata...');
      const registerTx = await nodeRegistry.registerNode(metadata, {
        gasLimit: 300000,
        maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
        maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
      });
      await registerTx.wait();
      console.log('  ✅ Registration successful!');
      
      const finalInfo = await nodeRegistry.nodes(hostAddress);
      console.log('  Final state: Active =', finalInfo.active, ', Staked =', ethers.utils.formatUnits(finalInfo.stakedAmount, 18), 'FAB');
      return finalInfo.active;
    }
    
    console.log('  ❌ Unable to fix stuck state - manual intervention needed');
    return false;
    
  } catch (error) {
    console.error(`  ❌ Error:`, error.reason || error.message);
    return false;
  }
}

async function main() {
  console.log('\n🔧 Fixing Stuck Hosts');
  console.log('================================');
  
  const host1Success = await fixStuckHost('TEST_HOST_1', 'TEST_HOST_1_PRIVATE_KEY', 'TEST_HOST_1_ADDRESS');
  const user2Success = await fixStuckHost('TEST_USER_2', 'TEST_USER_2_PRIVATE_KEY', 'TEST_USER_2_ADDRESS');
  
  console.log('\n================================');
  console.log('SUMMARY');
  console.log('================================\n');
  
  console.log('TEST_HOST_1:', host1Success ? '✅ Active' : '❌ Failed');
  console.log('TEST_USER_2:', user2Success ? '✅ Active' : '❌ Failed');
  
  if (!host1Success || !user2Success) {
    console.log('\n⚠️  Some hosts could not be activated.');
    console.log('The contract prevents re-registration when operator is already set.');
    console.log('Manual intervention or contract upgrade may be needed.');
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });