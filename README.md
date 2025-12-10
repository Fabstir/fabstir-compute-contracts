# Fabstir Compute Contracts

**Decentralized AI Inference Marketplace on Base L2**

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-yellow.svg)](https://mariadb.com/bsl11/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Base Sepolia](https://img.shields.io/badge/Network-Base%20Sepolia-0052FF.svg)](https://sepolia.basescan.org)

**Last Updated**: October 14, 2025

## Overview

Fabstir Compute is a **peer-to-peer AI inference marketplace** that connects GPU hosts with users seeking AI model inference. The system enables trustless, pay-per-token AI conversations with cryptographic proof-of-work validation.

**Key Innovation**: **S5 Off-Chain Proof Storage** (Oct 14, 2025)
- Full STARK proofs (221KB) stored in S5 decentralized storage
- Only hash (32 bytes) + CID (string) submitted on-chain
- **737x transaction size reduction** (221KB → 300 bytes)
- **5000x cost reduction** (~$50 → ~$0.001 per proof)

## Features

🔐 **Trustless AI Inference**
- STARK proof-of-work validation via RISC0
- SHA256 hash commitment prevents proof tampering
- S5 decentralized storage ensures proof availability

💰 **Session-Based Streaming Payments**
- Pay per AI token generated (not per prompt)
- 85-95% reduction in transaction costs vs per-prompt payments
- Automatic refunds for unused deposits

🌐 **Multi-Chain Ready**
- Current: Base Sepolia (Testnet)
- Future: Base Mainnet, opBNB
- Native token agnostic (ETH/BNB)
- Dual pricing (native + stablecoin)

🎯 **Model Governance**
- 2 approved models: TinyVicuna-1B, TinyLlama-1.1B
- Community voting for new models via ModelRegistry

⚡ **Gas Optimized**
- HostEarnings accumulation: ~80% gas savings
- Anyone-can-complete: Gasless UX for renters
- S5 storage: ~$0.001 vs ~$50 for on-chain proofs

## Current Deployment (Base Sepolia)

| Contract | Address | Status |
|----------|---------|--------|
| **JobMarketplaceWithModels** | `0x75C72e8C3eC707D8beF5Ba9b9C4f75CbB5bced97` | ✅ PRICE_PRECISION + 2000 tok/sec (Dec 10, 2025) |
| **NodeRegistryWithModels** | `0x906F4A8Cb944E4fe12Fb85Be7E627CeDAA8B8999` | ✅ PRICE_PRECISION=1000 (Dec 9, 2025) |
| **ModelRegistry** | `0x92b2De840bB2171203011A6dBA928d855cA8183E` | ✅ Active |
| **ProofSystem** | `0x2ACcc60893872A499700908889B38C5420CBcFD1` | ✅ Configured |
| **HostEarnings** | `0x908962e8c6CE72610021586f85ebDE09aAc97776` | ✅ Active |
| **FAB Token** | `0xC78949004B4EB6dEf2D66e49Cd81231472612D62` | Testnet |
| **USDC** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Testnet |

See [client-abis/README.md](client-abis/README.md) for full integration details.

## Quick Start

### For Renters (Use AI Inference)

```javascript
import { ethers } from 'ethers';

// 1. Query host pricing (REQUIRED before creating session)
const [nativeMin, stableMin] = await nodeRegistry.getNodePricing(hostAddress);

// 2. Create session with ETH
const marketplace = new ethers.Contract(
  '0x75C72e8C3eC707D8beF5Ba9b9C4f75CbB5bced97',
  JobMarketplaceABI,
  signer
);

const tx = await marketplace.createSessionJob(
  hostAddress,
  pricePerToken,    // Must be >= nativeMin
  3600,             // 1 hour max duration
  100,              // Proof every 100 tokens
  { value: ethers.utils.parseEther("0.1") }
);

console.log('Session created! Start your AI conversation.');
```

### For Hosts (Provide GPU Inference)

```javascript
import crypto from 'crypto';
import { S5Client } from '@lumeweb/s5-js';

const s5 = new S5Client('https://s5.lumeweb.com');

// 1. Register node with dual pricing
await fabToken.approve(nodeRegistry.address, ethers.utils.parseEther("1000"));
await nodeRegistry.registerNode(
  metadata,
  apiUrl,
  supportedModels,
  minPriceNative,   // e.g., 3000000000 wei
  minPriceStable    // e.g., 15000 (0.000015 USDC)
);

// 2. Process inference and generate proof
const proof = await generateRisc0Proof(jobData);

// 3. Upload to S5
const proofCID = await s5.uploadBlob(proof);

// 4. Calculate hash
const proofHash = '0x' + crypto.createHash('sha256').update(proof).digest('hex');

// 5. Submit hash + CID (NOT full proof)
await marketplace.submitProofOfWork(jobId, tokensClaimed, proofHash, proofCID);

// 6. Complete session to claim payment
await marketplace.completeSessionJob(jobId, conversationCID);
```

## Documentation

### 📚 Technical Documentation
- [Technical README](docs/technical/README.md) - Comprehensive technical reference
- [Architecture](docs/ARCHITECTURE.md) - System architecture and S5 proof storage
- [Contract Addresses](CONTRACT_ADDRESSES.md) - All deployed contracts

### 📖 Contract Documentation
- [JobMarketplace](docs/technical/contracts/JobMarketplace.md) - Session jobs with S5 storage
- [NodeRegistry](docs/technical/contracts/NodeRegistry.md) - Host registration and dual pricing
- [ProofSystem](docs/technical/contracts/ProofSystem.md) - S5 proof verification

### 🚀 Deployment Guides
- [S5 Proof Storage Deployment](docs/S5_PROOF_STORAGE_DEPLOYMENT.md) - S5 deployment guide
- [Contract Deployment Checklist](docs/CONTRACT_DEPLOYMENT_CHECKLIST.md) - Complete deployment steps

### 📝 Implementation Guides
- [Session Jobs](docs/SESSION_JOBS.md) - Session-based streaming payments
- [Multi-Chain Deployment](docs/MULTI_CHAIN_DEPLOYMENT.md) - Multi-chain support

## Development

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (for integration tests)

### Installation

```bash
# Clone repository
git clone https://github.com/fabstir/fabstir-compute-contracts
cd fabstir-compute-contracts

# Install dependencies
forge install

# Build contracts
forge build
```

### Testing

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vv

# Run specific test file
forge test --match-path test/JobMarketplace/test_session_jobs.t.sol

# Generate gas snapshots
forge snapshot
```

### Deployment

See [Contract Deployment Checklist](docs/CONTRACT_DEPLOYMENT_CHECKLIST.md) for complete deployment procedures.

```bash
# Deploy to Base Sepolia
forge create src/JobMarketplaceWithModels.sol:JobMarketplaceWithModels \
  --broadcast \
  --private-key $PRIVATE_KEY \
  --rpc-url "https://sepolia.base.org" \
  --constructor-args <NODE_REGISTRY> <HOST_EARNINGS> <FEE_BPS> <DISPUTE_WINDOW> \
  --legacy
```

### Key Commands

```bash
# Format code
forge fmt

# Check contract size
forge build --sizes

# Verify on BaseScan
forge verify-contract <ADDRESS> <CONTRACT> \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY

# Query contract (example)
cast call 0x75C72e8C3eC707D8beF5Ba9b9C4f75CbB5bced97 \
  "nextJobId()" \
  --rpc-url "https://sepolia.base.org"
```

## Architecture

```
┌──────────────────────────┐
│   ModelRegistry          │  ← AI model governance (2 approved models)
└───────────┬──────────────┘
            │
            ▼
┌──────────────────────────┐
│ NodeRegistryWithModels   │  ← Host registration + dual pricing
└───────────┬──────────────┘
            │
            ▼
┌──────────────────────────┐
│ JobMarketplaceWithModels │  ← Session jobs with S5 proof storage
└───────┬──────────────────┘
        │
        ├─────────►┌──────────────┐
        │          │ HostEarnings │  ← 90% host payment
        │          └──────────────┘
        │
        ├─────────►┌──────────────┐
        │          │ ProofSystem  │  ← Dispute resolution
        │          └──────────────┘
        │
        └─────────►┌──────────────┐
                   │ S5 Storage   │  ← Off-chain proofs (221KB)
                   └──────────────┘
```

## Breaking Changes (October 14, 2025)

### S5 Off-Chain Proof Storage

**Old Contract**: `0xe169A4B57700080725f9553E3Cc69885fea13629`
```solidity
function submitProofOfWork(
    uint256 jobId,
    bytes calldata ekzlProof,  // ❌ 221KB - exceeds RPC limit
    uint256 tokensInBatch
) external
```

**New Contract**: `0x75C72e8C3eC707D8beF5Ba9b9C4f75CbB5bced97`
```solidity
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes32 proofHash,         // ✅ 32 bytes - SHA256 hash
    string calldata proofCID   // ✅ S5 CID for retrieval
) external
```

**Migration Required**:
- Node operators must integrate S5 client
- Upload proofs to S5 before blockchain submission
- Calculate SHA256 hash and submit with CID

See [S5_PROOF_STORAGE_DEPLOYMENT.md](docs/S5_PROOF_STORAGE_DEPLOYMENT.md) for migration guide.

## Security

### Audits
- [ ] External audit pending

### Security Features
- ReentrancyGuard on all payment functions
- SHA256 hash verification for proof integrity
- S5 decentralized storage for proof availability
- Dual pricing validation (prevents under-payment)
- Access control for treasury functions

### Bug Bounty
- Coming soon

## License & Usage

This project is source-available under the **Business Source License 1.1** (BUSL-1.1).

### You MAY:
- ✅ View, audit, and review the code (trustless verification)
- ✅ Use in production on the Official Platformless AI Network with FAB token
- ✅ Run nodes on the Official Platformless AI Network
- ✅ Fork for development, testing, research, and security audits

### You MAY NOT (before 2029-01-01):
- ❌ Launch competing networks with different staking tokens
- ❌ Operate nodes on competing networks
- ❌ Offer as commercial hosting service (SaaS/PaaS)

**After 2029-01-01**: Automatically converts to AGPL-3.0-or-later.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and [NETWORKS.md](NETWORKS.md) for complete details.

## Network Information

- **Network**: Base Sepolia (Testnet)
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org
- **Faucet**: https://www.coinbase.com/faucets/base-ethereum-goerli-faucet

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/fabstir/fabstir-compute-contracts/issues)
- **Discord**: Coming soon

## Roadmap

- [x] Session-based streaming payments (Jan 2025)
- [x] Dual pricing (native + stable) (Jan 2025)
- [x] S5 off-chain proof storage (Oct 2025)
- [ ] Base Mainnet deployment
- [ ] opBNB testnet deployment
- [ ] Additional approved models
- [ ] External audit
- [ ] Multi-chain support (opBNB Mainnet)

---

**Built with Foundry** | **Deployed on Base L2** | **Powered by S5 Storage**
