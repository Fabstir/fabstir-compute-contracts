# Fabstir Compute Contracts - Implementation Plan

## Overview

Smart contracts for the Fabstir P2P LLM marketplace on Base L2, enabling direct host-renter interactions without centralized coordination.

## Development Setup

- **Framework**: Foundry
- **Chain**: Base L2 (local dev, Sepolia testnet, mainnet)
- **Dependencies**: OpenZeppelin, Base Account SDK
- **Testing**: Solidity tests with 100% coverage target

## Phase 1: Foundation (Month 1)

### Sub-phase 1.1: Project Setup

- [ ] Initialize Foundry project structure
- [ ] Configure for Base L2 deployment
- [ ] Set up development environment
- [ ] Create contract interfaces

**Test Files:**

- `test/Setup/test_project_structure.t.sol`
- `test/Setup/test_base_config.t.sol`
- `test/Setup/test_interfaces.t.sol`
- `test/Setup/test_dependencies.t.sol`

### Sub-phase 1.2: NodeRegistry Contract

- [ ] Implement host registration with staking
- [ ] Implement capability advertisement
- [ ] Implement node discovery helpers
- [ ] Implement stake management

**Test Files:**

- `test/NodeRegistry/test_registration.t.sol`
- `test/NodeRegistry/test_staking.t.sol`
- `test/NodeRegistry/test_capabilities.t.sol`
- `test/NodeRegistry/test_discovery.t.sol`

### Sub-phase 1.3: JobMarketplace Contract

- [ ] Implement direct job posting
- [ ] Implement job claiming by hosts
- [ ] Implement job status tracking
- [ ] Implement completion verification

**Test Files:**

- `test/JobMarketplace/test_job_posting.t.sol`
- `test/JobMarketplace/test_job_claiming.t.sol`
- `test/JobMarketplace/test_status_tracking.t.sol`
- `test/JobMarketplace/test_completion.t.sol`

### Sub-phase 1.4: PaymentEscrow Contract

- [ ] Implement multi-token support
- [ ] Implement escrow mechanics
- [ ] Implement automatic release
- [ ] Implement dispute resolution

**Test Files:**

- `test/PaymentEscrow/test_multi_token.t.sol`
- `test/PaymentEscrow/test_escrow.t.sol`
- `test/PaymentEscrow/test_auto_release.t.sol`
- `test/PaymentEscrow/test_disputes.t.sol`

## Phase 2: Advanced Features (Month 2)

### Sub-phase 2.1: ReputationSystem Contract

- [ ] Implement performance tracking
- [ ] Implement quality scoring
- [ ] Implement reputation-based incentives
- [ ] Implement slashing mechanics

**Test Files:**

- `test/Reputation/test_performance.t.sol`
- `test/Reputation/test_quality_scoring.t.sol`
- `test/Reputation/test_incentives.t.sol`
- `test/Reputation/test_slashing.t.sol`

### Sub-phase 2.2: Base Account Integration

- [ ] Implement smart wallet support
- [ ] Implement gasless transactions
- [ ] Implement session keys
- [ ] Implement batch operations

**Test Files:**

- `test/BaseAccount/test_smart_wallets.t.sol`
- `test/BaseAccount/test_gasless.t.sol`
- `test/BaseAccount/test_session_keys.t.sol`
- `test/BaseAccount/test_batch_ops.t.sol`

### Sub-phase 2.3: ProofSystem Contract

- [ ] Implement EZKL verification
- [ ] Implement proof submission
- [ ] Implement batch verification
- [ ] Implement proof challenges

**Test Files:**

- `test/ProofSystem/test_ezkl_verify.t.sol`
- `test/ProofSystem/test_submission.t.sol`
- `test/ProofSystem/test_batch_verify.t.sol`
- `test/ProofSystem/test_challenges.t.sol`

### Sub-phase 2.4: Governance Contract

- [ ] Implement parameter updates
- [ ] Implement emergency pause
- [ ] Implement upgrade mechanisms
- [ ] Implement community voting

**Test Files:**

- `test/Governance/test_parameters.t.sol`
- `test/Governance/test_emergency.t.sol`
- `test/Governance/test_upgrades.t.sol`
- `test/Governance/test_voting.t.sol`

## Phase 3: Production Ready (Month 3)

### Sub-phase 3.1: Integration Testing

- [ ] Test contract interactions
- [ ] Test edge cases
- [ ] Test gas optimization
- [ ] Test failure scenarios

**Test Files:**

- `test/Integration/test_full_flow.t.sol`
- `test/Integration/test_edge_cases.t.sol`
- `test/Integration/test_gas_usage.t.sol`
- `test/Integration/test_failures.t.sol`

### Sub-phase 3.2: Security Hardening

- [ ] Implement reentrancy guards
- [ ] Implement access controls
- [ ] Implement input validation
- [ ] Implement circuit breakers

**Test Files:**

- `test/Security/test_reentrancy.t.sol`
- `test/Security/test_access.t.sol`
- `test/Security/test_validation.t.sol`
- `test/Security/test_breakers.t.sol`

### Sub-phase 3.3: Deployment Scripts

- [ ] Create deployment scripts
- [ ] Create verification scripts
- [ ] Create migration scripts
- [ ] Create monitoring scripts

**Test Files:**

- `test/Deploy/test_deployment.t.sol`
- `test/Deploy/test_verification.t.sol`
- `test/Deploy/test_migration.t.sol`
- `test/Deploy/test_monitoring.t.sol`

### Sub-phase 3.4: Documentation

- [ ] Write technical documentation
- [ ] Create integration guides
- [ ] Document best practices
- [ ] Create example usage

**Test Files:**

- `test/Docs/test_technical_docs.t.sol`
- `test/Docs/test_integration.t.sol`
- `test/Docs/test_best_practices.t.sol`
- `test/Docs/test_examples.t.sol`
