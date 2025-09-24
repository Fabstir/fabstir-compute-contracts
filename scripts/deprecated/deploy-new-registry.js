#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

async function deployNewRegistry() {
  console.log('\n🚀 Deploying New NodeRegistryFAB Contract');
  console.log('================================\n');

  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  // Use TEST_USER_1 as deployer
  const deployerPrivateKey = process.env.TEST_USER_1_PRIVATE_KEY;
  const deployerAddress = process.env.TEST_USER_1_ADDRESS;
  
  if (!deployerPrivateKey || !deployerAddress) {
    console.error('❌ TEST_USER_1_PRIVATE_KEY and TEST_USER_1_ADDRESS must be set');
    return;
  }

  const deployer = new ethers.Wallet(deployerPrivateKey, provider);
  console.log('Deployer:', deployerAddress);
  
  const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';
  
  // Check deployer balance
  const ethBalance = await provider.getBalance(deployerAddress);
  console.log('ETH Balance:', ethers.utils.formatEther(ethBalance), 'ETH');
  
  if (ethBalance.lt(ethers.utils.parseEther('0.01'))) {
    console.error('❌ Insufficient ETH for deployment (need at least 0.01 ETH)');
    return;
  }

  // NodeRegistryFAB bytecode (compiled from src/NodeRegistryFAB.sol)
  // You would need to compile this first with: forge build
  console.log('\n⚠️  NOTE: To deploy a new registry, you need to:');
  console.log('1. Run: forge build');
  console.log('2. Get bytecode from: out/NodeRegistryFAB.sol/NodeRegistryFAB.json');
  console.log('3. Deploy using the bytecode\n');
  
  console.log('Alternative: Since the hosts are stuck in the current registry,');
  console.log('the recommended approach is to:');
  console.log('1. Use fresh addresses for testing');
  console.log('2. Or wait for contract owner to upgrade/fix the registry');
  console.log('3. Or deploy fresh test environment with ./scripts/deploy-fresh-test.sh');
  
  return null;
}

async function useAlternativeAddresses() {
  console.log('\n🔄 Alternative Solution: Use Fresh Test Addresses');
  console.log('================================\n');
  
  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );
  
  console.log('Current stuck addresses:');
  console.log('- TEST_HOST_1:', process.env.TEST_HOST_1_ADDRESS);
  console.log('- TEST_USER_2:', process.env.TEST_USER_2_ADDRESS);
  
  console.log('\nYou can:');
  console.log('1. Generate new test wallets and update .env');
  console.log('2. Transfer FAB tokens to new addresses');
  console.log('3. Register the new addresses in the current registry');
  
  console.log('\nOr deploy a completely fresh test environment:');
  console.log('$ ./scripts/deploy-fresh-test.sh');
  console.log('\nThis will deploy new JobMarketplace with fresh registry.');
}

async function main() {
  const newRegistry = await deployNewRegistry();
  
  if (!newRegistry) {
    await useAlternativeAddresses();
  }
}

main()
  .then(() => {
    console.log('\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('Error:', error);
    process.exit(1);
  });