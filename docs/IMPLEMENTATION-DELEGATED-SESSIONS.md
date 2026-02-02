# IMPLEMENTATION-DELEGATED-SESSIONS.md - Delegated Session Creation for Sub-Account Support

## Overview

Add delegated session creation to enable Coinbase Smart Wallet sub-accounts to create sessions using the primary account's pre-deposited funds. This enables popup-free transactions after initial setup.

## Repository

fabstir-compute-contracts

## Feature Reference

- **Requested By**: SDK Developer
- **Branch**: `feature/delegated-sessions`
- **Priority**: HIGH (UX improvement for repeat users)

## Problem Statement

Current `createSessionFromDepositForModel` uses `msg.sender` to look up deposits:
- When sub-account calls function: `msg.sender` = sub-account address
- `userDeposits[sub-account]` = 0 (sub-account never deposited)
- Transaction reverts with "Insufficient balance"

The primary account has the deposit, but the sub-account cannot access it.

## Solution Design

**Approach**: Mapping-based delegation (`isAuthorizedDelegate[depositor][delegate]`)

**Why this approach:**
- Matches existing `authorizedCallers` pattern in HostEarnings/ProofSystem
- Gas-efficient: ~2,100 gas per check (vs ~6,000 for signature verification)
- Simple to audit and maintain
- Persistent authorization ideal for sub-accounts

## User Flow

```typescript
// 0. User deposits funds (one-time, from primary wallet)
await marketplace.connect(primaryWallet).depositToken(usdcAddress, amount);

// 1. One-time setup (from primary wallet - requires popup)
await marketplace.connect(primaryWallet).authorizeDelegate(subAccount, true);

// 2. Subsequent sessions (from sub-account, NO popup!)
await marketplace.connect(subAccount).createSessionFromDepositForModelAsDelegate(
    primaryWallet.address,  // depositor whose funds to use
    modelId,
    host,
    usdcAddress,
    depositAmount,
    pricePerToken,
    maxDuration,
    proofInterval,
    proofTimeoutWindow
);
```

## Implementation Progress

**Overall Status: COMPLETE (100%)**

- [x] **Phase 1: Storage and Events** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 1.1: Write Tests for Storage Layout
  - [x] Sub-phase 1.2: Add Storage and Events
- [x] **Phase 2: Authorization Functions** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 2.1: Write Tests for Authorization
  - [x] Sub-phase 2.2: Implement Authorization Functions
- [x] **Phase 3: Delegated Session Creation** (3/3 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 3.1: Write Tests for Delegated Sessions
  - [x] Sub-phase 3.2: Implement createSessionFromDepositAsDelegate
  - [x] Sub-phase 3.3: Implement createSessionFromDepositForModelAsDelegate
- [x] **Phase 4: Security Hardening** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 4.1: Write Security Tests
  - [x] Sub-phase 4.2: Security Review and Edge Cases
- [x] **Phase 5: Documentation and Deployment** (2/2 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 5.1: Update Documentation
  - [x] Sub-phase 5.2: Deploy and Verify

**Last Updated:** 2026-02-02

**Documentation Updated:**
- client-abis/CHANGELOG.md
- client-abis/README.md
- docs/API_REFERENCE.md
- docs/ARCHITECTURE.md
- docs/BREAKING_CHANGES.md
- docs/REMEDIATION_CHANGES.md

---

## Phase 1: Storage and Events

**Goal**: Add delegation mapping and events without breaking UUPS upgrade safety.

### Sub-phase 1.1: Write Tests for Storage Layout

**Goal**: Verify storage additions don't break upgrade safety.

**Tasks:**
- [x] Create test file `test/SecurityFixes/DelegatedSessions/test_storage_layout.t.sol`
- [x] Test: Contract compiles with new mapping
- [x] Test: Storage gap reduced correctly (35 → 34)
- [x] Test: Existing storage slots unchanged after upgrade
- [x] Test: New mapping is accessible and writable
- [x] Run tests and verify compilation fails (mapping doesn't exist yet)

**File Limits:**
- Test file: 60 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_storage_layout.t.sol
contract DelegatedSessionStorageTest is TestSetupUpgradeable {
    function test_StorageGapReduced() public {
        // Verify __gap is now 34 slots, not 35
    }

    function test_DelegationMappingAccessible() public {
        // Verify isAuthorizedDelegate mapping exists and is writable
    }

    function test_ExistingStorageUnchanged() public {
        // Verify userDepositsNative, userDepositsToken unchanged
    }
}
```

**Verification:**
```bash
forge test --match-contract DelegatedSessionStorageTest -vv
# Expected: Compilation fails (mapping doesn't exist)
```

---

### Sub-phase 1.2: Add Storage and Events

**Goal**: Add delegation mapping and events to contract.

**Tasks:**
- [x] Add `isAuthorizedDelegate` mapping after line 158 (after chainConfig)
- [x] Reduce `__gap` from 35 to 34 slots
- [x] Add `DelegateAuthorized` event
- [x] Add `SessionCreatedByDelegate` event
- [x] Run `forge build` to verify compilation
- [x] Run storage layout test to verify no collisions

**Implementation (add after line 158):**
```solidity
// Delegation mapping for Smart Wallet sub-account support
// depositor => delegate => authorized
mapping(address => mapping(address => bool)) public isAuthorizedDelegate;

// Storage gap reduced from 35 to 34 (1 mapping = 1 slot)
uint256[34] private __gap;
```

**Events (add after line 201):**
```solidity
/// @notice Emitted when a delegate is authorized or revoked
event DelegateAuthorized(
    address indexed depositor,
    address indexed delegate,
    bool authorized
);

/// @notice Emitted when a session is created by a delegate
event SessionCreatedByDelegate(
    uint256 indexed sessionId,
    address indexed depositor,
    address indexed delegate,
    address host,
    bytes32 modelId,
    uint256 deposit
);
```

**File Limits:**
- Lines added: 15 lines (mapping + gap change + 2 events)

**Verification:**
```bash
forge build
forge test --match-contract DelegatedSessionStorageTest -vv
```

---

## Phase 2: Authorization Functions

**Goal**: Implement delegate authorization management.

### Sub-phase 2.1: Write Tests for Authorization

**Goal**: Verify authorization functions work correctly.

**Tasks:**
- [x] Create test file `test/SecurityFixes/DelegatedSessions/test_delegation_authorization.t.sol`
- [x] Test: `authorizeDelegate(delegate, true)` authorizes delegate
- [x] Test: `authorizeDelegate(delegate, false)` revokes authorization
- [x] Test: `isDelegateAuthorized()` returns correct status
- [x] Test: Cannot authorize zero address (reverts)
- [x] Test: Cannot authorize self (reverts)
- [x] Test: Emits `DelegateAuthorized` event
- [x] Test: Multiple depositors can have different delegates
- [x] Test: One delegate can serve multiple depositors
- [x] Run tests and verify they FAIL (functions don't exist)

**File Limits:**
- Test file: 120 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_delegation_authorization.t.sol
contract DelegationAuthorizationTest is TestSetupUpgradeable {
    address depositor;
    address delegate;

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

    function test_MultipleDelegatorsIndependentDelegates() public { /* ... */ }
    function test_OneDelegateMultipleDepositors() public { /* ... */ }
}
```

**Verification:**
```bash
forge test --match-contract DelegationAuthorizationTest -vv
# Expected: Compilation fails (functions don't exist)
```

---

### Sub-phase 2.2: Implement Authorization Functions

**Goal**: Add authorize and query functions.

**Tasks:**
- [x] Add `authorizeDelegate(address delegate, bool authorized)` function
- [x] Add `isDelegateAuthorized(address depositor, address delegate)` view function
- [x] Validate delegate is not zero address
- [x] Validate delegate is not msg.sender (self)
- [x] Emit `DelegateAuthorized` event
- [x] Run all authorization tests - all passing
- [x] Mark sub-phase complete

**Implementation (add after line 928, after withdrawToken):**
```solidity
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
 * @notice Check if a delegate is authorized for a depositor
 * @param depositor The primary account address
 * @param delegate The delegate address to check
 * @return True if delegate is authorized for depositor
 */
function isDelegateAuthorized(address depositor, address delegate)
    external view returns (bool)
{
    return isAuthorizedDelegate[depositor][delegate];
}
```

**File Limits:**
- Lines added: 20 lines (2 functions)

**Verification:**
```bash
forge test --match-contract DelegationAuthorizationTest -vv
forge test  # Full suite - no regressions
```

---

## Phase 3: Delegated Session Creation

**Goal**: Implement delegated session creation functions.

### Sub-phase 3.1: Write Tests for Delegated Sessions

**Goal**: Comprehensive tests for delegated session creation.

**Tasks:**
- [x] Create test file `test/SecurityFixes/DelegatedSessions/test_delegated_session_creation.t.sol`
- [x] Test: Successfully creates session from depositor's ETH balance
- [x] Test: Successfully creates session from depositor's USDC balance
- [x] Test: Session owner is depositor (not delegate)
- [x] Test: Funds deducted from depositor's balance
- [x] Test: Unauthorized delegate reverts with "Not authorized delegate"
- [x] Test: Revoked delegate cannot create sessions
- [x] Test: Insufficient depositor balance reverts
- [x] Test: Emits `SessionCreatedByDelegate` event
- [x] Test: Emits standard session events (SessionJobCreated, etc.)
- [x] Test: Depositor can still create sessions directly
- [x] Test: Multiple sessions by same delegate
- [x] Test: Zero depositor address reverts
- [x] Run tests and verify they FAIL (functions don't exist)

**File Limits:**
- Test file: 200 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_delegated_session_creation.t.sol
contract DelegatedSessionCreationTest is TestSetupUpgradeable {
    address depositor;
    address delegate;
    uint256 depositAmount = 1 ether;

    function setUp() public override {
        super.setUp();
        depositor = makeAddr("depositor");
        delegate = makeAddr("delegate");

        // Setup: depositor deposits funds
        vm.deal(depositor, 10 ether);
        vm.prank(depositor);
        jobMarketplace.depositNative{value: 5 ether}();

        // Setup: depositor authorizes delegate
        vm.prank(depositor);
        jobMarketplace.authorizeDelegate(delegate, true);
    }

    function test_CreateSessionAsDelegate_ETH_Success() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        assertGt(sessionId, 0);
    }

    function test_CreateSessionAsDelegate_SessionOwnerIsDepositor() public {
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );

        (,address sessionDepositor,,,,,,,,,,,,,,,,) = jobMarketplace.sessionJobs(sessionId);
        assertEq(sessionDepositor, depositor);  // NOT delegate!
    }

    function test_CreateSessionAsDelegate_DeductsFundsFromDepositor() public {
        uint256 balanceBefore = jobMarketplace.userDepositsNative(depositor);

        vm.prank(delegate);
        jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );

        uint256 balanceAfter = jobMarketplace.userDepositsNative(depositor);
        assertEq(balanceAfter, balanceBefore - depositAmount);
    }

    function test_CreateSessionAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_CreateSessionAsDelegate_EmitsSessionCreatedByDelegate() public {
        vm.prank(delegate);
        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDelegate(1, depositor, delegate, host, bytes32(0), depositAmount);
        jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    // ... additional tests
}
```

**Verification:**
```bash
forge test --match-contract DelegatedSessionCreationTest -vv
# Expected: Compilation fails (functions don't exist)
```

---

### Sub-phase 3.2: Implement createSessionFromDepositAsDelegate

**Goal**: Add non-model delegated session creation.

**Tasks:**
- [x] Add `createSessionFromDepositAsDelegate()` function after `createSessionFromDeposit()`
- [x] Validate depositor is not zero address
- [x] Check authorization: `msg.sender == depositor || isAuthorizedDelegate[depositor][msg.sender]`
- [x] Deduct funds from `depositor`'s balance (not msg.sender)
- [x] Set `session.depositor = depositor`
- [x] Add to `userSessions[depositor]` (not msg.sender)
- [x] Emit `SessionCreatedByDelegate` event when delegate != depositor
- [x] Run non-model delegated session tests - all passing

**Implementation (add after createSessionFromDeposit, ~line 1107):**
```solidity
/**
 * @notice Create a session from pre-deposited funds on behalf of a depositor
 * @dev Caller must be depositor OR authorized delegate for the depositor
 * @param depositor The primary account whose deposits to use
 * @param host The host to create the session with
 * @param paymentToken address(0) for ETH, token address for ERC20
 * @param deposit Amount to use from depositor's pre-deposited balance
 * @param pricePerToken Price per inference token
 * @param maxDuration Maximum session duration in seconds
 * @param proofInterval Minimum tokens per proof submission
 * @param proofTimeoutWindow Time in seconds before session times out without proof
 * @return sessionId The created session ID
 */
function createSessionFromDepositAsDelegate(
    address depositor,
    address host,
    address paymentToken,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval,
    uint256 proofTimeoutWindow
) external nonReentrant whenNotPaused returns (uint256 sessionId) {
    // Delegation validation
    require(depositor != address(0), "Invalid depositor");
    require(
        msg.sender == depositor || isAuthorizedDelegate[depositor][msg.sender],
        "Not authorized delegate"
    );

    // Standard parameter validation
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

    // Price validation using default pricing (non-model session)
    (uint256 hostMinNative, uint256 hostMinStable) = nodeRegistry.getNodePricing(host);
    if (paymentToken == address(0)) {
        require(pricePerToken >= hostMinNative, "Price below host minimum (native)");
    } else {
        require(pricePerToken >= hostMinStable, "Price below host minimum (stable)");
    }

    // Deduct from DEPOSITOR's balance (not msg.sender)
    if (paymentToken == address(0)) {
        require(deposit >= MIN_DEPOSIT, "Insufficient deposit");
        require(deposit <= 1000 ether, "Deposit too large");
        require(userDepositsNative[depositor] >= deposit, "Insufficient native balance");
        userDepositsNative[depositor] -= deposit;
    } else {
        require(acceptedTokens[paymentToken], "Token not accepted");
        uint256 minRequired = tokenMinDeposits[paymentToken];
        uint256 maxAllowed = tokenMaxDeposits[paymentToken];
        require(minRequired > 0, "Token not configured");
        require(maxAllowed > 0, "Token max deposit not configured");
        require(deposit >= minRequired, "Insufficient deposit");
        require(deposit <= maxAllowed, "Deposit too large");
        require(userDepositsToken[depositor][paymentToken] >= deposit, "Insufficient token balance");
        userDepositsToken[depositor][paymentToken] -= deposit;
    }

    sessionId = nextJobId++;

    SessionJob storage session = sessionJobs[sessionId];
    session.id = sessionId;
    session.depositor = depositor;  // CRITICAL: depositor owns session, NOT msg.sender
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

    userSessions[depositor].push(sessionId);  // CRITICAL: depositor's sessions
    hostSessions[host].push(sessionId);

    emit SessionJobCreated(sessionId, depositor, host, deposit);
    emit SessionCreatedByDepositor(sessionId, depositor, host, deposit);

    // Emit delegate-specific event if caller is not the depositor
    if (msg.sender != depositor) {
        emit SessionCreatedByDelegate(sessionId, depositor, msg.sender, host, bytes32(0), deposit);
    }

    return sessionId;
}
```

**File Limits:**
- Lines added: 85 lines (new function)

**Verification:**
```bash
forge test --match-test "CreateSessionAsDelegate" -vv
```

---

### Sub-phase 3.3: Implement createSessionFromDepositForModelAsDelegate

**Goal**: Add model-specific delegated session creation (highest priority function).

**Tasks:**
- [x] Add `createSessionFromDepositForModelAsDelegate()` function after the non-model version
- [x] Include all validations from non-model version
- [x] Add modelId validation (not bytes32(0))
- [x] Validate host supports model via `nodeRegistry.nodeSupportsModel()`
- [x] Use model-specific pricing via `nodeRegistry.getModelPricing()`
- [x] Store modelId in `sessionModel[sessionId]` mapping
- [x] Emit `SessionJobCreatedForModel` event
- [x] Run model delegated session tests - all passing
- [x] Mark sub-phase complete

**Implementation (add after createSessionFromDepositAsDelegate):**
```solidity
/**
 * @notice Create a model-specific session from pre-deposited funds on behalf of a depositor
 * @dev Caller must be depositor OR authorized delegate for the depositor
 * @param depositor The primary account whose deposits to use
 * @param modelId The approved model ID for this session
 * @param host The host to create the session with
 * @param paymentToken address(0) for ETH, token address for ERC20
 * @param deposit Amount to use from depositor's pre-deposited balance
 * @param pricePerToken Price per inference token
 * @param maxDuration Maximum session duration in seconds
 * @param proofInterval Minimum tokens per proof submission
 * @param proofTimeoutWindow Time in seconds before session times out without proof
 * @return sessionId The created session ID
 */
function createSessionFromDepositForModelAsDelegate(
    address depositor,
    bytes32 modelId,
    address host,
    address paymentToken,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval,
    uint256 proofTimeoutWindow
) external nonReentrant whenNotPaused returns (uint256 sessionId) {
    // Delegation validation
    require(depositor != address(0), "Invalid depositor");
    require(
        msg.sender == depositor || isAuthorizedDelegate[depositor][msg.sender],
        "Not authorized delegate"
    );

    // Model validation
    require(modelId != bytes32(0), "Invalid model ID");

    // Standard parameter validation
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

    // Model-specific validation: host must support the model
    require(nodeRegistry.nodeSupportsModel(host, modelId), "Host does not support model");

    // Model-specific pricing validation
    uint256 hostMinPrice = nodeRegistry.getModelPricing(host, modelId, paymentToken);
    require(pricePerToken >= hostMinPrice, "Price below host minimum for model");

    // Deduct from DEPOSITOR's balance (not msg.sender)
    if (paymentToken == address(0)) {
        require(deposit >= MIN_DEPOSIT, "Insufficient deposit");
        require(deposit <= 1000 ether, "Deposit too large");
        require(userDepositsNative[depositor] >= deposit, "Insufficient native balance");
        userDepositsNative[depositor] -= deposit;
    } else {
        require(acceptedTokens[paymentToken], "Token not accepted");
        uint256 minRequired = tokenMinDeposits[paymentToken];
        uint256 maxAllowed = tokenMaxDeposits[paymentToken];
        require(minRequired > 0, "Token not configured");
        require(maxAllowed > 0, "Token max deposit not configured");
        require(deposit >= minRequired, "Insufficient deposit");
        require(deposit <= maxAllowed, "Deposit too large");
        require(userDepositsToken[depositor][paymentToken] >= deposit, "Insufficient token balance");
        userDepositsToken[depositor][paymentToken] -= deposit;
    }

    sessionId = nextJobId++;

    SessionJob storage session = sessionJobs[sessionId];
    session.id = sessionId;
    session.depositor = depositor;  // CRITICAL: depositor owns session
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

    // Store model for this session
    sessionModel[sessionId] = modelId;

    userSessions[depositor].push(sessionId);  // CRITICAL: depositor's sessions
    hostSessions[host].push(sessionId);

    emit SessionJobCreated(sessionId, depositor, host, deposit);
    emit SessionCreatedByDepositor(sessionId, depositor, host, deposit);
    emit SessionJobCreatedForModel(sessionId, depositor, host, modelId, deposit);

    // Emit delegate-specific event if caller is not the depositor
    if (msg.sender != depositor) {
        emit SessionCreatedByDelegate(sessionId, depositor, msg.sender, host, modelId, deposit);
    }

    return sessionId;
}
```

**File Limits:**
- Lines added: 95 lines (new function)

**Verification:**
```bash
forge test --match-test "CreateSessionForModelAsDelegate" -vv
forge test  # Full suite
```

---

## Phase 4: Security Hardening

**Goal**: Verify security properties and edge cases.

### Sub-phase 4.1: Write Security Tests

**Goal**: Comprehensive security test coverage.

**Tasks:**
- [x] Create test file `test/SecurityFixes/DelegatedSessions/test_delegation_security.t.sol`
- [x] Test: Unauthorized address cannot drain any deposits
- [x] Test: Previously authorized delegate fails after revocation
- [x] Test: Delegate cannot access other users' deposits
- [x] Test: Session refunds go to depositor (not delegate)
- [x] Test: Session completion allowed by depositor or host only
- [x] Test: Reentrancy protection active on delegated functions
- [x] Test: Pause mechanism blocks delegated functions
- [x] Run all security tests - all passing

**File Limits:**
- Test file: 150 lines maximum

**Test File:**
```solidity
// test/SecurityFixes/DelegatedSessions/test_delegation_security.t.sol
contract DelegationSecurityTest is TestSetupUpgradeable {
    function test_UnauthorizedCannotDrainDeposits() public {
        // Attacker tries to use victim's deposits without authorization
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");

        // Victim deposits funds
        vm.deal(victim, 10 ether);
        vm.prank(victim);
        jobMarketplace.depositNative{value: 5 ether}();

        // Attacker tries to create session using victim's funds
        vm.prank(attacker);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionFromDepositAsDelegate(
            victim, host, address(0), 1 ether,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_RevokedDelegateCannotCreateSession() public {
        // Setup: authorize then revoke
        vm.startPrank(depositor);
        jobMarketplace.authorizeDelegate(delegate, true);
        jobMarketplace.authorizeDelegate(delegate, false);
        vm.stopPrank();

        // Delegate tries to create session after revocation
        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), 1 ether,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_SessionRefundsGoToDepositor() public {
        // Create session via delegate
        vm.prank(delegate);
        uint256 sessionId = jobMarketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), 1 ether,
            pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );

        // Complete session - refund should go to depositor
        uint256 depositorBalanceBefore = depositor.balance;
        vm.prank(depositor);
        jobMarketplace.completeSessionJob(sessionId, "cid");

        // Depositor receives refund (minus host earnings)
        assertGt(depositor.balance, depositorBalanceBefore);
    }

    function test_DelegateCannotAccessOtherUsersDeposits() public { /* ... */ }
    function test_ReentrancyProtection() public { /* ... */ }
    function test_PauseMechanismBlocksDelegatedFunctions() public { /* ... */ }
}
```

**Verification:**
```bash
forge test --match-contract DelegationSecurityTest -vv
```

---

### Sub-phase 4.2: Security Review and Edge Cases

**Goal**: Final security review.

**Tasks:**
- [x] Review authorization check is FIRST in function (before any state changes)
- [x] Verify all deposit deductions use `depositor` address
- [x] Verify all session assignments use `depositor` address
- [x] Check for front-running vulnerabilities
- [x] Verify event emissions are correct
- [x] Run full test suite - no regressions
- [x] Mark Phase 4 complete

**Security Checklist:**
```
[x] Authorization checked before ANY state change
[x] Deposits deducted from `depositor`, not `msg.sender`
[x] session.depositor = depositor (not msg.sender)
[x] userSessions[depositor] updated (not msg.sender)
[x] Refunds use session.depositor
[x] nonReentrant modifier present
[x] whenNotPaused modifier present
[x] Events log both depositor and delegate
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
- [x] Update `CLAUDE.md` with new functions and usage
- [x] Update `client-abis/README.md` with new function signatures
- [x] Extract new ABIs to `client-abis/`
- [x] Create SDK integration example in docs
- [x] Mark documentation complete

**ABI Extraction:**
```bash
cat out/JobMarketplaceWithModelsUpgradeable.sol/JobMarketplaceWithModelsUpgradeable.json | jq '.abi' > client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json
```

**SDK Example for docs:**
```typescript
// docs/examples/delegated-sessions.ts

// Step 0: User deposits funds (one-time)
const depositTx = await marketplace.connect(primaryWallet).depositToken(
  usdcAddress,
  ethers.parseUnits("100", 6)  // 100 USDC
);
await depositTx.wait();

// Step 1: Authorize sub-account (one-time)
const authTx = await marketplace.connect(primaryWallet).authorizeDelegate(
  subAccountAddress,
  true
);
await authTx.wait();

// Step 2: Create sessions from sub-account (popup-free!)
const sessionTx = await marketplace.connect(subAccount).createSessionFromDepositForModelAsDelegate(
  primaryWallet.address,  // depositor
  modelId,                // bytes32 model ID
  hostAddress,            // host
  usdcAddress,           // payment token
  ethers.parseUnits("10", 6),  // 10 USDC deposit
  ethers.parseUnits("0.001", 6),  // price per token
  3600,                   // 1 hour max duration
  100,                    // proof every 100 tokens
  300                     // 5 minute timeout window
);
const receipt = await sessionTx.wait();
const sessionId = receipt.logs[0].args.jobId;
```

---

### Sub-phase 5.2: Deploy and Verify

**Goal**: Deploy upgraded contract and verify.

**Tasks:**
- [x] Deploy new implementation contract: `0x305EC43ae2D6D110c2db8DD9F5420FFd2b551F57`
- [x] Upgrade proxy to new implementation (owner only)
- [x] Verify delegation functions accessible
- [x] Test authorization on testnet
- [x] Test delegated session creation on testnet
- [x] Mark Phase 5 complete

**Deployment Commands:**
```bash
# Deploy new implementation
JOB_IMPL=$(forge create src/JobMarketplaceWithModelsUpgradeable.sol:JobMarketplaceWithModelsUpgradeable \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --json | jq -r '.deployedTo')

echo "New implementation: $JOB_IMPL"

# Upgrade proxy (owner only)
JOB_PROXY=0x3CaCbf3f448B420918A93a88706B26Ab27a3523E
cast send $JOB_PROXY "upgradeToAndCall(address,bytes)" $JOB_IMPL 0x \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Verify new functions exist
cast call $JOB_PROXY "isDelegateAuthorized(address,address)" $DEPOSITOR $DELEGATE \
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
- [x] Storage and events added without breaking upgrades
- [x] Authorization functions work correctly
- [x] Both delegated session functions implemented
- [x] All security tests pass
- [x] Full test suite passes (no regressions)
- [x] Documentation updated
- [x] Contract deployed and verified on testnet

### Final Deployment Details (Feb 2, 2026)
- **New Implementation**: `0x305EC43ae2D6D110c2db8DD9F5420FFd2b551F57`
- **Proxy Address**: `0x95132177F964FF053C1E874b53CF74d819618E06` (remediation proxy)
- **Upgrade Tx**: `0x3420eef983fb57eb642af6d05fbc0da2d401d49c74fdfe8129ce3066f9594e3e`

### Remediation Contract Addresses
```
CONTRACT_JOB_MARKETPLACE=0x95132177F964FF053C1E874b53CF74d819618E06
CONTRACT_PROOF_SYSTEM=0xE8DCa89e1588bbbdc4F7D5F78263632B35401B31
CONTRACT_NODE_REGISTRY=0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22
CONTRACT_HOST_EARNINGS=0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0
CONTRACT_MODEL_REGISTRY=0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2
```

---

## File Summary

| File | Action | Max Lines |
|------|--------|-----------|
| `src/JobMarketplaceWithModelsUpgradeable.sol` | Modify | +215 lines |
| `test/SecurityFixes/DelegatedSessions/test_storage_layout.t.sol` | Create | 60 lines |
| `test/SecurityFixes/DelegatedSessions/test_delegation_authorization.t.sol` | Create | 120 lines |
| `test/SecurityFixes/DelegatedSessions/test_delegated_session_creation.t.sol` | Create | 200 lines |
| `test/SecurityFixes/DelegatedSessions/test_delegation_security.t.sol` | Create | 150 lines |

---

## Gas Estimates

| Operation | Estimated Gas |
|-----------|---------------|
| `authorizeDelegate(true)` | ~45,000 |
| `authorizeDelegate(false)` | ~23,000 |
| `isDelegateAuthorized()` | ~2,600 |
| `createSessionFromDepositAsDelegate()` | ~172,000 |
| `createSessionFromDepositForModelAsDelegate()` | ~175,000 |

**Delegation check overhead**: ~2,100 gas (one SLOAD)

---

## Notes

### TDD Approach (Bounded Autonomy)

Each sub-phase follows strict TDD:
1. **RED**: Write tests FIRST, verify they FAIL
2. **GREEN**: Implement minimal code to pass tests
3. **REFACTOR**: Clean up while keeping tests green
4. **COMMIT**: Commit with descriptive message

### Commit Message Format

```
feat(delegation): Add delegate authorization functions

- Add isAuthorizedDelegate mapping
- Add authorizeDelegate() function
- Add isDelegateAuthorized() view function
- Emit DelegateAuthorized event

Ref: SDK-REQUEST-SUBACCOUNT
```

### Breaking Changes

| Change | SDK Impact |
|--------|------------|
| New storage mapping | None - additive |
| New functions | None - additive |
| New events | SDK should listen for SessionCreatedByDelegate |

### Upgrade Safety

- Storage gap reduced from 35 to 34 (safe)
- New mapping added before gap (safe)
- No existing storage slots moved (safe)
- Existing functions unchanged (safe)
