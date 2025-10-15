# Fabstir Compute Contracts - Technical Documentation

**Last Updated**: October 14, 2025

## Overview

This documentation provides comprehensive technical reference for the Fabstir P2P LLM marketplace smart contracts deployed on Base Sepolia L2. The system enables decentralized AI model inference with **S5 off-chain proof storage**, session-based streaming payments, and direct host-renter interactions.

> **🚀 LATEST UPDATE**: S5 Off-Chain Proof Storage (Oct 14, 2025)
>
> - Full STARK proofs (221KB) now stored in S5 decentralized storage
> - Only hash (32 bytes) + CID (string) submitted on-chain
> - Transaction size: 221KB → 300 bytes (737x reduction)
> - Storage cost: ~$50 → ~$0.001 per proof (5000x cheaper)

## Current Contract Architecture (S5 Storage)

```
┌──────────────────────────┐
│   ModelRegistry          │  ← AI model governance (2 approved models)
│   0x92b2De...3E          │
└───────────┬──────────────┘
            │
            ▼
┌──────────────────────────┐
│ NodeRegistryWithModels   │  ← Host registration + dual pricing
│ 0xDFFDec...D6            │
└───────────┬──────────────┘
            │
            ▼
┌──────────────────────────┐
│ JobMarketplaceWithModels │  ← Session jobs with S5 proof storage
│ 0xc6D44D...6E (NEW)      │
└───────┬──────────────────┘
        │
        ├─────────────────►┌──────────────────────┐
        │                  │   HostEarnings       │  ← 90% host payment accumulation
        │                  │   0x908962...776     │
        │                  └──────────────────────┘
        │
        ├─────────────────►┌──────────────────────┐
        │                  │   ProofSystem        │  ← Configured for dispute resolution
        │                  │   0x2ACcc6...FD1     │  (not actively verifying on-chain)
        │                  └──────────────────────┘
        │
        └─────────────────►┌──────────────────────┐
                           │   S5 Storage         │  ← Decentralized proof storage
                           │   (Off-Chain)        │  (221KB proofs)
                           └──────────────────────┘
```

## Core Contracts (Current Deployment)

### 🚀 Active Production Contracts

#### JobMarketplaceWithModels (S5 Proof Storage)
- **Address**: `0xc6D44D7f2DfA8fdbb1614a8b6675c78D3cfA376E`
- **[Documentation](contracts/JobMarketplace.md)**
- **Features**: Session-based jobs, S5 off-chain proof storage, dual pricing validation, anyone-can-complete
- **Status**: ✅ ACTIVE (Oct 14, 2025)

#### NodeRegistryWithModels (Dual Pricing)
- **Address**: `0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6`
- **[Documentation](contracts/NodeRegistry.md)**
- **Features**: Host registration, dual pricing (native + stable), model validation, 1000 FAB stake
- **Status**: ✅ ACTIVE (Jan 28, 2025)

#### ModelRegistry
- **Address**: `0x92b2De840bB2171203011A6dBA928d855cA8183E`
- **Features**: AI model governance, 2 approved models (TinyVicuna-1B, TinyLlama-1.1B)
- **Status**: ✅ ACTIVE

#### ProofSystem (S5 Integration)
- **Address**: `0x2ACcc60893872A499700908889B38C5420CBcFD1`
- **[Documentation](contracts/ProofSystem.md)**
- **Features**: Configured for dispute resolution (NOT actively verifying on-chain with S5 storage)
- **Status**: ✅ ACTIVE (configured, standby mode)

#### HostEarnings
- **Address**: `0x908962e8c6CE72610021586f85ebDE09aAc97776`
- **Features**: Host payment accumulation (90%), batch withdrawals, gas optimization
- **Status**: ✅ ACTIVE

### Token Contracts

#### FAB Token (Governance & Staking)
- **Address**: `0xC78949004B4EB6dEf2D66e49Cd81231472612D62`
- **Base Sepolia**: Testnet token

#### USDC (Payments)
- **Address**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- **Base Sepolia**: Official testnet USDC

## Interfaces

See **[interfaces/README.md](interfaces/README.md)** for all contract interfaces and integration patterns.

## Architecture Documentation

- **[System Design](architecture/system-design.md)** - High-level architecture and design decisions
- **[Contract Interactions](architecture/contract-interactions.md)** - Detailed interaction flows between contracts

## Key Features

### S5 Off-Chain Proof Storage (NEW - Oct 14, 2025)
- **Problem Solved**: STARK proofs (221KB) exceeded RPC transaction limit (128KB)
- **Solution**: Full proofs stored in S5, only hash + CID on-chain
- **Benefits**: 737x transaction size reduction, 5000x cost reduction
- **Security**: SHA256 hash prevents tampering, decentralized S5 storage ensures availability
- **Trust Model**: Hash commitment during normal operation, full verification on dispute

### For Hosts
- Minimum 1000 FAB token stake requirement
- Support for 2 approved AI models (TinyVicuna-1B, TinyLlama-1.1B)
- Dual pricing (native ETH + stable USDC)
- S5 proof upload integration required
- 90% revenue share via HostEarnings

### For Renters
- Session-based streaming payments (pay per token)
- Query host dual pricing before session creation
- Automatic refunds for unused deposit
- Hash-based proof integrity verification
- Anyone-can-complete for gasless session ending

### Security Features
- Reentrancy protection on all payment functions
- SHA256 hash verification for proof integrity
- S5 decentralized storage for proof availability
- Dual pricing validation (prevents under-payment)
- Access control for treasury functions

### Gas Optimization
- S5 storage: ~$0.001 vs ~$50 for on-chain proof storage
- Session-based payments: 85-95% reduction in transactions
- HostEarnings accumulation: ~80% gas savings
- Anyone-can-complete: Gasless UX for renters
- Efficient dual pricing validation

## Integration Guide

### Quick Start for Renters (JavaScript/TypeScript)

```javascript
import { ethers } from 'ethers';
import { S5Client } from '@lumeweb/s5-js';

// 1. Query host dual pricing (REQUIRED before creating session)
const nodeRegistry = new ethers.Contract(
  '0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6',
  NodeRegistryABI,
  provider
);
const [hostMinNative, hostMinStable] = await nodeRegistry.getNodePricing(hostAddress);

// 2. Create session job with ETH
const marketplace = new ethers.Contract(
  '0xc6D44D7f2DfA8fdbb1614a8b6675c78D3cfA376E',
  JobMarketplaceABI,
  signer
);

const pricePerToken = ethers.BigNumber.from("4000000000"); // Must be >= hostMinNative
const deposit = ethers.utils.parseEther("0.1");

const tx = await marketplace.createSessionJob(
  hostAddress,
  pricePerToken,
  3600, // 1 hour max duration
  100,  // Proof every 100 tokens
  { value: deposit }
);

// 3. Listen for session events
marketplace.on('SessionJobCreated', (jobId, user, host, deposit, price, duration) => {
  console.log(`Session created: ${jobId}`);
});
```

### Quick Start for Hosts (Node Operators)

```javascript
import crypto from 'crypto';
import { S5Client } from '@lumeweb/s5-js';

// Initialize S5 client
const s5 = new S5Client('https://s5.lumeweb.com');

// 1. Register node with dual pricing
const fabToken = new ethers.Contract(FAB_TOKEN_ADDRESS, ERC20_ABI, signer);
await fabToken.approve(nodeRegistryAddress, ethers.utils.parseEther("1000"));

await nodeRegistry.registerNode(
  metadata,
  apiUrl,
  supportedModels,
  minPriceNative,  // e.g., 3000000000 wei (~$0.000013 @ $4400 ETH)
  minPriceStable   // e.g., 15000 (0.000015 USDC per token)
);

// 2. Process AI inference (off-chain)
const proof = await generateRisc0Proof(jobData);

// 3. Upload proof to S5
const proofCID = await s5.uploadBlob(proof);
console.log(`Proof uploaded to S5: ${proofCID}`);

// 4. Calculate SHA256 hash
const proofHash = '0x' + crypto.createHash('sha256').update(proof).digest('hex');

// 5. Submit proof to blockchain (only hash + CID)
await marketplace.submitProofOfWork(
  jobId,
  tokensClaimed,  // e.g., 1000 tokens
  proofHash,      // 32-byte hash
  proofCID        // S5 CID string
);

// 6. Complete session to claim payment
await marketplace.completeSessionJob(jobId, conversationCID);
```

### Network Information
- **Current Network**: Base Sepolia (Testnet)
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org
- **Required FAB for Hosting**: 1000 FAB minimum stake
- **S5 Storage**: Required for proof submission

## Development

### Building
```bash
forge build
```

### Testing
```bash
forge test
```

### Deployment
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

## Security Considerations

1. **Reentrancy Protection**: All payment functions use OpenZeppelin's ReentrancyGuard
2. **Access Control**: Role-based permissions for critical functions
3. **Input Validation**: Comprehensive validation on all user inputs
4. **Circuit Breakers**: Emergency pause functionality with cooldown periods
5. **Rate Limiting**: Protection against spam and DoS attacks

## Gas Costs (Base Sepolia L2)

### Current Costs with S5 Storage
- **Node Registration**: ~180,000 gas (includes dual pricing)
- **Session Creation**: ~200,000 gas
- **Proof Submission (S5)**: ~60,000 gas (hash + CID only)
- **Session Completion**: ~140,000 gas (with HostEarnings accumulation)

### Cost Comparison: S5 vs On-Chain Proofs
| Operation | On-Chain Proof | S5 Storage | Savings |
|-----------|----------------|------------|---------|
| Proof Submission | ❌ FAILED (221KB > 128KB limit) | ~60,000 gas | N/A |
| Storage Cost | ~$50 (theoretical) | ~$0.001 | 5000x |
| Transaction Size | 221KB | ~300 bytes | 737x |

### Session Job Economics
For a typical 50-prompt conversation:
- **Old Model** (per-prompt): 50 tx × ~$0.05 = ~$2.50
- **Session Model** (checkpoints): 5-10 tx × ~$0.02 = ~$0.10-$0.20
- **Savings**: 85-95% reduction

## Support & Resources

- **Contract Addresses**: [CONTRACT_ADDRESSES.md](../../CONTRACT_ADDRESSES.md)
- **S5 Deployment Guide**: [S5_PROOF_STORAGE_DEPLOYMENT.md](../S5_PROOF_STORAGE_DEPLOYMENT.md)
- **Architecture Overview**: [ARCHITECTURE.md](../ARCHITECTURE.md)
- **Session Jobs Guide**: [SESSION_JOBS.md](../SESSION_JOBS.md)
- **S5 Documentation**: [docs.sfive.net](https://docs.sfive.net/)
- **Base Sepolia Explorer**: [sepolia.basescan.org](https://sepolia.basescan.org)
- **GitHub**: [fabstir/fabstir-compute-contracts](https://github.com/fabstir/fabstir-compute-contracts)