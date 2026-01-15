# Test Coverage Report

**Generated:** January 15, 2026
**Test Framework:** Foundry/Forge
**Total Tests:** 640 passing

---

## Executive Summary

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Line Coverage | 66.69% | 85%+ | ⚠️ Needs improvement |
| Statement Coverage | 66.84% | 85%+ | ⚠️ Needs improvement |
| Branch Coverage | 14.92% | 60%+ | ❌ Critical gap |
| Function Coverage | 68.00% | 95%+ | ⚠️ Needs improvement |

---

## Per-Contract Coverage Analysis

### Source Contracts (Production Code)

| Contract | Lines | Statements | Branches | Functions | Priority |
|----------|-------|------------|----------|-----------|----------|
| **JobMarketplaceWithModelsUpgradeable.sol** | 86.17% | 85.96% | 17.55% | 87.18% | HIGH |
| **NodeRegistryWithModelsUpgradeable.sol** | 59.02% | 61.24% | 8.16% | 62.96% | **CRITICAL** |
| **ModelRegistryUpgradeable.sol** | 97.94% | 97.67% | 22.22% | 100% | LOW |
| **ProofSystemUpgradeable.sol** | 89.47% | 89.04% | 23.81% | 100% | MEDIUM |
| **HostEarningsUpgradeable.sol** | 87.32% | 82.09% | 8.57% | 100% | MEDIUM |
| **ReentrancyGuardTransient.sol** | 61.90% | 52.63% | 0.00% | 85.71% | LOW (EIP-1153) |

---

## Test Distribution

| Contract Area | Test Count | Coverage Focus |
|---------------|------------|----------------|
| JobMarketplace | 176 | Session lifecycle, proofs, payments, deltaCID |
| ProofSystem | 83 | Verification, access control |
| ModelRegistry | 94 | Governance, voting, anti-sniping, re-proposal |
| HostEarnings | 61 | Withdrawals, credits |
| NodeRegistry | 52 | Registration, pricing |
| Integration | 96 | Cross-contract flows |

---

## Critical Gaps: NodeRegistryWithModelsUpgradeable.sol

**Current Coverage:** 59.02% lines, 62.96% functions

### Untested Functions (HIGH Priority)

| Function | Lines | Risk Level | Description |
|----------|-------|------------|-------------|
| `updateMetadata()` | 223-229 | MEDIUM | Metadata update validation |
| `updateApiUrl()` | 234-240 | MEDIUM | API URL update validation |
| `updatePricingStable()` | 259-268 | HIGH | Stablecoin pricing updates |
| `setModelPricing()` | 273-291 | HIGH | Per-model pricing overrides |
| `clearModelPricing()` | 296-303 | MEDIUM | Clear pricing overrides |
| `setTokenPricing()` | 308-321 | HIGH | Token-specific pricing |
| `stake()` | 371-377 | HIGH | Additional stake deposits |
| `isActiveNode()` | 382-384 | LOW | Active status check |
| `getNodeApiUrl()` | 389-391 | LOW | View function |
| `getNodeFullInfo()` | 396-417 | LOW | View function |
| `getModelPricing()` | 437-447 | MEDIUM | Pricing with fallback |
| `getHostModelPrices()` | 452-480 | MEDIUM | Batch pricing query |
| `getAllActiveNodes()` | 485-487 | LOW | View function |
| `updateModelRegistry()` | 492-496 | HIGH | Admin function |

### Negative Cases Needed

```solidity
// Access control violations
test_UpdateMetadata_RejectsUnregistered()
test_UpdateApiUrl_RejectsUnregistered()
test_SetModelPricing_RejectsUnsupportedModel()
test_UpdateModelRegistry_RejectsNonOwner()

// Boundary conditions
test_SetModelPricing_RejectsBelowMinimum()
test_SetModelPricing_RejectsAboveMaximum()
test_Stake_RejectsZeroAmount()
test_RegisterNode_RejectsPriceBelowMinimum()
test_RegisterNode_RejectsPriceAboveMaximum()

// State validations
test_UpdatePricingNative_RejectsInactiveNode()
test_UpdatePricingStable_RejectsInactiveNode()
test_SetTokenPricing_RejectsInactiveNode()
```

---

## Medium Gaps: JobMarketplaceWithModelsUpgradeable.sol

**Current Coverage:** 86.17% lines, 87.18% functions

### Under-tested Functions

| Function | Current Coverage | Gap |
|----------|------------------|-----|
| `createSessionJobForModel()` | Partial | ETH path tested, edge cases missing |
| `createSessionJobForModelWithToken()` | Partial | USDC path tested, edge cases missing |
| `submitProofOfWork()` | Good | 6-param signature with deltaCID, branch coverage low |
| `completeSessionJob()` | Good | 2-param signature with conversationCID, timeout scenarios under-tested |
| `triggerSessionTimeout()` | Partial | Edge cases missing |

### Negative Cases Needed

```solidity
// Session creation failures
test_CreateSession_RejectsZeroDeposit()
test_CreateSession_RejectsUnapprovedModel()
test_CreateSession_RejectsInactiveHost()
test_CreateSession_RejectsPriceBelowHostMinimum()
test_CreateSession_RejectsWhenPaused()

// Proof submission failures (6-param signature with deltaCID)
test_SubmitProof_RejectsNonHost()
test_SubmitProof_RejectsCompletedSession()
test_SubmitProof_RejectsInvalidSignature()
test_SubmitProof_RejectsZeroTokens()
test_SubmitProof_RejectsExceedingDeposit()
test_SubmitProof_ValidatesProofCIDFormat()  // NEW: CID validation
test_SubmitProof_ValidatesDeltaCIDFormat()  // NEW: deltaCID validation

// Completion failures (2-param signature with conversationCID)
test_CompleteSession_RejectsNonParticipant()
test_CompleteSession_RejectsAlreadyCompleted()
test_CompleteSession_RejectsTimedOutSession()
test_CompleteSession_RequiresConversationCID()  // NEW: conversationCID required

// Timeout failures
test_TriggerTimeout_RejectsActiveSession()
test_TriggerTimeout_RejectsCompletedSession()
test_TriggerTimeout_RejectsAlreadyTimedOut()
```

---

## Recent Additions: deltaCID Tests (January 14, 2026)

The deltaCID feature was added to `submitProofOfWork()` to support incremental proof tracking on S5.

**New Test File:** `test/JobMarketplace/test_deltaCID.t.sol`

| Test | Purpose |
|------|---------|
| `test_ProofSubmittedEventIncludesDeltaCID()` | Verify event emits deltaCID |
| `test_DeltaCIDStoredInProofSubmission()` | Verify deltaCID stored in ProofSystem |
| `test_MultipleProofsWithDifferentDeltaCIDs()` | Verify sequential proofs track different CIDs |
| `test_EmptyDeltaCIDAllowed()` | Verify empty string is valid deltaCID |
| `test_GetProofSubmissionReturnsDeltaCID()` | Verify getter returns deltaCID correctly |

**Coverage Status:** ✅ All 5 tests passing

**Related Changes:**
- `submitProofOfWork()`: 5 params → 6 params (added `deltaCID`)
- `getProofSubmission()`: 4 returns → 5 returns (added `deltaCID`)
- `completeSessionJob()`: 1 param → 2 params (added `conversationCID`)
- `ProofSubmitted` event: 5 fields → 6 fields (added `deltaCID`)

---

## Branch Coverage Analysis

Branch coverage is critically low across all contracts (14.92% overall).

### Key Branch Gaps by Contract

**JobMarketplaceWithModelsUpgradeable.sol (17.55%)**
- Token type branching (ETH vs USDC) - partial
- Session state checks - partial
- Proof validation branches - partial
- Fee calculation paths - needs coverage

**NodeRegistryWithModelsUpgradeable.sol (8.16%)**
- Pricing type branching (native vs stable) - untested
- Model pricing overrides vs defaults - untested
- Custom token pricing fallbacks - untested

**HostEarningsUpgradeable.sol (8.57%)**
- Token type branching in credits - partial
- Zero balance checks - untested
- Withdrawal validation paths - partial

**ModelRegistryUpgradeable.sol (22.22%)**
- Voting outcome branches - partial
- Proposal execution paths - partial
- Fee refund conditions - partial

---

## Prioritized Test Backlog

### P0: Critical (Must Fix)

1. **NodeRegistry pricing functions** - HIGH risk, untested
   - `setModelPricing()`, `setTokenPricing()`, `updatePricingStable()`
   - Estimated: 15-20 new tests

2. **NodeRegistry stake function** - Funds at risk
   - `stake()` additional stake deposits
   - Estimated: 5 new tests

3. **NodeRegistry admin function** - Governance risk
   - `updateModelRegistry()`
   - Estimated: 3 new tests

### P1: High (Should Fix)

4. **JobMarketplace negative cases** - Security
   - Access control violations
   - State transition rejections
   - Estimated: 20-25 new tests

5. **HostEarnings branch coverage** - Payment safety
   - Token type branching
   - Zero balance edge cases
   - Estimated: 10 new tests

### P2: Medium (Nice to Have)

6. **NodeRegistry view functions** - Completeness
   - `getNodeFullInfo()`, `getHostModelPrices()`, etc.
   - Estimated: 8 new tests

7. **Integration tests expansion** - End-to-end confidence
   - Multi-session scenarios
   - Upgrade safety tests
   - Estimated: 10 new tests

### P3: Low (Future)

8. **ReentrancyGuardTransient coverage** - Already protected (EIP-1153)
   - Internal function coverage (transient storage)
   - Estimated: 5 new tests

---

## Recommended Test Files to Create

### New Files

```
test/NegativeCases/
├── NodeRegistry/
│   ├── test_access_control.t.sol      # 15 tests
│   ├── test_boundary_conditions.t.sol # 12 tests
│   └── test_state_validation.t.sol    # 8 tests
├── JobMarketplace/
│   ├── test_session_creation_negative.t.sol  # 12 tests
│   ├── test_proof_submission_negative.t.sol  # 10 tests
│   └── test_completion_negative.t.sol        # 8 tests
└── HostEarnings/
    └── test_withdrawal_negative.t.sol        # 8 tests
```

### Files to Extend

```
test/Upgradeable/NodeRegistry/test_initialization.t.sol
  + Add: updateMetadata, updateApiUrl, stake tests

test/Upgradeable/NodeRegistry/test_pricing.t.sol (NEW)
  + Add: setModelPricing, clearModelPricing, setTokenPricing tests

test/Integration/test_full_lifecycle.t.sol (NEW)
  + Add: Complete session with all edge cases
```

---

## Estimated Effort

| Category | New Tests | Effort |
|----------|-----------|--------|
| P0: Critical | 25-30 | HIGH (8-12 hours) |
| P1: High | 30-35 | HIGH (10-15 hours) |
| P2: Medium | 15-20 | MEDIUM (4-6 hours) |
| P3: Low | 5-10 | LOW (2-3 hours) |
| **Total** | **75-95** | **24-36 hours** |

---

## Coverage Targets After Remediation

| Contract | Current Lines | Target Lines | Delta |
|----------|---------------|--------------|-------|
| JobMarketplaceWithModelsUpgradeable | 86.17% | 95%+ | +9% |
| NodeRegistryWithModelsUpgradeable | 59.02% | 90%+ | +31% |
| ModelRegistryUpgradeable | 97.94% | 98%+ | +1% |
| ProofSystemUpgradeable | 89.47% | 95%+ | +6% |
| HostEarningsUpgradeable | 87.32% | 95%+ | +8% |

**Overall Target:** 85%+ line coverage, 60%+ branch coverage

---

## Commands

```bash
# Generate coverage report
forge coverage --ir-minimum

# Generate HTML report
forge coverage --ir-minimum --report lcov
genhtml lcov.info -o coverage-report

# Run specific contract tests
forge test --match-contract NodeRegistry -vv

# Check coverage for specific file
forge coverage --ir-minimum --match-contract NodeRegistryWithModelsUpgradeable
```
