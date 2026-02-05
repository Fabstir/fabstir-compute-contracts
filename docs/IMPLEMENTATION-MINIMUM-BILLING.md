# IMPLEMENTATION-MINIMUM-BILLING.md - Enforce Minimum Billing (proofInterval)

## Overview

Enforce minimum billing on first proof submission to ensure hosts receive at least the session's `proofInterval` worth of tokens. Currently, the contract accepts any `tokensClaimed >= MIN_PROVEN_TOKENS (100)`, allowing hosts to bill less than the agreed minimum.

## Repository

fabstir-compute-contracts

## Issue Reference

- **Reported By**: Node Developer
- **Date**: February 2026
- **Contract**: JobMarketplaceWithModelsUpgradeable
- **Proxy**: `0x95132177F964FF053C1E874b53CF74d819618E06`

## Problem Statement

| Behavior | Description |
|----------|-------------|
| **Current** | Contract accepts any `tokensClaimed >= 100` (MIN_PROVEN_TOKENS) |
| **Expected** | First proof must bill at least `proofInterval` tokens for minimum fee collection |

## Implementation Approach

**Defense in Depth**: Implement both primary enforcement and fallback:

| Option | Enforcement Point | Purpose |
|--------|-------------------|---------|
| **A (Primary)** | `submitProofOfWork()` | Reject first proof below proofInterval |
| **B (Fallback)** | `_settleSessionPayments()` | Pad billing to proofInterval at completion |

## Goals

- Enforce minimum billing for first proof submission
- Provide fallback enforcement at session completion
- Maintain backward compatibility for compliant nodes (v8.14.2+)
- Preserve existing early cancellation fee logic
- Follow strict TDD with bounded autonomy approach

## Implementation Progress

**Overall Status: COMPLETE (100%)**

- [x] **Phase 1: Test Infrastructure** (1/1 sub-phases) ✅
  - [x] Sub-phase 1.1: Create Test File with Failing Tests ✅
- [x] **Phase 2: Primary Enforcement** (1/1 sub-phases) ✅
  - [x] Sub-phase 2.1: First Proof Validation in submitProofOfWork ✅
- [x] **Phase 3: Fallback Enforcement** (1/1 sub-phases) ✅
  - [x] Sub-phase 3.1: Minimum Billing in _settleSessionPayments ✅
- [x] **Phase 4: Deployment** (2/2 sub-phases) ✅
  - [x] Sub-phase 4.1: Deploy and Upgrade ✅
  - [x] Sub-phase 4.2: Update Documentation and ABIs ✅

**Deployment Details:**
- Implementation Address: `0x56b66c5210ba67452d991cd2a3037dc3b3e2eec7`
- Proxy Address: `0x95132177F964FF053C1E874b53CF74d819618E06`
- Transaction Hash: `0x22e7d0aca882f8c5ff15f3a719938d10c7a3074f045e58e5d45642f63f0953bd`
- Block: 37251201

**Last Updated:** 2026-02-05

---

## Phase 1: Test Infrastructure

### Sub-phase 1.1: Create Test File with Failing Tests

**Approach**: TDD - Write all tests first, verify they FAIL (RED), then implement (GREEN).

**File Limits (Bounded Autonomy)**:
- Test file: No limit (comprehensive coverage required)
- Each test function: ~30 lines max

**Tasks:**
- [ ] Create test file `test/SecurityFixes/Remediation/test_minimum_billing.t.sol`
- [ ] Write test setup with proxy deployment and session creation helpers
- [ ] Test: `test_RejectFirstProofBelowProofInterval()` - First proof < proofInterval reverts
- [ ] Test: `test_AcceptFirstProofMeetingProofInterval()` - First proof >= proofInterval succeeds
- [ ] Test: `test_AcceptSubsequentProofsBelowProofInterval()` - Second+ proofs can be < proofInterval
- [ ] Test: `test_EnforceMinimumBillingAtCompletion()` - billableTokens padded to proofInterval
- [ ] Test: `test_NormalCompletionNoAdjustment()` - tokensUsed >= proofInterval, no padding
- [ ] Test: `test_EarlyCancellationUnaffected()` - proofs.length == 0 uses early cancel logic
- [ ] Run tests, verify all FAIL with expected errors
- [ ] Commit: "test(minimum-billing): add failing tests for proofInterval enforcement (RED)"

**Test Specification:**

```solidity
// test/SecurityFixes/Remediation/test_minimum_billing.t.sol
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
// ... other imports

contract MinimumBillingTest is Test {
    // Constants
    uint256 constant PROOF_INTERVAL = 500;  // Session proofInterval
    uint256 constant MIN_PROVEN_TOKENS = 100;  // Contract minimum

    function setUp() public {
        // Deploy all contracts via proxy
        // Register host in NodeRegistry
        // Create session with proofInterval = 500
    }

    function test_RejectFirstProofBelowProofInterval() public {
        // Create session with proofInterval = 500
        // Advance time to satisfy rate limit
        // Try to submit proof with 100 tokens (below 500)
        // Expect revert: "First proof must meet proofInterval minimum"
    }

    function test_AcceptFirstProofMeetingProofInterval() public {
        // Create session with proofInterval = 500
        // Advance time
        // Submit proof with 500 tokens
        // Assert: tokensUsed == 500
    }

    function test_AcceptSubsequentProofsBelowProofInterval() public {
        // Create session with proofInterval = 500
        // Submit first proof: 500 tokens ✓
        // Advance time
        // Submit second proof: 150 tokens (>= MIN_PROVEN_TOKENS but < proofInterval)
        // Assert: tokensUsed == 650
    }

    function test_EnforceMinimumBillingAtCompletion() public {
        // Edge case: somehow tokensUsed < proofInterval at completion
        // (This shouldn't happen with Option A, but test fallback)
        // Create session, submit proof meeting proofInterval
        // Complete session
        // Verify host payment uses max(tokensUsed, proofInterval)
    }

    function test_NormalCompletionNoAdjustment() public {
        // Create session with proofInterval = 500
        // Submit proof: 1000 tokens
        // Complete session
        // Verify hostPayment based on 1000 (not padded)
    }

    function test_EarlyCancellationUnaffected() public {
        // Create session
        // Complete WITHOUT submitting any proofs (depositor early cancel)
        // Verify early cancellation fee logic applies (minTokensFee)
        // Verify proofInterval padding does NOT apply (no proofs)
    }
}
```

**Expected Test Failures (RED):**

| Test | Expected Failure |
|------|------------------|
| `test_RejectFirstProofBelowProofInterval` | No revert (currently accepts 100 tokens) |
| `test_EnforceMinimumBillingAtCompletion` | hostPayment based on tokensUsed, not padded |

---

## Phase 2: Primary Enforcement

### Sub-phase 2.1: First Proof Validation in submitProofOfWork

**Severity**: Feature Enhancement
**Location**: `src/JobMarketplaceWithModelsUpgradeable.sol` line 630

**File Limits (Bounded Autonomy)**:
- New code: 6 lines max (the require block)
- No other modifications to submitProofOfWork

**Tasks:**
- [ ] Read current `submitProofOfWork` implementation (lines 619-670)
- [ ] Add first-proof validation after line 629's MIN_PROVEN_TOKENS check
- [ ] Run tests, verify `test_RejectFirstProofBelowProofInterval` PASSES
- [ ] Verify `test_AcceptFirstProofMeetingProofInterval` PASSES
- [ ] Verify `test_AcceptSubsequentProofsBelowProofInterval` PASSES
- [ ] Verify all existing tests still pass
- [ ] Commit: "feat(minimum-billing): enforce proofInterval on first proof (GREEN)"

**Implementation (6 lines):**

```solidity
// src/JobMarketplaceWithModelsUpgradeable.sol
// Insert AFTER line 629: require(tokensClaimed >= MIN_PROVEN_TOKENS, "Min tokens required");

// First proof must meet proofInterval for minimum billing
if (session.tokensUsed == 0) {
    require(
        tokensClaimed >= session.proofInterval,
        "First proof must meet proofInterval minimum"
    );
}
```

**Files Modified:**
- `src/JobMarketplaceWithModelsUpgradeable.sol` (line 630, +6 lines)

---

## Phase 3: Fallback Enforcement

### Sub-phase 3.1: Minimum Billing in _settleSessionPayments

**Severity**: Defense in Depth
**Location**: `src/JobMarketplaceWithModelsUpgradeable.sol` line 721

**File Limits (Bounded Autonomy)**:
- New code: 5 lines max (the padding logic)
- Modify hostPayment calculation only

**Tasks:**
- [ ] Read current `_settleSessionPayments` implementation (lines 718-762)
- [ ] Add billableTokens calculation with proofInterval padding
- [ ] Ensure early cancellation logic (line 724) is NOT affected
- [ ] Run tests, verify `test_EnforceMinimumBillingAtCompletion` PASSES
- [ ] Verify `test_NormalCompletionNoAdjustment` PASSES
- [ ] Verify `test_EarlyCancellationUnaffected` PASSES
- [ ] Verify all existing tests still pass
- [ ] Commit: "feat(minimum-billing): add completion fallback for edge cases (GREEN)"

**Implementation (5 lines):**

```solidity
// src/JobMarketplaceWithModelsUpgradeable.sol
// REPLACE line 721:
// OLD: uint256 hostPayment = (session.tokensUsed * session.pricePerToken) / PRICE_PRECISION;
// NEW:

// Enforce minimum billing at completion (fallback for edge cases)
// Only apply if at least one proof submitted (don't affect early cancellation)
uint256 billableTokens = session.tokensUsed;
if (billableTokens < session.proofInterval && session.proofs.length > 0) {
    billableTokens = session.proofInterval;
}

uint256 hostPayment = (billableTokens * session.pricePerToken) / PRICE_PRECISION;
```

**Files Modified:**
- `src/JobMarketplaceWithModelsUpgradeable.sol` (line 721, +4 lines net)

**Interaction with Existing Logic:**

```
Line 724: if (completedBy == session.depositor && session.proofs.length == 0 && minTokensFee > 0)
```

The early cancellation logic only triggers when `session.proofs.length == 0`, so our padding logic (which requires `session.proofs.length > 0`) does NOT conflict.

---

## Phase 4: Deployment

### Sub-phase 4.1: Deploy and Upgrade

**Tasks:**
- [ ] Run full test suite: `forge test`
- [ ] Verify all tests pass (expected: ~400+ tests)
- [ ] Build contracts: `forge build`
- [ ] Deploy new JobMarketplace implementation
- [ ] Upgrade proxy at `0x95132177F964FF053C1E874b53CF74d819618E06`
- [ ] Verify upgrade via cast call
- [ ] Commit: "deploy(minimum-billing): upgrade JobMarketplace on Base Sepolia"

**Deployment Commands:**

```bash
source /workspace/.env

# Deploy new implementation
forge script script/DeployJobMarketplaceImpl.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy

# Note the new implementation address from output

# Upgrade proxy
cast send 0x95132177F964FF053C1E874b53CF74d819618E06 \
  "upgradeToAndCall(address,bytes)" \
  $NEW_IMPL_ADDRESS 0x \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Verify upgrade
cast call 0x95132177F964FF053C1E874b53CF74d819618E06 \
  "MIN_PROVEN_TOKENS()" \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

---

### Sub-phase 4.2: Update Documentation and ABIs

**File Limits (Bounded Autonomy)**:
- ABI: Auto-generated (no limit)
- CLAUDE.md: Update implementation address only (~2 lines)

**Tasks:**
- [ ] Extract updated ABI: `jq '.abi' out/JobMarketplaceWithModelsUpgradeable.sol/JobMarketplaceWithModelsUpgradeable.json > client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json`
- [ ] Update CLAUDE.md with new implementation address
- [ ] Verify no SDK breaking changes (function signatures unchanged)
- [ ] Commit: "docs(minimum-billing): update ABIs and implementation address"

**Files Modified:**
- `client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json`
- `CLAUDE.md` (implementation address)

---

## Verification Checklist

After all phases complete:

- [ ] All new tests pass
- [ ] All existing tests pass (no regressions)
- [ ] First proof with tokens < proofInterval reverts
- [ ] First proof with tokens >= proofInterval succeeds
- [ ] Subsequent proofs can be >= MIN_PROVEN_TOKENS (100)
- [ ] Completion pads billing to proofInterval (if proofs exist)
- [ ] Early cancellation logic unchanged
- [ ] Contract deployed and upgraded on Base Sepolia
- [ ] ABI and documentation updated

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Non-compliant nodes get tx reverts | Medium | Low | Node v8.14.2+ already pads correctly |
| Existing sessions affected | None | None | Only new submissions after upgrade |
| Event changes break integrations | None | None | Events unchanged |
| Early cancellation broken | High | Low | Guarded by `session.proofs.length > 0` check |

---

## Backward Compatibility

| Aspect | Status | Notes |
|--------|--------|-------|
| ABI | ✅ Compatible | No function signature changes |
| Events | ✅ Compatible | SessionCompleted unchanged |
| Existing sessions | ✅ Unaffected | Only new proof submissions affected |
| Node v8.14.2+ | ✅ Compatible | Already pads to proofInterval |
| Node < v8.14.2 | ⚠️ Breaking | First proof will revert if < proofInterval |

---

## Notes

### TDD Approach

Each sub-phase follows strict TDD with bounded autonomy:
1. Write tests FIRST (show them failing - RED)
2. Implement minimal code to pass tests (GREEN)
3. Refactor if needed while keeping tests green
4. Verify all tests pass
5. Mark sub-phase complete with `x`

### File Limits (Bounded Autonomy)

| File Type | Max Lines |
|-----------|-----------|
| Test files | No limit |
| New implementation code (per sub-phase) | 10 lines |
| Modified functions | Keep changes minimal |
| Commit after each sub-phase | Required |

### Why Both Options?

| Option | Purpose |
|--------|---------|
| Option A (submitProofOfWork) | Primary enforcement - prevents undercharging at submission |
| Option B (_settleSessionPayments) | Fallback - catches edge cases and future code paths |

Defense in depth ensures minimum billing regardless of how the session ends.
