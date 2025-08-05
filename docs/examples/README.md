# Fabstir Examples

This directory contains practical, working examples demonstrating how to use the Fabstir P2P LLM marketplace contracts and APIs. All examples are designed to be copy-paste ready with clear documentation.

## 📁 Directory Structure

```
examples/
├── basic/              # Simple, single-operation examples
├── intermediate/       # Multi-step workflows and integrations
├── advanced/           # Complex automation and monitoring
└── full-applications/  # Complete application examples
```

## 🚀 Getting Started

### Prerequisites

Before running any examples, ensure you have:

1. **Node.js** (v18 or higher)
2. **npm** or **yarn**
3. **A wallet** with ETH on Base (or Base Sepolia for testing)
4. **Environment variables** configured (see below)

### Installation

```bash
# Clone the repository
git clone https://github.com/fabstir/fabstir-compute-contracts
cd fabstir-compute-contracts/docs/examples

# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Edit .env with your values
```

### Environment Setup

Create a `.env` file with:

```bash
# Network Configuration
RPC_URL=https://base-mainnet.g.alchemy.com/v2/YOUR_KEY
CHAIN_ID=8453

# For testing use Base Sepolia
# RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_KEY
# CHAIN_ID=84532

# Your Wallet
PRIVATE_KEY=0xYOUR_PRIVATE_KEY

# Contract Addresses (Base Mainnet)
NODE_REGISTRY=0x...
JOB_MARKETPLACE=0x...
PAYMENT_ESCROW=0x...
REPUTATION_SYSTEM=0x...
PROOF_SYSTEM=0x...
BASE_ACCOUNT_INTEGRATION=0x...
GOVERNANCE=0x...
GOVERNANCE_TOKEN=0x...

# Optional: For full applications
API_KEY=your-api-key
WEBHOOK_URL=https://your-webhook-url
```

## 📚 Example Categories

### Basic Examples
Perfect for getting started with individual operations:
- **register-node.js** - Register as a compute node provider
- **post-job.js** - Post an AI inference job
- **claim-job.js** - Claim and start working on a job
- **complete-job.js** - Complete a job and receive payment

### Intermediate Examples
Learn how to build more complex workflows:
- **batch-operations.js** - Execute multiple operations efficiently
- **reputation-tracking.js** - Monitor and improve node reputation
- **escrow-management.js** - Handle payments and refunds
- **proof-verification.js** - Submit and verify computation proofs

### Advanced Examples
Sophisticated automation and monitoring:
- **automated-node-operator.js** - Fully automated node operation
- **job-aggregator.js** - Aggregate and route jobs efficiently
- **governance-bot.js** - Automated governance participation
- **monitoring-dashboard.js** - Real-time monitoring system

### Full Applications
Complete, production-ready applications:
- **ai-chatbot/** - AI chatbot using Fabstir for inference
- **marketplace-ui/** - Web interface for the marketplace
- **api-gateway/** - REST API gateway for easy integration

## 🛠️ Running Examples

### Basic Example
```bash
# Navigate to basic examples
cd basic

# Run an example
node register-node.js

# Or with npm scripts
npm run example:register-node
```

### With Custom Parameters
```bash
# Many examples accept command-line arguments
node post-job.js --model gpt-4 --tokens 1000 --payment 0.1
```

### Testing Mode
```bash
# Run in test mode (uses Base Sepolia)
NODE_ENV=test node register-node.js
```

## 📖 Example Structure

Each example follows this structure:

```javascript
/**
 * Example: [Name]
 * Purpose: [What this example demonstrates]
 * Prerequisites: [What you need before running]
 */

// 1. Imports and Configuration
const { ethers } = require('ethers');
require('dotenv').config();

// 2. Contract ABIs and Addresses
const contracts = require('../contracts');

// 3. Main Function with Error Handling
async function main() {
    try {
        // Setup
        const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        // Execute operation
        console.log('Starting operation...');
        
        // ... implementation ...
        
        console.log('✅ Success!');
        
    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// 4. Execute if run directly
if (require.main === module) {
    main();
}

// 5. Export for use in other modules
module.exports = { main };
```

## 🔧 Common Modifications

### Changing Network
```javascript
// Mainnet
const RPC_URL = 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY';

// Testnet
const RPC_URL = 'https://base-sepolia.g.alchemy.com/v2/YOUR_KEY';
```

### Using Different Models
```javascript
const MODEL_IDS = {
    'gpt-4': '0x1234...',
    'claude-2': '0x5678...',
    'llama-2-70b': '0x9abc...'
};
```

### Adjusting Gas Settings
```javascript
const tx = await contract.method({
    gasLimit: 500000,
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
});
```

## 🐛 Troubleshooting

### Common Issues

1. **"Insufficient funds"**
   - Ensure your wallet has enough ETH for gas
   - Check you're on the correct network

2. **"Contract not found"**
   - Verify contract addresses in .env
   - Ensure you're connected to the right network

3. **"Transaction reverted"**
   - Check contract requirements (min stake, etc.)
   - Verify function parameters

4. **"Network timeout"**
   - Try a different RPC endpoint
   - Increase timeout in provider settings

### Debug Mode

Run with debug logging:
```bash
DEBUG=* node register-node.js
```

## 📝 Contributing

We welcome contributions! To add a new example:

1. Follow the existing structure
2. Include comprehensive comments
3. Add error handling
4. Test on both mainnet and testnet
5. Update this README

## 📚 Additional Resources

- [API Documentation](../api/)
- [Integration Guides](../guides/)
- [Best Practices](../best-practices/)
- [Contract Documentation](../../src/)

## 🆘 Getting Help

- **Discord**: [Join our community](https://discord.gg/fabstir)
- **GitHub Issues**: [Report bugs](https://github.com/fabstir/fabstir-compute-contracts/issues)
- **Documentation**: [Full docs](https://docs.fabstir.com)

---

Happy building! 🚀