# Implementation: Add deltaCID to submitProofOfWork

**Implementation Date:** January 14, 2026
**Feature Branch:** `feature/deltacid-proof-tracking`
**Network:** Base Sepolia (Chain ID: 84532)
**Methodology:** Strict TDD with Bounded Autonomy

---

## Executive Summary

Add `deltaCID` parameter to `submitProofOfWork` function and `ProofSubmitted` event to support delta CID tracking for incremental proof storage. This enables SDK developers to track delta changes between proof submissions.

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Write Tests First (RED) | ✅ Complete |
| Phase 2 | Contract Implementation (GREEN) | ✅ Complete |
| Phase 3 | Update Existing Tests | Pending |
| Phase 4 | Deployment | Pending |
| Phase 5 | Documentation & ABI Export | Pending |

**Breaking Changes:**
- `submitProofOfWork` signature: 5 → 6 parameters
- `getProofSubmission` return tuple: 4 → 5 values
- `ProofSubmitted` event: 5 → 6 fields

---

## Phase 1: Write Tests First (RED)

### Sub-phase 1.1: Create deltaCID Test File

**Scope:** `test/JobMarketplace/test_deltaCID.t.sol`
**Line Limit:** No limit on test files

| Task | Status | Description |
|------|--------|-------------|
| [x] | Create test file | `test/JobMarketplace/test_deltaCID.t.sol` |
| [x] | Add test setup | Standard UUPS proxy deployment pattern |
| [x] | Write `test_ProofSubmittedEventIncludesDeltaCID` | Verify event emission includes deltaCID |
| [x] | Write `test_DeltaCIDStoredInProofSubmission` | Verify deltaCID is stored and retrievable |
| [x] | Write `test_MultipleProofsWithDifferentDeltaCIDs` | Verify each proof stores unique deltaCID |
| [x] | Write `test_EmptyDeltaCIDAllowed` | Verify empty string deltaCID is accepted |
| [x] | Write `test_GetProofSubmissionReturnsDeltaCID` | Verify getter returns correct deltaCID |

**Test Template:**
```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/JobMarketplaceWithModelsUpgradeable.sol";
// ... other imports

contract DeltaCIDTest is Test {
    // Test: Event includes deltaCID
    function test_ProofSubmittedEventIncludesDeltaCID() public {
        // Setup session
        // Expect emit with deltaCID
        // Submit proof with deltaCID
    }

    // Test: deltaCID stored in struct
    function test_DeltaCIDStoredInProofSubmission() public {
        // Submit proof with deltaCID
        // Call getProofSubmission
        // Assert deltaCID matches
    }

    // Test: Multiple proofs with different deltaCIDs
    function test_MultipleProofsWithDifferentDeltaCIDs() public {
        // Submit 3 proofs with different deltaCIDs
        // Verify each stored correctly
    }

    // Test: Empty deltaCID allowed
    function test_EmptyDeltaCIDAllowed() public {
        // Submit proof with empty deltaCID
        // Should not revert
    }

    // Test: Getter returns deltaCID
    function test_GetProofSubmissionReturnsDeltaCID() public {
        // Submit proof
        // Call getProofSubmission
        // Verify 5th return value is deltaCID
    }
}
```

### Sub-phase 1.2: Verify Tests Fail (RED)

| Task | Status | Description |
|------|--------|-------------|
| [x] | Run new tests | `forge test --match-path test/JobMarketplace/test_deltaCID.t.sol -vvv` |
| [x] | Verify compilation fails | Tests should fail to compile (function signature mismatch) |
| [x] | Document failure reason | "Wrong argument count: 6 given but expected 5" |

**Verification Command:**
```bash
forge test --match-path test/JobMarketplace/test_deltaCID.t.sol -vvv 2>&1 | head -50
# Expected: Compilation error - function signature mismatch
```

---

## Phase 2: Contract Implementation (GREEN)

### Sub-phase 2.1: Update ProofSubmission Struct

**Scope:** `src/JobMarketplaceWithModelsUpgradeable.sol` (Lines 47-52)
**Line Limit:** 75 lines for components

| Task | Status | Description |
|------|--------|-------------|
| [x] | Add `deltaCID` field | `string deltaCID;` as 5th field in struct |

**Before:**
```solidity
struct ProofSubmission {
    bytes32 proofHash;
    uint256 tokensClaimed;
    uint256 timestamp;
    bool verified;
}
```

**After:**
```solidity
struct ProofSubmission {
    bytes32 proofHash;
    uint256 tokensClaimed;
    uint256 timestamp;
    bool verified;
    string deltaCID;  // NEW: Delta CID for incremental proof storage
}
```

### Sub-phase 2.2: Update ProofSubmitted Event

**Scope:** `src/JobMarketplaceWithModelsUpgradeable.sol` (Lines 149-151)

| Task | Status | Description |
|------|--------|-------------|
| [x] | Add `deltaCID` parameter | `string deltaCID` as 6th event field |

**Before:**
```solidity
event ProofSubmitted(
    uint256 indexed jobId, address indexed host, uint256 tokensClaimed, bytes32 proofHash, string proofCID
);
```

**After:**
```solidity
event ProofSubmitted(
    uint256 indexed jobId, address indexed host, uint256 tokensClaimed, bytes32 proofHash, string proofCID, string deltaCID
);
```

### Sub-phase 2.3: Update submitProofOfWork Function

**Scope:** `src/JobMarketplaceWithModelsUpgradeable.sol` (Lines 576-629)

| Task | Status | Description |
|------|--------|-------------|
| [x] | Add `deltaCID` parameter | `string calldata deltaCID` as 6th parameter |
| [x] | Update struct push | Include `deltaCID: deltaCID` in ProofSubmission |
| [x] | Update event emission | Include `deltaCID` in ProofSubmitted emit |

**Function Signature Change:**
```solidity
// Before
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes32 proofHash,
    bytes calldata signature,
    string calldata proofCID
) external nonReentrant whenNotPaused

// After
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes32 proofHash,
    bytes calldata signature,
    string calldata proofCID,
    string calldata deltaCID  // NEW
) external nonReentrant whenNotPaused
```

**Struct Push Change (Lines 616-622):**
```solidity
// Before
session.proofs.push(
    ProofSubmission({
        proofHash: proofHash,
        tokensClaimed: tokensClaimed,
        timestamp: block.timestamp,
        verified: verified
    })
);

// After
session.proofs.push(
    ProofSubmission({
        proofHash: proofHash,
        tokensClaimed: tokensClaimed,
        timestamp: block.timestamp,
        verified: verified,
        deltaCID: deltaCID  // NEW
    })
);
```

**Event Emission Change (Line 628):**
```solidity
// Before
emit ProofSubmitted(jobId, msg.sender, tokensClaimed, proofHash, proofCID);

// After
emit ProofSubmitted(jobId, msg.sender, tokensClaimed, proofHash, proofCID, deltaCID);
```

### Sub-phase 2.4: Update getProofSubmission Function

**Scope:** `src/JobMarketplaceWithModelsUpgradeable.sol` (Lines 993-1002)

| Task | Status | Description |
|------|--------|-------------|
| [x] | Add `deltaCID` to return tuple | `string memory deltaCID` as 5th return value |
| [x] | Update return statement | Include `proof.deltaCID` |

**Before:**
```solidity
function getProofSubmission(uint256 sessionId, uint256 proofIndex)
    external
    view
    returns (bytes32 proofHash, uint256 tokensClaimed, uint256 timestamp, bool verified)
{
    SessionJob storage session = sessionJobs[sessionId];
    require(proofIndex < session.proofs.length, "Proof index out of bounds");
    ProofSubmission storage proof = session.proofs[proofIndex];
    return (proof.proofHash, proof.tokensClaimed, proof.timestamp, proof.verified);
}
```

**After:**
```solidity
function getProofSubmission(uint256 sessionId, uint256 proofIndex)
    external
    view
    returns (bytes32 proofHash, uint256 tokensClaimed, uint256 timestamp, bool verified, string memory deltaCID)
{
    SessionJob storage session = sessionJobs[sessionId];
    require(proofIndex < session.proofs.length, "Proof index out of bounds");
    ProofSubmission storage proof = session.proofs[proofIndex];
    return (proof.proofHash, proof.tokensClaimed, proof.timestamp, proof.verified, proof.deltaCID);
}
```

### Sub-phase 2.5: Verify Tests Pass (GREEN)

| Task | Status | Description |
|------|--------|-------------|
| [x] | Run deltaCID tests | Contract compiles with `forge build --skip test` |
| [ ] | Verify all pass | All 5 tests should pass |

**Verification Command:**
```bash
forge test --match-path test/JobMarketplace/test_deltaCID.t.sol -vvv
# Expected: All tests pass
```

---

## Phase 3: Update Existing Tests

### Sub-phase 3.1: Update submitProofOfWork Calls

**Scope:** All test files calling `submitProofOfWork` (add 6th parameter `""`)

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Update `test/Integration/test_proof_verification_e2e.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Integration/test_full_session_lifecycle.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Integration/test_fund_safety.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Integration/test_host_validation_e2e.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/SecurityFixes/JobMarketplace/test_balance_separation.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/SecurityFixes/JobMarketplace/test_double_spend_prevention.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/SecurityFixes/JobMarketplace/test_legacy_removal.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/SecurityFixes/JobMarketplace/test_proof_signature_required.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/SecurityFixes/JobMarketplace/test_proofsystem_integration.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Upgradeable/JobMarketplace/test_upgrade.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Upgradeable/JobMarketplace/test_pause.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Upgradeable/Integration/test_deploy_all.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Upgradeable/Integration/test_full_flow.t.sol` | Add `""` as 6th parameter |
| [ ] | Update `test/Upgradeable/Integration/test_upgrade_flow.t.sol` | Add `""` as 6th parameter |

**Update Pattern:**
```solidity
// Before
marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProofCID");

// After
marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProofCID", "");
```

### Sub-phase 3.2: Update getProofSubmission Tuple Unpacking

**Scope:** Test files using `getProofSubmission` (add 5th return value wildcard)

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Update `test/Integration/test_proof_verification_e2e.t.sol` | Add 5th wildcard `_` |
| [ ] | Update `test/SecurityFixes/JobMarketplace/test_proofsystem_integration.t.sol` | Add 5th wildcard `_` |

**Update Pattern:**
```solidity
// Before (4 values)
(bytes32 storedHash, uint256 storedTokens, , bool verified) =
    marketplace.getProofSubmission(sessionId, 0);

// After (5 values)
(bytes32 storedHash, uint256 storedTokens, , bool verified, ) =
    marketplace.getProofSubmission(sessionId, 0);
```

### Sub-phase 3.3: Run Full Test Suite

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Run full test suite | `forge test -vvv` |
| [ ] | Verify all tests pass | 415+ tests should pass |
| [ ] | Document test count | Record total passing tests |

**Verification Command:**
```bash
forge test -vvv
# Expected: All tests pass (415+ tests)
```

---

## Phase 4: Deployment

### Sub-phase 4.1: Build and Deploy Implementation

**Prerequisites:**
- `BASE_SEPOLIA_RPC_URL` environment variable set
- `PRIVATE_KEY` environment variable set

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Build contracts | `forge build` |
| [ ] | Verify build clean | No compiler warnings in main contracts |
| [ ] | Deploy new implementation | Record deployed address |

**Commands:**
```bash
# Build
forge build

# Deploy new implementation
forge create src/JobMarketplaceWithModelsUpgradeable.sol:JobMarketplaceWithModelsUpgradeable \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --legacy

# Record: NEW_IMPL_ADDRESS=<deployed-address>
```

### Sub-phase 4.2: Upgrade Proxy

**Proxy Address:** `0x3CaCbf3f448B420918A93a88706B26Ab27a3523E`

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Upgrade proxy to new implementation | `upgradeToAndCall` |
| [ ] | Record upgrade transaction hash | For audit trail |

**Commands:**
```bash
# Upgrade proxy (owner only)
cast send 0x3CaCbf3f448B420918A93a88706B26Ab27a3523E \
  "upgradeToAndCall(address,bytes)" \
  <NEW_IMPL_ADDRESS> \
  0x \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

### Sub-phase 4.3: Verify Deployment

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Verify implementation address | `cast call` to check implementation |
| [ ] | Verify contract code exists | `cast code` check |
| [ ] | Test function signature | Verify submitProofOfWork accepts 6 params |

**Verification Commands:**
```bash
# Check implementation was updated
cast call 0x3CaCbf3f448B420918A93a88706B26Ab27a3523E \
  "implementation()" \
  --rpc-url "https://sepolia.base.org"
# Expected: Returns new implementation address

# Verify contract code exists at new implementation
cast code <NEW_IMPL_ADDRESS> --rpc-url "https://sepolia.base.org"
# Expected: Non-empty bytecode
```

---

## Phase 5: Documentation & ABI Export

### Sub-phase 5.1: Export Client ABI

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Extract ABI from build output | `jq '.abi'` |
| [ ] | Save to client-abis directory | Update existing file |

**Command:**
```bash
cat out/JobMarketplaceWithModelsUpgradeable.sol/JobMarketplaceWithModelsUpgradeable.json \
  | jq '.abi' > client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json
```

### Sub-phase 5.2: Update CONTRACT_ADDRESSES.md

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Add new implementation address | Under JobMarketplace section |
| [ ] | Update "Last Updated" date | January 14, 2026 |
| [ ] | Add deployment notes | deltaCID feature addition |

### Sub-phase 5.3: Update client-abis Documentation

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Update `client-abis/README.md` | Document deltaCID changes |
| [ ] | Update `client-abis/CHANGELOG.md` | Add entry for deltaCID |

**CHANGELOG Entry:**
```markdown
## [2026-01-14] - deltaCID Support

### Added
- `submitProofOfWork` now accepts 6th parameter: `deltaCID` (string)
- `getProofSubmission` now returns 5th value: `deltaCID` (string)
- `ProofSubmitted` event now includes `deltaCID` field

### Breaking Changes
- SDK must be updated to pass `deltaCID` parameter to `submitProofOfWork`
- SDK must handle 5-value tuple from `getProofSubmission`
```

### Sub-phase 5.4: Update CLAUDE.md

| Task | Status | Description |
|------|--------|-------------|
| [ ] | Update implementation address | New JobMarketplace implementation |
| [ ] | Update submitProofOfWork docs | Add deltaCID parameter |

---

## Completion Checklist

### Phase 1 Criteria
- [ ] Test file created with 5 tests
- [ ] Tests fail to compile (expected - RED phase)

### Phase 2 Criteria
- [ ] ProofSubmission struct has deltaCID field
- [ ] ProofSubmitted event has deltaCID parameter
- [ ] submitProofOfWork accepts 6 parameters
- [ ] getProofSubmission returns 5 values
- [ ] New tests pass (GREEN phase)

### Phase 3 Criteria
- [ ] All 14 test files updated with 6th parameter
- [ ] All 2 test files updated with 5th return value
- [ ] Full test suite passes (415+ tests)

### Phase 4 Criteria
- [ ] New implementation deployed
- [ ] Proxy upgraded
- [ ] Deployment verified on-chain

### Phase 5 Criteria
- [ ] Client ABI exported
- [ ] CONTRACT_ADDRESSES.md updated
- [ ] client-abis documentation updated
- [ ] CLAUDE.md updated

---

## Appendix: Files Modified

| File | Type | Changes |
|------|------|---------|
| `src/JobMarketplaceWithModelsUpgradeable.sol` | Contract | Struct, event, 2 functions |
| `test/JobMarketplace/test_deltaCID.t.sol` | Test | New file (5 tests) |
| `test/Integration/test_proof_verification_e2e.t.sol` | Test | submitProofOfWork + getProofSubmission |
| `test/Integration/test_full_session_lifecycle.t.sol` | Test | submitProofOfWork calls |
| `test/Integration/test_fund_safety.t.sol` | Test | submitProofOfWork calls |
| `test/Integration/test_host_validation_e2e.t.sol` | Test | submitProofOfWork calls |
| `test/SecurityFixes/JobMarketplace/test_balance_separation.t.sol` | Test | submitProofOfWork calls |
| `test/SecurityFixes/JobMarketplace/test_double_spend_prevention.t.sol` | Test | submitProofOfWork calls |
| `test/SecurityFixes/JobMarketplace/test_legacy_removal.t.sol` | Test | submitProofOfWork calls |
| `test/SecurityFixes/JobMarketplace/test_proof_signature_required.t.sol` | Test | submitProofOfWork calls |
| `test/SecurityFixes/JobMarketplace/test_proofsystem_integration.t.sol` | Test | submitProofOfWork + getProofSubmission |
| `test/Upgradeable/JobMarketplace/test_upgrade.t.sol` | Test | submitProofOfWork calls |
| `test/Upgradeable/JobMarketplace/test_pause.t.sol` | Test | submitProofOfWork calls |
| `test/Upgradeable/Integration/test_deploy_all.t.sol` | Test | submitProofOfWork calls |
| `test/Upgradeable/Integration/test_full_flow.t.sol` | Test | submitProofOfWork calls |
| `test/Upgradeable/Integration/test_upgrade_flow.t.sol` | Test | submitProofOfWork calls |
| `client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json` | ABI | Updated |
| `client-abis/README.md` | Docs | Updated |
| `client-abis/CHANGELOG.md` | Docs | Updated |
| `CONTRACT_ADDRESSES.md` | Docs | New implementation address |
| `CLAUDE.md` | Docs | Implementation address + submitProofOfWork |

---

**Date:** January 14, 2026
**Version:** 1.0
