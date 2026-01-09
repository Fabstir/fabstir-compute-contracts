# Security Audit Remediation Report V3

**Report Date:** January 8, 2026
**Previous Remediation:** `docs/SECURITY-AUDIT-REMEDIATION-REPORT.md` (January 7, 2026)
**Branch:** `fix/audit-remediation-v3`
**Network:** Base Sepolia (Chain ID: 84532)

---

## Executive Summary

This report addresses remaining code quality issues from the January 2026 security audit that were not prioritized in the initial remediation (V1/V2). These are non-security improvements focused on code maintainability and best practices.

| Severity     | Issues Identified | Issues Fixed | Status      |
| ------------ | ----------------- | ------------ | ----------- |
| Code Quality | 8 planned + 3 deferred | 7       | In Progress |

**Phases Overview:**

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | HostEarningsUpgradeable Code Deduplication | ✅ Complete |
| 2 | Unrestricted `receive` Function Fixes | ✅ Complete |
| 3 | Deprecated Funds Transfer Method Usage | ✅ Complete |
| 4 | Variables Named as Constants | ✅ Complete |
| 5 | Session Creation Code Deduplication | ✅ Complete |
| 6 | Model Tiers Design Duplication | ✅ Complete |
| 7 | Unbounded Array Iteration | ✅ Complete |
| 8 | ProofSystem Function Naming Clarity | ✅ Complete |
| 9 | Inline Comment Cleanup (Final Pass) | ✅ Complete |
| 10 | Architecture and Testing System Improvements | Planned |
| 11 | Solidity Upgrade + ReentrancyGuard Replacement | Planned |

**Focus:** Code quality improvements across all upgradeable contracts.

---

## Phase 1: HostEarningsUpgradeable Code Deduplication

### 1.1 Duplications in Withdrawal Functions

**Severity:** Code Quality (LOW)
**Original Finding:**

> The `withdraw`, `withdrawAll`, and `withdrawMultiple` functions share same funds withdrawal logic which can be isolated in a separate function for simplicity.

**Duplicated Code (appears 3 times):**

```solidity
if (token == address(0)) {
    // ETH withdrawal
    (bool success, ) = payable(msg.sender).call{value: amount}("");
    require(success, "ETH transfer failed");
} else {
    // ERC20 withdrawal
    IERC20(token).transfer(msg.sender, amount);
}

emit EarningsWithdrawn(msg.sender, token, amount, remainingBalance);
```

**Current Locations:**

| Function | Lines | Description |
| -------- | ----- | ----------- |
| `withdraw()` | 130-144 | Withdraw specific amount |
| `withdrawAll()` | 158-167 | Withdraw full balance for token |
| `withdrawMultiple()` | 181-190 | Withdraw multiple tokens in loop |

**Fix Plan:**

Extract common withdrawal logic into a shared internal function:

```solidity
/**
 * @dev Internal function to execute token transfer and emit withdrawal event
 * @param token The token address (address(0) for ETH)
 * @param amount The amount to transfer
 * @param remainingBalance The balance remaining after withdrawal (for event)
 */
function _executeTransfer(address token, uint256 amount, uint256 remainingBalance) internal {
    if (token == address(0)) {
        // ETH withdrawal
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
    } else {
        // ERC20 withdrawal
        IERC20(token).transfer(msg.sender, amount);
    }

    emit EarningsWithdrawn(msg.sender, token, amount, remainingBalance);
}
```

**Refactored Functions:**

```solidity
function withdraw(uint256 amount, address token) external nonReentrant {
    require(amount > 0, "Amount must be positive");
    require(earnings[msg.sender][token] >= amount, "Insufficient earnings");

    earnings[msg.sender][token] -= amount;
    totalWithdrawn[token] += amount;

    _executeTransfer(token, amount, earnings[msg.sender][token]);
}

function withdrawAll(address token) external nonReentrant {
    uint256 amount = earnings[msg.sender][token];
    require(amount > 0, "No earnings to withdraw");

    earnings[msg.sender][token] = 0;
    totalWithdrawn[token] += amount;

    _executeTransfer(token, amount, 0);
}

function withdrawMultiple(address[] calldata tokens) external nonReentrant {
    for (uint256 i = 0; i < tokens.length; i++) {
        uint256 amount = earnings[msg.sender][tokens[i]];
        if (amount > 0) {
            earnings[msg.sender][tokens[i]] = 0;
            totalWithdrawn[tokens[i]] += amount;

            _executeTransfer(tokens[i], amount, 0);
        }
    }
}
```

**Tasks:**

- [x] Create internal `_executeTransfer()` function
- [x] Refactor `withdraw()` to use `_executeTransfer()`
- [x] Refactor `withdrawAll()` to use `_executeTransfer()`
- [x] Refactor `withdrawMultiple()` to use `_executeTransfer()`
- [x] Write tests to verify behavior unchanged (17 tests in `test/SecurityFixes/HostEarnings/test_withdrawal_refactor.t.sol`)
- [x] Run full test suite (432 tests passing)
- [x] Verify gas impact is minimal (< 0.25% variance)

**Tests Required:**

```solidity
// test/SecurityFixes/HostEarnings/test_withdrawal_refactor.t.sol
function test_Withdraw_BehaviorUnchanged() public { /* ... */ }
function test_WithdrawAll_BehaviorUnchanged() public { /* ... */ }
function test_WithdrawMultiple_BehaviorUnchanged() public { /* ... */ }
function test_WithdrawETH_Success() public { /* ... */ }
function test_WithdrawERC20_Success() public { /* ... */ }
function test_WithdrawMultiple_MixedTokens() public { /* ... */ }
```

**Benefits:**

| Benefit | Impact |
| ------- | ------ |
| Reduced code duplication | ~30 lines removed |
| Single point of maintenance | Future changes in one place |
| Consistency guaranteed | Same logic for all withdrawal paths |
| Easier auditing | Less code to review |

**Gas Impact Assessment:**

| Function | Before | After (Est.) | Difference |
| -------- | ------ | ------------ | ---------- |
| `withdraw()` | ~45,000 | ~45,100 | +100 (~0.2%) |
| `withdrawAll()` | ~43,000 | ~43,100 | +100 (~0.2%) |
| `withdrawMultiple()` (3 tokens) | ~95,000 | ~95,300 | +300 (~0.3%) |

*Note: Extra internal function call adds minimal overhead (~100 gas). Negligible impact.*

**Status:** ✅ Complete (January 8, 2026)

**Actual Gas Impact:**

| Function | Before | After | Difference |
| -------- | ------ | ----- | ---------- |
| `withdraw()` | 136,755 | 136,740 | -15 gas (-0.01%) |
| `withdrawAll()` | 115,354 | 115,379 | +25 gas (+0.02%) |
| `withdrawMultiple()` (3 tokens) | 306,150 | 305,371 | -779 gas (-0.25%) |

---

## Phase 2: Unrestricted `receive` Function Fixes

### 2.1 HostEarningsUpgradeable: Unrestricted `receive()`

**Severity:** Code Quality (LOW)
**Original Finding:**

> The `HostEarningsUpgradeable` contract implements the `receive` function for other system parts to be able to deposit funds which are credited to users as earnings. However, the function does not validate the funds are coming from authorized contracts accepting funds from any destination potentially leading to funds lock. Unrestricted empty `receive` function is considered to be an antipattern in Solidity.

**Current Code (line 246):**

```solidity
receive() external payable {
    // Accept ETH transfers
}
```

**Risk Assessment:**

| Risk | Mitigation | Severity |
| ---- | ---------- | -------- |
| Funds lock from accidental sends | `rescueTokens()` function exists to recover excess funds | LOW |
| Unauthorized deposits | No current mitigation | LOW |

**Fix Plan:**

Restrict `receive()` to only accept ETH from authorized callers (reuses existing `authorizedCallers` mapping):

```solidity
receive() external payable {
    require(authorizedCallers[msg.sender], "Unauthorized ETH sender");
}
```

**Why This Works:**
- The `authorizedCallers` mapping already exists for `creditEarnings()`
- JobMarketplace is already set as authorized during deployment
- No new infrastructure needed - reuses existing access control

**Tasks:**

- [x] Modify `receive()` to check `authorizedCallers[msg.sender]`
- [x] Write test: unauthorized sender reverts
- [x] Write test: authorized sender (JobMarketplace) succeeds
- [x] Verify existing fund flow still works

---

### 2.2 JobMarketplaceWithModelsUpgradeable: Unnecessary `receive()` and `fallback()`

**Severity:** Code Quality (MEDIUM)
**Original Finding:**

> The `JobMarketplaceWithModelsUpgradeable` contract introduces empty `receive` and `fallback` functions not required by the design which are considered to be an antipattern and lead to funds lock.

**Current Code (lines 1037-1038):**

```solidity
receive() external payable {}
fallback() external payable {}
```

**Risk Assessment:**

| Risk | Mitigation | Severity |
| ---- | ---------- | -------- |
| Funds permanently locked | **None** - no rescue mechanism | MEDIUM |
| Unnecessary attack surface | None | LOW |

**Analysis:**

ETH enters JobMarketplace through these legitimate payable functions:
- `createSessionJob()` - payable function
- `createSessionJobForModel()` - payable function
- `depositNative()` - payable function

The `receive()` and `fallback()` functions serve **no purpose** - they only allow ETH to be sent directly and locked forever.

**Fix Plan:**

Remove both functions entirely:

```solidity
// REMOVE these lines (1037-1038):
// receive() external payable {}
// fallback() external payable {}
```

**Tasks:**

- [x] Remove `receive() external payable {}`
- [x] Remove `fallback() external payable {}`
- [x] Write test: direct ETH send reverts (expected behavior)
- [x] Verify session creation with ETH still works
- [x] Run full test suite (444 tests passing)

---

### Phase 2 Test Summary

```solidity
// test/SecurityFixes/ReceiveFunction/test_receive_restriction.t.sol

// HostEarnings tests
function test_ReceiveFromUnauthorized_Reverts() public { /* ... */ }
function test_ReceiveFromAuthorized_Succeeds() public { /* ... */ }
function test_ExistingFundFlow_StillWorks() public { /* ... */ }

// JobMarketplace tests
function test_DirectETHSend_Reverts() public { /* ... */ }
function test_SessionCreationWithETH_StillWorks() public { /* ... */ }
function test_DepositNative_StillWorks() public { /* ... */ }
```

**Status:** ✅ Complete (January 8, 2026)

**Implementation:**
- `src/HostEarningsUpgradeable.sol` line 234: Added `require(authorizedCallers[msg.sender], "Unauthorized ETH sender")`
- `src/JobMarketplaceWithModelsUpgradeable.sol`: Removed `receive()` and `fallback()` functions (lines 1037-1038)
- 11 new tests in `test/SecurityFixes/ReceiveFunction/test_receive_restriction.t.sol`
- Updated 1 existing test in `test/Upgradeable/HostEarnings/test_initialization.t.sol`
- Full test suite: 444 tests passing

---

## Phase 3: Deprecated Funds Transfer Method Usage

### 3.1 Deprecated `payable().transfer()` for Native ETH

**Severity:** Code Quality (LOW)
**Original Finding:**

> The `withdrawNative` function uses `payable(address).transfer` method to transfer native currency. The method is considered to be deprecated and unsafe due to the limited amount of attached Gas. The `payable(address).call` usage is recommended.

**Current Code (line 850):**

```solidity
function withdrawNative(uint256 amount) external nonReentrant {
    require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");

    userDepositsNative[msg.sender] -= amount;
    payable(msg.sender).transfer(amount);  // DEPRECATED

    emit WithdrawalProcessed(msg.sender, amount, address(0));
}
```

**Why `.transfer()` is Deprecated:**
- Limited to 2300 gas stipend
- Can fail if recipient is a contract with a `receive()` function that uses more gas
- The EIP-1884 gas repricing made this worse

**Note:** Most ETH transfers in the codebase already use the safe `.call{value:}` pattern. This is the only exception.

**Fix Plan:**

```solidity
function withdrawNative(uint256 amount) external nonReentrant {
    require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");

    userDepositsNative[msg.sender] -= amount;

    (bool success, ) = payable(msg.sender).call{value: amount}("");
    require(success, "ETH transfer failed");

    emit WithdrawalProcessed(msg.sender, amount, address(0));
}
```

**Tasks:**

- [x] Replace `.transfer()` with `.call{value:}()` in `withdrawNative()`
- [x] Add success check with require
- [x] Write test to verify withdrawal still works
- [x] Verify reentrancy protection (`nonReentrant` modifier already present)

---

### 3.2 Direct `IERC20.transfer()` Without SafeERC20

**Severity:** Code Quality (LOW)
**Original Finding:**

> The system overall directly uses `IERC20(token).transfer` pattern to transfer ERC20 tokens. The pattern is considered to be deprecated due to variety in ERC20 tokens implementations, usage of `SafeERC20` library is recommended.

**Why SafeERC20 is Recommended:**
- Some tokens don't return a boolean (e.g., USDT on mainnet)
- Some tokens return false instead of reverting on failure
- SafeERC20 handles all these edge cases

**Current Token Usage:**
- USDC (Base Sepolia): Standard ERC20, returns bool ✅
- FAB Token: Standard ERC20, returns bool ✅

**Risk Assessment:**
Since the current tokens (USDC, FAB) are standard ERC20 implementations, the immediate risk is LOW. However, if the protocol adds support for non-standard tokens in the future, this could cause issues.

**Instances Requiring Fix (19 total):**

| Contract | Function | Line | Method |
| -------- | -------- | ---- | ------ |
| JobMarketplaceWithModelsUpgradeable | `createSessionJobWithToken` | 426 | `transferFrom` |
| JobMarketplaceWithModelsUpgradeable | `createSessionJobForModelWithToken` | 491 | `transferFrom` |
| JobMarketplaceWithModelsUpgradeable | `_settleSessionPayments` | 687 | `transfer` |
| JobMarketplaceWithModelsUpgradeable | `_settleSessionPayments` | 700 | `transfer` |
| JobMarketplaceWithModelsUpgradeable | `withdrawTreasuryTokens` | 766 | `transfer` |
| JobMarketplaceWithModelsUpgradeable | `withdrawAllTreasuryFees` | 786 | `transfer` |
| JobMarketplaceWithModelsUpgradeable | `depositToken` | 837 | `transferFrom` |
| JobMarketplaceWithModelsUpgradeable | `withdrawToken` | 859 | `transfer` |
| HostEarningsUpgradeable | `withdraw` | 136 | `transfer` |
| HostEarningsUpgradeable | `withdrawAll` | 164 | `transfer` |
| HostEarningsUpgradeable | `withdrawMultiple` | 187 | `transfer` |
| HostEarningsUpgradeable | `rescueTokens` | 239 | `transfer` |
| NodeRegistryWithModelsUpgradeable | `registerNode` | 130 | `transferFrom` |
| NodeRegistryWithModelsUpgradeable | `unregisterNode` | 355 | `transfer` |
| NodeRegistryWithModelsUpgradeable | `addStake` | 367 | `transferFrom` |
| ModelRegistryUpgradeable | `proposeModel` | 131 | `transferFrom` |
| ModelRegistryUpgradeable | `voteForModel` | 164 | `transferFrom` |
| ModelRegistryUpgradeable | `finalizeProposal` | 204 | `transfer` |
| ModelRegistryUpgradeable | `unlockVotes` | 226 | `transfer` |

**Fix Plan:**

1. Import SafeERC20 from OpenZeppelin in each contract:
```solidity
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
```

2. Add using directive:
```solidity
using SafeERC20 for IERC20;
```

3. Replace all instances:
```solidity
// Before
IERC20(token).transfer(recipient, amount);
IERC20(token).transferFrom(sender, recipient, amount);

// After
IERC20(token).safeTransfer(recipient, amount);
IERC20(token).safeTransferFrom(sender, recipient, amount);
```

**Tasks:**

- [x] Add SafeERC20 import to JobMarketplaceWithModelsUpgradeable
- [x] Add SafeERC20 import to HostEarningsUpgradeable
- [x] Add SafeERC20 import to NodeRegistryWithModelsUpgradeable
- [x] Add SafeERC20 import to ModelRegistryUpgradeable
- [x] Replace 8 instances in JobMarketplaceWithModelsUpgradeable
- [x] Replace 2 instances in HostEarningsUpgradeable (after Phase 1 refactor)
- [x] Replace 3 instances in NodeRegistryWithModelsUpgradeable
- [x] Replace 4 instances in ModelRegistryUpgradeable
- [x] Run full test suite (457 tests passing)

---

### Phase 3 Test Summary

```solidity
// test/SecurityFixes/TransferMethods/test_safe_transfers.t.sol

// Native ETH tests
function test_WithdrawNative_UsesCallPattern() public { /* ... */ }
function test_WithdrawNative_FailsGracefully() public { /* ... */ }

// SafeERC20 tests (verify existing behavior unchanged)
function test_TokenDeposit_StillWorks() public { /* ... */ }
function test_TokenWithdraw_StillWorks() public { /* ... */ }
function test_SessionPayment_StillWorks() public { /* ... */ }
function test_StakeTransfer_StillWorks() public { /* ... */ }
```

**Status:** ✅ Complete (January 8, 2026)

**Implementation:**
- `src/JobMarketplaceWithModelsUpgradeable.sol`:
  - Added SafeERC20 import and `using SafeERC20 for IERC20;`
  - Replaced 8 ERC20 transfer/transferFrom with safe versions
  - Replaced `.transfer()` with `.call{value:}` in `withdrawNative()`
- `src/HostEarningsUpgradeable.sol`: Added SafeERC20, replaced 2 instances
- `src/NodeRegistryWithModelsUpgradeable.sol`: Added SafeERC20, replaced 3 instances
- `src/ModelRegistryUpgradeable.sol`: Added SafeERC20, replaced 4 instances
- 13 new tests in `test/SecurityFixes/TransferMethods/test_safe_transfers.t.sol`
- Full test suite: 457 tests passing

---

## Phase 4: Variables Named as Constants

### 4.1 Non-Constant Variables Using UPPER_SNAKE_CASE

**Severity:** Code Quality (LOW)
**Original Finding:**

> According to the Solidity style guide, constants are named in upper case snake case and variables in camel case. Immutable variables might use upper case snake case for an exception. The following variables pretend to be constants.

**Current Code (lines 89-91):**

```solidity
// Converted from immutable to storage (set in initialize)
uint256 public DISPUTE_WINDOW;
uint256 public FEE_BASIS_POINTS;
```

**Why This Is Wrong:**
- `DISPUTE_WINDOW` and `FEE_BASIS_POINTS` are **storage variables**, not constants
- They are set in `initialize()`, not at compile time
- Solidity style guide: constants = `UPPER_SNAKE_CASE`, variables = `camelCase`
- The naming is misleading - suggests immutability when values could theoretically change

**Fix Plan:**

Rename to follow Solidity naming conventions:

```solidity
// Before
uint256 public DISPUTE_WINDOW;
uint256 public FEE_BASIS_POINTS;

// After
uint256 public disputeWindow;
uint256 public feeBasisPoints;
```

**Scope of Change:**

| Location | Files | Occurrences |
| -------- | ----- | ----------- |
| Source code | 1 | 8 |
| Test files | 20 | ~120 |
| Deploy scripts | 2 | ~15 |
| Client ABIs | 1 | 2 |
| Documentation | 1 | 1 |
| **Total** | **25** | **~142** |

**Breaking Change Warning:**

This is a **breaking change** for external integrations:
- SDK/client code calling `marketplace.DISPUTE_WINDOW()` will break
- Must be renamed to `marketplace.disputeWindow()`
- ABI regeneration required
- Client documentation updates needed

Since the system is on testnet (not mainnet), this change is acceptable.

**Status:** ✅ COMPLETED

**Tasks:**

- [x] Rename `DISPUTE_WINDOW` → `disputeWindow` in source
- [x] Rename `FEE_BASIS_POINTS` → `feeBasisPoints` in source
- [x] Update comment from "Converted from immutable" to standard NatSpec
- [x] Update all 18 test files (~120 occurrences)
- [x] Update 2 deployment scripts
- [x] Regenerate client ABIs
- [x] Run full test suite (457 tests passing)

**Implementation Details:**

```solidity
// File: src/JobMarketplaceWithModelsUpgradeable.sol

// Before (lines 89-91):
// Converted from immutable to storage (set in initialize)
uint256 public DISPUTE_WINDOW;
uint256 public FEE_BASIS_POINTS;

// After:
/// @notice Time window before non-depositor can complete session (default 30s)
uint256 public disputeWindow;

/// @notice Treasury fee in basis points (1000 = 10%)
uint256 public feeBasisPoints;
```

**Files Requiring Updates:**

Source:
- `src/JobMarketplaceWithModelsUpgradeable.sol`

Scripts:
- `script/DeployAllUpgradeable.s.sol`
- `script/DeployJobMarketplaceUpgradeable.s.sol`

Tests (20 files):
- `test/Upgradeable/JobMarketplace/test_initialization.t.sol`
- `test/Upgradeable/JobMarketplace/test_upgrade.t.sol`
- `test/Upgradeable/JobMarketplace/test_deployment_script.t.sol`
- `test/Upgradeable/JobMarketplace/test_pause.t.sol`
- `test/Upgradeable/JobMarketplace/test_token_min_deposit.t.sol`
- `test/Upgradeable/Integration/test_full_flow.t.sol`
- `test/Upgradeable/Integration/test_upgrade_flow.t.sol`
- `test/Upgradeable/Integration/test_deploy_all.t.sol`
- `test/Integration/test_host_validation_e2e.t.sol`
- `test/Integration/test_fund_safety.t.sol`
- `test/Integration/test_proof_verification_e2e.t.sol`
- `test/SecurityFixes/JobMarketplace/test_host_validation.t.sol`
- `test/SecurityFixes/JobMarketplace/test_host_validation_all_paths.t.sol`
- `test/SecurityFixes/JobMarketplace/test_double_spend_prevention.t.sol`
- `test/SecurityFixes/JobMarketplace/test_balance_separation.t.sol`
- `test/SecurityFixes/JobMarketplace/test_proof_signature_required.t.sol`
- `test/SecurityFixes/JobMarketplace/test_proofsystem_integration.t.sol`
- `test/SecurityFixes/JobMarketplace/test_legacy_removal.t.sol`

Client ABIs:
- `client-abis/JobMarketplaceWithModelsUpgradeable-CLIENT-ABI.json`
- `client-abis/README.md`

**Status:** Planned

---

## Phase 5: Session Creation Code Deduplication (Optional)

### 5.1 Duplications in Session Creation Functions

**Severity:** Code Quality (LOW)
**Original Finding:**

> `createSessionJob`, `createSessionJobForModel`, `createSessionJobWithToken`, and `createSessionJobForModelWithToken` functions have a significant amount of duplicated code (e.g. validations, session initialization, events emission) making the contract harder to understand and maintain.

**Analysis of Duplication:**

Each of the 4 session creation functions contains ~45-55 lines with the following duplicated patterns:

**1. Parameter Validation (~8 lines, repeated 4x):**
```solidity
require(pricePerToken > 0, "Invalid price");
require(maxDuration > 0 && maxDuration <= 365 days, "Invalid duration");
require(proofInterval > 0, "Invalid proof interval");
require(host != address(0), "Invalid host");
_validateHostRegistration(host);
_validateProofRequirements(proofInterval, deposit, pricePerToken);
```

**2. Session Initialization (~12 lines, repeated 4x):**
```solidity
SessionJob storage session = sessionJobs[jobId];
session.id = jobId;
session.depositor = msg.sender;
session.host = host;
session.paymentToken = <varies>;
session.deposit = <varies>;
session.pricePerToken = pricePerToken;
session.maxDuration = maxDuration;
session.startTime = block.timestamp;
session.lastProofTime = block.timestamp;
session.proofInterval = proofInterval;
session.status = SessionStatus.Active;
```

**3. Tracking Updates (~3 lines, repeated 4x):**
```solidity
userSessions[msg.sender].push(jobId);
hostSessions[host].push(jobId);
```

**Function Differences:**

| Function | Payment Type | Model Support | Lines |
| -------- | ------------ | ------------- | ----- |
| `createSessionJob` | Native (ETH) | No | 46 |
| `createSessionJobForModel` | Native (ETH) | Yes | 54 |
| `createSessionJobWithToken` | ERC20 | No | 54 |
| `createSessionJobForModelWithToken` | ERC20 | Yes | 66 |

**Total Duplicated Code:** ~80-100 lines across 4 functions

**Potential Fix:**

Extract shared logic into internal functions:

```solidity
struct SessionParams {
    address host;
    address paymentToken;
    uint256 deposit;
    uint256 pricePerToken;
    uint256 maxDuration;
    uint256 proofInterval;
    bytes32 modelId;  // bytes32(0) if no model
}

function _validateSessionParams(SessionParams memory params) internal view {
    require(params.pricePerToken > 0, "Invalid price");
    require(params.maxDuration > 0 && params.maxDuration <= 365 days, "Invalid duration");
    require(params.proofInterval > 0, "Invalid proof interval");
    require(params.host != address(0), "Invalid host");
    require(params.deposit <= 1000 ether, "Deposit too large");

    _validateHostRegistration(params.host);
    _validateProofRequirements(params.proofInterval, params.deposit, params.pricePerToken);
}

function _initializeSession(
    uint256 jobId,
    SessionParams memory params
) internal returns (SessionJob storage) {
    SessionJob storage session = sessionJobs[jobId];
    session.id = jobId;
    session.depositor = msg.sender;
    session.host = params.host;
    session.paymentToken = params.paymentToken;
    session.deposit = params.deposit;
    session.pricePerToken = params.pricePerToken;
    session.maxDuration = params.maxDuration;
    session.startTime = block.timestamp;
    session.lastProofTime = block.timestamp;
    session.proofInterval = params.proofInterval;
    session.status = SessionStatus.Active;

    userSessions[msg.sender].push(jobId);
    hostSessions[params.host].push(jobId);

    return session;
}
```

**Trade-offs:**

| Aspect | Current (Duplicated) | Refactored |
| ------ | -------------------- | ---------- |
| Lines of code | ~220 | ~140 |
| Gas cost | Lower (no internal calls) | Higher (+~200 gas per call) |
| Readability | Each function self-contained | Must follow internal function calls |
| Maintainability | Changes in 4 places | Changes in 1 place |
| Audit complexity | More code to review | Less code, but more indirection |

**Implementation (Completed January 8, 2026):**

Tasks completed:
- [x] Create `SessionParams` struct (lines 87-96)
- [x] Create `_validateSessionParams()` internal function (lines 585-594)
- [x] Create `_initializeSession()` internal function (lines 603-625)
- [x] Refactor `createSessionJob()` to use helpers (lines 310-342)
- [x] Refactor `createSessionJobForModel()` to use helpers (lines 344-382)
- [x] Refactor `createSessionJobWithToken()` to use helpers (lines 384-425)
- [x] Refactor `createSessionJobForModelWithToken()` to use helpers (lines 427-475)
- [x] Run full test suite (483 tests pass)
- [x] Verify gas impact is acceptable

**Gas Impact Analysis:**

| Function | Before | After | Delta | Change |
| -------- | ------ | ----- | ----- | ------ |
| `createSessionJob` | 365,241 | 365,739 | +498 | +0.14% |
| `createSessionJobForModel` | 394,566 | 395,069 | +503 | +0.13% |
| `createSessionJobWithToken` | 426,099 | 426,592 | +493 | +0.12% |
| `createSessionJobForModelWithToken` | 453,343 | 453,825 | +482 | +0.11% |

The gas increase is minimal (~500 gas per call, 0.11-0.14%), well within acceptable limits.

**Code Reduction:**
- Before: ~220 lines across 4 functions
- After: ~140 lines (4 functions + 2 helpers)
- Reduction: ~80 lines (~36%)

**Test Coverage:**
- New test file: `test/SecurityFixes/JobMarketplace/test_session_creation_refactor.t.sol`
- 26 tests covering all session creation paths
- All 483 tests in the full suite pass

**Status:** ✅ IMPLEMENTED

---

### 5.2 Duplications in Withdraw Functions

**Severity:** Code Quality (VERY LOW)
**Original Finding:**

> The same applies to `withdrawNative` and `withdrawToken` functions sharing similar logic for funds withdrawal.

**Current Implementation:**

```solidity
// withdrawNative (6 lines)
function withdrawNative(uint256 amount) external nonReentrant {
    require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");
    userDepositsNative[msg.sender] -= amount;
    payable(msg.sender).transfer(amount);
    emit WithdrawalProcessed(msg.sender, amount, address(0));
}

// withdrawToken (6 lines)
function withdrawToken(address token, uint256 amount) external nonReentrant {
    require(userDepositsToken[msg.sender][token] >= amount, "Insufficient balance");
    userDepositsToken[msg.sender][token] -= amount;
    IERC20(token).transfer(msg.sender, amount);
    emit WithdrawalProcessed(msg.sender, amount, token);
}
```

**Analysis:**

The duplication here is minimal (6 lines each, ~4 lines similar pattern). The functions are:
- Short and readable
- Self-contained
- Different storage access patterns (`userDepositsNative` vs `userDepositsToken`)
- Different transfer mechanisms (ETH vs ERC20)

**Recommendation: NO ACTION**

Refactoring these would add complexity without meaningful benefit. The functions are already concise.

**Status:** No Action Required

---

## Phase 6: Model Tiers Design Duplication (Optional)

### 6.1 Redundant `trustedModels` Mapping

**Severity:** Code Quality (LOW)
**Original Finding:**

> The `trustedModels[modelId]` value is factually equal to `models[modelId].approvalTier == 1` which creates a logic duplication and might lead to inconsistencies in future development.

**Current Code (ModelRegistryUpgradeable.sol):**

```solidity
// Line 45: Separate mapping for trusted status
mapping(bytes32 => bool) public trustedModels;

// Line 21: approvalTier in Model struct
uint256 approvalTier;  // 1 = trusted (owner), 2 = community approved

// Lines 103-112 in addTrustedModel():
models[modelId] = Model({
    approvalTier: 1,  // Indicates trusted
    ...
});
trustedModels[modelId] = true;  // REDUNDANT - same information!
```

**Problem:**

The same information is stored in two places:
- `trustedModels[modelId] == true`
- `models[modelId].approvalTier == 1`

This creates:
1. **Storage waste**: ~20,000 gas per SSTORE for redundant data
2. **Inconsistency risk**: If one is updated but not the other
3. **Maintenance burden**: Two places to modify for any logic change

**Current Usage Analysis:**

| Component | `trustedModels` | `approvalTier` |
|-----------|-----------------|----------------|
| Source (writes) | 2 locations | 3 locations |
| Tests (queries) | 5 assertions | 2 assertions |
| Client ABI | Public getter | In Model struct |

**Fix Plan:**

1. Remove `trustedModels` mapping entirely
2. Add `isTrustedModel()` view function that checks `approvalTier == 1`
3. Update tests to use new function
4. Regenerate client ABIs

```solidity
// REMOVE this mapping:
// mapping(bytes32 => bool) public trustedModels;

// ADD this function:
/**
 * @notice Check if a model is owner-trusted (tier 1)
 * @param modelId The model identifier
 * @return True if model is trusted (approvalTier == 1)
 */
function isTrustedModel(bytes32 modelId) external view returns (bool) {
    return models[modelId].approvalTier == 1 && models[modelId].active;
}

// REMOVE from addTrustedModel() and batchAddTrustedModels():
// trustedModels[modelId] = true;
```

**Breaking Change Warning:**

This is a **breaking change** for external integrations:
- Code calling `modelRegistry.trustedModels(modelId)` will break
- Must be renamed to `modelRegistry.isTrustedModel(modelId)`
- Client ABI update required

Since the system is on testnet, this change is acceptable.

**Tasks (If Implemented):**

- [ ] Remove `trustedModels` mapping declaration (line 45)
- [ ] Add `isTrustedModel(bytes32 modelId)` view function
- [ ] Remove `trustedModels[modelId] = true` from `addTrustedModel()` (line 112)
- [ ] Remove `trustedModels[modelId] = true` from `batchAddTrustedModels()` (line 317)
- [ ] Update storage gap (increase by 1 slot)
- [ ] Update 5 test assertions to use `isTrustedModel()`
- [ ] Regenerate client ABIs
- [ ] Run full test suite

**Gas Savings:**

| Operation | Before | After | Savings |
|-----------|--------|-------|---------|
| `addTrustedModel()` | ~65,000 | ~45,000 | ~20,000 (30%) |
| `batchAddTrustedModels()` (per model) | ~65,000 | ~45,000 | ~20,000 (30%) |
| `isTrustedModel()` query | N/A | ~2,600 | N/A (new) |

**Implementation (Completed January 8, 2026):**

Tasks completed:
- [x] Remove `trustedModels` mapping declaration (line 48)
- [x] Add `isTrustedModel(bytes32 modelId)` view function (lines 239-246)
- [x] Remove `trustedModels[modelId] = true` from `addTrustedModel()` (line 115)
- [x] Remove `trustedModels[modelId] = true` from `batchAddTrustedModels()` (line 329)
- [x] Update storage gap from 49 to 50 slots (line 64)
- [x] Update 5 test assertions to use `isTrustedModel()`
- [x] Create new test file with 12 comprehensive tests
- [x] Run full test suite (495 tests pass)

**Gas Impact Analysis:**

| Operation | Before (with trustedModels) | After (isTrustedModel) | Change |
|-----------|----------------------------|------------------------|--------|
| `addTrustedModel()` | ~220,000 | ~196,630 | -23,370 (-10.6%) |
| `isTrustedModel()` query | N/A (used trustedModels) | ~1,321 | New view function |

**Breaking Change Notes:**
- `trustedModels(bytes32)` public getter removed
- Replaced with `isTrustedModel(bytes32)` view function
- Client ABIs updated

**Test Coverage:**
- New test file: `test/SecurityFixes/ModelRegistry/test_trusted_models_refactor.t.sol`
- 12 tests covering tier 1/tier 2 distinction, deactivation, reactivation, batch add

**Status:** ✅ IMPLEMENTED

---

## Phase 7: Unbounded Array Iteration (Optional)

### 7.1 Array Manipulation Gas Limit Risk

**Severity:** Code Quality (MEDIUM)
**Original Finding:**

> Operations with long storage arrays might be stuck due to the transaction Gas limit. The `SLOAD` EVM instruction is quite costly and even an efficient swap-remove operation might reach the Gas limit and stall the execution. Consider avoiding usage of unbound arrays. Either limit the storage arrays length or modify storage model to reach item location at O(1) complexity.

**Affected Functions:**

| Contract | Function | Array | Complexity | Risk |
|----------|----------|-------|------------|------|
| ModelRegistryUpgradeable | `_removeFromActiveProposals()` | `activeProposals` | O(n) | MEDIUM |
| NodeRegistryWithModelsUpgradeable | `_removeNodeFromModel()` | `modelToNodes[modelId]` | O(n) | MEDIUM |

**Good Pattern Already Used:**

NodeRegistry's `activeNodesList` correctly uses O(1) indexed removal:

```solidity
// O(1) removal using index mapping
mapping(address => uint256) public activeNodesIndex;
address[] public activeNodesList;

// In unregisterNode():
uint256 index = activeNodesIndex[msg.sender];
uint256 lastIndex = activeNodesList.length - 1;
if (index != lastIndex) {
    address lastNode = activeNodesList[lastIndex];
    activeNodesList[index] = lastNode;
    activeNodesIndex[lastNode] = index;
}
activeNodesList.pop();
```

**Problem Code 1: ModelRegistryUpgradeable (lines 285-293)**

```solidity
function _removeFromActiveProposals(bytes32 modelId) private {
    for (uint i = 0; i < activeProposals.length; i++) {  // O(n) iteration
        if (activeProposals[i] == modelId) {
            activeProposals[i] = activeProposals[activeProposals.length - 1];
            activeProposals.pop();
            break;
        }
    }
}
```

**Problem Code 2: NodeRegistryWithModelsUpgradeable (lines 493-502)**

```solidity
function _removeNodeFromModel(bytes32 modelId, address nodeAddress) private {
    address[] storage nodesForModel = modelToNodes[modelId];
    for (uint i = 0; i < nodesForModel.length; i++) {  // O(n) iteration
        if (nodesForModel[i] == nodeAddress) {
            nodesForModel[i] = nodesForModel[nodesForModel.length - 1];
            nodesForModel.pop();
            break;
        }
    }
}
```

**Risk Assessment:**

| Array | Growth Factor | Attack Cost | Realistic Scenario |
|-------|---------------|-------------|-------------------|
| `activeProposals` | 100 FAB per proposal | 100,000 FAB for 1000 proposals | LOW - economic barrier |
| `modelToNodes[modelId]` | Stake required per node | Stake × node count | MEDIUM - popular models could have many nodes |

**DoS Threshold Calculation:**

- Each SLOAD costs ~2,100 gas (cold) or ~100 gas (warm)
- Block gas limit: ~30M gas
- Approximate safe iteration limit: ~10,000-15,000 elements
- Beyond this, `executeProposal()` or `unregisterNode()` could fail

**Fix Plan:**

Add index mappings for O(1) removal (same pattern as `activeNodesList`):

**ModelRegistryUpgradeable:**

```solidity
// ADD: Index mapping for O(1) removal
mapping(bytes32 => uint256) private activeProposalIndex;

// MODIFY proposeModel():
activeProposalIndex[modelId] = activeProposals.length;
activeProposals.push(modelId);

// REPLACE _removeFromActiveProposals():
function _removeFromActiveProposals(bytes32 modelId) private {
    uint256 index = activeProposalIndex[modelId];
    uint256 lastIndex = activeProposals.length - 1;

    if (index != lastIndex) {
        bytes32 lastProposal = activeProposals[lastIndex];
        activeProposals[index] = lastProposal;
        activeProposalIndex[lastProposal] = index;
    }

    activeProposals.pop();
    delete activeProposalIndex[modelId];
}
```

**NodeRegistryWithModelsUpgradeable:**

```solidity
// ADD: Index mapping for each model's node list
mapping(bytes32 => mapping(address => uint256)) private modelNodeIndex;

// MODIFY in registerNode() loop:
modelNodeIndex[modelIds[i]][msg.sender] = modelToNodes[modelIds[i]].length;
modelToNodes[modelIds[i]].push(msg.sender);

// REPLACE _removeNodeFromModel():
function _removeNodeFromModel(bytes32 modelId, address nodeAddress) private {
    address[] storage nodesForModel = modelToNodes[modelId];
    uint256 index = modelNodeIndex[modelId][nodeAddress];
    uint256 lastIndex = nodesForModel.length - 1;

    if (index != lastIndex) {
        address lastNode = nodesForModel[lastIndex];
        nodesForModel[index] = lastNode;
        modelNodeIndex[modelId][lastNode] = index;
    }

    nodesForModel.pop();
    delete modelNodeIndex[modelId][nodeAddress];
}
```

**Tasks (If Implemented):**

ModelRegistryUpgradeable:
- [ ] Add `activeProposalIndex` mapping
- [ ] Update `proposeModel()` to set index
- [ ] Refactor `_removeFromActiveProposals()` to O(1)
- [ ] Update storage gap (reduce by 1)
- [ ] Write tests for large proposal counts

NodeRegistryWithModelsUpgradeable:
- [ ] Add `modelNodeIndex` nested mapping
- [ ] Update `registerNode()` to set indices
- [ ] Update `updateSupportedModels()` to manage indices
- [ ] Refactor `_removeNodeFromModel()` to O(1)
- [ ] Update storage gap (reduce by 1)
- [ ] Write tests for large node counts per model

**Storage Migration Note:**

For deployed contracts, new mappings start empty. Existing array elements won't have index entries. Options:
1. Add migration function to rebuild indices (one-time admin call)
2. Fallback to O(n) if index not found (hybrid approach)
3. Only apply to new deployments

**Implementation (Completed January 8, 2026):**

**ModelRegistryUpgradeable:**
- [x] Add `activeProposalIndex` mapping (line 56)
- [x] Update `proposeModel()` to set index (line 157)
- [x] Refactor `_removeFromActiveProposals()` to O(1) (lines 303-317)
- [x] Update storage gap from 50 to 49 slots (line 67)
- [x] 12 tests for proposal removal behavior

**NodeRegistryWithModelsUpgradeable:**
- [x] Add `modelNodeIndex` nested mapping (line 60)
- [x] Update `registerNode()` to set indices (lines 155-158)
- [x] Update `updateSupportedModels()` to manage indices (lines 185-188)
- [x] Refactor `_removeNodeFromModel()` to O(1) (lines 502-517)
- [x] Update storage gap from 40 to 39 slots (line 83)
- [x] 13 tests for node removal behavior

**Gas Impact:**

| Operation | Before (O(n)) | After (O(1)) | Notes |
|-----------|---------------|--------------|-------|
| `executeProposal` (10 proposals) | ~28,032 | ~25,697 | Constant regardless of array size |
| `unregisterNode` (5 nodes/model) | ~18,666 | ~17,977 | Constant regardless of array size |

**Key Benefit:** Gas is now constant regardless of array size, preventing potential DoS when arrays grow large.

**Test Coverage:**
- `test/SecurityFixes/ModelRegistry/test_o1_proposal_removal.t.sol` - 12 tests
- `test/SecurityFixes/NodeRegistry/test_o1_model_node_removal.t.sol` - 13 tests
- Full suite: 520 tests pass

**Status:** ✅ IMPLEMENTED

---

## Phase 8: ProofSystem Function Naming Clarity

### 8.1 Rename Misleading EZKL Functions

**Severity:** Code Quality (LOW)
**Original Finding:**

> The initial codebase missed real EZKL proof validation implementation. The updated codebase does not employ EZKL and uses ECDSA instead. Usage of ECDSA breaks the original idea of the trustless proof of LLM computations validation.

**Problem:**

The function names suggest EZKL zero-knowledge proof verification, but the implementation uses ECDSA signature verification:

```solidity
// Current names suggest ZK proofs:
function verifyEKZL(...) external view returns (bool)
function _verifyEKZL(...) internal view returns (bool)
function _verifyEKZLInternal(...) internal view returns (bool)

// But implementation is ECDSA signature verification:
address recoveredSigner = ecrecover(messageHash, v, r, s);
return recoveredSigner == prover;
```

**Why This Matters:**

- Misleading function names confuse future developers and auditors
- Suggests cryptographic proof verification when it's signature verification
- The system uses an optimistic trust model, not ZK proofs
- Pre-MVP with no public users - safe to rename now

**Affected Code (ProofSystemUpgradeable.sol):**

| Line | Current Name | New Name |
|------|--------------|----------|
| 12 | "EZKL proof verification" (NatSpec) | "Host signature verification" |
| 73 | `verifyEKZL()` | `verifyHostSignature()` |
| 87 | `_verifyEKZL()` | `_verifyHostSignature()` |
| 256 | `_verifyEKZLInternal()` | `_verifyHostSignatureInternal()` |

**Fix Plan:**

1. Rename public function:
```solidity
// Before
function verifyEKZL(bytes calldata proof, address prover, uint256 claimedTokens)
    external view override returns (bool)

// After
function verifyHostSignature(bytes calldata proof, address prover, uint256 claimedTokens)
    external view override returns (bool)
```

2. Rename internal functions:
```solidity
// Before
function _verifyEKZL(...) internal view returns (bool)
function _verifyEKZLInternal(...) internal view returns (bool)

// After
function _verifyHostSignature(...) internal view returns (bool)
function _verifyHostSignatureInternal(...) internal view returns (bool)
```

3. Update NatSpec:
```solidity
// Before
@notice EZKL proof verification system for the Fabstir P2P LLM marketplace

// After
@notice Host signature verification system for the Fabstir P2P LLM marketplace
@dev Uses ECDSA signatures with optimistic trust model. Hosts stake FAB tokens
     as economic bond. Proofs are stored on S5 for post-hoc auditing.
```

4. Update interface `IProofSystem.sol` if it exists

**Tasks:**

- [x] Rename `verifyEKZL` → `verifyHostSignature` (line 78)
- [x] Rename `_verifyEKZL` → `_verifyHostSignature` (line 92)
- [x] Rename `_verifyEKZLInternal` → `_verifyHostSignatureInternal` (line 261)
- [x] Update all call sites (lines 84, 148, 207, 237, 266)
- [x] Update NatSpec contract description (lines 12-17)
- [x] Add NatSpec explaining optimistic trust model
- [x] Update `IProofSystem.sol` interface
- [x] Update `IProofSystemUpgradeable` local interface in JobMarketplaceWithModelsUpgradeable.sol
- [x] Update `ProofSystemMock.sol` mock contract
- [x] Update 8 test files referencing old function names
- [x] Regenerate client ABIs
- [x] Run full test suite (520 tests pass)

**Implementation (Completed January 9, 2026):**

Files modified:
- `src/ProofSystemUpgradeable.sol` - Main contract with renamed functions and updated NatSpec
- `src/interfaces/IProofSystem.sol` - Interface updated
- `src/JobMarketplaceWithModelsUpgradeable.sol` - Local interface updated (line 19)
- `test/mocks/ProofSystemMock.sol` - Mock contract updated
- 8 test files updated with new function names
- `client-abis/ProofSystemUpgradeable-CLIENT-ABI.json` - Regenerated

**Breaking Change Note:**

This is a breaking change for:
- External callers using `verifyEKZL()`
- Client ABIs referencing old function name

Since this is pre-MVP with no public users, this is acceptable.

**Status:** ✅ IMPLEMENTED

---

## Phase 9: Inline Comment Cleanup (Final Pass)

### 9.1 Remove Development Phase References and TODO Comments

**Severity:** Code Quality (LOW)
**Original Finding:**

> The inline comments are overwhelmed with references to past implementations, code-review notes, references to development phases, and contains TODO comments. Those are signs of code actively in development and not a production ready system.

**Problem:**

The codebase contains development artifacts that should be cleaned before production:
- References to "Phase X.X" implementation phases
- "REMOVED:" comments explaining what was deleted
- "Sub-phase" references
- Legacy compatibility notes
- TODO/FIXME comments (if any remain)

**Scope Analysis:**

| File | Occurrences | Examples |
|------|-------------|----------|
| JobMarketplaceWithModelsUpgradeable.sol | 18 | "Phase 7 cleanup", "Phase 3.1", "REMOVED in Phase 7" |
| ProofSystemUpgradeable.sol | 1 | "Sub-phase 1.1 security fix" |
| NodeRegistryWithModelsUpgradeable.sol | 1 | "Legacy function for compatibility" |
| **Total** | **20** | |

**Example Comments to Clean:**

```solidity
// Current (development artifacts):
// were removed in Phase 7 cleanup as they were never implemented.
// Chain configuration structure (Phase 4.1)
// Session model tracking (sessionId => modelId) - Phase 3.1
// REMOVED in Phase 7: event SessionAbandoned - was never emitted
// Access control for recordVerifiedProof (Sub-phase 1.1 security fix)

// After cleanup (production-ready):
// Chain configuration structure
// Session model tracking (sessionId => modelId)
// Access control for recordVerifiedProof
```

**Cleanup Guidelines:**

1. **Remove phase references**: Delete "(Phase X.X)" and "(Sub-phase X.X)" suffixes
2. **Remove "REMOVED:" comments**: These document history, not current functionality
3. **Remove "was:" explanations**: Historical context not needed in production
4. **Keep meaningful comments**: Retain comments that explain *what* the code does
5. **Update "legacy" comments**: Either remove legacy code or document why it's kept

**Why Final Pass:**

This cleanup should be done **after all other phases** because:
1. Other phases may add/modify comments
2. Ensures consistent comment style across final codebase
3. Single pass is more efficient than incremental cleanup
4. Reduces risk of removing comments that are still being referenced

**Tasks:**

- [x] Clean JobMarketplaceWithModelsUpgradeable.sol (18 occurrences)
- [x] Clean ModelRegistryUpgradeable.sol (7 occurrences - additional cleanup)
- [x] Clean NodeRegistryWithModelsUpgradeable.sol (5 occurrences + remove legacy function)
- [x] Search for any remaining TODO/FIXME comments
- [x] Verify no functional comments were removed
- [x] Run full test suite (520 tests pass)

**Implementation (Completed January 9, 2026):**

Files modified:
- `src/JobMarketplaceWithModelsUpgradeable.sol` - 18 comment cleanups
- `src/ModelRegistryUpgradeable.sol` - 7 comment cleanups
- `src/NodeRegistryWithModelsUpgradeable.sol` - 5 comment cleanups + removed legacy `getNodeController()` function

Note: ProofSystemUpgradeable.sol was already cleaned in Phase 8.

**Verification Command:**

```bash
# After cleanup, this returns 0 results:
grep -rn "Phase [0-9]\|Sub-phase\|REMOVED:\|was:" src/
```

**Status:** ✅ IMPLEMENTED

---

## Phase 10: Architecture and Testing System Improvements

### 10.0 Overview

**Severity:** Code Quality (MEDIUM)
**Original Finding:**

> While various documentation files are provided, nor Functional Requirements neither Architecture are described clearly. Documentation is overwhelmed with lists, tables, headers, bold text, special symbols, comparisons. Documentation does not outline purpose and role of the contracts, instead it consists of separate statements out of a logic sequence.
>
> It is essential for project documentation to outline purpose and role of the contracts as well as example usage workflows, define the main actors, their privileges and responsibilities. Smart contracts is an isolated system part and is accessible by anyone from blockchain, though, access control should be transparent and follow the system requirements.
>
> The testing system requires improvement. Current function coverage is identified to be only 62%. Critical functionalities such as voting for models, certain session types creation, claim with proof functionality, node configuration are completely untested. Some of the other functionalities are tested briefly, the functions are called only once in certain specific conditions limiting the function coverage. Consider covering negative cases as well as positive ones.

**Current State:**

| Metric | At Audit | Current | Target |
|--------|----------|---------|--------|
| Test count | ~62% coverage | 415 tests | TBD after coverage analysis |
| Requirements doc | None | Partial (CLAUDE.md) | Formal specification |
| Architecture diagrams | None | None | Full diagrams |
| Access control matrix | None | None | Complete matrix |

---

### Sub-phase 10.1: Formal Requirements Specification

**Objective:** Create a single authoritative document defining what the system does, who can do what, and why.

**Deliverable:** `docs/REQUIREMENTS.md`

**Contents:**

1. **System Purpose**
   - One-paragraph mission statement
   - Problem being solved
   - Target users

2. **Actors and Roles**

   | Actor | Description | Authentication |
   |-------|-------------|----------------|
   | Owner | Contract deployer, governance admin | Private key holder |
   | Host | AI node operator providing compute | Registered + staked |
   | Depositor | User paying for AI inference | Any wallet |
   | Treasury | Protocol fee recipient | Configured address |

3. **Actor Privileges Matrix**

   | Function | Owner | Host | Depositor | Anyone |
   |----------|-------|------|-----------|--------|
   | `registerNode()` | - | ✓ | ✓ | - |
   | `createSessionJob()` | - | - | ✓ | - |
   | `submitProofOfWork()` | - | ✓ (own sessions) | - | - |
   | `completeSessionJob()` | - | ✓ (own sessions) | ✓ (own sessions) | - |
   | `triggerSessionTimeout()` | - | - | - | ✓ |
   | `addTrustedModel()` | ✓ | - | - | - |
   | `pause()` | ✓ | - | - | - |
   | ... | ... | ... | ... | ... |

4. **Invariants**
   - "A host can only withdraw earnings for proofs they submitted"
   - "Total withdrawable ≤ Total deposited - Total withdrawn"
   - "Session deposits are locked until completion/timeout"
   - etc.

5. **Security Assumptions**
   - Host stake provides economic security
   - ECDSA signatures are unforgeable
   - Block timestamps are accurate within bounds
   - etc.

**Tasks:**

- [ ] Define system purpose and mission
- [ ] Document all actor types with descriptions
- [ ] Create complete actor-function privilege matrix
- [ ] Document system invariants
- [ ] Document security assumptions and trust model
- [ ] Cross-reference with actual contract access control

---

### Sub-phase 10.2: Architecture Documentation

**Objective:** Visual and textual documentation of how contracts interact.

**Deliverable:** `docs/ARCHITECTURE.md`

**Contents:**

1. **Contract Dependency Diagram**

   ```
   ┌─────────────────┐     ┌──────────────────┐
   │  ModelRegistry  │◄────│  NodeRegistry    │
   │  (model whitelist)│    │  (host staking)  │
   └────────┬────────┘     └────────┬─────────┘
            │                       │
            │    ┌──────────────────┘
            │    │
            ▼    ▼
   ┌─────────────────────────────────┐
   │   JobMarketplaceWithModels      │
   │   (session management)          │
   └──────────────┬──────────────────┘
                  │
         ┌───────┴───────┐
         ▼               ▼
   ┌──────────────┐ ┌─────────────┐
   │ ProofSystem  │ │HostEarnings │
   │ (verification)│ │ (payments) │
   └──────────────┘ └─────────────┘
   ```

2. **Data Flow Diagrams**
   - Session creation flow
   - Proof submission flow
   - Payment settlement flow
   - Model governance flow

3. **State Machine: Session Lifecycle**

   ```
   [Created] ──deposit──► [Active] ──proofs──► [Active]
                              │                   │
                              │                   │
                       timeout│            complete│
                              ▼                   ▼
                        [TimedOut]          [Completed]
   ```

4. **Storage Layout Documentation**
   - Key mappings and their purposes
   - Storage slot assignments for upgradeability
   - Storage gaps explanation

5. **External Dependencies**
   - OpenZeppelin contracts used
   - Token interfaces (IERC20)
   - Upgrade patterns (UUPS)

**Tasks:**

- [ ] Create contract dependency diagram (Mermaid or ASCII)
- [ ] Document session lifecycle state machine
- [ ] Create data flow diagrams for key operations
- [ ] Document storage layout and upgrade considerations
- [ ] List and explain external dependencies

---

### Sub-phase 10.3: Usage Workflow Documentation

**Objective:** Step-by-step guides for common operations with code examples.

**Deliverable:** `docs/WORKFLOWS.md`

**Contents:**

1. **Host Registration Workflow**
   ```
   1. Approve FAB tokens for NodeRegistry
   2. Call registerNode() with:
      - modelIds: supported AI models
      - minPricePerTokenNative: ETH pricing
      - minPricePerTokenStable: USDC pricing
      - metadata: node description
      - apiUrl: endpoint URL
   3. Verify registration via getNodeFullInfo()
   ```

2. **Session Creation Workflow (Depositor)**
   ```
   1. Query host pricing: getNodePricing(host)
   2. Verify model support: nodeSupportsModel(host, modelId)
   3. Calculate deposit: estimatedTokens × pricePerToken
   4. Call createSessionJobForModelWithToken() with USDC
      OR createSessionJobForModel() with ETH
   5. Receive jobId from SessionJobCreated event
   ```

3. **Proof Submission Workflow (Host)**
   ```
   1. Provide AI inference service off-chain
   2. Track tokens consumed
   3. Sign proof: keccak256(proofHash, prover, claimedTokens)
   4. Call submitProofOfWork() with signature
   5. Repeat every proofInterval tokens
   ```

4. **Session Completion Workflow**
   ```
   1. Host/Depositor calls completeSessionJob()
   2. Contract calculates: hostPayment = tokensUsed × pricePerToken
   3. 10% treasury fee deducted
   4. 90% credited to HostEarnings
   5. Remaining deposit refunded to depositor
   ```

5. **Model Governance Workflow**
   ```
   1. Proposer locks 100 FAB, calls proposeModel()
   2. 3-day voting period begins
   3. Voters lock FAB via voteForModel()
   4. After 3 days, anyone calls executeProposal()
   5. If threshold met: model approved (tier 2)
   6. Voters unlock tokens via unlockVotes()
   ```

**Tasks:**

- [ ] Document host registration workflow with code examples
- [ ] Document session creation workflow (ETH and USDC paths)
- [ ] Document proof submission workflow with signature format
- [ ] Document session completion and payment settlement
- [ ] Document model governance workflow
- [ ] Add error handling guidance for each workflow

---

### Sub-phase 10.4: Test Coverage Analysis and Gap Identification

**Objective:** Quantify current coverage and identify gaps.

**Deliverable:** `docs/TEST_COVERAGE_REPORT.md`

**Analysis Steps:**

1. **Generate Coverage Report**
   ```bash
   forge coverage --report lcov
   genhtml lcov.info -o coverage-report
   ```

2. **Identify Coverage Gaps**

   | Contract | Functions | Covered | Uncovered | Priority |
   |----------|-----------|---------|-----------|----------|
   | JobMarketplace | TBD | TBD | TBD | HIGH |
   | NodeRegistry | TBD | TBD | TBD | MEDIUM |
   | ModelRegistry | TBD | TBD | TBD | MEDIUM |
   | ProofSystem | TBD | TBD | TBD | HIGH |
   | HostEarnings | TBD | TBD | TBD | MEDIUM |

3. **Prioritize by Risk**
   - Functions handling funds: HIGH
   - Access control functions: HIGH
   - State transitions: MEDIUM
   - View functions: LOW

4. **Create Test Backlog**
   - List specific untested functions
   - List under-tested functions (called <3 times)
   - Estimate effort for each

**Tasks:**

- [ ] Generate forge coverage report
- [ ] Analyze per-function coverage
- [ ] Identify HIGH priority gaps (fund handling, access control)
- [ ] Identify MEDIUM priority gaps (state transitions)
- [ ] Create prioritized test backlog

---

### Sub-phase 10.5: Negative and Edge Case Testing

**Objective:** Add tests for failure paths, reverts, and boundary conditions.

**Deliverable:** New test files in `test/NegativeCases/`

**Test Categories:**

1. **Access Control Violations**
   ```solidity
   function test_RegisterNode_RejectsUnauthorizedCaller() public { }
   function test_SubmitProof_RejectsNonHost() public { }
   function test_CompleteSession_RejectsThirdParty() public { }
   function test_AddTrustedModel_RejectsNonOwner() public { }
   function test_Pause_RejectsNonOwner() public { }
   ```

2. **Invalid State Transitions**
   ```solidity
   function test_CompleteSession_RejectsIfNotActive() public { }
   function test_SubmitProof_RejectsIfCompleted() public { }
   function test_TriggerTimeout_RejectsIfNotTimedOut() public { }
   function test_ExecuteProposal_RejectsIfVotingNotEnded() public { }
   ```

3. **Boundary Conditions**
   ```solidity
   function test_CreateSession_RejectsZeroDeposit() public { }
   function test_CreateSession_RejectsAboveMaxDeposit() public { }
   function test_SubmitProof_RejectsZeroTokens() public { }
   function test_RegisterNode_RejectsBelowMinStake() public { }
   function test_Withdraw_RejectsExceedingBalance() public { }
   ```

4. **Arithmetic Edge Cases**
   ```solidity
   function test_Settlement_HandlesMaxTokenCount() public { }
   function test_Settlement_HandlesPrecisionLoss() public { }
   function test_FeeCalculation_RoundsCorrectly() public { }
   ```

5. **Reentrancy Attempts**
   ```solidity
   function test_Withdraw_BlocksReentrancy() public { }
   function test_Settlement_BlocksReentrancy() public { }
   ```

**Tasks:**

- [ ] Create `test/NegativeCases/` directory structure
- [ ] Add access control violation tests (all protected functions)
- [ ] Add invalid state transition tests
- [ ] Add boundary condition tests (min/max values)
- [ ] Add arithmetic edge case tests
- [ ] Add reentrancy attempt tests with attacker contracts

---

### Sub-phase 10.6: Integration Test Expansion

**Objective:** Test complex multi-contract scenarios and real-world workflows.

**Deliverable:** New test files in `test/Integration/`

**Test Scenarios:**

1. **Complete Session Lifecycle**
   ```solidity
   function test_FullLifecycle_HostRegistersAndServesSession() public {
       // 1. Host registers with stake
       // 2. Depositor creates session
       // 3. Host submits 3 proofs
       // 4. Host completes session
       // 5. Host withdraws from HostEarnings
       // 6. Verify all balances correct
   }
   ```

2. **Timeout and Refund Flow**
   ```solidity
   function test_Timeout_PartialRefundAfterSomeProofs() public {
       // 1. Create session
       // 2. Host submits 1 proof
       // 3. Host goes offline
       // 4. Time passes beyond 3x proofInterval
       // 5. Anyone triggers timeout
       // 6. Verify partial payment to host, remainder to depositor
   }
   ```

3. **Multi-Session Concurrent Operations**
   ```solidity
   function test_MultiSession_HostServesMultipleDepositors() public {
       // 1. Single host, 3 depositors
       // 2. All create sessions
       // 3. Host submits proofs to all
       // 4. Different completion times
       // 5. Verify earnings accumulate correctly
   }
   ```

4. **Model Governance Full Cycle**
   ```solidity
   function test_ModelGovernance_ProposeVoteExecute() public {
       // 1. Proposer submits new model
       // 2. Multiple voters support
       // 3. Voting period ends
       // 4. Execute succeeds
       // 5. Model now usable in sessions
   }
   ```

5. **Upgrade Safety**
   ```solidity
   function test_Upgrade_PreservesActiveSessionData() public {
       // 1. Create active session
       // 2. Deploy new implementation
       // 3. Upgrade proxy
       // 4. Verify session data intact
       // 5. Complete session normally
   }
   ```

6. **Gas Limit Scenarios**
   ```solidity
   function test_GasLimit_LargeProofBatchSucceeds() public { }
   function test_GasLimit_ManyActiveSessionsQueryable() public { }
   ```

**Tasks:**

- [ ] Implement full session lifecycle test
- [ ] Implement timeout/refund scenario test
- [ ] Implement multi-session concurrent test
- [ ] Implement model governance full cycle test
- [ ] Implement upgrade safety test
- [ ] Implement gas limit boundary tests

---

### Phase 10 Summary

| Sub-phase | Deliverable | Effort Estimate |
|-----------|-------------|-----------------|
| 10.1 | `docs/REQUIREMENTS.md` | Medium |
| 10.2 | `docs/ARCHITECTURE.md` | Medium |
| 10.3 | `docs/WORKFLOWS.md` | Medium |
| 10.4 | `docs/TEST_COVERAGE_REPORT.md` | Low |
| 10.5 | `test/NegativeCases/*.t.sol` | High |
| 10.6 | `test/Integration/*.t.sol` | High |

**Execution Order:**

1. Sub-phase 10.4 first (understand current gaps)
2. Sub-phases 10.1-10.3 in parallel (documentation)
3. Sub-phases 10.5-10.6 after (testing)

**Dependencies:**

- Phases 1-4, 8-9 should complete first (code changes finalized)
- Documentation reflects final code state
- Tests validate final implementation

**Status:** Planned

---

## Phase 11: Solidity Version Upgrade and ReentrancyGuard Replacement

### 11.0 Overview

**Severity:** Code Quality (MEDIUM)
**Related Finding:** Custom Reentrancy Guard (Appendix)

**Original Auditor Concern:**

> Modifying the OpenZeppelin libraries is considered to be an antipattern. Instead of custom modification of `ReentrancyGuardUpgradeable`, consider directly using `ReentrancyGuard` or `ReentrancyGuardTransient` provided by OpenZeppelin libraries.

**Root Cause Analysis:**

The custom `ReentrancyGuardUpgradeable` exists because:
1. OpenZeppelin 5.x does NOT provide an upgradeable version
2. `ReentrancyGuard` has a constructor (doesn't work with proxies)
3. `ReentrancyGuardTransient` requires Solidity ^0.8.24

**Solution:**

Upgrade Solidity from `^0.8.19` to `^0.8.24`, enabling use of OpenZeppelin's `ReentrancyGuardTransient`.

**Verification Performed:**

| Solidity Version | Compilation | Tests | Status |
|------------------|-------------|-------|--------|
| 0.8.19 (current) | ✓ | 415 pass | Working |
| 0.8.24 | ✗ Stack-too-deep | N/A | Blocked |
| 0.8.28 | ✓ | 415 pass | ✅ Ready |

**Recommendation:** Upgrade to `^0.8.24` pragma (allows 0.8.28+ which works).

---

### Sub-phase 11.1: Update Solidity Pragma

**Objective:** Update all source files to use Solidity 0.8.24+.

**Files to Modify:**

| File | Current | New |
|------|---------|-----|
| `src/JobMarketplaceWithModelsUpgradeable.sol` | `^0.8.19` | `^0.8.24` |
| `src/NodeRegistryWithModelsUpgradeable.sol` | `^0.8.19` | `^0.8.24` |
| `src/ModelRegistryUpgradeable.sol` | `^0.8.19` | `^0.8.24` |
| `src/HostEarningsUpgradeable.sol` | `^0.8.19` | `^0.8.24` |
| `src/ProofSystemUpgradeable.sol` | `^0.8.19` | `^0.8.24` |
| `src/utils/ReentrancyGuardUpgradeable.sol` | `^0.8.19` | (will be deleted) |

**Tasks:**

- [ ] Update pragma in all 5 main contracts
- [ ] Update pragma in test files if needed
- [ ] Verify compilation with `forge build`
- [ ] Run full test suite

---

### Sub-phase 11.2: Replace Custom ReentrancyGuard with OZ Transient

**Objective:** Replace custom implementation with OpenZeppelin's gas-optimized version.

**Current Implementation:**

```solidity
// src/utils/ReentrancyGuardUpgradeable.sol (CUSTOM - TO BE DELETED)
import "./utils/ReentrancyGuardUpgradeable.sol";

contract JobMarketplaceWithModelsUpgradeable is
    ReentrancyGuardUpgradeable,  // Custom
    ...
```

**New Implementation:**

```solidity
// Use OpenZeppelin's transient storage version
import "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract JobMarketplaceWithModelsUpgradeable is
    ReentrancyGuardTransient,  // OZ native
    ...
```

**Contracts to Update:**

| Contract | Current Import | New Import |
|----------|----------------|------------|
| `JobMarketplaceWithModelsUpgradeable` | `./utils/ReentrancyGuardUpgradeable.sol` | `@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol` |
| `HostEarningsUpgradeable` | `./utils/ReentrancyGuardUpgradeable.sol` | `@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol` |
| `NodeRegistryWithModelsUpgradeable` | `./utils/ReentrancyGuardUpgradeable.sol` | `@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol` |

**Key Differences:**

| Aspect | Custom (current) | OZ Transient (new) |
|--------|------------------|-------------------|
| Storage | Regular SSTORE/SLOAD | Transient (EIP-1153) |
| Gas cost | ~5,000 gas | ~100 gas |
| Initializer | `__ReentrancyGuard_init()` | None needed |
| Inheritance | Abstract + Initializable | Abstract only |

**Tasks:**

- [ ] Update import in `JobMarketplaceWithModelsUpgradeable`
- [ ] Update import in `HostEarningsUpgradeable`
- [ ] Update import in `NodeRegistryWithModelsUpgradeable`
- [ ] Remove `__ReentrancyGuard_init()` calls from `initialize()` functions
- [ ] Update inheritance declarations
- [ ] Verify `nonReentrant` modifier still works

---

### Sub-phase 11.3: Remove Custom Implementation

**Objective:** Delete the custom ReentrancyGuard file.

**File to Delete:**

```
src/utils/ReentrancyGuardUpgradeable.sol
```

**Verification:**

```bash
# After deletion, this should show no results:
grep -r "ReentrancyGuardUpgradeable" src/

# This should show OZ imports:
grep -r "ReentrancyGuardTransient" src/
```

**Tasks:**

- [ ] Delete `src/utils/ReentrancyGuardUpgradeable.sol`
- [ ] Verify no remaining references to custom implementation
- [ ] Run `forge build` to confirm no broken imports

---

### Sub-phase 11.4: Update Initialize Functions

**Objective:** Remove now-unnecessary `__ReentrancyGuard_init()` calls.

**Current Pattern:**

```solidity
function initialize() public initializer {
    __ReentrancyGuard_init();  // REMOVE - not needed for Transient
    __Ownable_init(msg.sender);
    // ...
}
```

**New Pattern:**

```solidity
function initialize() public initializer {
    // ReentrancyGuardTransient needs no initialization
    __Ownable_init(msg.sender);
    // ...
}
```

**Files to Modify:**

| File | Line | Change |
|------|------|--------|
| `JobMarketplaceWithModelsUpgradeable.sol` | ~145 | Remove `__ReentrancyGuard_init()` |
| `HostEarningsUpgradeable.sol` | ~69 | Remove `__ReentrancyGuard_init()` |
| `NodeRegistryWithModelsUpgradeable.sol` | ~95 | Remove `__ReentrancyGuard_init()` |

**Tasks:**

- [ ] Remove init call from JobMarketplace
- [ ] Remove init call from HostEarnings
- [ ] Remove init call from NodeRegistry
- [ ] Verify initialization still works in tests

---

### Sub-phase 11.5: Verify EIP-1153 Support

**Objective:** Confirm transient storage works on target networks.

**EIP-1153 (Transient Storage) Support:**

| Network | Cancun Upgrade | EIP-1153 Support |
|---------|----------------|------------------|
| Base Mainnet | March 2024 | ✅ Supported |
| Base Sepolia | March 2024 | ✅ Supported |
| Ethereum Mainnet | March 2024 | ✅ Supported |

**Verification Steps:**

```bash
# 1. Run tests with specific Solidity version
forge test --use 0.8.28

# 2. Deploy to Base Sepolia and test
forge script script/DeployAllUpgradeable.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast

# 3. Verify reentrancy protection works
cast call $PROXY "nonReentrantTest()" --rpc-url $BASE_SEPOLIA_RPC_URL
```

**Tasks:**

- [ ] Confirm Base Sepolia supports EIP-1153
- [ ] Run full test suite with 0.8.28
- [ ] Deploy to testnet and verify functionality
- [ ] Test reentrancy protection manually

---

### Phase 11 Summary

| Sub-phase | Description | Effort |
|-----------|-------------|--------|
| 11.1 | Update Solidity pragma | Low |
| 11.2 | Replace imports with OZ Transient | Low |
| 11.3 | Delete custom implementation | Low |
| 11.4 | Update initialize functions | Low |
| 11.5 | Verify EIP-1153 support | Low |

**Total Effort:** Low (mostly search-and-replace)

**Benefits:**

| Benefit | Impact |
|---------|--------|
| Removes auditor concern | Custom code eliminated |
| Gas savings | ~4,900 gas per protected call |
| Reduced codebase | -1 file (~80 lines) |
| Uses battle-tested OZ code | Improved security posture |
| Future-proof | Access to latest Solidity features |

**Dependencies:**

- Should be done BEFORE Phase 10 (tests/docs should reflect final code)
- Can be done in parallel with Phases 1-4, 8-9

**Status:** Planned

---

## Testing Summary

### Test Coverage Required

| Test Category | Tests | Status |
| ------------- | ----- | ------ |
| Phase 1: Withdrawal Refactor | 6 | Pending |
| Phase 2: Receive Function Fixes | 6 | Pending |
| Phase 3: Safe Transfer Methods | 6 | Pending |
| Phase 4: Variable Naming | 0 (refactor only) | Pending |
| Phase 5: Session Deduplication | 0 (deferred) | Deferred |
| Phase 6: Model Tiers Duplication | 0 (deferred) | Deferred |
| Phase 7: Array Iteration | 0 (deferred) | Deferred |
| Phase 8: ProofSystem Naming | 0 (refactor only) | Pending |
| Phase 9: Inline Comment Cleanup | 0 (cleanup only) | Pending |
| Phase 10: Negative/Edge Case Tests | TBD (Sub-phase 10.5) | Pending |
| Phase 10: Integration Test Expansion | TBD (Sub-phase 10.6) | Pending |
| Phase 11: Solidity Upgrade | 0 (upgrade only) | Pending |
| Existing HostEarnings | ~15 | Must Pass |
| Existing JobMarketplace | ~200 | Must Pass |
| Existing ProofSystem | ~30 | Must Pass |
| Full Test Suite | 415+ | Must Pass |

---

## Deployment Plan

### Upgrade Procedure

Since `HostEarningsUpgradeable` is a UUPS upgradeable contract, the fix will be deployed as a new implementation:

```bash
# 1. Deploy new implementation
forge create src/HostEarningsUpgradeable.sol:HostEarningsUpgradeable \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --legacy

# 2. Upgrade proxy (owner only)
cast send $HOST_EARNINGS_PROXY "upgradeToAndCall(address,bytes)" $NEW_IMPL 0x \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# 3. Verify upgrade
cast call $HOST_EARNINGS_PROXY "implementation()" --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Current Proxy Addresses

| Contract | Proxy Address | Current Implementation | Phases |
| -------- | ------------- | ---------------------- | ------ |
| HostEarningsUpgradeable | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | `0x588c42249F85C6ac4B4E27f97416C0289980aabB` | 1, 2, 3 |
| JobMarketplaceWithModelsUpgradeable | `0xeebEEbc9BCD35e81B06885b63f980FeC71d56e2D` | `0x05c7d3a1b748dEbdbc12dd75D1aC195fb93228a3` | 2, 3, 4 |
| NodeRegistryWithModelsUpgradeable | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | `0x68298e2b74a106763aC99E3D973E98012dB5c75F` | 3 |
| ModelRegistryUpgradeable | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | `0xd7Df5c6D4ffe6961d47753D1dd32f844e0F73f50` | 3 |
| ProofSystemUpgradeable | `0x5afB91977e69Cc5003288849059bc62d47E7deeb` | `0xf0DA90e1ae1A3aB7b9Da47790Abd73D26b17670F` | 8 |

---

## Appendix: Issues NOT Addressed in V3

The following audit findings were analyzed and determined to be either:
- Already fixed in V1/V2
- Working as designed
- Not applicable

| Finding | Status | Reason |
| ------- | ------ | ------ |
| Double Accounting of User Deposits | ✅ Fixed (V1) | Session deposits no longer credit withdrawable balance |
| `completeSessionJob()` Authorization | ✅ Fixed (V2) | Restricted to depositor/host only |
| Timed Out Sessions Pay Host | Working as Designed | Pays for cryptographically proven work |
| `claimWithProof()` Unreachable | ✅ Fixed (V1) | Dead code removed |
| Unused `SessionStatus` Values | ✅ Fixed (V2) | Enum reduced to 3 values |
| `_validateHostRegistration()` Stub | ✅ Fixed (V1) | Proper NodeRegistry validation |
| `depositor`/`requester` Redundancy | ✅ Fixed (V2) | `requester` field removed |
| Unused State Variables (`__deprecated_*`) | ✅ Fixed (V2) | All deprecated slots removed in Phase 7.4 |
| Storage Gaps (`__gap`) | Working as Designed | Best practice for UUPS upgrades (see below) |
| Magic Numbers in `estimateBatchGas` | ✅ Fixed (V1) | Comprehensive NatSpec documentation added (see below) |
| Invalid Max Deposit Validation | ✅ Fixed | All session creation functions now have `1000 ether` limit (see below) |
| Custom Reentrancy Guard | Phase 11 | Solidity upgrade enables OZ `ReentrancyGuardTransient` (see Phase 11) |
| Unfair Voting Model | Working as Designed | Governance design trade-off, not security vulnerability (see below) |

### Storage Gaps (`__gap`) Analysis

**Auditor's Finding:**

> `uint256[..] private __gap` variables are not required by the system design for target contracts (the contracts which are not inherited by other contracts).

**Current State:**

| Contract | Gap Size | Comment |
| -------- | -------- | ------- |
| JobMarketplaceWithModelsUpgradeable | `[35]` | 35 slots reserved |
| NodeRegistryWithModelsUpgradeable | `[40]` | 40 slots reserved |
| HostEarningsUpgradeable | `[46]` | 46 slots reserved |
| ProofSystemUpgradeable | `[46]` | 46 slots reserved |
| ModelRegistryUpgradeable | `[49]` | 49 slots reserved |

**Decision: KEEP (Working as Designed)**

While the auditor is correct that storage gaps are not *strictly required* for leaf contracts, they are:

1. **OpenZeppelin Best Practice**: Explicitly recommended for ALL upgradeable contracts
2. **Upgrade Safety**: Prevents storage collisions when adding new state variables in future upgrades
3. **Already Deployed**: Contracts are on Base Sepolia - removing gaps would require redeployment and state migration
4. **Low Cost**: Empty storage slots have negligible gas impact

**Conclusion**: The `__gap` variables serve as future-proofing for UUPS upgrades and should be retained.

---

### Magic Numbers in `estimateBatchGas` Analysis

**Auditor's Finding:**

> `estimateBatchGas` function uses magic numbers which hurt code understanding. Consider introducing meaningful constants for these values.

**Current Implementation (ProofSystemUpgradeable.sol lines 236-251):**

```solidity
/**
 * @notice Estimate gas for batch verification
 * @dev Gas constants derived from actual measurements on verifyBatch():
 *      - Base cost: ~15,000 gas (function call overhead, array setup, event emission)
 *      - Per-proof: ~27,000 gas (signature recovery via ecrecover, hash computations,
 *        storage write for verifiedProofs mapping)
 *      Constants include ~10% safety margin for variance across different EVM implementations.
 *      Measured values: Base ~14,839, Per-proof ~26,824 (rounded up for safety)
 * @param batchSize Number of proofs in batch (1-10)
 * @return Estimated gas consumption for the batch verification
 */
function estimateBatchGas(uint256 batchSize) external pure returns (uint256) {
    require(batchSize > 0 && batchSize <= 10, "Invalid batch size");
    // BASE_VERIFICATION_GAS = 15000, PER_PROOF_GAS = 27000
    return 15000 + (batchSize * 27000);
}
```

**Fix Applied (V1):**
- Comprehensive NatSpec documentation added explaining:
  - What each constant represents
  - How values were derived (actual measurements)
  - Safety margins applied
  - Measured vs. rounded values
- Inline comment naming the constants

**Decision: ADEQUATELY ADDRESSED**

While named constants could be extracted, the current approach with comprehensive documentation is acceptable because:
1. The function is `pure` - no state impact
2. Values are thoroughly documented in NatSpec
3. Inline comment provides quick reference
4. The function is a gas estimation helper, not core business logic

**Commit:** `eef0a97` - fix(ProofSystem): document and fix estimateBatchGas constants

---

### Invalid Max Deposit Validation Analysis

**Auditor's Finding:**

> The `createSessionJob` and `createSessionJobForModel` functions accept ETH transfers without validating the maximum deposit limit (native token instead of ERC20 check).

**Current Implementation:**

All five session creation functions now have max deposit validation:

| Function | Line | Validation |
| -------- | ---- | ---------- |
| `createSessionJob` | 302 | `require(msg.value <= 1000 ether, "Deposit too large");` |
| `createSessionJobForModel` | 352 | `require(msg.value <= 1000 ether, "Deposit too large");` |
| `createSessionJobWithToken` | 417 | `require(deposit <= 1000 ether, "Deposit too large");` |
| `createSessionJobForModelWithToken` | 471 | `require(deposit <= 1000 ether, "Deposit too large");` |
| `createSessionFromDeposit` | 986 | `require(deposit <= 1000 ether, "Deposit too large");` |

**Verification:**

```solidity
// createSessionJob (line 301-302)
require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");
require(msg.value <= 1000 ether, "Deposit too large");  // ✅ PRESENT

// createSessionJobForModel (line 351-352)
require(msg.value >= MIN_DEPOSIT, "Insufficient deposit");
require(msg.value <= 1000 ether, "Deposit too large");  // ✅ PRESENT
```

**Status:** ✅ FIXED - All session creation functions enforce the 1000 ETH maximum deposit limit.

---

### Custom Reentrancy Guard Analysis

**Auditor's Finding:**

> Modifying the OpenZeppelin libraries is considered to be an antipattern. Instead of custom modification of `ReentrancyGuardUpgradeable`, consider directly using `ReentrancyGuard` or `ReentrancyGuardTransient` provided by OpenZeppelin libraries.

**Investigation:**

The custom `src/utils/ReentrancyGuardUpgradeable.sol` is used by:
- `JobMarketplaceWithModelsUpgradeable`
- `HostEarningsUpgradeable`
- `NodeRegistryWithModelsUpgradeable`

**Why Custom Implementation Exists:**

OpenZeppelin 5.x does **NOT** provide a `ReentrancyGuardUpgradeable`:

| OZ Contract | Has Constructor | Works with Proxies |
|-------------|-----------------|-------------------|
| `ReentrancyGuard` | Yes | ❌ No (constructor doesn't run) |
| `ReentrancyGuardTransient` | No | ✓ Yes (requires ^0.8.24) |
| `ReentrancyGuardUpgradeable` | N/A | ❌ Not provided by OZ 5.x |

**Auditor's Alternatives:**

1. **Use `ReentrancyGuard` directly**: ❌ Won't work - constructor sets `_status = NOT_ENTERED` which doesn't run on proxies
2. **Use `ReentrancyGuardTransient`**: Requires Solidity ^0.8.24 (currently using ^0.8.19)

**Is the Custom Implementation Correct?**

✅ Yes - comparing to OZ patterns:

| Aspect | Custom Implementation | Matches OZ |
|--------|----------------------|------------|
| Storage pattern | ERC-7201 namespaced | ✓ |
| Storage slot hash | `0x9b779b17...55f00` | ✓ Identical |
| Initializer pattern | `__ReentrancyGuard_init()` | ✓ |
| Core logic | Same as OZ ReentrancyGuard | ✓ |
| Error type | `ReentrancyGuardReentrantCall()` | ✓ |

**Decision: ADDRESSED BY PHASE 11**

Investigation confirmed the custom implementation is correct and necessary for Solidity ^0.8.19. However, upgrading to Solidity ^0.8.24 enables use of OpenZeppelin's `ReentrancyGuardTransient`.

**Phase 11 Resolution:**

| Action | Result |
|--------|--------|
| Upgrade Solidity to ^0.8.24 | Enables OZ Transient |
| Replace custom with `ReentrancyGuardTransient` | Uses battle-tested OZ code |
| Delete `src/utils/ReentrancyGuardUpgradeable.sol` | Removes custom code entirely |
| Gas savings | ~4,900 gas per protected call |

See **Phase 11: Solidity Version Upgrade and ReentrancyGuard Replacement** for full implementation plan.

---

### Unfair Voting Model Analysis

**Auditor's Finding:**

> Voting functionality in the Model Registry allows users to temporarily lock their FAB tokens to support certain AI models. However, the system allows immediate unlocking ability as soon as the voting period ends. This makes it more reasonable for the users to vote for the model at the end of the voting period. This causes a race condition situation and instead of gradual voting progression, a single whale user might decline certain AI models from being accepted at the last moment.
>
> As well the system does not allow the same model to be proposed twice disabling the ability to change the community decision in future.

**Analysis:**

1. **Last-Minute Voting Attack:**
   - Voting period: 3 days
   - Tokens locked during voting
   - After `executeProposal()`, tokens can be withdrawn immediately
   - A whale could wait until the last block to cast a decisive vote

2. **No Re-Proposal Allowed:**
   - `require(proposals[modelId].proposalTime == 0, "Proposal already exists")`
   - Failed proposals permanently block that model from being proposed again

**Risk Assessment:**

| Concern | Mitigation | Severity |
|---------|------------|----------|
| Whale attack | 100,000 FAB threshold, tokens locked 3 days | LOW |
| No re-proposal | Owner can add as trusted model instead | LOW |

**Decision: KEEP (Working as Designed)**

These are **governance design trade-offs**, not security vulnerabilities:

1. No funds can be stolen
2. No core marketplace functionality affected
3. Economic barriers (100 FAB proposal fee, 3-day token lock)
4. Solutions like commit-reveal voting add significant complexity
5. Owner can always add models as trusted (tier 1) to override

**Future Enhancement (Optional):**

Consider implementing in a future governance upgrade:
- Time-weighted voting or conviction voting
- Proposal cooldown period for re-submission
- Commit-reveal scheme to prevent last-minute attacks

---

**Date:** January 8, 2026
**Version:** 3.0 (In Progress)
