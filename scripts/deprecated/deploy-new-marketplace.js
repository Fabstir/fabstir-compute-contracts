#!/usr/bin/env node

const { ethers } = require('ethers');
const fs = require('fs');
require('dotenv').config();

async function deployNewMarketplace() {
  console.log('\n🚀 Deploying New JobMarketplaceFABWithS5');
  console.log('==========================================\n');

  const provider = new ethers.providers.JsonRpcProvider(
    process.env.BASE_SEPOLIA_RPC_URL || 'https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR'
  );

  // Use TEST_HOST_1 as deployer (has more ETH)
  const deployerPrivateKey = process.env.TEST_HOST_1_PRIVATE_KEY;
  const deployerAddress = process.env.TEST_HOST_1_ADDRESS;
  
  if (!deployerPrivateKey || !deployerAddress) {
    console.error('❌ TEST_HOST_1_PRIVATE_KEY and TEST_HOST_1_ADDRESS must be set');
    process.exit(1);
  }

  const deployer = new ethers.Wallet(deployerPrivateKey, provider);
  console.log('Deployer:', deployerAddress);
  
  // Correct addresses
  const NEW_NODE_REGISTRY = '0x039AB5d5e8D5426f9963140202F506A2Ce6988F9'; // Fixed registry
  const HOST_EARNINGS = '0x908962e8c6CE72610021586f85ebDE09aAc97776';     // Current HostEarnings
  
  console.log('Configuration:');
  console.log('  NodeRegistry (NEW/FIXED):', NEW_NODE_REGISTRY);
  console.log('  HostEarnings:', HOST_EARNINGS);
  
  // Check deployer balance
  const ethBalance = await provider.getBalance(deployerAddress);
  console.log('  ETH Balance:', ethers.utils.formatEther(ethBalance), 'ETH');
  
  if (ethBalance.lt(ethers.utils.parseEther('0.02'))) {
    console.error('\n❌ Insufficient ETH for deployment (need at least 0.02 ETH)');
    process.exit(1);
  }

  try {
    // Read the compiled OPTIMIZED contract (smaller size)
    const contractJson = JSON.parse(
      fs.readFileSync('/workspace/out/JobMarketplaceFABWithS5Deploy.sol/JobMarketplaceFABWithS5.json', 'utf8')
    );
    
    const abi = contractJson.abi;
    const bytecode = contractJson.bytecode.object;
    
    console.log('\nContract bytecode loaded');
    console.log('Bytecode length:', bytecode.length);
    
    // Deploy the contract
    const ContractFactory = new ethers.ContractFactory(abi, bytecode, deployer);
    
    console.log('\n📝 Deploying JobMarketplaceFABWithS5...');
    console.log('  Constructor parameters:');
    console.log('    _nodeRegistry:', NEW_NODE_REGISTRY);
    console.log('    _hostEarnings:', HOST_EARNINGS);
    console.log('  Estimated deployment cost: ~0.01 ETH\n');
    
    const contract = await ContractFactory.deploy(
      NEW_NODE_REGISTRY,
      HOST_EARNINGS,
      {
        gasLimit: 5000000,
        maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
        maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
      }
    );
    
    console.log('Transaction hash:', contract.deployTransaction.hash);
    console.log('Waiting for confirmation...');
    
    await contract.deployed();
    
    console.log('\n✅ Contract deployed successfully!');
    console.log('==========================================');
    console.log('New JobMarketplaceFABWithS5:', contract.address);
    console.log('==========================================\n');
    
    // Verify deployment
    const code = await provider.getCode(contract.address);
    if (code === '0x') {
      console.error('❌ Contract deployment verification failed');
      process.exit(1);
    }
    
    // Initialize the contract
    console.log('📋 Initializing contract...');
    
    // Set treasury
    const TREASURY = '0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11';
    console.log('  Setting treasury:', TREASURY);
    const setTreasuryTx = await contract.setTreasuryAddress(TREASURY, {
      gasLimit: 100000,
      maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
    });
    await setTreasuryTx.wait();
    console.log('  ✅ Treasury set');
    
    // Set USDC as accepted token
    const USDC = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
    console.log('  Setting USDC as accepted token...');
    const setUsdcTx = await contract.setAcceptedToken(
      USDC,
      true,
      800000, // 0.8 USDC minimum
      {
        gasLimit: 100000,
        maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
        maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
      }
    );
    await setUsdcTx.wait();
    console.log('  ✅ USDC configured (min: 0.8 USDC)');
    
    // Set ProofSystem (optional but good to have)
    const PROOF_SYSTEM = '0x2ACcc60893872A499700908889B38C5420CBcFD1';
    console.log('  Setting ProofSystem:', PROOF_SYSTEM);
    const setProofTx = await contract.setProofSystem(PROOF_SYSTEM, {
      gasLimit: 100000,
      maxFeePerGas: ethers.utils.parseUnits('10', 'gwei'),
      maxPriorityFeePerGas: ethers.utils.parseUnits('1', 'gwei')
    });
    await setProofTx.wait();
    console.log('  ✅ ProofSystem set');
    
    // Verify configuration
    console.log('\n📊 Verifying configuration...');
    const nodeRegistry = await contract.nodeRegistry();
    const hostEarnings = await contract.hostEarnings();
    const treasury = await contract.treasuryAddress();
    const usdcAccepted = await contract.acceptedTokens(USDC);
    const usdcMin = await contract.tokenMinDeposits(USDC);
    
    console.log('  NodeRegistry:', nodeRegistry);
    console.log('  HostEarnings:', hostEarnings);
    console.log('  Treasury:', treasury);
    console.log('  USDC Accepted:', usdcAccepted);
    console.log('  USDC Min Deposit:', ethers.utils.formatUnits(usdcMin, 6), 'USDC');
    
    // Verify registry is correct
    if (nodeRegistry.toLowerCase() !== NEW_NODE_REGISTRY.toLowerCase()) {
      console.error('\n❌ Registry mismatch! Something went wrong.');
      process.exit(1);
    }
    
    console.log('\n✅ All configurations verified!');
    
    // Test that hosts are registered in the new registry
    console.log('\n📋 Verifying host registrations...');
    const registryAbi = ['function nodes(address) view returns (address operator, uint256 stakedAmount, bool active, string metadata)'];
    const registry = new ethers.Contract(NEW_NODE_REGISTRY, registryAbi, provider);
    
    const host1 = process.env.TEST_HOST_1_ADDRESS;
    const host1Info = await registry.nodes(host1);
    console.log('  TEST_HOST_1:', host1Info.active ? '✅ Active' : '❌ Not active');
    
    const user2 = process.env.TEST_USER_2_ADDRESS;
    const user2Info = await registry.nodes(user2);
    console.log('  TEST_USER_2:', user2Info.active ? '✅ Active' : '❌ Not active');
    
    // Output update instructions
    console.log('\n==========================================');
    console.log('🎉 DEPLOYMENT SUCCESSFUL!');
    console.log('==========================================\n');
    
    console.log('New JobMarketplaceFABWithS5 Address:');
    console.log('  ', contract.address, '\n');
    
    console.log('📝 Next Steps:');
    console.log('1. Update .env file:');
    console.log(`   JOB_MARKETPLACE_ADDRESS="${contract.address}"`);
    console.log('\n2. Update CONTRACT_ADDRESSES.md with new address');
    console.log('\n3. Update your client app configuration');
    
    return contract.address;
    
  } catch (error) {
    console.error('\n❌ Deployment failed:', error.message);
    if (error.reason) console.error('Reason:', error.reason);
    if (error.data) console.error('Data:', error.data);
    process.exit(1);
  }
}

deployNewMarketplace()
  .then(address => {
    console.log('\n✅ Script completed successfully!');
    console.log('New marketplace:', address);
    process.exit(0);
  })
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });