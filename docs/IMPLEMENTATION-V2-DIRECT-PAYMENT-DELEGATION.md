# IMPLEMENTATION-V2-DIRECT-PAYMENT-DELEGATION.md - Direct Payment Delegation for Coinbase Smart Wallet

## Overview

Add V2 direct payment delegation for Coinbase Smart Wallet sub-accounts using ERC-20 `transferFrom` pattern. This is **additive** - existing escrow/deposit functions are kept for general wallet support and native token use cases.

## Repository

fabstir-compute-contracts

## Feature Reference

- **Requested By**: SDK Developer
- **Branch**: `fix/v2-direct-payment-delegation`
- **Priority**: HIGH (Coinbase Smart Wallet support)
- **Predecessor**: `docs/IMPLEMENTATION-DELEGATED-SESSIONS.md` (V1 - rolled back)

## Problem Statement

Coinbase Smart Wallet uses a primary/sub-account permission model. Sub-accounts need to create sessions using the primary account's funds without requiring a popup for each transaction.

## Solution Design

**Two complementary systems (coexisting):**

### 1. Escrow System (KEEP - for general wallets)
- User deposits funds to contract (native ETH/BNB or USDC)
- User creates sessions from deposited balance
- Works with any wallet on any chain (Base, OpBNB, etc.)
- Supports native tokens

### 2. V2 Direct Payment Delegation (ADD - for Coinbase Smart Wallet)
- Primary approves USDC to contract (one-time popup, $1,000 default)
- Primary authorizes sub-account as delegate (one-time popup)
- Sub-account creates session → contract pulls from primary's wallet via `transferFrom`
- USDC only (no ETH - `transferFrom` doesn't work for native tokens)

**Key Changes (Additive):**
- ADD `isAuthorizedDelegate` mapping
- ADD `authorizeDelegate()` and `isDelegateAuthorized()` functions
- ADD `createSessionAsDelegate()` for non-model sessions
- ADD `createSessionForModelAsDelegate()` for model-specific sessions
- KEEP all existing escrow/deposit/withdraw functions

## Implementation Progress

**Overall Status: IN PROGRESS (70%)**

- [x] **Phase 0: Git Rollback** (1/1 sub-phases)
  - [x] Sub-phase 0.1: Roll back to before V1 delegation
- [x] **Phase 1: Verify Baseline** (Escrow kept, no changes needed)
- [x] **Phase 2: Add Authorization Infrastructure** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 2.1: Write Authorization Tests (11 tests)
  - [x] Sub-phase 2.2: Implement Authorization Functions
- [x] **Phase 3: Add V2 Direct Payment Delegation** (3/3 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 3.1: Write Tests for Direct Payment Delegation (15 tests)
  - [x] Sub-phase 3.2: Implement createSessionAsDelegate
  - [x] Sub-phase 3.3: Implement createSessionForModelAsDelegate
- [ ] **Phase 4: Security Hardening** (2/2 sub-phases)
  - [ ] Sub-phase 4.1: Write Security Tests
  - [ ] Sub-phase 4.2: Security Review
- [ ] **Phase 5: Documentation and Deployment** (2/2 sub-phases)
  - [ ] Sub-phase 5.1: Update Documentation
  - [ ] Sub-phase 5.2: Deploy and Verify

**Last Updated:** 2026-02-02

---

## Phase 0: Git Rollback

**Goal**: Roll back to clean state before V1 delegation.

### Sub-phase 0.1: Roll Back to Before V1 Delegation

**Goal**: Return to commit `75437e2` (last commit before V1 delegation session).

**Tasks:**
- [x] Verify current HEAD is `b46e0b5` (V1 delegation)
- [x] Create backup branch: `git branch backup-v1-delegation`
- [x] Roll back: `git reset --hard 75437e2`
- [x] Verify rollback: `git log --oneline -3`
- [x] Create new branch: `git checkout -b fix/v2-direct-payment-delegation`
- [x] Mark sub-phase complete

**Commands:**
```bash
# Backup current work
git branch backup-v1-delegation

# Roll back to last commit before V1 delegation session
git reset --hard 75437e2

# Verify
git log --oneline -3
# Expected:
# 75437e2 chore: remove node/sdk reference docs from tracking
# 99a916e chore: update .gitignore
# 724c868 docs(Phase-6): Complete deployment and documentation

# Create new branch
git checkout -b fix/v2-direct-payment-delegation
```

**What Gets Removed by Rollback:**
- `b46e0b5` - V1 delegation code and tests
- `8f18bd6` - AUDIT security remediation breaking changes docs

**What Gets Preserved:**
- All escrow/deposit functions (depositNative, depositToken, withdrawNative, withdrawToken, createSessionFromDeposit)
- AUDIT-F5 fix (`createSessionFromDepositForModel`) - KEPT for general wallet support
- All AUDIT-F1 to F4 fixes
- Documentation chores (`.gitignore`, etc.)

**Verification:**
```bash
# Confirm V1 delegation files are gone
ls test/SecurityFixes/DelegatedSessions/
# Expected: No such file or directory

# Confirm AUDIT-F5 test still exists (KEPT)
ls test/SecurityFixes/Remediation/test_create_from_deposit_for_model.t.sol
# Expected: File exists

# Confirm contract compiles
forge build
```

---

## Phase 1: Verify Baseline (SKIPPED - Escrow Kept)

**Goal**: ~~Remove all deposit/escrow functions~~ → Escrow functions are KEPT for general wallet support.

**Decision**: Keep all escrow/deposit functions because:
1. **Multi-chain support**: Works with any wallet on Base, OpBNB, etc.
2. **Native token support**: ETH/BNB deposits use escrow (can't use `transferFrom` for native tokens)
3. **Security audit**: Minimal changes reduce audit scope
4. **V2 delegation is additive**: New functions for Coinbase Smart Wallet, existing functions unchanged

**Status**: ✅ COMPLETE (no changes needed)

---

### Sub-phase 2.1: Write Authorization Tests

**Goal**: Test authorization functions (TDD - tests first).

**Tasks:**
- [ ] Create `test/SecurityFixes/DelegatedSessions/test_delegation_authorization.t.sol`
- [ ] Test: `authorizeDelegate(delegate, true)` authorizes delegate
- [ ] Test: `authorizeDelegate(delegate, false)` revokes authorization
- [ ] Test: `isDelegateAuthorized()` returns correct status
- [ ] Test: Cannot authorize zero address (reverts)
- [ ] Test: Cannot authorize self (reverts)
- [ ] Test: Emits `DelegateAuthorized` event
- [ ] Run tests - verify they FAIL (functions don't exist yet)

**File Limits:**
- Test file: 100 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_delegation_authorization.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestSetupUpgradeable} from "test/TestSetupUpgradeable.t.sol";

contract DelegationAuthorizationTest is TestSetupUpgradeable {
    address depositor;
    address delegate;

    event DelegateAuthorized(address indexed depositor, address indexed delegate, bool authorized);

    function setUp() public override {
        super.setUp();
        depositor = makeAddr("depositor");
        delegate = makeAddr("delegate");
    }

    function test_AuthorizeDelegate_Success() public {
        vm.prank(depositor);
        jobMarketplace.authorizeDelegate(delegate, true);
        assertTrue(jobMarketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_RevokeDelegate_Success() public {
        vm.startPrank(depositor);
        jobMarketplace.authorizeDelegate(delegate, true);
        jobMarketplace.authorizeDelegate(delegate, false);
        vm.stopPrank();
        assertFalse(jobMarketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_AuthorizeDelegate_ZeroAddress_Reverts() public {
        vm.prank(depositor);
        vm.expectRevert("Invalid delegate address");
        jobMarketplace.authorizeDelegate(address(0), true);
    }

    function test_AuthorizeDelegate_Self_Reverts() public {
        vm.prank(depositor);
        vm.expectRevert("Cannot delegate to self");
        jobMarketplace.authorizeDelegate(depositor, true);
    }

    function test_AuthorizeDelegate_EmitsEvent() public {
        vm.prank(depositor);
        vm.expectEmit(true, true, false, true);
        emit DelegateAuthorized(depositor, delegate, true);
        jobMarketplace.authorizeDelegate(delegate, true);
    }

    function test_MultipleDelegatorsIndependentDelegates() public {
        address depositor2 = makeAddr("depositor2");
        address delegate2 = makeAddr("delegate2");

        vm.prank(depositor);
        jobMarketplace.authorizeDelegate(delegate, true);

        vm.prank(depositor2);
        jobMarketplace.authorizeDelegate(delegate2, true);

        assertTrue(jobMarketplace.isDelegateAuthorized(depositor, delegate));
        assertTrue(jobMarketplace.isDelegateAuthorized(depositor2, delegate2));
        assertFalse(jobMarketplace.isDelegateAuthorized(depositor, delegate2));
        assertFalse(jobMarketplace.isDelegateAuthorized(depositor2, delegate));
    }
}
```

**Verification:**
```bash
forge test --match-contract DelegationAuthorizationTest -vv
# Expected: Compilation fails (functions don't exist yet) - RED
```

---

### Sub-phase 2.2: Implement Authorization Functions

**Goal**: Add authorization mapping, events, and functions.

**Tasks:**
- [ ] Add `isAuthorizedDelegate` mapping after existing mappings
- [ ] Add `DelegateAuthorized` event
- [ ] Add `SessionCreatedByDelegate` event
- [ ] Add `authorizeDelegate(address, bool)` function
- [ ] Add `isDelegateAuthorized(address, address)` view function
- [ ] Reduce `__gap` by 1 slot (for new mapping)
- [ ] Run authorization tests - all passing
- [ ] Mark sub-phase complete

**Implementation (add to `src/JobMarketplaceWithModelsUpgradeable.sol`):**

```solidity
// Storage (add after existing mappings, before __gap)
// Delegation mapping for Smart Wallet sub-account support
mapping(address => mapping(address => bool)) public isAuthorizedDelegate;

// Reduce __gap from current size to current-1 (mapping uses 1 slot)
uint256[XX] private __gap;  // Adjust XX to be 1 less than current

// Events (add with other events)
/// @notice Emitted when a delegate is authorized or revoked
event DelegateAuthorized(
    address indexed depositor,
    address indexed delegate,
    bool authorized
);

/// @notice Emitted when a session is created by a delegate
event SessionCreatedByDelegate(
    uint256 indexed sessionId,
    address indexed payer,
    address indexed delegate,
    address host,
    bytes32 modelId,
    uint256 amount
);

// Functions (add after other session functions)
/**
 * @notice Authorize or revoke a delegate to create sessions on behalf of caller
 * @param delegate The address to authorize (e.g., Smart Wallet sub-account)
 * @param authorized True to authorize, false to revoke
 */
function authorizeDelegate(address delegate, bool authorized) external {
    require(delegate != address(0), "Invalid delegate address");
    require(delegate != msg.sender, "Cannot delegate to self");

    isAuthorizedDelegate[msg.sender][delegate] = authorized;
    emit DelegateAuthorized(msg.sender, delegate, authorized);
}

/**
 * @notice Check if a delegate is authorized for a payer
 * @param payer The primary account address
 * @param delegate The delegate address to check
 * @return True if delegate is authorized for payer
 */
function isDelegateAuthorized(address payer, address delegate)
    external view returns (bool)
{
    return isAuthorizedDelegate[payer][delegate];
}
```

**File Limits:**
- Lines added: 35 lines (mapping + events + 2 functions)

**Verification:**
```bash
forge build
forge test --match-contract DelegationAuthorizationTest -vv
# Expected: All tests pass - GREEN
```

---

## Phase 3: Add V2 Direct Payment Delegation

**Goal**: Implement direct payment delegation functions (USDC only).

### Sub-phase 3.1: Write Tests for Direct Payment Delegation

**Goal**: Comprehensive tests for V2 delegation (TDD - tests first).

**Tasks:**
- [ ] Create `test/SecurityFixes/DelegatedSessions/test_direct_payment_delegation.t.sol`
- [ ] Test: Successfully creates session pulling USDC from payer
- [ ] Test: Payer's USDC balance decreases
- [ ] Test: Contract's USDC balance increases
- [ ] Test: Session owner is payer (not delegate)
- [ ] Test: Unauthorized delegate reverts
- [ ] Test: Payer without approval reverts (ERC-20 error)
- [ ] Test: ETH (address(0)) reverts with "Direct delegation requires ERC-20 token"
- [ ] Test: Emits `SessionCreatedByDelegate` event
- [ ] Test: Emits standard session events
- [ ] Test: Session refunds go to payer
- [ ] Test: Model validation works
- [ ] Run tests - verify they FAIL (functions don't exist)

**File Limits:**
- Test file: 250 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_direct_payment_delegation.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestSetupUpgradeable} from "test/TestSetupUpgradeable.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DirectPaymentDelegationTest is TestSetupUpgradeable {
    address payer;
    address delegate;
    uint256 sessionAmount = 10e6; // 10 USDC (6 decimals)
    uint256 approvalAmount = 1000e6; // $1,000 USDC

    event SessionCreatedByDelegate(
        uint256 indexed sessionId,
        address indexed payer,
        address indexed delegate,
        address host,
        bytes32 modelId,
        uint256 amount
    );

    function setUp() public override {
        super.setUp();
        payer = makeAddr("payer");
        delegate = makeAddr("delegate");

        // Give payer USDC
        deal(address(usdc), payer, 10000e6); // $10,000 USDC

        // Payer approves contract
        vm.prank(payer);
        usdc.approve(address(jobMarketplace), approvalAmount);

        // Payer authorizes delegate
        vm.prank(payer);
        jobMarketplace.authorizeDelegate(delegate, true);
    }

    // ============ Happy Path Tests ============

    function test_CreateSessionForModelAsDelegate_Success() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionForModelAsDelegate(
            payer,
            TINY_VICUNA_MODEL_ID,
            host,
            address(usdc),
            sessionAmount,
            MIN_PRICE_STABLE,
            3600, // 1 hour
            100,  // proof interval
            300   // timeout window
        );
        assertGt(sessionId, 0);
    }

    function test_CreateSessionForModelAsDelegate_PullsFromPayerWallet() public {
        uint256 payerBalanceBefore = usdc.balanceOf(payer);
        uint256 contractBalanceBefore = usdc.balanceOf(address(jobMarketplace));

        vm.prank(delegate);
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );

        assertEq(usdc.balanceOf(payer), payerBalanceBefore - sessionAmount);
        assertEq(usdc.balanceOf(address(jobMarketplace)), contractBalanceBefore + sessionAmount);
    }

    function test_CreateSessionForModelAsDelegate_SessionOwnedByPayer() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );

        (,address sessionDepositor,,,,,,,,,,,,,,,,) = jobMarketplace.sessionJobs(sessionId);
        assertEq(sessionDepositor, payer); // NOT delegate!
    }

    function test_CreateSessionForModelAsDelegate_EmitsEvent() public {
        vm.prank(delegate);
        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDelegate(1, payer, delegate, host, TINY_VICUNA_MODEL_ID, sessionAmount);
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    // ============ Authorization Tests ============

    function test_CreateSessionForModelAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_RevokedDelegate_Reverts() public {
        // Revoke authorization
        vm.prank(payer);
        jobMarketplace.authorizeDelegate(delegate, false);

        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    // ============ Token Validation Tests ============

    function test_CreateSessionForModelAsDelegate_ETH_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Direct delegation requires ERC-20 token");
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host,
            address(0), // ETH - should fail
            1 ether, MIN_PRICE_NATIVE, 3600, 100, 300
        );
    }

    function test_CreateSessionForModelAsDelegate_NoApproval_Reverts() public {
        // Create new payer without approval
        address newPayer = makeAddr("newPayer");
        deal(address(usdc), newPayer, 10000e6);
        vm.prank(newPayer);
        jobMarketplace.authorizeDelegate(delegate, true);
        // Note: newPayer has NOT approved contract

        vm.prank(delegate);
        vm.expectRevert(); // ERC-20 will revert (insufficient allowance)
        jobMarketplace.createSessionForModelAsDelegate(
            newPayer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    // ============ Non-Model Version Tests ============

    function test_CreateSessionAsDelegate_Success() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionAsDelegate(
            payer, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );
        assertGt(sessionId, 0);
    }

    function test_CreateSessionAsDelegate_ETH_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Direct delegation requires ERC-20 token");
        jobMarketplace.createSessionAsDelegate(
            payer, host, address(0),
            1 ether, MIN_PRICE_NATIVE, 3600, 100, 300
        );
    }

    // ============ Refund Tests ============

    function test_SessionRefundsGoToPayer() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            sessionAmount, MIN_PRICE_STABLE, 3600, 100, 300
        );

        uint256 payerBalanceBefore = usdc.balanceOf(payer);

        // Complete session (no tokens used = full refund minus fees)
        vm.prank(payer);
        jobMarketplace.completeSessionJob(sessionId, "cid");

        // Payer should receive refund
        assertGt(usdc.balanceOf(payer), payerBalanceBefore);
    }
}
```

**Verification:**
```bash
forge test --match-contract DirectPaymentDelegationTest -vv
# Expected: Compilation fails (functions don't exist) - RED
```

---

### Sub-phase 3.2: Implement createSessionAsDelegate

**Goal**: Add non-model direct payment delegation function.

**Tasks:**
- [ ] Add `createSessionAsDelegate()` function
- [ ] Validate payer is not zero address
- [ ] Check authorization: `isAuthorizedDelegate[payer][msg.sender]`
- [ ] Require ERC-20 token (not ETH)
- [ ] Pull funds via `safeTransferFrom(payer, address(this), amount)`
- [ ] Set `session.depositor = payer`
- [ ] Add to `userSessions[payer]`
- [ ] Emit events including `SessionCreatedByDelegate`
- [ ] Run non-model tests - all passing

**Implementation:**
```solidity
/**
 * @notice Create a session as an authorized delegate (direct payment)
 * @dev Pulls funds directly from payer's wallet via ERC-20 transferFrom
 * @param payer The address whose funds will be used (must have approved this contract)
 * @param host The host address to connect to
 * @param paymentToken The ERC-20 token address (cannot be address(0))
 * @param amount Amount to pull from payer's wallet
 * @param pricePerToken Agreed price per token (must meet host's minimum)
 * @param maxDuration Maximum session duration in seconds
 * @param proofInterval Minimum tokens between proofs (>=100)
 * @param proofTimeoutWindow Timeout window for proofs (60-3600 seconds)
 * @return sessionId The created session ID
 */
function createSessionAsDelegate(
    address payer,
    address host,
    address paymentToken,
    uint256 amount,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval,
    uint256 proofTimeoutWindow
) external nonReentrant whenNotPaused returns (uint256 sessionId) {
    // Authorization check (FIRST - before any state changes)
    require(payer != address(0), "Invalid payer");
    require(isAuthorizedDelegate[payer][msg.sender], "Not authorized delegate");

    // Must be ERC-20 (can't do transferFrom for ETH)
    require(paymentToken != address(0), "Direct delegation requires ERC-20 token");
    require(acceptedTokens[paymentToken], "Token not accepted");

    // Validate amount limits
    uint256 minRequired = tokenMinDeposits[paymentToken];
    uint256 maxAllowed = tokenMaxDeposits[paymentToken];
    require(minRequired > 0 && maxAllowed > 0, "Token not configured");
    require(amount >= minRequired, "Amount below minimum");
    require(amount <= maxAllowed, "Amount above maximum");

    // Standard validations
    require(pricePerToken > 0, "Invalid price");
    require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
    require(proofInterval >= MIN_PROOF_INTERVAL, "Proof interval too small");
    require(
        proofTimeoutWindow >= MIN_PROOF_TIMEOUT && proofTimeoutWindow <= MAX_PROOF_TIMEOUT,
        "Invalid proof timeout window"
    );

    _validateHostRegistration(host);
    _validateProofRequirements(proofInterval, amount, pricePerToken);

    // Validate host pricing (stable pricing for ERC-20)
    (, uint256 hostMinPrice) = nodeRegistry.getNodePricing(host);
    require(pricePerToken >= hostMinPrice, "Price below host minimum (stable)");

    // Pull payment directly from payer's wallet
    IERC20(paymentToken).safeTransferFrom(payer, address(this), amount);

    // Create session owned by payer
    sessionId = nextJobId++;

    SessionJob storage session = sessionJobs[sessionId];
    session.id = sessionId;
    session.depositor = payer;  // CRITICAL: Payer owns session, NOT delegate
    session.host = host;
    session.paymentToken = paymentToken;
    session.deposit = amount;
    session.pricePerToken = pricePerToken;
    session.maxDuration = maxDuration;
    session.startTime = block.timestamp;
    session.lastProofTime = block.timestamp;
    session.proofInterval = proofInterval;
    session.proofTimeoutWindow = proofTimeoutWindow;
    session.status = SessionStatus.Active;

    userSessions[payer].push(sessionId);  // CRITICAL: Payer's sessions
    hostSessions[host].push(sessionId);

    emit SessionJobCreated(sessionId, payer, host, amount);
    emit SessionCreatedByDelegate(sessionId, payer, msg.sender, host, bytes32(0), amount);

    return sessionId;
}
```

**File Limits:**
- Lines added: 70 lines (new function)

**Verification:**
```bash
forge test --match-test "CreateSessionAsDelegate" -vv
# Expected: Non-model tests pass - GREEN
```

---

### Sub-phase 3.3: Implement createSessionForModelAsDelegate

**Goal**: Add model-specific direct payment delegation function (primary use case).

**Tasks:**
- [ ] Add `createSessionForModelAsDelegate()` function
- [ ] Include all validations from non-model version
- [ ] Add modelId validation (not bytes32(0))
- [ ] Validate host supports model via `nodeRegistry.nodeSupportsModel()`
- [ ] Use model-specific pricing via `nodeRegistry.getModelPricing()`
- [ ] Store modelId in `sessionModel[sessionId]`
- [ ] Emit `SessionJobCreatedForModel` event
- [ ] Run all delegation tests - all passing
- [ ] Mark sub-phase complete

**Implementation:**
```solidity
/**
 * @notice Create a model-specific session as an authorized delegate (direct payment)
 * @dev Pulls funds directly from payer's wallet via ERC-20 transferFrom
 * @param payer The address whose funds will be used (must have approved this contract)
 * @param modelId The model to use (must be approved in ModelRegistry)
 * @param host The host address to connect to
 * @param paymentToken The ERC-20 token address (cannot be address(0))
 * @param amount Amount to pull from payer's wallet
 * @param pricePerToken Agreed price per token (must meet host's minimum)
 * @param maxDuration Maximum session duration in seconds
 * @param proofInterval Minimum tokens between proofs (>=100)
 * @param proofTimeoutWindow Timeout window for proofs (60-3600 seconds)
 * @return sessionId The created session ID
 */
function createSessionForModelAsDelegate(
    address payer,
    bytes32 modelId,
    address host,
    address paymentToken,
    uint256 amount,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval,
    uint256 proofTimeoutWindow
) external nonReentrant whenNotPaused returns (uint256 sessionId) {
    // Authorization check (FIRST - before any state changes)
    require(payer != address(0), "Invalid payer");
    require(isAuthorizedDelegate[payer][msg.sender], "Not authorized delegate");

    // Must be ERC-20 (can't do transferFrom for ETH)
    require(paymentToken != address(0), "Direct delegation requires ERC-20 token");
    require(acceptedTokens[paymentToken], "Token not accepted");

    // Model validation
    require(modelId != bytes32(0), "Invalid model ID");
    require(modelRegistry.isModelApproved(modelId), "Model not approved");

    // Validate amount limits
    uint256 minRequired = tokenMinDeposits[paymentToken];
    uint256 maxAllowed = tokenMaxDeposits[paymentToken];
    require(minRequired > 0 && maxAllowed > 0, "Token not configured");
    require(amount >= minRequired, "Amount below minimum");
    require(amount <= maxAllowed, "Amount above maximum");

    // Standard validations
    require(pricePerToken > 0, "Invalid price");
    require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
    require(proofInterval >= MIN_PROOF_INTERVAL, "Proof interval too small");
    require(
        proofTimeoutWindow >= MIN_PROOF_TIMEOUT && proofTimeoutWindow <= MAX_PROOF_TIMEOUT,
        "Invalid proof timeout window"
    );

    _validateHostRegistration(host);
    _validateProofRequirements(proofInterval, amount, pricePerToken);

    // Model-specific validation
    require(nodeRegistry.nodeSupportsModel(host, modelId), "Host does not support model");

    // Model-specific pricing
    uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, paymentToken);
    require(pricePerToken >= hostMinPrice, "Price below host minimum");

    // Pull payment directly from payer's wallet
    IERC20(paymentToken).safeTransferFrom(payer, address(this), amount);

    // Create session owned by payer
    sessionId = nextJobId++;

    SessionJob storage session = sessionJobs[sessionId];
    session.id = sessionId;
    session.depositor = payer;  // CRITICAL: Payer owns session
    session.host = host;
    session.paymentToken = paymentToken;
    session.deposit = amount;
    session.pricePerToken = pricePerToken;
    session.maxDuration = maxDuration;
    session.startTime = block.timestamp;
    session.lastProofTime = block.timestamp;
    session.proofInterval = proofInterval;
    session.proofTimeoutWindow = proofTimeoutWindow;
    session.status = SessionStatus.Active;

    // Store model for this session
    sessionModel[sessionId] = modelId;

    userSessions[payer].push(sessionId);  // CRITICAL: Payer's sessions
    hostSessions[host].push(sessionId);

    emit SessionJobCreated(sessionId, payer, host, amount);
    emit SessionJobCreatedForModel(sessionId, payer, host, modelId, amount);
    emit SessionCreatedByDelegate(sessionId, payer, msg.sender, host, modelId, amount);

    return sessionId;
}
```

**File Limits:**
- Lines added: 85 lines (new function)

**Verification:**
```bash
forge test --match-contract DirectPaymentDelegationTest -vv
forge test  # Full suite
# Expected: All tests pass - GREEN
```

---

## Phase 4: Security Hardening

**Goal**: Verify security properties and edge cases.

### Sub-phase 4.1: Write Security Tests

**Goal**: Comprehensive security test coverage.

**Tasks:**
- [ ] Create `test/SecurityFixes/DelegatedSessions/test_delegation_security.t.sol`
- [ ] Test: Unauthorized address cannot pull from any payer
- [ ] Test: Previously authorized delegate fails after revocation
- [ ] Test: Delegate cannot exceed payer's approval amount
- [ ] Test: Session refunds go to payer (not delegate)
- [ ] Test: Reentrancy protection active
- [ ] Test: Pause mechanism blocks delegated functions
- [ ] Test: Payer can still use non-delegated functions
- [ ] Run all security tests - all passing

**File Limits:**
- Test file: 150 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_delegation_security.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestSetupUpgradeable} from "test/TestSetupUpgradeable.t.sol";

contract DelegationSecurityTest is TestSetupUpgradeable {
    address payer;
    address delegate;
    address attacker;

    function setUp() public override {
        super.setUp();
        payer = makeAddr("payer");
        delegate = makeAddr("delegate");
        attacker = makeAddr("attacker");

        // Setup payer with USDC and approval
        deal(address(usdc), payer, 10000e6);
        vm.prank(payer);
        usdc.approve(address(jobMarketplace), 1000e6);
        vm.prank(payer);
        jobMarketplace.authorizeDelegate(delegate, true);
    }

    function test_UnauthorizedCannotPullFromPayer() public {
        vm.prank(attacker);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            10e6, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    function test_RevokedDelegateCannotCreateSession() public {
        // Revoke
        vm.prank(payer);
        jobMarketplace.authorizeDelegate(delegate, false);

        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            10e6, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    function test_DelegateCannotExceedApproval() public {
        // Payer only approved 1000 USDC, try to use 2000
        vm.prank(delegate);
        vm.expectRevert(); // ERC-20 revert
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            2000e6, // Exceeds approval
            MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    function test_SessionRefundsGoToPayer() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            100e6, MIN_PRICE_STABLE, 3600, 100, 300
        );

        uint256 payerBalanceBefore = usdc.balanceOf(payer);
        uint256 delegateBalanceBefore = usdc.balanceOf(delegate);

        vm.prank(payer);
        jobMarketplace.completeSessionJob(sessionId, "cid");

        // Payer receives refund
        assertGt(usdc.balanceOf(payer), payerBalanceBefore);
        // Delegate balance unchanged
        assertEq(usdc.balanceOf(delegate), delegateBalanceBefore);
    }

    function test_PauseMechanismBlocksDelegatedFunctions() public {
        // Owner pauses
        vm.prank(owner);
        jobMarketplace.pause();

        vm.prank(delegate);
        vm.expectRevert("Pausable: paused");
        jobMarketplace.createSessionForModelAsDelegate(
            payer, TINY_VICUNA_MODEL_ID, host, address(usdc),
            10e6, MIN_PRICE_STABLE, 3600, 100, 300
        );
    }

    function test_PayerCanUseNonDelegatedFunctions() public {
        // Payer can still create sessions directly
        vm.prank(payer);
        usdc.approve(address(jobMarketplace), 100e6);

        vm.prank(payer);
        uint256 sessionId = jobMarketplace.createSessionJobForModelWithToken(
            host, TINY_VICUNA_MODEL_ID, address(usdc),
            50e6, MIN_PRICE_STABLE, 3600, 100, 300
        );
        assertGt(sessionId, 0);
    }
}
```

**Verification:**
```bash
forge test --match-contract DelegationSecurityTest -vv
```

---

### Sub-phase 4.2: Security Review

**Goal**: Final security review checklist.

**Tasks:**
- [ ] Review authorization check is FIRST in function
- [ ] Verify `safeTransferFrom` used (not `transferFrom`)
- [ ] Verify session ownership uses `payer` address
- [ ] Verify events log both payer and delegate
- [ ] Run full test suite - no regressions
- [ ] Mark Phase 4 complete

**Security Checklist:**
```
[ ] Authorization checked BEFORE any state change or transfer
[ ] Uses safeTransferFrom (reverts on failure)
[ ] session.depositor = payer (NOT msg.sender)
[ ] userSessions[payer] updated (NOT msg.sender)
[ ] Refunds use session.depositor
[ ] nonReentrant modifier present
[ ] whenNotPaused modifier present
[ ] Events log both payer and delegate addresses
[ ] ETH explicitly rejected (address(0) check)
```

**Verification:**
```bash
forge test
# All tests must pass
```

---

## Phase 5: Documentation and Deployment

### Sub-phase 5.1: Update Documentation

**Goal**: Update all relevant documentation.

**Tasks:**
- [ ] Update `client-abis/README.md` with new functions
- [ ] Regenerate ABI: `client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json`
- [ ] Update `docs/API_REFERENCE.md` with V2 functions
- [ ] Update `docs/BREAKING_CHANGES.md` with escrow removal
- [ ] Create SDK integration example
- [ ] Mark documentation complete

**ABI Extraction:**
```bash
cat out/JobMarketplaceWithModelsUpgradeable.sol/JobMarketplaceWithModelsUpgradeable.json | jq '.abi' > client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json
```

**SDK Example:**
```typescript
// V2 Direct Payment Delegation - SDK Integration

const APPROVAL_AMOUNT = parseUnits("1000", 6); // $1,000 USDC

// One-time setup (2 popups total)
async function setupDelegation(marketplace, usdc, primaryWallet, subAccount) {
  // 1. Approve USDC to contract
  await usdc.connect(primaryWallet).approve(marketplace.address, APPROVAL_AMOUNT);

  // 2. Authorize sub-account
  await marketplace.connect(primaryWallet).authorizeDelegate(subAccount.address, true);
}

// Per-session (NO popup!)
async function createDelegatedSession(marketplace, subAccount, payerAddress, params) {
  const tx = await marketplace.connect(subAccount).createSessionForModelAsDelegate(
    payerAddress,           // payer
    params.modelId,         // model
    params.hostAddress,     // host
    params.usdcAddress,     // USDC token
    params.amount,          // session amount
    params.pricePerToken,   // price
    params.maxDuration,     // duration
    params.proofInterval,   // proof interval
    params.proofTimeoutWindow // timeout
  );
  return tx;
}

// Check allowance before session
async function checkAllowance(usdc, payer, marketplace, sessionAmount) {
  const allowance = await usdc.allowance(payer, marketplace.address);
  if (allowance < sessionAmount) {
    // Prompt re-approval
    await usdc.connect(payer).approve(marketplace.address, APPROVAL_AMOUNT);
  }
}
```

---

### Sub-phase 5.2: Deploy and Verify

**Goal**: Deploy upgraded contract and verify.

**Tasks:**
- [ ] Deploy new implementation contract
- [ ] Upgrade remediation proxy to new implementation
- [ ] Verify authorization functions work
- [ ] Verify direct payment delegation works
- [ ] Test full flow: approve → authorize → delegate session
- [ ] Update `docs/REMEDIATION_CHANGES.md` with deployment
- [ ] Mark Phase 5 complete

**Deployment Commands:**
```bash
# Deploy new implementation
JOB_IMPL=$(forge create src/JobMarketplaceWithModelsUpgradeable.sol:JobMarketplaceWithModelsUpgradeable \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --json | jq -r '.deployedTo')

echo "New implementation: $JOB_IMPL"

# Upgrade remediation proxy (owner only)
JOB_PROXY=0x95132177F964FF053C1E874b53CF74d819618E06
cast send $JOB_PROXY "upgradeToAndCall(address,bytes)" $JOB_IMPL 0x \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Verify new functions exist
cast call $JOB_PROXY "isDelegateAuthorized(address,address)" $PAYER $DELEGATE \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

**Verification:**
```bash
# Test authorization
cast send $JOB_PROXY "authorizeDelegate(address,bool)" $DELEGATE true \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Verify
cast call $JOB_PROXY "isDelegateAuthorized(address,address)" $MY_ADDRESS $DELEGATE \
  --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: true
```

---

## Completion Criteria

All phases complete when:
- [ ] Rollback successful, clean baseline
- [ ] Escrow functions removed
- [ ] Authorization infrastructure added
- [ ] Both V2 delegation functions implemented
- [ ] All security tests pass
- [ ] Full test suite passes
- [ ] Documentation updated
- [ ] Contract deployed and verified on testnet

---

## File Summary

| File | Action | Max Lines |
|------|--------|-----------|
| `src/JobMarketplaceWithModelsUpgradeable.sol` | Modify | -105 lines (escrow), +190 lines (V2) |
| `test/SecurityFixes/EscrowRemoval/test_escrow_removed.t.sol` | Create | 80 lines |
| `test/SecurityFixes/DelegatedSessions/test_delegation_authorization.t.sol` | Create | 100 lines |
| `test/SecurityFixes/DelegatedSessions/test_direct_payment_delegation.t.sol` | Create | 250 lines |
| `test/SecurityFixes/DelegatedSessions/test_delegation_security.t.sol` | Create | 150 lines |

---

## Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| `authorizeDelegate(true)` | ~45,000 |
| `authorizeDelegate(false)` | ~23,000 |
| `isDelegateAuthorized()` | ~2,600 |
| `createSessionAsDelegate()` | ~180,000 |
| `createSessionForModelAsDelegate()` | ~185,000 |

**Note**: V2 uses more gas per session than V1 (~60k more due to `transferFrom`) but eliminates escrow complexity and user confusion.

---

## Notes

### TDD Approach (Bounded Autonomy)

Each sub-phase follows strict TDD:
1. **RED**: Write tests FIRST, verify they FAIL (compilation or assertion)
2. **GREEN**: Implement minimal code to pass tests
3. **REFACTOR**: Clean up while keeping tests green
4. **COMMIT**: Commit with descriptive message

### Commit Message Format

```
feat(delegation-v2): Add direct payment delegation functions

- Remove escrow/deposit functions
- Add createSessionAsDelegate (USDC direct payment)
- Add createSessionForModelAsDelegate (USDC direct payment)
- Session owned by payer, refunds go to payer

Breaking: Escrow functions removed
Ref: SDK-REQUEST-V2-DELEGATION
```

### Breaking Changes

| Removed | Replacement |
|---------|-------------|
| `depositToken()` | `usdc.approve(marketplace, amount)` |
| `depositNative()` | N/A (ETH delegation not supported) |
| `withdrawToken()` | N/A (funds stay in wallet) |
| `withdrawNative()` | N/A |
| `createSessionFromDeposit()` | `createSessionJobWithToken()` |
| `createSessionFromDepositAsDelegate()` | `createSessionAsDelegate()` |
| `createSessionFromDepositForModelAsDelegate()` | `createSessionForModelAsDelegate()` |

### Security Benefits

- **Smaller attack surface**: No escrow state to manage
- **No withdrawal bugs**: Funds stay in user's wallet until needed
- **Standard pattern**: ERC-20 approve + transferFrom is well-understood
- **Bounded risk**: User controls approval amount ($1,000 default)
