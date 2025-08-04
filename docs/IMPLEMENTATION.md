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

- [x] Initialize Foundry project structure
- [x] Configure for Base L2 deployment
- [x] Set up development environment
- [x] Create contract interfaces

**Test Files:**

- `test/Setup/test_project_structure.t.sol`
- `test/Setup/test_base_config.t.sol`
- `test/Setup/test_interfaces.t.sol`
- `test/Setup/test_dependencies.t.sol`

### Sub-phase 1.2: NodeRegistry Contract

- [x] Implement host registration with staking
- [x] Implement capability advertisement
- [x] Implement node discovery helpers
- [x] Implement stake management

**Test Files:**

- `test/NodeRegistry/test_registration.t.sol`
- `test/NodeRegistry/test_staking.t.sol`
- `test/NodeRegistry/test_capabilities.t.sol`
- `test/NodeRegistry/test_discovery.t.sol`

### Sub-phase 1.3: JobMarketplace Contract

- [x] Implement direct job posting
- [x] Implement job claiming by hosts
- [x] Implement job status tracking
- [x] Implement completion verification

**Test Files:**

- `test/JobMarketplace/test_job_posting.t.sol`
- `test/JobMarketplace/test_job_claiming.t.sol`
- `test/JobMarketplace/test_status_tracking.t.sol`
- `test/JobMarketplace/test_completion.t.sol`

### Sub-phase 1.4: PaymentEscrow Contract

- [x] Implement multi-token support
- [x] Implement escrow mechanics
- [x] Implement automatic release
- [x] Implement dispute resolution

**Test Files:**

- `test/PaymentEscrow/test_multi_token.t.sol`
- `test/PaymentEscrow/test_escrow.t.sol`
- `test/PaymentEscrow/test_auto_release.t.sol`
- `test/PaymentEscrow/test_disputes.t.sol`

## Phase 2: Advanced Features (Month 2)

### Sub-phase 2.1: ReputationSystem Contract

- [x] Implement performance tracking
- [x] Implement quality scoring
- [x] Implement reputation-based incentives
- [x] Implement slashing mechanics

**Test Files:**

- `test/Reputation/test_performance.t.sol`
- `test/Reputation/test_quality_scoring.t.sol`
- `test/Reputation/test_incentives.t.sol`
- `test/Reputation/test_slashing.t.sol`

### Sub-phase 2.2: Base Account Integration

- [x] Implement smart wallet support
- [x] Implement gasless transactions
- [x] Implement session keys
- [x] Implement batch operations

**Test Files:**

- `test/BaseAccount/test_smart_wallets.t.sol`
- `test/BaseAccount/test_gasless.t.sol`
- `test/BaseAccount/test_session_keys.t.sol`
- `test/BaseAccount/test_batch_ops.t.sol`

### Sub-phase 2.3: ProofSystem Contract

- [x] Implement EZKL verification
- [x] Implement proof submission
- [x] Implement batch verification
- [x] Implement proof challenges

**Test Files:**

- `test/ProofSystem/test_ezkl_verify.t.sol`
- `test/ProofSystem/test_submission.t.sol`
- `test/ProofSystem/test_batch_verify.t.sol`
- `test/ProofSystem/test_challenges.t.sol`

### Sub-phase 2.4: Governance Contract

- [x] Implement parameter updates
- [x] Implement emergency pause
- [x] Implement upgrade mechanisms
- [x] Implement community voting

**Test Files:**

- `test/Governance/test_governance.t.sol`
- `test/Governance/test_governance_token.t.sol`

### Sub-phase 2.5: Tokenomics & Revenue Distribution (**NEW**)

- [x] Implement payment splitting (85% host, 10% protocol, 5% stakers)
- [x] Implement FAB buyback mechanism
- [x] Implement stakers pool distribution
- [x] Implement staking tiers and multipliers

**Test Files:**

- `test/Tokenomics/test_payment_splits.t.sol`
- `test/Tokenomics/test_buyback.t.sol`
- `test/Tokenomics/test_staker_rewards.t.sol`
- `test/Tokenomics/test_staking_tiers.t.sol`

### Sub-phase 2.6: Model Marketplace Features (**NEW**)

- [x] Implement model listing with pricing
- [x] Implement host pricing per token/minute
- [x] Implement dynamic pricing mechanisms
- [x] Implement subscription plans

**Test Files:**

- `test/ModelMarketplace/test_model_listing.t.sol`
- `test/ModelMarketplace/test_pricing.t.sol`
- `test/ModelMarketplace/test_dynamic_pricing.t.sol`
- `test/ModelMarketplace/test_subscriptions.t.sol`

## Phase 3: Production Ready (Month 3)

### Sub-phase 3.1: Integration Testing

- [x] Test contract interactions
- [x] Test edge cases
- [x] Test gas optimization
- [x] Test failure scenarios

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
