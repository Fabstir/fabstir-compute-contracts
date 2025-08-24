# Fabstir Compute Contracts - Technical Documentation

## Overview

This documentation provides comprehensive technical reference for the Fabstir P2P LLM marketplace smart contracts deployed on Base L2. The system enables decentralized AI model inference with direct host-renter interactions, eliminating the need for centralized coordination.

## Contract Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  NodeRegistry   │◄────│ JobMarketplace   │────►│ PaymentEscrow   │
└────────┬────────┘     └────────┬─────────┘     └─────────────────┘
         │                       │
         │              ┌────────▼─────────┐
         └──────────────┤ ReputationSystem │
                        └────────┬─────────┘
                                 │
                        ┌────────▼────────┐
                        │   ProofSystem    │
                        └─────────────────┘
                                 
┌─────────────────┐     ┌──────────────────┐
│   Governance    │────►│ GovernanceToken  │
└─────────────────┘     └──────────────────┘

┌────────────────────────┐
│ BaseAccountIntegration │ (ERC-4337 Support)
└────────────────────────┘
```

## Core Contracts

### Host & Node Management
- **[NodeRegistry](contracts/NodeRegistry.md)** - Manages GPU host registration, staking, and node capabilities

### Job Lifecycle
- **[JobMarketplace](contracts/JobMarketplace.md)** - Handles job posting, claiming, and completion workflows

### Payment Infrastructure
- **[PaymentEscrow](contracts/PaymentEscrow.md)** - Multi-token escrow system for secure payments

### Quality & Trust
- **[ReputationSystem](contracts/ReputationSystem.md)** - Tracks host performance and enables quality-based routing
- **[ProofSystem](contracts/ProofSystem.md)** - EZKL-based proof verification for output correctness

### Protocol Governance
- **[Governance](contracts/Governance.md)** - Decentralized governance for protocol upgrades
- **[GovernanceToken](contracts/GovernanceToken.md)** - ERC20 voting token with delegation

### Account Abstraction
- **[BaseAccountIntegration](contracts/BaseAccountIntegration.md)** - ERC-4337 integration for gasless transactions

## Interfaces

See **[interfaces/README.md](interfaces/README.md)** for all contract interfaces and integration patterns.

## Architecture Documentation

- **[System Design](architecture/system-design.md)** - High-level architecture and design decisions
- **[Contract Interactions](architecture/contract-interactions.md)** - Detailed interaction flows between contracts

## Key Features

### For Hosts
- Minimum 1000 FAB token stake requirement
- Support for multiple AI models and regions
- Reputation-based job assignment
- Slashing for malicious behavior

### For Renters
- Post jobs with specific model requirements
- Escrow-based payment protection
- Proof verification for outputs
- Dispute resolution mechanism

### Security Features
- Reentrancy protection on all critical functions
- Circuit breakers for emergency pausing
- Rate limiting and anti-spam measures
- Sybil attack detection
- Access control for sensitive operations

### Gas Optimization
- Batch operations for multiple jobs
- Efficient storage patterns
- ERC-4337 for gasless transactions
- Optimized checkpoint systems

## Integration Guide

### Quick Start
```solidity
// 1. Register as a host with FAB tokens
fabToken.approve(nodeRegistryFAB, 1000 ether);
nodeRegistryFAB.registerNode(metadata);

// 2. Post a job
uint256 jobId = jobMarketplace.createJob{value: payment}(
    modelId,
    inputHash,
    maxPrice,
    deadline
);

// 3. Claim and complete job
jobMarketplace.claimJob(jobId);
proofSystem.submitProof(jobId, proof);
jobMarketplace.completeJob(jobId, resultHash, proof);
```

### Network Information
- **Target Network**: Base L2 Mainnet
- **Testnet**: Base Sepolia
- **Required FAB for Hosting**: 1000 FAB minimum stake

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

## Gas Costs

Typical transaction costs on Base L2:
- Node Registration: ~150,000 gas
- Job Creation: ~200,000 gas
- Job Claim: ~100,000 gas
- Job Completion: ~250,000 gas (with proof)

## Support & Resources

- **GitHub**: [fabstir/fabstir-compute-contracts](https://github.com/fabstir/fabstir-compute-contracts)
- **Documentation**: This repository
- **Audits**: Pending