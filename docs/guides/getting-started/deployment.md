# Contract Deployment Guide

This guide walks you through deploying the Fabstir compute contracts to Base Sepolia testnet and mainnet.

## Prerequisites

- Completed [Environment Setup](setup.md)
- Base Sepolia ETH (at least 0.5 ETH for deployment)
- Private key configured in `.env`
- Foundry installed and configured

## Deployment Overview

The deployment process involves:
1. Deploying core contracts in the correct order
2. Configuring contract connections
3. Setting up initial parameters
4. Verifying contracts on Basescan

### Contract Deployment Order
```
1. GovernanceToken
2. NodeRegistry
3. JobMarketplace
4. PaymentEscrow
5. ReputationSystem
6. ProofSystem
7. Governance
8. BaseAccountIntegration
```

## Step 1: Prepare Deployment Script

### Check Deployment Script
Review `script/Deploy.s.sol`:

```solidity
// script/Deploy.s.sol
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/NodeRegistry.sol";
import "../src/JobMarketplace.sol";
// ... other imports

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contracts
        GovernanceToken token = new GovernanceToken(
            "Fabstir Governance",
            "FAB",
            1_000_000 ether
        );
        
        NodeRegistry registry = new NodeRegistry(100 ether);
        // ... continue deployment
        
        vm.stopBroadcast();
    }
}
```

### Configure Deployment Parameters
Create `script/DeployConfig.sol`:

```solidity
// script/DeployConfig.sol
pragma solidity ^0.8.19;

contract DeployConfig {
    // Network-specific configurations
    struct NetworkConfig {
        uint256 minStake;
        uint256 feeBasisPoints;
        address arbiter;
        address paymaster;
        address entryPoint;
    }
    
    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            minStake: 0.1 ether,  // Lower for testnet
            feeBasisPoints: 250,   // 2.5%
            arbiter: 0x...,        // Testnet arbiter
            paymaster: 0x...,      // Base testnet paymaster
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
        });
    }
    
    function getBaseMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            minStake: 100 ether,   // Production stake
            feeBasisPoints: 250,   // 2.5%
            arbiter: 0x...,        // Mainnet arbiter
            paymaster: 0x...,      // Base mainnet paymaster
            entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789
        });
    }
}
```

## Step 2: Deploy to Base Sepolia

### Run Deployment
```bash
# Load environment variables
source .env

# Deploy to Base Sepolia
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv
```

### Expected Output
```
[⠊] Compiling...
[⠒] Compiling 45 files with 0.8.19
[⠢] Solc 0.8.19 finished in 3.45s
Script ran successfully.

== Logs ==
Deploying GovernanceToken...
GovernanceToken deployed at: 0x1234...
Deploying NodeRegistry...
NodeRegistry deployed at: 0x5678...
...

Gas used: 15,234,567
Transaction hash: 0xabcd...
```

### Save Deployed Addresses
Update your `.env` file:
```bash
# Contract Addresses (Base Sepolia)
NODE_REGISTRY_ADDRESS="0x5678..."
JOB_MARKETPLACE_ADDRESS="0x9abc..."
PAYMENT_ESCROW_ADDRESS="0xdef0..."
REPUTATION_SYSTEM_ADDRESS="0x1234..."
PROOF_SYSTEM_ADDRESS="0x5678..."
GOVERNANCE_ADDRESS="0x9abc..."
GOVERNANCE_TOKEN_ADDRESS="0xdef0..."
BASE_ACCOUNT_INTEGRATION_ADDRESS="0x1111..."
```

## Step 3: Configure Contracts

After deployment, contracts need to be connected:

### Configure Contract Connections
Create `script/Configure.s.sol`:

```solidity
// script/Configure.s.sol
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/interfaces/IJobMarketplace.sol";
// ... other imports

contract ConfigureScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address nodeRegistry = vm.envAddress("NODE_REGISTRY_ADDRESS");
        address jobMarketplace = vm.envAddress("JOB_MARKETPLACE_ADDRESS");
        // ... load other addresses
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Set ReputationSystem in JobMarketplace
        JobMarketplace(jobMarketplace).setReputationSystem(reputationSystem);
        
        // 2. Set JobMarketplace in PaymentEscrow
        PaymentEscrow(paymentEscrow).setJobMarketplace(jobMarketplace);
        
        // 3. Add authorized contracts to ReputationSystem
        ReputationSystem(reputationSystem).addAuthorizedContract(jobMarketplace);
        
        // 4. Set governance in contracts
        NodeRegistry(nodeRegistry).setGovernance(governance);
        
        // 5. Grant roles
        ProofSystem(proofSystem).grantRole(VERIFIER_ROLE, verifierAddress);
        
        vm.stopBroadcast();
    }
}
```

### Run Configuration
```bash
forge script script/Configure.s.sol:ConfigureScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --broadcast \
    -vvvv
```

## Step 4: Verify Contracts

### Automatic Verification
If verification failed during deployment, manually verify:

```bash
# Verify NodeRegistry
forge verify-contract \
    --chain-id 84532 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(uint256)" 100000000000000000000) \
    --etherscan-api-key $BASESCAN_API_KEY \
    --compiler-version v0.8.19+commit.7dd6d404 \
    $NODE_REGISTRY_ADDRESS \
    src/NodeRegistry.sol:NodeRegistry

# Verify JobMarketplace
forge verify-contract \
    --chain-id 84532 \
    --num-of-optimizations 200 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address)" $NODE_REGISTRY_ADDRESS) \
    --etherscan-api-key $BASESCAN_API_KEY \
    --compiler-version v0.8.19+commit.7dd6d404 \
    $JOB_MARKETPLACE_ADDRESS \
    src/JobMarketplace.sol:JobMarketplace
```

## Step 5: Post-Deployment Testing

### Test Contract Connections
Create `test/integration/PostDeploy.t.sol`:

```solidity
// test/integration/PostDeploy.t.sol
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/NodeRegistry.sol";
// ... other imports

contract PostDeployTest is Test {
    function testDeployedContracts() public {
        // Load deployed addresses
        address nodeRegistry = vm.envAddress("NODE_REGISTRY_ADDRESS");
        address jobMarketplace = vm.envAddress("JOB_MARKETPLACE_ADDRESS");
        
        // Test NodeRegistry
        NodeRegistry registry = NodeRegistry(nodeRegistry);
        assertEq(registry.requiredStake(), 100 ether);
        
        // Test JobMarketplace
        JobMarketplace marketplace = JobMarketplace(jobMarketplace);
        assertEq(address(marketplace.nodeRegistry()), nodeRegistry);
        
        // Test connections
        assertTrue(marketplace.reputationSystem() != address(0));
        
        console.log("All post-deployment tests passed!");
    }
}
```

### Run Tests
```bash
forge test --match-contract PostDeployTest --fork-url $BASE_SEPOLIA_RPC_URL -vvv
```

## Step 6: Initial Setup

### Fund Contracts (if needed)
```bash
# Send ETH to contracts that need it
cast send $PAYMENT_ESCROW_ADDRESS --value 0.1ether --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Set Initial Parameters
```bash
# Set circuit breaker threshold
cast send $JOB_MARKETPLACE_ADDRESS "setFailureThreshold(uint256)" 10 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Grant emergency role
cast send $GOVERNANCE_ADDRESS "grantRole(bytes32,address)" \
    0x[EMERGENCY_ROLE_HASH] 0x[EMERGENCY_MULTISIG] \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

## Mainnet Deployment

### Pre-Mainnet Checklist
- [ ] All contracts tested on testnet
- [ ] Security audit completed
- [ ] Deployment script reviewed
- [ ] Gas prices checked
- [ ] Multisig wallets ready
- [ ] Emergency procedures documented

### Deploy to Base Mainnet
```bash
# Use mainnet RPC and higher gas settings
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $BASE_MAINNET_RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    --gas-price 2gwei \
    --priority-gas-price 2gwei \
    -vvvv
```

## Common Issues & Solutions

### Issue: "Insufficient funds"
**Solution**: Check balance and gas prices:
```bash
# Check balance
cast balance $DEPLOYER_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL

# Check gas price
cast gas-price --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Issue: "Contract verification failed"
**Solution**: Manually verify with correct parameters:
```bash
# Get constructor arguments
cast abi-encode "constructor(uint256)" 100000000000000000000

# Flatten contract if needed
forge flatten src/NodeRegistry.sol > NodeRegistryFlat.sol
```

### Issue: "Transaction reverted"
**Solution**: Simulate transaction first:
```bash
# Simulate deployment
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    -vvvv
# Don't include --broadcast to simulate only
```

## Best Practices

### 1. Use Different Accounts
```bash
# Deployer account (only for deployment)
DEPLOYER_KEY="0x..."

# Admin account (for configuration)
ADMIN_KEY="0x..."

# Operator account (for daily operations)
OPERATOR_KEY="0x..."
```

### 2. Verify Everything
After deployment:
- Check all contract addresses
- Verify on Basescan
- Test all connections
- Confirm parameters

### 3. Document Deployment
Create `deployments/base-sepolia.json`:
```json
{
  "network": "base-sepolia",
  "chainId": 84532,
  "deploymentDate": "2024-01-20",
  "deployer": "0x...",
  "contracts": {
    "NodeRegistry": {
      "address": "0x...",
      "blockNumber": 12345678,
      "transactionHash": "0x..."
    },
    // ... other contracts
  }
}
```

### 4. Monitor After Deployment
```bash
# Watch for events
cast logs --from-block [DEPLOYMENT_BLOCK] \
    --address $JOB_MARKETPLACE_ADDRESS \
    --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Cost Estimation

### Testnet Deployment
- Total gas: ~15-20M gas
- Cost: ~0.01-0.02 ETH (Base Sepolia)

### Mainnet Deployment
- Total gas: ~15-20M gas
- Cost at 2 gwei: ~0.03-0.04 ETH
- Add 50% buffer for safety

## Next Steps

After successful deployment:

1. **[Create Your First Job](first-job.md)** - Test the deployed contracts
2. **[Run a Node](../node-operators/running-a-node.md)** - Become a compute provider
3. **[Monitor Your Deployment](../advanced/monitoring-setup.md)** - Set up monitoring

## Resources

- [Base Sepolia Explorer](https://sepolia.basescan.org)
- [Base Mainnet Explorer](https://basescan.org)
- [Foundry Deploy Documentation](https://book.getfoundry.sh/tutorials/solidity-scripting)
- [Base Documentation](https://docs.base.org/guides/deploy-smart-contracts)

---

Ready to use your deployed contracts? Continue to [Creating Your First Job](first-job.md) →