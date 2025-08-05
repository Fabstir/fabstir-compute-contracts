# Environment Setup Guide

This guide walks you through setting up your development environment for working with Fabstir compute contracts.

## Prerequisites

- **Operating System**: Linux, macOS, or Windows with WSL2
- **Node.js**: v18.0.0 or higher
- **Git**: For cloning repositories
- **Hardware**: 8GB RAM minimum, 16GB recommended

## Step 1: Install Foundry

Foundry is the smart contract development toolkit we use.

### Linux/macOS/WSL2
```bash
# Install foundryup
curl -L https://foundry.paradigm.xyz | bash

# Follow the instructions to add foundry to your PATH
source ~/.bashrc  # or ~/.zshrc

# Install Foundry
foundryup
```

### Verify Installation
```bash
forge --version
# Expected output: forge 0.2.0 (or higher)

cast --version
# Expected output: cast 0.2.0 (or higher)

anvil --version
# Expected output: anvil 0.2.0 (or higher)
```

## Step 2: Clone the Repository

```bash
# Clone the contracts repository
git clone https://github.com/fabstir/fabstir-compute-contracts.git
cd fabstir-compute-contracts

# Install dependencies
forge install
```

## Step 3: Set Up Environment Variables

Create a `.env` file in the project root:

```bash
# .env
# Base Sepolia (Testnet)
BASE_SEPOLIA_RPC_URL="https://sepolia.base.org"
BASE_SEPOLIA_EXPLORER="https://sepolia.basescan.org"

# Base Mainnet (Production)
BASE_MAINNET_RPC_URL="https://mainnet.base.org"
BASE_MAINNET_EXPLORER="https://basescan.org"

# Private Keys (NEVER commit these!)
PRIVATE_KEY="your-private-key-here"
DEPLOYER_ADDRESS="your-address-here"

# Contract Addresses (will be filled after deployment)
NODE_REGISTRY_ADDRESS=""
JOB_MARKETPLACE_ADDRESS=""
PAYMENT_ESCROW_ADDRESS=""
REPUTATION_SYSTEM_ADDRESS=""
PROOF_SYSTEM_ADDRESS=""
GOVERNANCE_ADDRESS=""
GOVERNANCE_TOKEN_ADDRESS=""

# IPFS Configuration
IPFS_GATEWAY="https://ipfs.io/ipfs/"
IPFS_API_URL="http://localhost:5001"

# Etherscan API (for verification)
BASESCAN_API_KEY="your-basescan-api-key"
```

### Security Note
⚠️ **NEVER commit your `.env` file or expose private keys!**

Add to `.gitignore`:
```bash
echo ".env" >> .gitignore
```

## Step 4: Get Testnet ETH

You'll need Base Sepolia ETH for testing.

### Option 1: Base Faucet
1. Visit [Base Sepolia Faucet](https://www.coinbase.com/faucets/base-ethereum-goerli-faucet)
2. Connect your wallet
3. Request test ETH

### Option 2: Bridge from Sepolia
1. Get Sepolia ETH from [Sepolia Faucet](https://sepoliafaucet.com)
2. Bridge to Base Sepolia using [Base Bridge](https://bridge.base.org)

### Verify Balance
```bash
# Check your balance
cast balance $DEPLOYER_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Step 5: Install Additional Tools

### IPFS (for decentralized storage)
```bash
# Download IPFS
wget https://dist.ipfs.io/go-ipfs/v0.18.0/go-ipfs_v0.18.0_linux-amd64.tar.gz
tar -xvzf go-ipfs_v0.18.0_linux-amd64.tar.gz
cd go-ipfs
sudo bash install.sh

# Initialize IPFS
ipfs init

# Start IPFS daemon
ipfs daemon &
```

### Node.js Dependencies (for scripts)
```bash
# Initialize package.json if not exists
npm init -y

# Install useful packages
npm install ethers dotenv @base/sdk
```

## Step 6: Test Your Setup

### Run Contract Tests
```bash
# Run all tests
forge test

# Run with verbosity for more details
forge test -vvv

# Run specific test
forge test --match-test test_NodeRegistration
```

### Start Local Blockchain
```bash
# Start Anvil (local Ethereum node)
anvil --fork-url $BASE_SEPOLIA_RPC_URL

# In another terminal, deploy contracts locally
forge script script/Deploy.s.sol:DeployScript --rpc-url http://localhost:8545 --broadcast
```

## Step 7: Configure Your Editor

### VS Code Setup
Install recommended extensions:
```bash
code --install-extension JuanBlanco.solidity
code --install-extension tintinweb.solidity-visual-auditor
code --install-extension streetsidesoftware.code-spell-checker
```

### VS Code Settings
Create `.vscode/settings.json`:
```json
{
  "solidity.defaultCompiler": "remote",
  "solidity.compileUsingRemoteVersion": "v0.8.19+commit.7dd6d404",
  "solidity.packageDefaultDependenciesContractsDirectory": "src",
  "solidity.packageDefaultDependenciesDirectory": "lib",
  "editor.formatOnSave": true,
  "files.associations": {
    "*.sol": "solidity"
  }
}
```

## Common Issues & Solutions

### Issue: Foundry installation fails
**Solution**: Make sure you have `curl` and `git` installed:
```bash
sudo apt update && sudo apt install curl git  # Ubuntu/Debian
brew install curl git  # macOS
```

### Issue: "Cannot find module" errors
**Solution**: Install Node.js dependencies:
```bash
npm install
```

### Issue: Gas estimation failed
**Solution**: Ensure you have enough testnet ETH and correct RPC URL:
```bash
# Test RPC connection
cast client --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Issue: IPFS connection failed
**Solution**: Make sure IPFS daemon is running:
```bash
ipfs daemon &
# Check if running
ipfs swarm peers
```

## Best Practices

### 1. Use Hardware Wallet for Mainnet
For production, use a hardware wallet:
```bash
# Example with Ledger
cast send --ledger --from 0x... CONTRACT_ADDRESS "function()" 
```

### 2. Keep Dependencies Updated
```bash
# Update Foundry
foundryup

# Update npm packages
npm update
```

### 3. Use Multiple Accounts
Create separate accounts for different roles:
```bash
# Generate new account
cast wallet new

# Save addresses for different roles
DEPLOYER_ADDRESS="0x..."
NODE_OPERATOR_ADDRESS="0x..."
JOB_CREATOR_ADDRESS="0x..."
```

### 4. Monitor Gas Prices
```bash
# Check current gas price
cast gas-price --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Next Steps

Now that your environment is set up:

1. **[Deploy Contracts](deployment.md)** - Deploy to Base Sepolia
2. **[Create Your First Job](first-job.md)** - Post and complete a job
3. **[Run a Node](../node-operators/running-a-node.md)** - Become a compute provider

## Useful Commands Reference

```bash
# Compile contracts
forge build

# Run tests
forge test

# Deploy contracts
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast

# Verify contract
forge verify-contract CONTRACT_ADDRESS ContractName --chain-id 84532

# Check gas usage
forge test --gas-report

# Format code
forge fmt
```

## Resources

- [Foundry Book](https://book.getfoundry.sh/)
- [Base Documentation](https://docs.base.org/)
- [Solidity Documentation](https://docs.soliditylang.org/)
- [IPFS Documentation](https://docs.ipfs.io/)

---

Ready to deploy? Continue to the [Deployment Guide](deployment.md) →