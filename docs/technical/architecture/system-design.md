# Fabstir Compute Contracts - System Architecture

## Overview

The Fabstir compute contracts implement a decentralized P2P marketplace for AI model inference on Base L2. The architecture prioritizes trustlessness, scalability, and security while enabling direct interactions between compute providers (hosts) and consumers (renters).

## Design Principles

### 1. Decentralization First
- No central coordinator or admin keys for core operations
- Permissionless participation with stake requirements
- On-chain state for critical operations
- Off-chain data referenced by content hashes

### 2. Economic Security
- 1000 FAB minimum stake aligns host incentives
- Escrow-based payments protect renters
- Reputation system enables quality differentiation
- Fee mechanism sustains protocol development

### 3. Defensive Architecture
- Circuit breakers prevent cascade failures
- Rate limiting mitigates spam attacks
- Sybil resistance through stake and controller tracking
- Emergency pause capabilities with governance oversight

### 4. Composability
- Clean interface separation
- ERC-4337 support for account abstraction
- Multi-token support (ETH and USDC)
- Batch operations for efficiency

## System Components

### Core Business Logic

```
┌─────────────────────────────────────────────────────────────┐
│                      Job Lifecycle Layer                      │
├─────────────────┬─────────────────┬─────────────────────────┤
│  JobMarketplace │  PaymentEscrow  │     ProofSystem         │
│  - Job posting  │  - ETH/USDC hold │  - Verify outputs       │
│  - Assignment   │  - Fee handling  │  - Challenge mechanism  │
│  - Completion   │  - Token refunds │  - EZKL integration     │
└─────────────────┴─────────────────┴─────────────────────────┘
```

### Infrastructure Layer

```
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                       │
├─────────────────┬─────────────────┬─────────────────────────┤
│  NodeRegistry   │ ReputationSystem│  BaseAccountIntegration │
│  - Host stakes  │  - Track quality │  - ERC-4337 support    │
│  - Capabilities │  - Decay scores  │  - Batch operations    │
│  - Sybil detect │  - Incentives    │  - Session keys        │
└─────────────────┴─────────────────┴─────────────────────────┘
```

### Governance Layer

```
┌─────────────────────────────────────────────────────────────┐
│                      Governance Layer                         │
├─────────────────────────┬───────────────────────────────────┤
│      Governance         │        GovernanceToken            │
│  - Proposal system      │  - ERC20Votes implementation      │
│  - Time-locked exec     │  - Delegation support             │
│  - Emergency actions    │  - Historical snapshots           │
└─────────────────────────┴───────────────────────────────────┘
```

## Data Flow Architecture

### Job Creation Flow
```
Renter → JobMarketplace → PaymentEscrow
   │           │              │
   │           ├──→ Event emission
   │           └──→ State update
   │
   └──→ Payment locked in escrow
```

### Job Execution Flow
```
Host → NodeRegistry (verification) → JobMarketplace (claim)
  │                                          │
  └──→ Off-chain computation                 │
            │                                │
            ▼                                │
       ProofSystem (submit) ←────────────────┘
            │
            ├──→ Verification
            └──→ Reputation update
```

### Payment Flow
```
Escrow holds payment → Job completion → Release decision
                            │                 │
                            ├─ Success → Host payment (minus fee)
                            ├─ Dispute → Arbiter resolution
                            └─ Failure → Renter refund
```

## Security Architecture

### Multi-Layer Defense

1. **Application Layer Security**
   - Input validation on all user inputs
   - Reentrancy guards on payment functions
   - Access control via roles and modifiers

2. **Economic Security**
   - High stakes deter malicious behavior
   - Reputation loss impacts future earnings
   - Challenge bonds prevent frivolous disputes

3. **Operational Security**
   - Circuit breakers with automatic triggers
   - Manual pause capabilities
   - Governance-controlled emergency actions

### Attack Mitigation

| Attack Vector | Mitigation Strategy |
|--------------|-------------------|
| Sybil Attacks | Controller tracking, stake requirements |
| Spam/DoS | Rate limiting, registration limits |
| Front-running | Commit-reveal where applicable |
| Griefing | Economic penalties, reputation loss |
| Rug pulls | No admin keys, time-locked governance |

## State Management

### On-Chain State
- Host registrations and stakes
- Job metadata and status
- Payment escrows
- Reputation scores
- Governance proposals

### Off-Chain State
- Actual computation data
- Model weights
- Input/output data
- Detailed proofs

### Hybrid Approach
```
On-chain: Hashes, commitments, critical metadata
Off-chain: Bulk data, computation
Bridge: IPFS, Arweave, or similar for content addressing
```

## Scalability Considerations

### L2 Optimization
- Base L2 for lower costs
- Batch operations to amortize gas
- Efficient storage patterns
- Event-based indexing

### Horizontal Scaling
```
┌──────────┐    ┌──────────┐    ┌──────────┐
│  Shard 1 │    │  Shard 2 │    │  Shard 3 │
│  GPT-4   │    │  Llama   │    │  Stable  │
│  Jobs    │    │  Jobs    │    │ Diffusion│
└──────────┘    └──────────┘    └──────────┘
     │               │               │
     └───────────────┴───────────────┘
                     │
              Cross-shard Registry
```

### Future Scaling
- Model-specific marketplaces
- Regional deployments
- Cross-chain bridges
- State channels for high-frequency operations

## Integration Patterns

### Direct Integration
```solidity
// Simple direct calls
// First approve FAB tokens, then register
fabToken.approve(nodeRegistryFAB, 1000 ether);
nodeRegistryFAB.registerNode(metadata);
// Post job with USDC
usdc.approve(jobMarketplaceFAB, payment);
jobMarketplaceFAB.postJobWithToken(details, requirements, usdc, payment);
```

### Smart Wallet Integration
```solidity
// ERC-4337 UserOperation
UserOperation memory op = buildOperation(
    target: baseAccountIntegration,
    callData: abi.encodeWithSelector(...)
);
entryPoint.handleOps([op], beneficiary);
```

### Batch Operations
```solidity
// Multiple operations in one transaction
Operation[] memory ops = new Operation[](3);
ops[0] = Operation(nodeRegistry, stake, registerData);
ops[1] = Operation(jobMarketplace, payment1, jobData1);
ops[2] = Operation(jobMarketplace, payment2, jobData2);
baseAccountIntegration.executeBatch{value: totalValue}(ops);
```

## Upgrade Architecture

### Governance-Controlled Upgrades
```
Proposal → Voting (7 days) → Queue (2 days) → Execution
    │           │                │               │
    └──────────┴────────────────┴───────────────┘
              Requires quorum and majority
```

### Migration Support
- Dedicated migration helper contracts
- State transfer functions
- Backward compatibility consideration
- Graceful deprecation paths

## Monitoring & Observability

### On-Chain Metrics
- Circuit breaker statistics
- Success/failure rates
- Active host count
- Job completion times

### Events for Indexing
```
JobCreated → JobClaimed → JobCompleted → PaymentReleased
     │            │             │               │
     └────────────┴─────────────┴───────────────┘
                    Off-chain indexer
```

### Health Indicators
- Registration rate
- Job success rate
- Average completion time
- Reputation distribution
- Payment velocity

## Future Architecture Evolution

### Phase 1: Current (Implemented)
- Basic marketplace functionality
- Simple proof verification
- Manual governance

### Phase 2: Enhanced (Planned)
- Advanced proof systems
- Automated market making
- Cross-chain support

### Phase 3: Mature (Vision)
- Fully autonomous operation
- Self-healing systems
- AI-driven optimization

## Design Trade-offs

### Chose Simplicity Over Complexity
- Fixed stake amounts vs dynamic staking
- Simple reputation vs complex scoring
- Direct payments vs payment channels

### Chose Security Over Efficiency
- Higher stakes vs lower barrier to entry
- Time locks vs instant execution
- Multiple checks vs gas optimization

### Chose Flexibility Over Rigidity
- Governance upgrades vs immutability
- Multiple token support vs ETH-only
- Extensible interfaces vs fixed APIs

## Conclusion

The Fabstir architecture balances decentralization, security, and usability to create a robust marketplace for AI compute. The modular design enables independent evolution of components while maintaining system coherence. Future iterations will build upon this foundation to support the growing demands of decentralized AI infrastructure.