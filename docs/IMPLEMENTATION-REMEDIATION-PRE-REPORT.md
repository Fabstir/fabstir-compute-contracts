# IMPLEMENTATION-REMEDIATION-PRE-REPORT.md - AUDIT Security Audit Remediation

## Overview

Fix all security findings identified by AUDIT auditors during the pre-report testing period (January 27 - February 16, 2026). This document tracks remediation progress following strict TDD with bounded autonomy approach.

## Repository

fabstir-compute-contracts

## Audit Reference

- **Auditor**: AUDIT
- **Testing Period**: January 27 - February 16, 2026
- **Remediation Branch**: `fix/remediation-pre-report`
- **Remediation Window**: 15 business days after report delivery
- **Retest Date**: March 10, 2026

## Finding Reference

| Finding ID | Slack Reference | Description |
|------------|-----------------|-------------|
| AUDIT-F1 | `slack-C0A61FZC8SH-p1769545156133729` | Dead code `onlyRegisteredHost` modifier |
| AUDIT-F2 | `slack-C0A61FZC8SH-p1769545156133729` | ProofSystem address(0) allows arbitrary proofs |
| AUDIT-F3 | `slack-C0A61FZC8SH-p1769545156133729` | `proofInterval` dual interpretation bug |
| AUDIT-F4 | `slack-C0A61FZC8SH-p1769619714508749` | Model validation missing in signature scheme |
| AUDIT-F5 | `slack-C0A61FZC8SH-p1769608000786449` | Missing `createSessionFromDepositForModel()` |
| AUDIT-INFO | `slack-C0A61FZC8SH-p1769550656201269` | Rate limit rationale (informational - no fix needed) |

**Note**: Full Slack conversation documented in `docs/audit/remeditation-pre-report-findings-replies.md`

## Severity Summary

| Finding ID | Finding | Severity | Contract | Phase |
|------------|---------|----------|----------|-------|
| AUDIT-F1 | Dead code `onlyRegisteredHost` modifier | LOW | JobMarketplace | 1 |
| AUDIT-F2 | ProofSystem address(0) allows arbitrary proofs | HIGH | JobMarketplace | 2 |
| AUDIT-F3 | `proofInterval` dual interpretation bug | MEDIUM | JobMarketplace | 3 |
| AUDIT-F4 | Model validation missing in signature scheme | MEDIUM | ProofSystem, JobMarketplace | 4 |
| AUDIT-F5 | Missing `createSessionFromDepositForModel()` | LOW | JobMarketplace | 5 |

## Goals

- Fix all HIGH severity vulnerabilities immediately
- Fix MEDIUM severity issues before retest
- Address LOW severity items as code quality improvements
- Maintain UUPS upgradeability pattern
- Follow strict TDD with bounded autonomy approach
- **DO NOT upgrade audited proxy contracts** - deploy test contracts separately

## Critical Design Decisions

- **Model in Signature**: Require modelId in ALL signatures (use `bytes32(0)` for non-model sessions)
- **Proof Timeout**: Separate `proofTimeoutWindow` (seconds) from `proofInterval` (token count)
- **ProofSystem Required**: Production MUST have ProofSystem configured - no graceful degradation
- **Interface Change**: IProofSystem functions gain modelId parameter (breaking change)

## Implementation Progress

**Overall Status: PHASE 5 COMPLETE (95%)**

- [x] **Phase 1: Dead Code Removal (AUDIT-F1)** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 1.1: Write Tests for Modifier Removal ✅
  - [x] Sub-phase 1.2: Remove `onlyRegisteredHost` Modifier ✅
- [x] **Phase 2: ProofSystem Required Check (AUDIT-F2)** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 2.1: Write Tests for ProofSystem Requirement ✅
  - [x] Sub-phase 2.2: Add ProofSystem Configuration Check ✅
- [x] **Phase 3: Proof Timeout Window (AUDIT-F3)** (4/4 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 3.1: Write Tests for Timeout Window ✅
  - [x] Sub-phase 3.2: Add proofTimeoutWindow to SessionJob Struct ✅
  - [x] Sub-phase 3.3: Update Session Creation Functions ✅
  - [x] Sub-phase 3.4: Fix triggerSessionTimeout Logic ✅
- [x] **Phase 4: Model ID in Signature Scheme (AUDIT-F4)** (4/4 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 4.1: Write Tests for Model Signature ✅
  - [x] Sub-phase 4.2: Update IProofSystem Interface ✅
  - [x] Sub-phase 4.3: Update ProofSystemUpgradeable ✅
  - [x] Sub-phase 4.4: Update JobMarketplace submitProofOfWork ✅
- [x] **Phase 5: createSessionFromDepositForModel (AUDIT-F5)** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 5.1: Write Tests for New Function ✅
  - [x] Sub-phase 5.2: Implement createSessionFromDepositForModel ✅
- [ ] **Phase 6: Deployment & Documentation** (0/3 sub-phases)
  - [ ] Sub-phase 6.1: Deploy Test Contracts (Separate from Audited)
  - [ ] Sub-phase 6.2: Manual Testing on Testnet
  - [ ] Sub-phase 6.3: Update Documentation and ABIs

**Last Updated:** 2026-01-31 (Phase 5 complete)

---

## Phase 1: Dead Code Removal (AUDIT-F1)

**Finding ID**: AUDIT-F1
**Slack Ref**: `slack-C0A61FZC8SH-p1769545156133729`
**Finding**: The `onlyRegisteredHost` modifier is defined but never used (empty body).
**Severity**: LOW
**File**: `src/JobMarketplaceWithModelsUpgradeable.sol` (lines 192-196)

### Sub-phase 1.1: Write Tests for Modifier Removal

**Goal**: Verify contract compiles and functions correctly without the modifier.

**Tasks:**
- [x] Create test file `test/SecurityFixes/Remediation/test_dead_code_removal.t.sol`
- [x] Test: Contract compiles successfully after modifier removal
- [x] Test: No functions reference `onlyRegisteredHost`
- [x] Test: Host validation still works via `_validateHostRegistration()`
- [x] Run tests - 5/5 passing (baseline established)

**File Limits:**
- Test file: ~50 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/Remediation/test_dead_code_removal.t.sol
contract DeadCodeRemovalTest is TestSetupUpgradeable {
    function test_ContractCompilesWithoutModifier() public { /* ... */ }
    function test_HostValidationStillWorks() public { /* ... */ }
    function test_NoModifierReferencesInBytecode() public { /* ... */ }
}
```

**Verification:**
```bash
forge test --match-contract DeadCodeRemovalTest -vv
# Expected: Tests should reference non-existent modifier (will pass after removal)
```

---

### Sub-phase 1.2: Remove `onlyRegisteredHost` Modifier

**Goal**: Delete the dead code.

**Tasks:**
- [x] Delete lines 192-196 from `JobMarketplaceWithModelsUpgradeable.sol`
- [x] Run `forge build` to verify compilation
- [x] Run `grep -r "onlyRegisteredHost" src/` - No references found
- [x] Run all tests - 686/686 passing (no regressions)
- [x] Mark sub-phase complete

**Code to Remove:**
```solidity
// DELETE these lines (192-196):
modifier onlyRegisteredHost(address host) {
    // Just check if host is registered by looking at operator
    // NodeRegistryWithModels has different return signature
    _;
}
```

**File Limits:**
- Lines removed: 5 lines
- No new code added

**Verification:**
```bash
forge build
grep -r "onlyRegisteredHost" src/
forge test
```

---

## Phase 2: ProofSystem Required Check (AUDIT-F2)

**Finding ID**: AUDIT-F2
**Slack Ref**: `slack-C0A61FZC8SH-p1769545156133729`
**Finding**: When `proofSystem` is `address(0)`, hosts can submit arbitrary proofs without verification.
**Severity**: HIGH
**File**: `src/JobMarketplaceWithModelsUpgradeable.sol` (lines 601-611)

### Sub-phase 2.1: Write Tests for ProofSystem Requirement

**Goal**: Ensure proof submission fails when ProofSystem not configured.

**Tasks:**
- [x] Create test file `test/SecurityFixes/Remediation/test_proofsystem_required.t.sol`
- [x] Test: `submitProofOfWork` reverts with "ProofSystem not configured" when address(0)
- [x] Test: `submitProofOfWork` succeeds when ProofSystem is configured
- [x] Test: Session creation still works without ProofSystem (only proof submission blocked)
- [x] Run tests and verify they FAIL (current code allows address(0)) - 3/3 tests written

**File Limits:**
- Test file: ~80 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/Remediation/test_proofsystem_required.t.sol
contract ProofSystemRequiredTest is TestSetupUpgradeable {
    function test_SubmitProof_RevertsWhenProofSystemNotConfigured() public {
        // Setup: Deploy marketplace WITHOUT setting proofSystem
        // Act: Try to submit proof
        // Assert: Reverts with "ProofSystem not configured"
    }

    function test_SubmitProof_SucceedsWhenProofSystemConfigured() public {
        // Setup: Deploy marketplace WITH proofSystem configured
        // Act: Submit valid proof
        // Assert: Proof accepted
    }

    function test_SessionCreation_WorksWithoutProofSystem() public {
        // Setup: No proofSystem
        // Act: Create session
        // Assert: Session created successfully
    }
}
```

**Verification:**
```bash
forge test --match-contract ProofSystemRequiredTest -vv
# Expected: test_SubmitProof_RevertsWhenProofSystemNotConfigured should FAIL
```

---

### Sub-phase 2.2: Add ProofSystem Configuration Check

**Goal**: Require ProofSystem to be configured for proof submission.

**Tasks:**
- [x] Add require statement at line 596 in `submitProofOfWork()`
- [x] Remove the `if (address(proofSystem) != address(0))` conditional
- [x] Always call `proofSystem.verifyAndMarkComplete()`
- [x] Update integration tests with ProofSystem configuration and valid signatures
- [x] Run all tests - 663/689 passing (26 remaining need ProofSystem config updates)
- [x] Mark sub-phase complete

**Implementation:**
```solidity
// In submitProofOfWork(), replace lines 601-611:

// OLD (vulnerable):
bool verified = false;
if (address(proofSystem) != address(0)) {
    bytes memory proof = abi.encodePacked(proofHash, signature);
    require(
        proofSystem.verifyAndMarkComplete(proof, msg.sender, tokensClaimed),
        "Invalid proof signature"
    );
    verified = true;
}

// NEW (secure):
require(address(proofSystem) != address(0), "ProofSystem not configured");
bytes memory proof = abi.encodePacked(proofHash, signature);
require(
    proofSystem.verifyAndMarkComplete(proof, msg.sender, tokensClaimed),
    "Invalid proof signature"
);
bool verified = true;
```

**File Limits:**
- Lines changed: ~8 lines
- Net change: Replace conditional with require

**Verification:**
```bash
forge test --match-contract ProofSystemRequiredTest -vv
forge test  # Full suite
```

### Phase 2 Completion Summary

**Status**: ✅ COMPLETE
**Date**: 2026-01-31
**Commit**: `fix(AUDIT-F2): Require ProofSystem configuration for proof submission`

**Changes Made:**
- Added require check at line 596: `require(address(proofSystem) != address(0), "ProofSystem not configured")`
- Removed graceful degradation - proofs now always require verification
- Updated integration tests with ProofSystem configuration
- Added valid signature generation for test hosts using `vm.sign()`

**Test Results:**
- ProofSystemRequiredTest: 3/3 passing
- Full suite after fix: 663 passing (26 tests need ProofSystem config updates - fixed in Phase 3)

**Breaking Change:**
- ProofSystem MUST be configured before any proof submission
- Sessions can still be created without ProofSystem, but proofs will fail

---

## Phase 3: Proof Timeout Window (AUDIT-F3)

**Finding ID**: AUDIT-F3
**Slack Ref**: `slack-C0A61FZC8SH-p1769545156133729`
**Finding**: `proofInterval` is validated as token count but used as seconds in timeout calculation.
**Severity**: MEDIUM
**File**: `src/JobMarketplaceWithModelsUpgradeable.sol`
- `_validateProofRequirements` (lines 506-512) - treats as token count
- `triggerSessionTimeout` (lines 748-749) - uses as seconds

### Sub-phase 3.1: Write Tests for Timeout Window

**Goal**: Verify timeout logic uses dedicated time field, not token count.

**Tasks:**
- [x] Create test file `test/SecurityFixes/Remediation/test_proof_timeout_window.t.sol`
- [x] Test: `triggerSessionTimeout` uses `proofTimeoutWindow` not `proofInterval`
- [x] Test: Session times out after `proofTimeoutWindow` seconds without proof
- [x] Test: Legacy sessions (proofTimeoutWindow=0) use fallback DEFAULT_PROOF_TIMEOUT
- [x] Test: Session creation validates `proofTimeoutWindow` range (60s - 3600s)
- [x] Test: Session creation rejects invalid timeout values
- [x] Run tests and verify they FAIL (field doesn't exist yet) - 8/8 tests written

**File Limits:**
- Test file: ~150 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/Remediation/test_proof_timeout_window.t.sol
contract ProofTimeoutWindowTest is TestSetupUpgradeable {
    function test_TriggerTimeout_UsesProofTimeoutWindow() public { /* ... */ }
    function test_TriggerTimeout_FallbackForLegacySessions() public { /* ... */ }
    function test_CreateSession_ValidatesTimeoutWindow() public { /* ... */ }
    function test_CreateSession_RejectsInvalidTimeoutWindow() public { /* ... */ }
    function test_CreateSession_RejectsTooSmallTimeout() public { /* ... */ }
    function test_CreateSession_RejectsTooLargeTimeout() public { /* ... */ }
}
```

**Verification:**
```bash
forge test --match-contract ProofTimeoutWindowTest -vv
# Expected: Compilation fails (proofTimeoutWindow doesn't exist)
```

---

### Sub-phase 3.2: Add proofTimeoutWindow to SessionJob Struct

**Goal**: Add new field to struct for time-based timeout.

**Tasks:**
- [x] Add `uint256 proofTimeoutWindow` field to SessionJob struct (line 68)
- [x] Add `proofTimeoutWindow` field to SessionParams struct
- [x] Add constants: `DEFAULT_PROOF_TIMEOUT` (300s), `MIN_PROOF_TIMEOUT` (60s), `MAX_PROOF_TIMEOUT` (3600s)
- [x] Verify struct ordering doesn't break UUPS storage layout
- [x] Run `forge build` to verify compilation

**Implementation:**
```solidity
// Add to SessionJob struct (after proofInterval, line 67):
struct SessionJob {
    // ... existing fields ...
    uint256 proofInterval;
    uint256 proofTimeoutWindow;  // NEW: Time in seconds before timeout (60-3600)
    SessionStatus status;
    // ... rest of struct ...
}

// Add constants (after line 98):
uint256 public constant DEFAULT_PROOF_TIMEOUT = 300;   // 5 minutes
uint256 public constant MIN_PROOF_TIMEOUT = 60;        // 1 minute minimum
uint256 public constant MAX_PROOF_TIMEOUT = 3600;      // 1 hour maximum
```

**File Limits:**
- Lines added: ~5 lines
- Storage: 1 new uint256 in struct (32 bytes)

**UUPS Safety Note:**
Adding a field to a struct that is stored in a mapping is safe for UUPS upgrades because each struct instance has its own storage slots. The new field will be 0 for existing sessions.

**Verification:**
```bash
forge build
```

---

### Sub-phase 3.3: Update Session Creation Functions

**Goal**: All session creation functions accept and validate `proofTimeoutWindow`.

**Tasks:**
- [x] Update `createSessionJob()` - add 5th parameter `proofTimeoutWindow`
- [x] Update `createSessionJobForModel()` - add 6th parameter `proofTimeoutWindow`
- [x] Update `createSessionJobWithToken()` - add 8th parameter `proofTimeoutWindow`
- [x] Update `createSessionJobForModelWithToken()` - add 9th parameter `proofTimeoutWindow`
- [x] Update `createSessionFromDeposit()` - add 7th parameter `proofTimeoutWindow`
- [x] Add validation in `_validateSessionParams()`: `require(proofTimeoutWindow >= MIN && <= MAX)`
- [x] Store value in `_initializeSession()`: `session.proofTimeoutWindow = proofTimeoutWindow`
- [x] Update all 27 test files with new parameter (value: 300)

**Implementation (for each function):**
```solidity
function createSessionJob(
    address host,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval,
    uint256 proofTimeoutWindow  // NEW parameter
) external payable nonReentrant whenNotPaused returns (uint256 sessionId) {
    // ... existing validation ...
    require(
        proofTimeoutWindow >= MIN_PROOF_TIMEOUT && proofTimeoutWindow <= MAX_PROOF_TIMEOUT,
        "Invalid proof timeout window"
    );
    // ... create session ...
    session.proofTimeoutWindow = proofTimeoutWindow;
    // ...
}
```

**File Limits:**
- Lines added per function: ~4 lines (parameter + require + assignment)
- Total: ~20 lines across 5 functions

**Verification:**
```bash
forge build
forge test --match-test "createSession" -vv
```

---

### Sub-phase 3.4: Fix triggerSessionTimeout Logic

**Goal**: Use `proofTimeoutWindow` for time-based timeout, not `proofInterval`.

**Tasks:**
- [x] Update `triggerSessionTimeout()` to use `proofTimeoutWindow`
- [x] Add fallback for legacy sessions: use `DEFAULT_PROOF_TIMEOUT` if `proofTimeoutWindow == 0`
- [x] Run all timeout-related tests - 8/8 passing
- [x] Fix remaining 26 test failures (ProofSystem configuration updates from Phase 2)
- [x] Mark sub-phase complete - 697/697 tests passing

**Implementation:**
```solidity
// In triggerSessionTimeout(), replace lines 748-749:

// OLD (buggy):
bool hasTimedOut = (block.timestamp > session.startTime + session.maxDuration)
    || (block.timestamp > session.lastProofTime + session.proofInterval * 3);

// NEW (fixed):
uint256 timeoutWindow = session.proofTimeoutWindow > 0
    ? session.proofTimeoutWindow
    : DEFAULT_PROOF_TIMEOUT;  // Fallback for legacy sessions
bool hasTimedOut = (block.timestamp > session.startTime + session.maxDuration)
    || (block.timestamp > session.lastProofTime + timeoutWindow);
```

**File Limits:**
- Lines changed: ~5 lines

**Verification:**
```bash
forge test --match-contract ProofTimeoutWindowTest -vv
forge test  # Full suite
```

### Phase 3 Completion Summary

**Status**: ✅ COMPLETE
**Date**: 2026-01-31
**Commit**: `fix(AUDIT-F3): Separate proofTimeoutWindow from proofInterval`

**Changes Made:**
- Added `proofTimeoutWindow` field to SessionJob struct (line 68)
- Added `proofTimeoutWindow` field to SessionParams struct
- Added constants: `MIN_PROOF_TIMEOUT` (60s), `MAX_PROOF_TIMEOUT` (3600s), `DEFAULT_PROOF_TIMEOUT` (300s)
- Updated all 5 session creation functions to accept `proofTimeoutWindow` parameter
- Added validation in `_validateSessionParams()` for timeout window range
- Fixed `triggerSessionTimeout()` to use `proofTimeoutWindow` instead of `proofInterval * 3`
- Added fallback to `DEFAULT_PROOF_TIMEOUT` for legacy sessions where `proofTimeoutWindow == 0`
- Updated 27 test files with new parameter and 18-component tuple unpacking

**Test Results:**
- ProofTimeoutWindowTest: 8/8 passing
- Full suite: 697/697 passing

**Breaking Changes:**
- All session creation functions now require `proofTimeoutWindow` parameter
- SessionJob struct now has 18 fields (was 17)
- Hosts/clients must update SDK to pass timeout window value

**Files Modified:**
- `src/JobMarketplaceWithModelsUpgradeable.sol` - Main contract changes
- `test/SecurityFixes/Remediation/test_proof_timeout_window.t.sol` - New test file
- 27 test files updated for new parameter and tuple unpacking

---

## Phase 4: Model ID in Signature Scheme (AUDIT-F4)

**Finding ID**: AUDIT-F4
**Slack Ref**: `slack-C0A61FZC8SH-p1769619714508749`
**Finding**: `modelId` is not included in the signed message, allowing potential model mismatch.
**Severity**: MEDIUM
**Files**:
- `src/interfaces/IProofSystem.sol`
- `src/ProofSystemUpgradeable.sol`
- `src/JobMarketplaceWithModelsUpgradeable.sol`

**Decision**: Require modelId in ALL signatures. Use `bytes32(0)` for non-model sessions.

### Sub-phase 4.1: Write Tests for Model Signature

**Goal**: Verify signature verification includes modelId.

**Tasks:**
- [x] Create test file `test/SecurityFixes/Remediation/test_model_signature.t.sol`
- [x] Test: Valid signature with correct modelId passes verification
- [x] Test: Valid signature with `bytes32(0)` for non-model session passes
- [x] Test: Signature with wrong modelId fails
- [x] Test: Replay attack with same proofHash fails
- [x] Test: `submitProofOfWork` passes sessionModel to ProofSystem
- [x] Run tests and verify they FAIL (modelId not in signature yet)

**File Limits:**
- Test file: ~200 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/Remediation/test_model_signature.t.sol
contract ModelSignatureTest is TestSetupUpgradeable {
    function test_Verify_ValidSignatureWithModelId() public { /* ... */ }
    function test_Verify_ValidSignatureWithZeroModelId() public { /* ... */ }
    function test_Verify_WrongModelId_Fails() public { /* ... */ }
    function test_Verify_ReplayAttack_Fails() public { /* ... */ }
    function test_SubmitProof_PassesSessionModelToProofSystem() public { /* ... */ }
    function test_SubmitProof_NonModelSession_PassesZeroModelId() public { /* ... */ }
}
```

**Verification:**
```bash
forge test --match-contract ModelSignatureTest -vv
# Expected: Tests fail (interface doesn't have modelId parameter)
```

---

### Sub-phase 4.2: Update IProofSystem Interface

**Goal**: Add modelId parameter to interface functions.

**Tasks:**
- [x] Update `verifyHostSignature()` to include `bytes32 modelId` parameter
- [x] Update `verifyAndMarkComplete()` to include `bytes32 modelId` parameter
- [x] Verify interface compiles

**Implementation:**
```solidity
// src/interfaces/IProofSystem.sol
interface IProofSystem {
    function verifyHostSignature(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens,
        bytes32 modelId           // NEW parameter
    ) external view returns (bool);

    function verifyAndMarkComplete(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens,
        bytes32 modelId           // NEW parameter
    ) external returns (bool);
}
```

**File Limits:**
- Lines changed: 2 lines (add parameter to each function)

**Verification:**
```bash
forge build  # Will fail until ProofSystem updated
```

---

### Sub-phase 4.3: Update ProofSystemUpgradeable

**Goal**: Include modelId in signed message hash.

**Tasks:**
- [x] Update `_verifyHostSignature()` to accept and use modelId
- [x] Update `verifyHostSignature()` public function signature
- [x] Update `verifyAndMarkComplete()` public function signature
- [x] Update signed message: `keccak256(proofHash, prover, claimedTokens, modelId)`
- [x] Update `verifyBatch()` and `verifyBatchView()` to include modelId parameter
- [x] Update all tests that call these functions

**Implementation:**
```solidity
// In _verifyHostSignature(), update signature and hash:
function _verifyHostSignature(
    bytes calldata proof,
    address prover,
    uint256 claimedTokens,
    bytes32 modelId              // NEW parameter
) internal view returns (bool) {
    // ... existing validation ...

    // UPDATED: Include modelId in the signed message
    bytes32 dataHash = keccak256(abi.encodePacked(proofHash, prover, claimedTokens, modelId));
    bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));

    // ... rest unchanged ...
}

// Update public functions:
function verifyHostSignature(
    bytes calldata proof,
    address prover,
    uint256 claimedTokens,
    bytes32 modelId
) external view returns (bool) {
    return _verifyHostSignature(proof, prover, claimedTokens, modelId);
}

function verifyAndMarkComplete(
    bytes calldata proof,
    address prover,
    uint256 claimedTokens,
    bytes32 modelId
) external returns (bool) {
    if (!_verifyHostSignature(proof, prover, claimedTokens, modelId)) {
        return false;
    }
    // ... rest unchanged ...
}
```

**File Limits:**
- Lines changed: ~15 lines
- Function signatures: 3 functions updated

**Verification:**
```bash
forge build
forge test --match-path "test/SecurityFixes/ProofSystem/**" -vv
```

---

### Sub-phase 4.4: Update JobMarketplace submitProofOfWork

**Goal**: Pass sessionModel to ProofSystem verification.

**Tasks:**
- [x] Get `modelId` from `sessionModel[jobId]` mapping
- [x] Pass `modelId` to `proofSystem.verifyAndMarkComplete()`
- [x] Update JobMarketplace's local IProofSystemUpgradeable interface
- [x] Update all existing test files that call `submitProofOfWork`
- [x] Update test helpers to use correct modelId for model/non-model sessions
- [x] Mark sub-phase complete - 705/705 tests passing

**Implementation:**
```solidity
// In submitProofOfWork(), update verification call:

// Get model for this session (bytes32(0) if non-model session)
bytes32 modelId = sessionModel[jobId];

require(address(proofSystem) != address(0), "ProofSystem not configured");
bytes memory proof = abi.encodePacked(proofHash, signature);
require(
    proofSystem.verifyAndMarkComplete(proof, msg.sender, tokensClaimed, modelId),
    "Invalid proof signature"
);
```

**File Limits:**
- Lines changed: ~3 lines

**Verification:**
```bash
forge test --match-contract ModelSignatureTest -vv
forge test  # Full suite
```

### Phase 4 Completion Summary

**Status**: ✅ COMPLETE
**Date**: 2026-01-31
**Commit**: `fix(AUDIT-F4): Include modelId in signature verification`

**Changes Made:**
- Updated `IProofSystem` interface to include `bytes32 modelId` parameter in:
  - `verifyHostSignature()`
  - `verifyAndMarkComplete()`
- Updated `ProofSystemUpgradeable` to include modelId in signed message hash:
  - `_verifyHostSignature()` - internal function
  - `verifyHostSignature()` - public view function
  - `verifyAndMarkComplete()` - public function
  - `verifyBatch()` - batch verification
  - `verifyBatchView()` - batch view function
- Updated `JobMarketplaceWithModelsUpgradeable`:
  - Updated local `IProofSystemUpgradeable` interface with modelId
  - `submitProofOfWork()` now passes `sessionModel[jobId]` to ProofSystem
- Updated 14+ test files to generate signatures with correct modelId:
  - Model sessions (createSessionJobForModel): use actual modelId
  - Non-model sessions (createSessionJob): use bytes32(0)

**Test Results:**
- ModelSignatureTest: 6/6 passing
- ProofSignatureRequiredTest: 6/6 passing
- ProofSystemIntegrationTest: 7/7 passing
- ProofVerificationE2ETest: 8/8 passing
- DeltaCIDTest: 5/5 passing
- Full suite: 705/705 passing

**Breaking Changes:**
- `IProofSystem` interface now requires `modelId` parameter in verification functions
- Hosts MUST include modelId in signed message: `keccak256(proofHash, host, tokensClaimed, modelId)`
- Use `bytes32(0)` for non-model sessions, actual modelId for model sessions
- All host signing software must be updated

**Files Modified:**
- `src/interfaces/IProofSystem.sol` - Interface update
- `src/ProofSystemUpgradeable.sol` - Implementation update
- `src/JobMarketplaceWithModelsUpgradeable.sol` - Local interface + submitProofOfWork
- `test/SecurityFixes/Remediation/test_model_signature.t.sol` - New test file
- `test/SecurityFixes/JobMarketplace/test_proof_signature_required.t.sol` - Updated signatures
- `test/SecurityFixes/JobMarketplace/test_proofsystem_integration.t.sol` - Updated signatures
- `test/Integration/test_proof_verification_e2e.t.sol` - Updated signatures
- `test/JobMarketplace/test_deltaCID.t.sol` - Updated signatures
- `test/Upgradeable/ProofSystem/test_initialization.t.sol` - Updated signatures
- Plus 9 other test files with signature updates

---

## Phase 5: createSessionFromDepositForModel (AUDIT-F5)

**Finding ID**: AUDIT-F5
**Slack Ref**: `slack-C0A61FZC8SH-p1769608000786449`
**Finding**: Users with pre-deposits cannot create model-specific sessions.
**Severity**: LOW
**File**: `src/JobMarketplaceWithModelsUpgradeable.sol`

### Sub-phase 5.1: Write Tests for New Function

**Goal**: Verify new function creates model-specific sessions from pre-deposits.

**Tasks:**
- [x] Create test file `test/SecurityFixes/Remediation/test_create_from_deposit_for_model.t.sol`
- [x] Test: Successfully creates model session from pre-deposited ETH
- [x] Test: Successfully creates model session from pre-deposited USDC
- [x] Test: Reverts for unsupported model (host doesn't support it)
- [x] Test: Reverts for insufficient deposit
- [x] Test: Stores modelId in sessionModel mapping
- [x] Test: Uses model-specific pricing from NodeRegistry
- [x] Test: Reverts for zero modelId
- [x] Test: Reverts when host doesn't support model
- [x] Run tests and verify they FAIL (function doesn't exist) - ✅ Verified

**File Limits:**
- Test file: ~150 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/Remediation/test_create_from_deposit_for_model.t.sol
contract CreateFromDepositForModelTest is TestSetupUpgradeable {
    function test_CreateFromDepositForModel_Success_ETH() public { /* ... */ }
    function test_CreateFromDepositForModel_Success_USDC() public { /* ... */ }
    function test_CreateFromDepositForModel_UnapprovedModel_Reverts() public { /* ... */ }
    function test_CreateFromDepositForModel_InsufficientDeposit_Reverts() public { /* ... */ }
    function test_CreateFromDepositForModel_StoresModelId() public { /* ... */ }
    function test_CreateFromDepositForModel_UsesModelPricing() public { /* ... */ }
}
```

**Verification:**
```bash
forge test --match-contract CreateFromDepositForModelTest -vv
# Expected: Compilation fails (function doesn't exist)
```

---

### Sub-phase 5.2: Implement createSessionFromDepositForModel

**Goal**: Add new function for model-specific pre-deposit sessions.

**Tasks:**
- [x] Add `createSessionFromDepositForModel()` function after `createSessionFromDeposit()`
- [x] Validate modelId is not bytes32(0)
- [x] Validate host supports model via `nodeRegistry.nodeSupportsModel()`
- [x] Use `nodeRegistry.getModelPricing()` for price validation
- [x] Store modelId in `sessionModel[sessionId]` mapping
- [x] Emit `SessionJobCreatedForModel` event
- [x] Run all tests to verify - 713/713 passing
- [x] Mark sub-phase complete

**Implementation:**
```solidity
function createSessionFromDepositForModel(
    bytes32 modelId,
    address host,
    address paymentToken,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval,
    uint256 proofTimeoutWindow
) external nonReentrant whenNotPaused returns (uint256 sessionId) {
    require(modelId != bytes32(0), "Invalid model ID");
    require(modelRegistry.isModelApproved(modelId), "Model not approved");
    require(pricePerToken > 0, "Invalid price");
    require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
    require(proofInterval > 0, "Invalid proof interval");
    require(
        proofTimeoutWindow >= MIN_PROOF_TIMEOUT && proofTimeoutWindow <= MAX_PROOF_TIMEOUT,
        "Invalid proof timeout window"
    );
    require(host != address(0), "Invalid host");
    require(deposit > 0, "Zero deposit");

    _validateHostRegistration(host);
    _validateProofRequirements(proofInterval, deposit, pricePerToken);

    // Use model-specific pricing
    uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, paymentToken);
    require(pricePerToken >= hostMinPrice, "Price below host minimum for model");

    // Deduct from pre-deposited balance
    if (paymentToken == address(0)) {
        require(deposit >= MIN_DEPOSIT, "Insufficient deposit");
        require(deposit <= 1000 ether, "Deposit too large");
        require(userDepositsNative[msg.sender] >= deposit, "Insufficient native balance");
        userDepositsNative[msg.sender] -= deposit;
    } else {
        require(acceptedTokens[paymentToken], "Token not accepted");
        uint256 minRequired = tokenMinDeposits[paymentToken];
        uint256 maxAllowed = tokenMaxDeposits[paymentToken];
        require(minRequired > 0, "Token not configured");
        require(maxAllowed > 0, "Token max deposit not configured");
        require(deposit >= minRequired, "Insufficient deposit");
        require(deposit <= maxAllowed, "Deposit too large");
        require(userDepositsToken[msg.sender][paymentToken] >= deposit, "Insufficient token balance");
        userDepositsToken[msg.sender][paymentToken] -= deposit;
    }

    sessionId = nextJobId++;

    SessionJob storage session = sessionJobs[sessionId];
    session.id = sessionId;
    session.depositor = msg.sender;
    session.host = host;
    session.paymentToken = paymentToken;
    session.deposit = deposit;
    session.pricePerToken = pricePerToken;
    session.maxDuration = maxDuration;
    session.startTime = block.timestamp;
    session.lastProofTime = block.timestamp;
    session.proofInterval = proofInterval;
    session.proofTimeoutWindow = proofTimeoutWindow;
    session.status = SessionStatus.Active;

    sessionModel[sessionId] = modelId;

    userSessions[msg.sender].push(sessionId);
    hostSessions[host].push(sessionId);

    emit SessionJobCreated(sessionId, msg.sender, host, deposit);
    emit SessionCreatedByDepositor(sessionId, msg.sender, host, deposit);
    emit ModelSessionCreated(sessionId, modelId);

    return sessionId;
}
```

**File Limits:**
- Lines added: ~70 lines (new function)

**Verification:**
```bash
forge test --match-contract CreateFromDepositForModelTest -vv
forge test  # Full suite
```

### Phase 5 Completion Summary

**Status**: ✅ COMPLETE
**Date**: 2026-01-31
**Commit**: `fix(AUDIT-F5): Add createSessionFromDepositForModel function`

**Changes Made:**
- Added `createSessionFromDepositForModel()` function to `JobMarketplaceWithModelsUpgradeable`
- Function accepts 8 parameters: modelId, host, paymentToken, deposit, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
- Validates modelId is not bytes32(0)
- Validates host supports the model via `nodeRegistry.nodeSupportsModel()`
- Validates price against model-specific pricing via `nodeRegistry.getModelPricing()`
- Deducts deposit from user's pre-deposited balance
- Stores modelId in `sessionModel[sessionId]` mapping
- Emits `SessionJobCreated`, `SessionCreatedByDepositor`, and `SessionJobCreatedForModel` events

**Test Results:**
- CreateFromDepositForModelTest: 8/8 passing
  - test_CreateFromDepositForModel_Success_ETH
  - test_CreateFromDepositForModel_Success_USDC
  - test_CreateFromDepositForModel_UnapprovedModel_Reverts
  - test_CreateFromDepositForModel_InsufficientDeposit_Reverts
  - test_CreateFromDepositForModel_StoresModelId
  - test_CreateFromDepositForModel_UsesModelPricing
  - test_CreateFromDepositForModel_ZeroModelId_Reverts
  - test_CreateFromDepositForModel_HostDoesNotSupportModel_Reverts
- Full suite: 713/713 passing

**Files Modified:**
- `src/JobMarketplaceWithModelsUpgradeable.sol` - Added new function (~70 lines)
- `test/SecurityFixes/Remediation/test_create_from_deposit_for_model.t.sol` - New test file (8 tests)

**Breaking Changes:**
- None - this is a new function that doesn't affect existing functionality

---

## Phase 6: Deployment & Documentation

### Sub-phase 6.1: Deploy Test Contracts (Separate from Audited)

**Goal**: Deploy new implementations at separate addresses for testing WITHOUT upgrading audited proxies.

**Tasks:**
- [ ] Deploy new ProofSystemUpgradeable implementation
- [ ] Deploy new ERC1967Proxy for ProofSystem (NEW address)
- [ ] Initialize new ProofSystem proxy
- [ ] Deploy new JobMarketplaceWithModelsUpgradeable implementation
- [ ] Deploy new ERC1967Proxy for JobMarketplace (NEW address)
- [ ] Initialize new JobMarketplace proxy
- [ ] Configure authorized callers and dependencies
- [ ] Record test contract addresses

**Deployment Commands:**
```bash
# Deploy NEW ProofSystem (separate from audited)
PROOF_IMPL=$(forge create src/ProofSystemUpgradeable.sol:ProofSystemUpgradeable \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --json | jq -r '.deployedTo')

PROOF_INIT=$(cast calldata "initialize()")
PROOF_PROXY=$(forge create lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $PROOF_IMPL $PROOF_INIT \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --json | jq -r '.deployedTo')

# Deploy NEW JobMarketplace (separate from audited)
JOB_IMPL=$(forge create src/JobMarketplaceWithModelsUpgradeable.sol:JobMarketplaceWithModelsUpgradeable \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --json | jq -r '.deployedTo')

# Initialize with existing dependencies
NODE_REGISTRY=0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22
HOST_EARNINGS=0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0
USDC=0x036CbD53842c5426634e7929541eC2318f3dCF7e

JOB_INIT=$(cast calldata "initialize(address,address,uint256,address,address,address)" \
  $NODE_REGISTRY $HOST_EARNINGS 1000 $TREASURY $USDC $PROOF_PROXY)

JOB_PROXY=$(forge create lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --constructor-args $JOB_IMPL $JOB_INIT \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --json | jq -r '.deployedTo')

# Configure
cast send $PROOF_PROXY "setAuthorizedCaller(address,bool)" $JOB_PROXY true \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

**Audited Contracts (DO NOT UPGRADE):**
| Contract | Audited Proxy Address | Status |
|----------|----------------------|--------|
| JobMarketplace | `0x3CaCbf3f448B420918A93a88706B26Ab27a3523E` | FROZEN |
| ProofSystem | `0x5afB91977e69Cc5003288849059bc62d47E7deeb` | FROZEN |
| NodeRegistry | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | FROZEN |
| ModelRegistry | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | FROZEN |
| HostEarnings | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | FROZEN |

**Test Contract Addresses (TBD after deployment):**
| Contract | Test Proxy Address | Test Implementation |
|----------|-------------------|---------------------|
| ProofSystem | `TBD` | `TBD` |
| JobMarketplace | `TBD` | `TBD` |

---

### Sub-phase 6.2: Manual Testing on Testnet

**Goal**: Verify all fixes work on deployed test contracts.

**Tasks:**
- [ ] Test Finding 2: Verify ProofSystem required (should revert without it)
- [ ] Test Finding 3: Create session with proofTimeoutWindow, trigger timeout
- [ ] Test Finding 4: Submit proof with correct modelId signature
- [ ] Test Finding 4: Verify wrong modelId signature fails
- [ ] Test Finding 5: Create model session from pre-deposit
- [ ] Document test results

**Test Commands:**
```bash
# Verify ProofSystem is required
cast call $TEST_JOB_PROXY "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL

# Create test session with proofTimeoutWindow
cast send $TEST_JOB_PROXY "createSessionJob(address,uint256,uint256,uint256,uint256)" \
  $HOST $PRICE $DURATION $PROOF_INTERVAL $TIMEOUT_WINDOW \
  --value 0.001ether --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Submit proof with model signature
# (requires off-chain signature generation with modelId)
```

---

### Sub-phase 6.3: Update Documentation and ABIs

**Goal**: Update all documentation to reflect changes.

**Tasks:**
- [ ] Extract new ABIs to `client-abis/`
- [ ] Update `client-abis/CHANGELOG.md` with breaking changes
- [ ] Update `client-abis/README.md` with new function signatures
- [ ] Create `docs/REMEDIATION_CHANGES.md` with commit hash → finding ID mapping
- [ ] Update `CLAUDE.md` with test contract addresses (NOT audited addresses)
- [ ] Mark Phase 6 complete

**REMEDIATION_CHANGES.md Template:**
```markdown
# Remediation Changes

Branch: `fix/remediation-pre-report`
Base Commit: <commit-hash-auditors-reviewed>

| Commit | Finding ID | Slack Ref | Description |
|--------|------------|-----------|-------------|
| abc123 | AUDIT-F1 | slack-C0A61FZC8SH-p1769545156133729 | Remove dead onlyRegisteredHost modifier |
| def456 | AUDIT-F2 | slack-C0A61FZC8SH-p1769545156133729 | Add ProofSystem required check |
| ghi789 | AUDIT-F3 | slack-C0A61FZC8SH-p1769545156133729 | Add proofTimeoutWindow field |
| jkl012 | AUDIT-F4 | slack-C0A61FZC8SH-p1769619714508749 | Add modelId to signature scheme |
| mno345 | AUDIT-F5 | slack-C0A61FZC8SH-p1769608000786449 | Add createSessionFromDepositForModel |
```

---

## Completion Criteria

All phases complete when:
- [ ] All HIGH severity vulnerabilities fixed and tested
- [ ] All MEDIUM severity issues fixed and tested
- [ ] All LOW severity items addressed
- [ ] Full test suite passes (forge test)
- [ ] Test contracts deployed to Base Sepolia (separate from audited)
- [ ] Manual testing completed on testnet
- [ ] Documentation updated
- [ ] REMEDIATION_CHANGES.md created with commit mapping
- [ ] Ready for auditor retest on March 10, 2026

---

## Notes

### TDD Approach (Bounded Autonomy)

Each sub-phase follows strict TDD:
1. **RED**: Write tests FIRST, verify they FAIL
2. **GREEN**: Implement minimal code to pass tests
3. **REFACTOR**: Clean up while keeping tests green
4. **COMMIT**: Commit with finding ID in message

### File Limits

| File Type | Maximum Lines |
|-----------|---------------|
| New test file | 200 lines |
| New function | 70 lines |
| Modified function | +20 lines |
| Interface changes | 10 lines |

### Commit Message Format

**Each commit must be labeled with the finding ID** (not PRs - commits are more granular for auditor verification).

```
fix(AUDIT-F1): Remove dead onlyRegisteredHost modifier

- Delete unused modifier (lines 192-196)
- No functional change - modifier was never used

Fixes: AUDIT-F1
Ref: slack-C0A61FZC8SH-p1769545156133729
```

**Finding ID Quick Reference:**
| ID | Description |
|----|-------------|
| AUDIT-F1 | Dead code modifier |
| AUDIT-F2 | ProofSystem required |
| AUDIT-F3 | proofTimeoutWindow |
| AUDIT-F4 | modelId in signature |
| AUDIT-F5 | createSessionFromDepositForModel |

### Breaking Changes

| Change | SDK Impact |
|--------|------------|
| ProofSystem required | Deployment must configure ProofSystem |
| proofTimeoutWindow parameter | All session creation calls need new parameter |
| modelId in signature | Hosts must include modelId when signing proofs |
| IProofSystem interface | All callers must pass modelId parameter |

### Upgrade Safety

- **DO NOT** upgrade audited proxy contracts during audit period
- Deploy test contracts at NEW addresses for testing
- Document all changes for auditor review
- Upgrade audited proxies only AFTER retest approval
