# Fabstir Compute Contracts

**Decentralized AI Inference Marketplace on Base L2**

[![License: BUSL-1.1](https://img.shields.io/badge/License-BUSL--1.1-yellow.svg)](https://mariadb.com/bsl11/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg)](https://getfoundry.sh/)
[![Base Sepolia](https://img.shields.io/badge/Network-Base%20Sepolia-0052FF.svg)](https://sepolia.basescan.org)

**Last Updated**: February 24, 2026

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
- 5 approved models: TinyVicuna-1B, TinyLlama-1.1B, GPT-OSS-20B, GPT-OSS-120B, GLM-4.7-Flash
- Community voting for new models via ModelRegistry

⚡ **Gas Optimized**
- HostEarnings accumulation: ~80% gas savings
- Anyone-can-complete: Gasless UX for renters
- S5 storage: ~$0.001 vs ~$50 for on-chain proofs
- Per-token pricing validation (F202614977)

🔄 **Upgradeable (UUPS)**
- All contracts use UUPS proxy pattern
- Future upgrades without data migration
- Owner-controlled upgrade authorization

🔒 **Security Audited** - 20 findings addressed in Feb 2026 audit remediation

## Current Deployment (Base Sepolia)

> **POST-AUDIT REMEDIATION** (Feb 22-24, 2026) — All 20 audit findings addressed. See [CHANGELOG](client-abis/CHANGELOG.md).

| Contract | Proxy Address | Status |
|----------|---------------|--------|
| **JobMarketplace** | `0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4` | ✅ FRESH PROXY — All 20 audit findings (Feb 22) |
| **NodeRegistry** | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | ✅ Per-token pricing fix (Feb 24) |
| **ModelRegistry** | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | ✅ Per-model rate limits (Feb 22) |
| **ProofSystem** | `0xE8DCa89e1588bbbdc4F7D5F78263632B35401B31` | ✅ markProofUsed (Feb 22) |
| **HostEarnings** | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | ✅ UUPS |
| **FAB Token** | `0xC78949004B4EB6dEf2D66e49Cd81231472612D62` | Testnet |
| **USDC** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Testnet |

See [client-abis/README.md](client-abis/README.md) for full integration details.

## Quick Start

### For Renters (Use AI Inference)

```javascript
import { ethers } from 'ethers';

// 1. Query host pricing (REQUIRED before creating session)
const hostPrice = await nodeRegistry.getNodePricing(hostAddress, ethers.ZeroAddress);

// 2. Create session with ETH
const marketplace = new ethers.Contract(
  '0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4',  // UUPS Proxy
  JobMarketplaceABI,
  signer
);

const tx = await marketplace.createSessionJob(
  hostAddress,
  pricePerToken,    // Must be >= hostPrice
  3600,             // 1 hour max duration
  100,              // Proof every 100 tokens
  300,              // 5 min proof timeout window
  { value: ethers.parseEther("0.1") }
);

console.log('Session created! Start your AI conversation.');
```

### For Hosts (Provide GPU Inference)

```javascript
import crypto from 'crypto';
import { S5Client } from '@lumeweb/s5-js';

const s5 = new S5Client('https://s5.lumeweb.com');

// 1. Register node with dual pricing
await fabToken.approve(nodeRegistry.address, ethers.parseEther("1000"));
await nodeRegistry.registerNode(
  metadata,
  apiUrl,
  supportedModels,
  minPriceNative,   // e.g., 3000000000 wei
  minPriceStable    // e.g., 15000 (0.000015 USDC)
);

// 2. Set per-token pricing for USDC (REQUIRED since Feb 24, 2026)
await nodeRegistry.setTokenPricing(usdcAddress, 15000);

// 3. Process inference and generate proof
const proof = await generateRisc0Proof(jobData);

// 4. Upload to S5
const proofCID = await s5.uploadBlob(proof);

// 5. Calculate hash
const proofHash = '0x' + crypto.createHash('sha256').update(proof).digest('hex');

// 6. Submit hash + CID (no signature needed — msg.sender auth)
await marketplace.submitProofOfWork(jobId, tokensClaimed, proofHash, proofCID, deltaCID);

// 7. Complete session to claim payment
await marketplace.completeSessionJob(jobId, conversationCID);
```

## Documentation

### 📚 Core Documentation
- [Client ABIs & Integration](client-abis/README.md) - Contract ABIs and SDK integration guide
- [API Reference](docs/API_REFERENCE.md) - Complete API documentation
- [Breaking Changes](docs/BREAKING_CHANGES.md) - Migration guide for SDK developers

### 🚀 Deployment
- [Contract Deployment Checklist](docs/CONTRACT_DEPLOYMENT_CHECKLIST.md) - Complete deployment steps

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
cast call 0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4 \
  "nextJobId()" \
  --rpc-url "https://sepolia.base.org"
```

## Architecture

```
┌──────────────────────────┐
│   ModelRegistry          │  ← AI model governance (5 approved models)
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
        │          │ ProofSystem  │  ← Proof replay protection
        │          └──────────────┘
        │
        └─────────►┌──────────────┐
                   │ S5 Storage   │  ← Off-chain proofs (221KB)
                   └──────────────┘
```

## Breaking Changes

### February 22-24, 2026: Post-Audit Security Remediation

All 20 security audit findings addressed with post-audit remediation deployment:

**Breaking Changes:**
- **Per-token pricing (F202614977):** Hosts MUST call `setTokenPricing(token, price)` for each ERC20 they accept. Silent fallback removed — `getNodePricing()` reverts with "No token pricing" for unconfigured tokens.
- **Proof signature removed:** `submitProofOfWork()` no longer requires ECDSA signature parameter. Authentication via `msg.sender == session.host`.
- **proofTimeoutWindow:** All session creation functions now require an additional `proofTimeoutWindow` parameter.
- **Shortened error strings (F202615067):** Error messages shortened for EVM size compliance.
- **Early cancellation fees:** Sessions completed before dispute window may incur minimum billing.
- **Pull-pattern refunds:** Refunds use pull pattern to prevent host payment blocking.
- **Fresh JobMarketplace proxy:** New proxy at `0xD067...adA4` (old proxy `0x95132...` deprecated).
- **New ProofSystem proxy:** `0xE8DC...` (old `0x5afB...` frozen).

See [client-abis/CHANGELOG.md](client-abis/CHANGELOG.md) for full migration details.

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

**Current Contract** (Feb 2026 post-audit remediation): `0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4` (UUPS Proxy)
```solidity
// Current (Feb 2026 post-audit remediation)
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes32 proofHash,         // ✅ 32 bytes - SHA256 hash
    string calldata proofCID,  // ✅ S5 CID for retrieval
    string calldata deltaCID   // ✅ S5 CID for delta changes
) external
```

See [Breaking Changes](docs/BREAKING_CHANGES.md) for full migration guide.

## Security

### Audits
- [x] Security audit completed (January 2026)
- [x] 20 findings remediated (February 2026)

### Security Features
- ReentrancyGuardTransient on all payment functions (EIP-1153)
- SHA256 hash verification for proof integrity
- S5 decentralized storage for proof availability
- Per-token pricing validation (prevents under-payment)
- Pull-pattern refunds (prevents host payment blocking)
- Delegated session authorization
- Emergency pause/unpause on JobMarketplace
- Access control for treasury and admin functions
- Per-model rate limits

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
- [x] Security audit (Jan 2026)
- [x] Audit remediation — 20 findings (Feb 2026)
- [x] Per-token pricing (F202614977) (Feb 2026)
- [x] Additional approved models (5 total)
- [ ] Base Mainnet deployment
- [ ] opBNB testnet deployment
- [ ] Multi-chain support (opBNB Mainnet)

---

**Built with Foundry** | **Deployed on Base L2** | **Powered by S5 Storage**
