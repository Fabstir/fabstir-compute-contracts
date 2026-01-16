# IMPLEMENTATION_SLASHING.md - Stake Slashing for MVP

## Overview

Implement stake slashing functionality in `NodeRegistryWithModelsUpgradeable` to penalize hosts for proven misbehavior (e.g., overclaiming tokens). This completes the enforcement loop with the existing evidence system (proofCID, deltaCID, conversationCID).

## Repository

fabstir-compute-contracts

## Specification Reference

- **Specification Document**: `docs/sdk-reference/SLASHING_SPECIFICATION.md`
- **Target Contract**: `src/NodeRegistryWithModelsUpgradeable.sol`
- **Proxy Address**: `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` (Base Sepolia)

## Feature Summary

| Feature        | Description                                                                   |
| -------------- | ----------------------------------------------------------------------------- |
| Core Function  | `slashStake(address host, uint256 amount, string evidenceCID, string reason)` |
| Max Slash      | 50% per action                                                                |
| Cooldown       | 24 hours between slashes on same host                                         |
| Minimum Stake  | 100 FAB after slash (auto-unregister if below)                                |
| Access Control | `slashingAuthority` (owner at MVP, DAO later)                                 |
| Slashed Tokens | Transfer to treasury address                                                  |

## Goals

- Add slashing functionality with proper safety constraints
- Maintain UUPS upgradeability (preserve storage layout)
- Enable future DAO transition via `setSlashingAuthority()`
- Follow strict TDD with bounded autonomy approach
- Complete the enforcement loop for evidence-based penalization

## Critical Design Decisions

- **Access Control Pattern**: Use `slashingAuthority` address (not hardcoded owner) for DAO upgrade path
- **Safety First**: 50% max slash + 24h cooldown prevents abuse
- **Evidence Required**: Every slash must have CID (accountability on S5)
- **Auto-Unregister**: If stake falls below 100 FAB, host is automatically removed
- **Graceful Cleanup**: Return remaining stake to host on auto-unregister

## Implementation Progress

**Overall Status: ✅ ALL PHASES COMPLETE - Deployed to Base Sepolia**

- [x] **Phase 1: Core Slashing Infrastructure** (3/3 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 1.1: Add Constants and State Variables ✅
  - [x] Sub-phase 1.2: Add Events and Modifier ✅
  - [x] Sub-phase 1.3: Add Access Control Functions ✅
- [x] **Phase 2: Slashing Logic Implementation** (3/3 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 2.1: Implement slashStake() Function ✅
  - [x] Sub-phase 2.2: Implement Auto-Unregister Logic ✅
  - [x] Sub-phase 2.3: Add \_removeFromActiveNodes Helper ✅
- [x] **Phase 3: Upgrade Initialization** (1/1 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 3.1: Implement initializeSlashing() ✅
- [x] **Phase 4: Final Verification & Deployment** (3/3 sub-phases) ✅ COMPLETE
  - [x] Sub-phase 4.1: Full Test Suite ✅ (681 tests pass)
  - [x] Sub-phase 4.2: Deploy to Testnet ✅ (Implementation: 0xF2D98D38B2dF95f4e8e4A49750823C415E795377)
  - [x] Sub-phase 4.3: Update Documentation and ABIs ✅

**Last Updated:** 2026-01-16

**Test Results:** 681 tests passing (41 slashing-specific tests + 640 existing tests)

**Deployment Details (Jan 16, 2026):**

- Implementation: `0xF2D98D38B2dF95f4e8e4A49750823C415E795377`
- Proxy: `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22`
- Treasury: `0x098f1Ea3FA1CA60d7A4A0f5927c6fc1DBe9c5e1C`
- Test slash executed: 100 FAB from test host `0x048afA7126A3B684832886b78e7cC1Dd4019557E`
- Tx: `0x1433107aa2e1ee2021c4d02096fd17ccfc5a74c653e7887196fa7e0584b4714c`

---

## Phase 1: Core Slashing Infrastructure

### Sub-phase 1.1: Add Constants and State Variables

**Severity**: FEATURE
**Issue**: Need to add slashing-related constants and state variables to contract.

**Storage Layout Consideration:**

- Current `__gap` is 39 slots
- Adding 3 new state variables: `slashingAuthority` (1), `treasury` (1), `lastSlashTime` (1)
- New `__gap` will be 36 slots

**Tasks:**

- [x] Write test file `test/Slashing/test_slashing.t.sol` with setup
- [x] Test: Constants are accessible and have correct values
- [x] Test: State variables are initialized correctly after upgrade
- [x] Add constant `MAX_SLASH_PERCENTAGE = 50`
- [x] Add constant `MIN_STAKE_AFTER_SLASH = 100 * 1e18`
- [x] Add constant `SLASH_COOLDOWN = 24 hours`
- [x] Add state variable `address public slashingAuthority`
- [x] Add state variable `address public treasury`
- [x] Add state variable `mapping(address => uint256) public lastSlashTime`
- [x] Reduce `__gap` from 39 to 36
- [x] Verify all tests pass (646/646)

**Implementation:**

```solidity
// Add after line 41 (after MAX_PRICE_PER_TOKEN_NATIVE)
uint256 public constant MAX_SLASH_PERCENTAGE = 50;          // 50% maximum per slash
uint256 public constant MIN_STAKE_AFTER_SLASH = 100 * 1e18; // 100 FAB minimum
uint256 public constant SLASH_COOLDOWN = 24 hours;          // Cooldown between slashes

// Add before __gap (after activeNodesList, line 69)
address public slashingAuthority;
address public treasury;
mapping(address => uint256) public lastSlashTime;

// Update __gap from 39 to 36
uint256[36] private __gap;  // Was: uint256[39] private __gap;
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol` (lines 42-44, 70-72, 84)

**Files Created:**

- `test/NodeRegistry/test_slashing.t.sol`

**Tests:**

```solidity
// test/NodeRegistry/test_slashing.t.sol
function test_Constants_MaxSlashPercentage() public { /* ... */ }
function test_Constants_MinStakeAfterSlash() public { /* ... */ }
function test_Constants_SlashCooldown() public { /* ... */ }
```

---

### Sub-phase 1.2: Add Events and Modifier

**Severity**: FEATURE
**Issue**: Need events for transparency and modifier for access control.

**Tasks:**

- [x] Test: Events are declared (compilation test)
- [x] Add `event SlashExecuted(address indexed host, uint256 amount, uint256 remainingStake, string evidenceCID, string reason, address indexed executor, uint256 timestamp)`
- [x] Add `event HostAutoUnregistered(address indexed host, uint256 slashedAmount, uint256 returnedAmount, string reason)`
- [x] Add `event SlashingAuthorityUpdated(address indexed previousAuthority, address indexed newAuthority)`
- [x] Add `event TreasuryUpdated(address indexed newTreasury)`
- [x] Add `modifier onlySlashingAuthority()`
- [x] Verify all tests pass (647/647)

_Note: Event emission and modifier tests will be done in Sub-phases 1.3 and 2.1 with the functions that use them._

**Implementation:**

```solidity
// Add after existing events (after line 81)
event SlashExecuted(
    address indexed host,
    uint256 amount,
    uint256 remainingStake,
    string evidenceCID,
    string reason,
    address indexed executor,
    uint256 timestamp
);
event HostAutoUnregistered(
    address indexed host,
    uint256 slashedAmount,
    uint256 returnedAmount,
    string reason
);
event SlashingAuthorityUpdated(
    address indexed previousAuthority,
    address indexed newAuthority
);
event TreasuryUpdated(address indexed newTreasury);

// Add modifier after constructor
modifier onlySlashingAuthority() {
    require(msg.sender == slashingAuthority, "Not slashing authority");
    _;
}
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol`

**Tests:**

```solidity
function test_OnlySlashingAuthority_RevertsForNonAuthority() public { /* ... */ }
function test_OnlySlashingAuthority_AllowsAuthority() public { /* ... */ }
```

---

### Sub-phase 1.3: Add Access Control Functions

**Severity**: FEATURE
**Issue**: Need functions to manage slashing authority and treasury.

**Tasks:**

- [x] Test: setSlashingAuthority only callable by owner
- [x] Test: setSlashingAuthority reverts on zero address
- [x] Test: setSlashingAuthority updates authority correctly
- [x] Test: setSlashingAuthority emits SlashingAuthorityUpdated event
- [x] Test: setTreasury only callable by owner
- [x] Test: setTreasury reverts on zero address
- [x] Test: setTreasury updates treasury correctly
- [x] Test: setTreasury emits TreasuryUpdated event
- [x] Implement `setSlashingAuthority(address newAuthority) external onlyOwner`
- [x] Implement `setTreasury(address newTreasury) external onlyOwner`
- [x] Verify all tests pass (655/655)

**Implementation:**

```solidity
/**
 * @notice Set the slashing authority address
 * @dev Only callable by owner. Authority can be transferred to DAO later.
 * @param newAuthority New slashing authority address
 */
function setSlashingAuthority(address newAuthority) external onlyOwner {
    require(newAuthority != address(0), "Invalid authority");
    emit SlashingAuthorityUpdated(slashingAuthority, newAuthority);
    slashingAuthority = newAuthority;
}

/**
 * @notice Set the treasury address for slashed tokens
 * @dev Only callable by owner
 * @param newTreasury New treasury address
 */
function setTreasury(address newTreasury) external onlyOwner {
    require(newTreasury != address(0), "Invalid treasury");
    emit TreasuryUpdated(newTreasury);
    treasury = newTreasury;
}
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol`

**Tests:**

```solidity
function test_SetSlashingAuthority_OnlyOwner() public { /* ... */ }
function test_SetSlashingAuthority_RevertsOnZeroAddress() public { /* ... */ }
function test_SetSlashingAuthority_UpdatesAuthority() public { /* ... */ }
function test_SetSlashingAuthority_EmitsEvent() public { /* ... */ }
function test_SetTreasury_OnlyOwner() public { /* ... */ }
function test_SetTreasury_RevertsOnZeroAddress() public { /* ... */ }
function test_SetTreasury_UpdatesTreasury() public { /* ... */ }
function test_SetTreasury_EmitsEvent() public { /* ... */ }
```

---

## Phase 2: Slashing Logic Implementation

### Sub-phase 2.1: Implement slashStake() Function

**Severity**: FEATURE
**Issue**: Core slashing function with all validations.

**Tasks:**

- [x] Test: slashStake reduces host stake correctly
- [x] Test: slashStake transfers slashed amount to treasury
- [x] Test: slashStake emits SlashExecuted event
- [x] Test: slashStake updates lastSlashTime
- [x] Test: slashStake reverts if host not active
- [x] Test: slashStake reverts if host not registered
- [x] Test: slashStake reverts if evidence CID is empty
- [x] Test: slashStake reverts if reason is empty
- [x] Test: slashStake reverts if amount exceeds stake
- [x] Test: slashStake reverts if amount exceeds max percentage (50%)
- [x] Test: slashStake reverts if cooldown is active
- [x] Test: slashStake reverts if caller is not authority
- [x] Test: slashStake works after cooldown expires
- [x] Test: slashStake allows exactly 50% slash
- [x] Implement `slashStake()` function with all validations
- [x] Verify all tests pass (669/669)

**Implementation:**

```solidity
/**
 * @notice Slash a portion of a host's stake for proven misbehavior
 * @dev Only callable by slashing authority (owner at MVP, DAO later)
 * @param host Address of the host to slash
 * @param amount Amount of FAB tokens to slash
 * @param evidenceCID S5 CID containing evidence (proofCID, deltaCID, or custom report)
 * @param reason Human-readable reason for the slash
 */
function slashStake(
    address host,
    uint256 amount,
    string calldata evidenceCID,
    string calldata reason
) external onlySlashingAuthority nonReentrant {
    // Validation
    require(nodes[host].operator != address(0), "Host not registered");
    require(nodes[host].active, "Host not active");
    require(nodes[host].stakedAmount > 0, "No stake to slash");
    require(bytes(evidenceCID).length > 0, "Evidence CID required");
    require(bytes(reason).length > 0, "Reason required");
    require(amount <= nodes[host].stakedAmount, "Amount exceeds stake");

    // Safety constraints
    uint256 maxSlash = (nodes[host].stakedAmount * MAX_SLASH_PERCENTAGE) / 100;
    require(amount <= maxSlash, "Exceeds max slash percentage");
    require(
        block.timestamp >= lastSlashTime[host] + SLASH_COOLDOWN,
        "Slash cooldown active"
    );

    // Execute slash
    nodes[host].stakedAmount -= amount;
    lastSlashTime[host] = block.timestamp;

    // Transfer slashed tokens to treasury
    fabToken.safeTransfer(treasury, amount);

    // Check if auto-unregister needed (handled in Sub-phase 2.2)
    // ...

    emit SlashExecuted(
        host,
        amount,
        nodes[host].stakedAmount,
        evidenceCID,
        reason,
        msg.sender,
        block.timestamp
    );
}
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol`

**Tests:**

```solidity
function test_SlashStake_ReducesHostStake() public { /* ... */ }
function test_SlashStake_TransfersToTreasury() public { /* ... */ }
function test_SlashStake_EmitsSlashExecutedEvent() public { /* ... */ }
function test_SlashStake_UpdatesLastSlashTime() public { /* ... */ }
function test_SlashStake_RevertsIfHostNotActive() public { /* ... */ }
function test_SlashStake_RevertsIfHostNotRegistered() public { /* ... */ }
function test_SlashStake_RevertsIfNoStake() public { /* ... */ }
function test_SlashStake_RevertsIfNoEvidence() public { /* ... */ }
function test_SlashStake_RevertsIfNoReason() public { /* ... */ }
function test_SlashStake_RevertsIfAmountExceedsStake() public { /* ... */ }
function test_SlashStake_RevertsIfExceedsMaxPercentage() public { /* ... */ }
function test_SlashStake_RevertsIfCooldownActive() public { /* ... */ }
function test_SlashStake_RevertsIfNotAuthority() public { /* ... */ }
```

---

### Sub-phase 2.2: Implement Auto-Unregister Logic

**Severity**: FEATURE
**Issue**: When stake falls below MIN_STAKE_AFTER_SLASH, host should be automatically unregistered.

**Tasks:**

- [ ] Test: Auto-unregister triggers when stake falls below 100 FAB
- [ ] Test: Auto-unregister returns remaining stake to host
- [ ] Test: Auto-unregister removes host from active nodes list
- [ ] Test: Auto-unregister removes host from model mappings
- [ ] Test: Auto-unregister emits HostAutoUnregistered event
- [ ] Test: Exact boundary - 100 FAB remaining does NOT trigger auto-unregister
- [ ] Test: Boundary - 99.99 FAB remaining DOES trigger auto-unregister
- [ ] Add auto-unregister logic to slashStake()
- [ ] Verify all tests pass

**Implementation:**

```solidity
// Add to slashStake() after slashing logic:

// Check if auto-unregister needed
if (nodes[host].stakedAmount < MIN_STAKE_AFTER_SLASH) {
    uint256 remaining = nodes[host].stakedAmount;

    // Clear stake
    nodes[host].stakedAmount = 0;
    nodes[host].active = false;

    // Remove from active nodes list
    _removeFromActiveNodes(host);

    // Remove from model mappings
    bytes32[] memory models = nodes[host].supportedModels;
    for (uint i = 0; i < models.length; i++) {
        _removeNodeFromModel(models[i], host);
    }

    // Return remaining stake to host
    if (remaining > 0) {
        fabToken.safeTransfer(host, remaining);
    }

    emit HostAutoUnregistered(host, amount, remaining, reason);
}
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol`

**Tests:**

```solidity
function test_SlashStake_AutoUnregistersIfBelowMinimum() public { /* ... */ }
function test_SlashStake_ReturnsRemainingStakeOnAutoUnregister() public { /* ... */ }
function test_SlashStake_RemovesFromActiveNodesOnAutoUnregister() public { /* ... */ }
function test_SlashStake_RemovesFromModelMappingsOnAutoUnregister() public { /* ... */ }
function test_SlashStake_EmitsHostAutoUnregisteredEvent() public { /* ... */ }
function test_SlashStake_ExactBoundary_100FAB_NoAutoUnregister() public { /* ... */ }
function test_SlashStake_Boundary_Below100FAB_AutoUnregisters() public { /* ... */ }
```

---

### Sub-phase 2.3: Add \_removeFromActiveNodes Helper

**Severity**: FEATURE
**Issue**: Need helper function to remove host from activeNodesList (extract from unregisterNode for reuse).

**Tasks:**

- [ ] Test: \_removeFromActiveNodes correctly removes host
- [ ] Test: \_removeFromActiveNodes maintains array integrity (swap-and-pop)
- [ ] Test: \_removeFromActiveNodes updates activeNodesIndex mapping
- [ ] Extract \_removeFromActiveNodes logic from unregisterNode()
- [ ] Refactor unregisterNode() to use \_removeFromActiveNodes()
- [ ] Use \_removeFromActiveNodes() in auto-unregister logic
- [ ] Verify all tests pass

**Implementation:**

```solidity
/**
 * @notice Remove a node from the active nodes list using swap-and-pop
 * @dev Internal helper used by unregisterNode and slashStake auto-unregister
 * @param nodeAddress Address of the node to remove
 */
function _removeFromActiveNodes(address nodeAddress) private {
    uint256 index = activeNodesIndex[nodeAddress];

    // Safety check for corrupt state
    bool isInActiveList = activeNodesList.length > 0 &&
        index < activeNodesList.length &&
        activeNodesList[index] == nodeAddress;

    if (isInActiveList) {
        uint256 lastIndex = activeNodesList.length - 1;
        if (index != lastIndex) {
            address lastNode = activeNodesList[lastIndex];
            activeNodesList[index] = lastNode;
            activeNodesIndex[lastNode] = index;
        }
        activeNodesList.pop();
    }

    delete activeNodesIndex[nodeAddress];
}
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol`

**Tests:**

```solidity
function test_RemoveFromActiveNodes_CorrectlyRemoves() public { /* ... */ }
function test_RemoveFromActiveNodes_SwapAndPopIntegrity() public { /* ... */ }
function test_RemoveFromActiveNodes_UpdatesIndex() public { /* ... */ }
function test_UnregisterNode_StillWorks_AfterRefactor() public { /* ... */ }
```

---

## Phase 3: Upgrade Initialization

### Sub-phase 3.1: Implement initializeSlashing()

**Severity**: FEATURE
**Issue**: Need initialization function for upgrading existing proxies.

**Tasks:**

- [ ] Test: initializeSlashing sets slashingAuthority to owner
- [ ] Test: initializeSlashing sets treasury correctly
- [ ] Test: initializeSlashing reverts if already initialized
- [ ] Test: initializeSlashing only callable by owner
- [ ] Implement `initializeSlashing(address _treasury) external onlyOwner`
- [ ] Verify all tests pass

**Implementation:**

```solidity
/**
 * @notice Initialize slashing functionality after upgrade
 * @dev Call this after upgrading to the new implementation
 * @param _treasury Address to receive slashed FAB tokens
 */
function initializeSlashing(address _treasury) external onlyOwner {
    require(slashingAuthority == address(0), "Already initialized");
    require(_treasury != address(0), "Invalid treasury");
    slashingAuthority = owner();
    treasury = _treasury;
}
```

**Files Modified:**

- `src/NodeRegistryWithModelsUpgradeable.sol`

**Tests:**

```solidity
function test_InitializeSlashing_SetsSlashingAuthority() public { /* ... */ }
function test_InitializeSlashing_SetsTreasury() public { /* ... */ }
function test_InitializeSlashing_RevertsIfAlreadyInitialized() public { /* ... */ }
function test_InitializeSlashing_OnlyOwner() public { /* ... */ }
```

---

## Phase 4: Final Verification & Deployment

### Sub-phase 4.1: Full Test Suite

**Tasks:**

- [ ] Run full test suite: `forge test`
- [ ] Verify all tests pass
- [ ] Verify no compiler warnings in source files
- [ ] Run gas snapshot: `forge snapshot`

**Commands:**

```bash
forge clean
forge build
forge test -vv
forge snapshot
```

---

### Sub-phase 4.2: Deploy to Testnet

**Tasks:**

- [ ] Deploy new NodeRegistryWithModelsUpgradeable implementation
- [ ] Upgrade proxy to new implementation
- [ ] Call initializeSlashing(treasuryAddress)
- [ ] Verify slashingAuthority is set to owner
- [ ] Verify treasury is set correctly
- [ ] Test slashStake on testnet (optional: with test host)

**Commands:**

```bash
source /workspace/.env

# Deploy new implementation
forge create src/NodeRegistryWithModelsUpgradeable.sol:NodeRegistryWithModelsUpgradeable \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --legacy --broadcast

# Upgrade proxy
cast send 0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22 "upgradeToAndCall(address,bytes)" \
  $NEW_IMPL_ADDRESS 0x \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Initialize slashing (treasury address TBD)
cast send 0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22 "initializeSlashing(address)" \
  $TREASURY_ADDRESS \
  --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

# Verify
cast call 0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22 "slashingAuthority()" \
  --rpc-url $BASE_SEPOLIA_RPC_URL
cast call 0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22 "treasury()" \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

---

### Sub-phase 4.3: Update Documentation and ABIs

**Tasks:**

- [ ] Extract updated ABI to `client-abis/NodeRegistry-CLIENT-ABI.json`
- [ ] Update `client-abis/CHANGELOG.md` with slashing feature
- [ ] Update `client-abis/README.md` with slashing documentation
- [ ] Update `CONTRACT_ADDRESSES.md` with new implementation address

**Files to Update:**

- `client-abis/NodeRegistryWithModelsUpgradeable-CLIENT-ABI.json`
- `client-abis/CHANGELOG.md`
- `client-abis/README.md`
- `CONTRACT_ADDRESSES.md`

---

## Completion Criteria

All phases complete when:

- [x] All slashing tests pass ✅
- [x] Full test suite passes (no regressions) ✅
- [x] No compiler warnings in source files ✅
- [x] Storage layout verified (gap reduced from 39 to 36) ✅
- [x] Testnet deployment successful ✅
- [x] initializeSlashing() called and verified ✅
- [x] Documentation and ABIs updated ✅

**✅ ALL CRITERIA MET - January 16, 2026**

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

- Test files: No limit
- Modified functions: Keep changes minimal and focused
- New functions: 40 lines maximum
- Commit after each sub-phase

### Storage Layout

```
// Current layout (before slashing):
mapping(address => Node) public nodes;                          // slot N
mapping(address => uint256) public activeNodesIndex;            // slot N+1
mapping(bytes32 => address[]) public modelToNodes;              // slot N+2
mapping(bytes32 => mapping(address => uint256)) private modelNodeIndex;  // slot N+3
mapping(address => mapping(bytes32 => uint256)) public modelPricingNative;  // slot N+4
mapping(address => mapping(bytes32 => uint256)) public modelPricingStable;  // slot N+5
mapping(address => mapping(address => uint256)) public customTokenPricing;  // slot N+6
address[] public activeNodesList;                               // slot N+7
uint256[39] private __gap;                                      // slots N+8 to N+46

// New layout (after slashing):
... (same as above through activeNodesList)
address public slashingAuthority;                               // slot N+8 (NEW)
address public treasury;                                        // slot N+9 (NEW)
mapping(address => uint256) public lastSlashTime;               // slot N+10 (NEW)
uint256[36] private __gap;                                      // slots N+11 to N+46 (REDUCED)
```

### Security Considerations

- `slashStake()` uses `nonReentrant` modifier
- All inputs validated before state changes
- Evidence CID requirement ensures accountability
- 50% cap prevents accidental complete stake destruction
- 24h cooldown prevents rapid-fire attacks

### SDK Integration (Future)

After deployment, SDK should add:

```typescript
// In HostManager
async slashStake(host: string, amount: string, evidenceCID: string, reason: string)
async getSlashHistory(host: string): Promise<SlashEvent[]>
```

---

## Answers to SDK Developer Questions

**Q: Any concerns with the approach?**
A: No concerns. The specification is comprehensive with proper safety constraints (50% max, 24h cooldown, evidence required). The implementation follows existing patterns in the codebase.

**Q: Estimated timeline?**
A: Following TDD approach, implementation is straightforward. The spec includes complete reference code in Appendix A. Estimate: 4 phases with ~10 sub-phases total.

**Q: Separate upgrade script or bundle with other changes?**
A: Not required as separate script. Can upgrade proxy and call `initializeSlashing()` manually, or bundle with other pending changes. The upgrade path is simple: deploy impl → upgrade proxy → initialize.

---

_End of Implementation Document_
