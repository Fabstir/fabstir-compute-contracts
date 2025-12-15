# Fabstir Compute Contracts

**Decentralized AI Inference Marketplace on Base L2**

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-yellow.svg)](https://mariadb.com/bsl11/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Base Sepolia](https://img.shields.io/badge/Network-Base%20Sepolia-0052FF.svg)](https://sepolia.basescan.org)

**Last Updated**: December 14, 2025

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

🔄 **Upgradeable (UUPS)**
- All contracts use UUPS proxy pattern
- Future upgrades without data migration
- Owner-controlled upgrade authorization

## Current Deployment (Base Sepolia)

> **All contracts use UUPS Upgradeable pattern** (December 14, 2025)
> Minimum deposits reduced to ~$0.50 (ETH: 0.0001, USDC: 500000)

| Contract | Proxy Address | Status |
|----------|---------------|--------|
| **JobMarketplace** | `0xeebEEbc9BCD35e81B06885b63f980FeC71d56e2D` | ✅ UUPS + updateTokenMinDeposit |
| **NodeRegistry** | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | ✅ UUPS + PRICE_PRECISION=1000 |
| **ModelRegistry** | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | ✅ UUPS |
| **ProofSystem** | `0x5afB91977e69Cc5003288849059bc62d47E7deeb` | ✅ UUPS |
| **HostEarnings** | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | ✅ UUPS |
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
  '0xeebEEbc9BCD35e81B06885b63f980FeC71d56e2D',  // UUPS Proxy
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

### 📚 Core Documentation
- [Client ABIs & Integration](client-abis/README.md) - Contract ABIs and SDK integration guide
- [API Reference](docs/API_REFERENCE.md) - Complete API documentation
- [Breaking Changes](docs/BREAKING_CHANGES.md) - Migration guide for SDK developers

### 🚀 Deployment
- [Contract Deployment Checklist](docs/CONTRACT_DEPLOYMENT_CHECKLIST.md) - Complete deployment steps

### 📖 Additional Resources
- [Best Practices](docs/best-practices/) - Security, performance, and operations
- [Examples](docs/examples/) - Code examples (basic to advanced)
- [Guides](docs/guides/) - Developer and operator guides

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
cast call 0xeebEEbc9BCD35e81B06885b63f980FeC71d56e2D \
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

## Breaking Changes

### December 14, 2025: UUPS Upgradeable Migration

All contracts migrated to UUPS pattern with new proxy addresses:
- Minimum deposits reduced to ~$0.50
- New admin function: `updateTokenMinDeposit(address, uint256)`
- Emergency pause functionality added to JobMarketplace

See [Migration Guide for Node Developers](docs/MIGRATION-NODE-DEVELOPER.md) and [SDK Developers](docs/MIGRATION-SDK-DEVELOPER.md).

### October 14, 2025: S5 Off-Chain Proof Storage

**Old Contract**: `0xe169A4B57700080725f9553E3Cc69885fea13629`
```solidity
function submitProofOfWork(
    uint256 jobId,
    bytes calldata ekzlProof,  // ❌ 221KB - exceeds RPC limit
    uint256 tokensInBatch
) external
```

**New Contract**: `0xeebEEbc9BCD35e81B06885b63f980FeC71d56e2D` (UUPS Proxy)
```solidity
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes32 proofHash,         // ✅ 32 bytes - SHA256 hash
    string calldata proofCID   // ✅ S5 CID for retrieval
) external
```

See [Breaking Changes](docs/BREAKING_CHANGES.md) for full migration guide.

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
- [x] UUPS upgradeable contracts (Dec 2025)
- [ ] Base Mainnet deployment
- [ ] opBNB testnet deployment
- [ ] Additional approved models
- [ ] External audit
- [ ] Multi-chain support (opBNB Mainnet)

---

**Built with Foundry** | **Deployed on Base L2** | **Powered by S5 Storage**
