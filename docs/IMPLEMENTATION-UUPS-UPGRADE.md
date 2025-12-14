# IMPLEMENTATION-UUPS-UPGRADE.md - Upgradeable Contract Architecture

## Overview

Convert all Fabstir marketplace contracts from immutable deployments to UUPS (Universal Upgradeable Proxy Standard) pattern. This enables future upgrades without data migration, critical for production systems on Base mainnet.

## Repository

fabstir-compute-contracts

## Goals

- Enable contract logic upgrades without migrating user data
- Preserve all existing functionality during upgrade
- Add emergency pause capability for critical situations
- Maintain backward compatibility with existing ABIs
- Support both testnet (fresh deploy) and mainnet (migration) scenarios

## Critical Design Decisions

- **Pattern**: UUPS (code in implementation, cheaper deploys than Transparent Proxy)
- **Authorization**: Owner-only upgrades via `_authorizeUpgrade()` (all contracts)
- **Storage Gap**: 50 slots reserved in each contract for future additions
- **Initialization**: Replace constructors with `initialize()` functions
- **Immutable Variables**: Convert to regular storage (set in `initialize()`)
- **File Strategy**: Hybrid - Keep originals during dev, delete before audit (see below)
- **Emergency Pause**: Add to JobMarketplace for security incidents

## File Strategy: Hybrid Approach

**Why**: Keeping original contracts during development allows:
- Side-by-side behavioral comparison
- Running existing tests against both versions
- Lower risk of introducing bugs
- Easy rollback if something breaks

**Development Phase:**
```
src/
├── ModelRegistry.sol                    ← Original (keep for reference)
├── ModelRegistryUpgradeable.sol         ← New UUPS version
├── ProofSystem.sol                      ← Original
├── ProofSystemUpgradeable.sol           ← New UUPS version
├── HostEarnings.sol                     ← Original
├── HostEarningsUpgradeable.sol          ← New UUPS version
├── NodeRegistryWithModels.sol           ← Original
├── NodeRegistryWithModelsUpgradeable.sol ← New UUPS version
├── JobMarketplaceWithModels.sol         ← Original
└── JobMarketplaceWithModelsUpgradeable.sol ← New UUPS version
```

**Pre-Audit Phase (Phase 8):**
```
src/
├── ModelRegistry.sol                    ← Renamed from Upgradeable version
├── ProofSystem.sol                      ← Renamed from Upgradeable version
├── HostEarnings.sol                     ← Renamed from Upgradeable version
├── NodeRegistryWithModels.sol           ← Renamed from Upgradeable version
└── JobMarketplaceWithModels.sol         ← Renamed from Upgradeable version
```

Originals deleted, upgradeable versions renamed → Clean codebase for audit

## Contract Dependency Order

```
ModelRegistry (no dependencies)
     ↓
ProofSystem (no dependencies)
     ↓
HostEarnings (no dependencies)
     ↓
NodeRegistryWithModels (depends on ModelRegistry)
     ↓
JobMarketplaceWithModels (depends on NodeRegistry, HostEarnings, ProofSystem)
```

## Implementation Progress

**Overall Status: NOT STARTED (0%)**

- [x] **Phase 1: Infrastructure Setup** (3/3 sub-phases complete) ✅
- [ ] **Phase 2: ModelRegistry Upgrade** (0/4 sub-phases complete)
- [ ] **Phase 3: ProofSystem Upgrade** (0/4 sub-phases complete)
- [ ] **Phase 4: HostEarnings Upgrade** (0/4 sub-phases complete)
- [ ] **Phase 5: NodeRegistryWithModels Upgrade** (0/4 sub-phases complete)
- [ ] **Phase 6: JobMarketplaceWithModels Upgrade** (0/5 sub-phases complete)
- [ ] **Phase 7: Integration & Deployment** (0/4 sub-phases complete)
- [ ] **Phase 8: Cleanup for Audit** (0/3 sub-phases complete)

**Last Updated:** 2025-12-14

---

## Phase 1: Infrastructure Setup

### Sub-phase 1.1: Install OpenZeppelin Upgradeable Contracts ✅

Install the upgradeable contracts library.

**Tasks:**
- [x] Install `@openzeppelin/contracts-upgradeable` via forge
- [x] Verify installation in `lib/` directory
- [x] Update remappings if needed (auto-detected by forge)
- [x] Verify imports work in test file
- [x] Create custom `ReentrancyGuardUpgradeable` (OZ 5.x removed this)

**Commands:**
```bash
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-git
```

**Files Created:**
- `src/utils/ReentrancyGuardUpgradeable.sol` (custom, OZ 5.x compatible)
- `test/Upgradeable/test_imports.t.sol` (verification test)

**Notes:**
- OpenZeppelin 5.x removed `ReentrancyGuardUpgradeable` from upgradeable package
- Created custom implementation using ERC-7201 namespaced storage pattern
- All imports verified working: Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable, ERC1967Proxy

---

### Sub-phase 1.2: Create Upgradeable Test Setup ✅

Create base test infrastructure for upgradeable contracts.

**Tasks:**
- [x] Create `test/Upgradeable/TestSetupUpgradeable.t.sol`
- [x] Add helper for deploying proxy + implementation
- [x] Add helper for upgrading implementations
- [x] Test: Deploy proxy and call initialize
- [x] Test: Upgrade implementation and verify state preserved

**Implementation:**
```solidity
// test/Upgradeable/TestSetupUpgradeable.t.sol
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestSetupUpgradeable is Test {
    function deployProxy(address implementation, bytes memory data) internal returns (address);
    function upgradeProxy(address proxy, address newImplementation, address caller) internal;
    function upgradeProxyWithData(address proxy, address newImpl, bytes memory data, address caller) internal;
    function getImplementation(address proxy) internal view returns (address);
}
```

**Files Created:**
- `test/Upgradeable/TestSetupUpgradeable.t.sol`

**Tests (7/7 passing):**
- `test_DeployProxy` - Deploy proxy with initialization ✅
- `test_GetImplementation` - Read implementation from proxy ✅
- `test_UpgradeProxy` - Upgrade to V2, verify state preserved ✅
- `test_UpgradeProxyWithData` - Upgrade with reinitialization ✅
- `test_OnlyOwnerCanUpgrade` - Non-owner cannot upgrade ✅
- `test_CannotInitializeTwice` - Double init reverts ✅
- `test_ImplementationCannotBeInitialized` - Direct init disabled ✅

---

### Sub-phase 1.3: Create Deployment Helper Script ✅

Create deployment scripts for proxy pattern.

**Tasks:**
- [x] Create `script/DeployUpgradeable.s.sol` base script
- [x] Add function to deploy implementation + proxy
- [x] Add function to upgrade existing proxy
- [x] Test deployment script on local anvil

**Files Created:**
- `script/DeployUpgradeable.s.sol`
- `test/Upgradeable/test_deployment_script.t.sol`

**Helper Functions:**
- `deployProxy(implementation, initData)` - Deploy proxy with initialization
- `upgradeProxy(proxy, newImplementation)` - Upgrade existing proxy
- `upgradeProxyWithData(proxy, newImpl, data)` - Upgrade with reinitialization
- `getImplementation(proxy)` - Read implementation from ERC1967 slot
- `logDeployment(name, proxy, implementation)` - Pretty print deployment info

**Tests (2/2 passing):**
- `test_DeploymentScriptWorks` - Deploy and verify initialization ✅
- `test_GetImplementationWorks` - Read implementation address ✅

---

## Phase 2: ModelRegistry Upgrade

### Sub-phase 2.1: Create ModelRegistryUpgradeable Contract

Create new UUPS version alongside original (kept for comparison).

**Tasks:**
- [ ] Create `src/ModelRegistryUpgradeable.sol` (copy from original)
- [ ] Replace `Ownable` with `OwnableUpgradeable`
- [ ] Add `Initializable` and `UUPSUpgradeable` imports
- [ ] Convert `immutable governanceToken` to regular storage
- [ ] Replace `constructor` with `initialize()` function
- [ ] Add `_authorizeUpgrade()` function (onlyOwner)
- [ ] Add `__gap` storage (50 slots)
- [ ] Verify contract compiles

**Implementation:**
```solidity
// src/ModelRegistryUpgradeable.sol (NEW FILE)
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ModelRegistryUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Storage (was immutable, now regular)
    IERC20 public governanceToken;

    // ... existing storage copied from ModelRegistry.sol ...

    // Storage gap for future upgrades
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _governanceToken) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        require(_governanceToken != address(0), "Invalid token address");
        governanceToken = IERC20(_governanceToken);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

**Files Created:**
- `src/ModelRegistryUpgradeable.sol`

**Files Kept (for comparison):**
- `src/ModelRegistry.sol` (original, unchanged)

---

### Sub-phase 2.2: Write ModelRegistry Upgrade Tests

Write comprehensive tests for upgradeable ModelRegistry.

**Tasks:**
- [ ] Create `test/Upgradeable/ModelRegistry/test_initialization.t.sol`
- [ ] Create `test/Upgradeable/ModelRegistry/test_upgrade.t.sol`
- [ ] Test: Initialize sets governance token correctly
- [ ] Test: Initialize can only be called once
- [ ] Test: All existing functions work through proxy
- [ ] Test: Upgrade preserves model data
- [ ] Test: Only owner can upgrade
- [ ] Test: Non-owner upgrade reverts

**Tests:**
```solidity
// test/Upgradeable/ModelRegistry/test_initialization.t.sol
function test_InitializeSetsGovernanceToken() public { /* ... */ }
function test_InitializeCanOnlyBeCalledOnce() public { /* ... */ }
function test_AddTrustedModelWorksThroughProxy() public { /* ... */ }

// test/Upgradeable/ModelRegistry/test_upgrade.t.sol
function test_UpgradePreservesModelData() public { /* ... */ }
function test_OnlyOwnerCanUpgrade() public { /* ... */ }
function test_NonOwnerUpgradeReverts() public { /* ... */ }
```

**Files Created:**
- `test/Upgradeable/ModelRegistry/test_initialization.t.sol`
- `test/Upgradeable/ModelRegistry/test_upgrade.t.sol`

---

### Sub-phase 2.3: Verify Tests Pass (RED → GREEN)

Run tests and verify implementation.

**Tasks:**
- [ ] Run tests, verify they FAIL initially (RED)
- [ ] Fix any issues in implementation
- [ ] Run tests, verify they PASS (GREEN)
- [ ] Verify all existing ModelRegistry tests still pass

**Commands:**
```bash
forge test --match-path "test/Upgradeable/ModelRegistry/*.t.sol" -vv
```

---

### Sub-phase 2.4: Create ModelRegistry Deployment Script

Create deployment script for ModelRegistryUpgradeable.

**Tasks:**
- [ ] Create `script/DeployModelRegistryUpgradeable.s.sol`
- [ ] Deploy implementation contract
- [ ] Deploy ERC1967 proxy
- [ ] Call initialize through proxy
- [ ] Verify deployment on local anvil

**Files Created:**
- `script/DeployModelRegistryUpgradeable.s.sol`

---

## Phase 3: ProofSystem Upgrade

### Sub-phase 3.1: Create ProofSystemUpgradeable Contract

Create new UUPS version alongside original (kept for comparison).

**Tasks:**
- [ ] Create `src/ProofSystemUpgradeable.sol` (copy from original)
- [ ] Add `Initializable` and `UUPSUpgradeable` imports
- [ ] Add `OwnableUpgradeable` (replace manual owner)
- [ ] Replace `constructor` with `initialize()` function
- [ ] Add `_authorizeUpgrade()` function (onlyOwner)
- [ ] Add `__gap` storage (50 slots)
- [ ] Verify contract compiles

**Files Created:**
- `src/ProofSystemUpgradeable.sol`

**Files Kept (for comparison):**
- `src/ProofSystem.sol` (original, unchanged)

---

### Sub-phase 3.2: Write ProofSystem Upgrade Tests

Write comprehensive tests for upgradeable ProofSystem.

**Tasks:**
- [ ] Create `test/Upgradeable/ProofSystem/test_initialization.t.sol`
- [ ] Create `test/Upgradeable/ProofSystem/test_upgrade.t.sol`
- [ ] Test: Initialize sets owner correctly
- [ ] Test: Initialize can only be called once
- [ ] Test: Proof verification works through proxy
- [ ] Test: Upgrade preserves verified proofs mapping
- [ ] Test: Only owner can upgrade

**Files Created:**
- `test/Upgradeable/ProofSystem/test_initialization.t.sol`
- `test/Upgradeable/ProofSystem/test_upgrade.t.sol`

---

### Sub-phase 3.3: Verify Tests Pass (RED → GREEN)

**Tasks:**
- [ ] Run tests, verify they FAIL initially (RED)
- [ ] Fix any issues in implementation
- [ ] Run tests, verify they PASS (GREEN)

---

### Sub-phase 3.4: Create ProofSystem Deployment Script

**Tasks:**
- [ ] Create `script/DeployProofSystemUpgradeable.s.sol`
- [ ] Deploy implementation + proxy
- [ ] Verify on local anvil

**Files Created:**
- `script/DeployProofSystemUpgradeable.s.sol`

---

## Phase 4: HostEarnings Upgrade

### Sub-phase 4.1: Create HostEarningsUpgradeable Contract

Create new UUPS version alongside original (kept for comparison).

**Tasks:**
- [ ] Create `src/HostEarningsUpgradeable.sol` (copy from original)
- [ ] Replace `ReentrancyGuard` with `ReentrancyGuardUpgradeable`
- [ ] Replace `Ownable` with `OwnableUpgradeable`
- [ ] Add `Initializable` and `UUPSUpgradeable`
- [ ] Replace `constructor` with `initialize()` function
- [ ] Add `_authorizeUpgrade()` function
- [ ] Add `__gap` storage (50 slots)

**Implementation:**
```solidity
// src/HostEarningsUpgradeable.sol (NEW FILE)
contract HostEarningsUpgradeable is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // ... existing storage copied from HostEarnings.sol ...
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

**Files Created:**
- `src/HostEarningsUpgradeable.sol`

**Files Kept (for comparison):**
- `src/HostEarnings.sol` (original, unchanged)

---

### Sub-phase 4.2: Write HostEarnings Upgrade Tests

**Tasks:**
- [ ] Create `test/Upgradeable/HostEarnings/test_initialization.t.sol`
- [ ] Create `test/Upgradeable/HostEarnings/test_upgrade.t.sol`
- [ ] Test: Initialize sets owner correctly
- [ ] Test: Earnings accumulation works through proxy
- [ ] Test: Upgrade preserves host earnings balances
- [ ] Test: Only owner can upgrade

**Files Created:**
- `test/Upgradeable/HostEarnings/test_initialization.t.sol`
- `test/Upgradeable/HostEarnings/test_upgrade.t.sol`

---

### Sub-phase 4.3: Verify Tests Pass (RED → GREEN)

**Tasks:**
- [ ] Run tests, verify they FAIL initially (RED)
- [ ] Fix any issues in implementation
- [ ] Run tests, verify they PASS (GREEN)

---

### Sub-phase 4.4: Create HostEarnings Deployment Script

**Tasks:**
- [ ] Create `script/DeployHostEarningsUpgradeable.s.sol`
- [ ] Deploy implementation + proxy
- [ ] Verify on local anvil

**Files Created:**
- `script/DeployHostEarningsUpgradeable.s.sol`

---

## Phase 5: NodeRegistryWithModels Upgrade

### Sub-phase 5.1: Create NodeRegistryWithModelsUpgradeable Contract

Create new UUPS version alongside original (kept for comparison). **Most complex due to immutable fabToken**.

**Tasks:**
- [ ] Create `src/NodeRegistryWithModelsUpgradeable.sol` (copy from original)
- [ ] Replace `Ownable` with `OwnableUpgradeable`
- [ ] Replace `ReentrancyGuard` with `ReentrancyGuardUpgradeable`
- [ ] Add `Initializable` and `UUPSUpgradeable`
- [ ] Convert `immutable fabToken` to regular storage
- [ ] Replace `constructor` with `initialize(address _fabToken, address _modelRegistry)`
- [ ] Add `_authorizeUpgrade()` function
- [ ] Add `__gap` storage (50 slots)
- [ ] Verify contract compiles

**Implementation:**
```solidity
// src/NodeRegistryWithModelsUpgradeable.sol (NEW FILE)
contract NodeRegistryWithModelsUpgradeable is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Was immutable, now regular storage
    IERC20 public fabToken;
    ModelRegistryUpgradeable public modelRegistry;

    // ... existing storage copied from NodeRegistryWithModels.sol ...
    uint256[48] private __gap; // 48 because fabToken and modelRegistry now use 2 slots

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _fabToken, address _modelRegistry) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        require(_fabToken != address(0), "Invalid FAB token");
        require(_modelRegistry != address(0), "Invalid model registry");
        fabToken = IERC20(_fabToken);
        modelRegistry = ModelRegistryUpgradeable(_modelRegistry);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```

**Files Created:**
- `src/NodeRegistryWithModelsUpgradeable.sol`

**Files Kept (for comparison):**
- `src/NodeRegistryWithModels.sol` (original, unchanged)

---

### Sub-phase 5.2: Write NodeRegistry Upgrade Tests

**Tasks:**
- [ ] Create `test/Upgradeable/NodeRegistry/test_initialization.t.sol`
- [ ] Create `test/Upgradeable/NodeRegistry/test_upgrade.t.sol`
- [ ] Test: Initialize sets fabToken and modelRegistry correctly
- [ ] Test: Initialize can only be called once
- [ ] Test: Node registration works through proxy
- [ ] Test: Upgrade preserves all node data (nodes mapping)
- [ ] Test: Upgrade preserves model-to-nodes mapping
- [ ] Test: Upgrade preserves pricing data
- [ ] Test: Only owner can upgrade

**Files Created:**
- `test/Upgradeable/NodeRegistry/test_initialization.t.sol`
- `test/Upgradeable/NodeRegistry/test_upgrade.t.sol`

---

### Sub-phase 5.3: Verify Tests Pass (RED → GREEN)

**Tasks:**
- [ ] Run tests, verify they FAIL initially (RED)
- [ ] Fix any issues in implementation
- [ ] Run tests, verify they PASS (GREEN)
- [ ] Verify all existing NodeRegistry tests still pass with upgradeable version

---

### Sub-phase 5.4: Create NodeRegistry Deployment Script

**Tasks:**
- [ ] Create `script/DeployNodeRegistryUpgradeable.s.sol`
- [ ] Deploy after ModelRegistry proxy is deployed
- [ ] Pass ModelRegistry proxy address to initialize
- [ ] Verify on local anvil

**Files Created:**
- `script/DeployNodeRegistryUpgradeable.s.sol`

---

## Phase 6: JobMarketplaceWithModels Upgrade

### Sub-phase 6.1: Create JobMarketplaceWithModelsUpgradeable Contract

Create new UUPS version alongside original (kept for comparison). **Most complex contract**.

**Tasks:**
- [ ] Create `src/JobMarketplaceWithModelsUpgradeable.sol` (copy from original)
- [ ] Replace `ReentrancyGuard` with `ReentrancyGuardUpgradeable`
- [ ] Add `Initializable` and `UUPSUpgradeable`
- [ ] Convert `immutable DISPUTE_WINDOW` to regular storage
- [ ] Convert `immutable FEE_BASIS_POINTS` to regular storage
- [ ] Replace `constructor` with `initialize(...)` function
- [ ] Add `_authorizeUpgrade()` function (onlyOwner)
- [ ] Add `__gap` storage (50 slots)
- [ ] Verify contract compiles

**Critical Changes:**
```solidity
// src/JobMarketplaceWithModelsUpgradeable.sol (NEW FILE)

// BEFORE (immutable in original)
uint256 public immutable DISPUTE_WINDOW;
uint256 public immutable FEE_BASIS_POINTS;

// AFTER (storage, set in initialize)
uint256 public DISPUTE_WINDOW;
uint256 public FEE_BASIS_POINTS;

function initialize(
    address _nodeRegistry,
    address _hostEarnings,
    uint256 _disputeWindow,
    uint256 _feeBasisPoints
) public initializer {
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    require(_nodeRegistry != address(0), "Invalid node registry");
    require(_hostEarnings != address(0), "Invalid host earnings");
    require(_feeBasisPoints <= 10000, "Fee too high");

    nodeRegistry = NodeRegistryWithModelsUpgradeable(_nodeRegistry);
    hostEarnings = HostEarningsUpgradeable(_hostEarnings);
    DISPUTE_WINDOW = _disputeWindow;
    FEE_BASIS_POINTS = _feeBasisPoints;
    treasuryAddress = msg.sender; // Deployer becomes treasury initially
}
```

**Files Created:**
- `src/JobMarketplaceWithModelsUpgradeable.sol`

**Files Kept (for comparison):**
- `src/JobMarketplaceWithModels.sol` (original, unchanged)

---

### Sub-phase 6.2: Add Emergency Pause Functionality

Add pause capability for emergencies (optional but recommended).

**Tasks:**
- [ ] Add `PausableUpgradeable` import
- [ ] Add `whenNotPaused` modifier to critical functions
- [ ] Add `pause()` and `unpause()` functions (treasury only)
- [ ] Test: Paused contract blocks session creation
- [ ] Test: Unpaused contract resumes normal operation
- [ ] Test: Only treasury can pause/unpause

**Implementation:**
```solidity
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract JobMarketplaceUpgradeable is
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    function pause() external {
        require(msg.sender == treasuryAddress, "Only treasury");
        _pause();
    }

    function unpause() external {
        require(msg.sender == treasuryAddress, "Only treasury");
        _unpause();
    }

    function createSessionJob(...) external payable nonReentrant whenNotPaused returns (uint256) {
        // ...
    }
}
```

---

### Sub-phase 6.3: Write JobMarketplace Upgrade Tests

**Tasks:**
- [ ] Create `test/Upgradeable/JobMarketplace/test_initialization.t.sol`
- [ ] Create `test/Upgradeable/JobMarketplace/test_upgrade.t.sol`
- [ ] Create `test/Upgradeable/JobMarketplace/test_pause.t.sol`
- [ ] Test: Initialize sets all parameters correctly
- [ ] Test: Initialize can only be called once
- [ ] Test: Session creation works through proxy
- [ ] Test: Proof submission works through proxy
- [ ] Test: **Upgrade preserves all sessionJobs data**
- [ ] Test: **Upgrade preserves user/host sessions arrays**
- [ ] Test: **Upgrade preserves treasury accumulation**
- [ ] Test: Only treasury can upgrade
- [ ] Test: Pause blocks session creation
- [ ] Test: Unpause resumes operations

**Files Created:**
- `test/Upgradeable/JobMarketplace/test_initialization.t.sol`
- `test/Upgradeable/JobMarketplace/test_upgrade.t.sol`
- `test/Upgradeable/JobMarketplace/test_pause.t.sol`

---

### Sub-phase 6.4: Verify Tests Pass (RED → GREEN)

**Tasks:**
- [ ] Run tests, verify they FAIL initially (RED)
- [ ] Fix any issues in implementation
- [ ] Run tests, verify they PASS (GREEN)
- [ ] Verify ALL existing JobMarketplace tests pass with upgradeable version

**Commands:**
```bash
# Run all upgradeable tests
forge test --match-path "test/Upgradeable/**/*.t.sol" -vv

# Run existing tests to verify backward compatibility
forge test -vv
```

---

### Sub-phase 6.5: Create JobMarketplace Deployment Script

**Tasks:**
- [ ] Create `script/DeployJobMarketplaceUpgradeable.s.sol`
- [ ] Deploy after NodeRegistry and HostEarnings proxies
- [ ] Pass proxy addresses to initialize
- [ ] Configure ProofSystem after deployment
- [ ] Authorize in HostEarnings after deployment
- [ ] Verify on local anvil

**Files Created:**
- `script/DeployJobMarketplaceUpgradeable.s.sol`

---

## Phase 7: Integration & Deployment

### Sub-phase 7.1: End-to-End Integration Tests

Test complete flow with all upgradeable contracts.

**Tasks:**
- [ ] Create `test/Upgradeable/Integration/test_full_flow.t.sol`
- [ ] Test: Deploy all proxies in correct order
- [ ] Test: Register host through NodeRegistry proxy
- [ ] Test: Create session through JobMarketplace proxy
- [ ] Test: Submit proof and complete session
- [ ] Test: Withdraw earnings through HostEarnings proxy
- [ ] Test: **Upgrade NodeRegistry, verify sessions still work**
- [ ] Test: **Upgrade JobMarketplace, verify state preserved**

**Files Created:**
- `test/Upgradeable/Integration/test_full_flow.t.sol`
- `test/Upgradeable/Integration/test_upgrade_flow.t.sol`

---

### Sub-phase 7.2: Create Master Deployment Script

Create single script to deploy entire upgradeable system.

**Tasks:**
- [ ] Create `script/DeployAllUpgradeable.s.sol`
- [ ] Deploy in dependency order:
  1. ModelRegistry implementation + proxy
  2. ProofSystem implementation + proxy
  3. HostEarnings implementation + proxy
  4. NodeRegistry implementation + proxy (with ModelRegistry address)
  5. JobMarketplace implementation + proxy (with NodeRegistry, HostEarnings)
- [ ] Configure cross-contract references
- [ ] Output all proxy addresses
- [ ] Test on local anvil

**Files Created:**
- `script/DeployAllUpgradeable.s.sol`

---

### Sub-phase 7.3: Deploy to Base Sepolia

Deploy upgradeable contracts to testnet.

**Tasks:**
- [ ] Deploy all implementation contracts
- [ ] Deploy all proxy contracts
- [ ] Initialize all proxies
- [ ] Configure cross-contract references
- [ ] Verify all contracts on BaseScan
- [ ] Record all addresses (implementation + proxy)
- [ ] Test basic operations through proxies

**Commands:**
```bash
forge script script/DeployAllUpgradeable.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --legacy
```

---

### Sub-phase 7.4: Update Documentation

Update all documentation with new addresses and patterns.

**Tasks:**
- [ ] Update `CONTRACT_ADDRESSES.md` with proxy addresses
- [ ] Update `CLAUDE.md` with upgradeable architecture notes
- [ ] Extract ABIs (same as non-upgradeable, ABIs don't change)
- [ ] Update `client-abis/README.md`
- [ ] Create `docs/UPGRADE_GUIDE.md` for future upgrades
- [ ] Document upgrade procedure for mainnet

**Files Modified:**
- `CONTRACT_ADDRESSES.md`
- `CLAUDE.md`
- `client-abis/README.md`

**Files Created:**
- `docs/UPGRADE_GUIDE.md`

---

## Phase 8: Cleanup for Audit

### Sub-phase 8.1: Verify Behavioral Equivalence

Run comprehensive tests to ensure upgradeable contracts behave identically to originals.

**Tasks:**
- [ ] Run ALL existing tests against upgradeable contracts
- [ ] Compare gas usage between original and upgradeable versions
- [ ] Verify all edge cases behave identically
- [ ] Document any intentional behavioral differences (e.g., pause functionality)

**Commands:**
```bash
# Run existing tests against upgradeable contracts
forge test -vv

# Compare gas snapshots
forge snapshot --diff
```

---

### Sub-phase 8.2: Delete Original Contracts

Remove original non-upgradeable contracts after verification.

**Tasks:**
- [ ] Delete `src/ModelRegistry.sol` (original)
- [ ] Delete `src/ProofSystem.sol` (original)
- [ ] Delete `src/HostEarnings.sol` (original)
- [ ] Delete `src/NodeRegistryWithModels.sol` (original)
- [ ] Delete `src/JobMarketplaceWithModels.sol` (original)
- [ ] Verify build still succeeds
- [ ] Verify all tests still pass

**Commands:**
```bash
rm src/ModelRegistry.sol
rm src/ProofSystem.sol
rm src/HostEarnings.sol
rm src/NodeRegistryWithModels.sol
rm src/JobMarketplaceWithModels.sol

forge build
forge test
```

---

### Sub-phase 8.3: Rename Upgradeable Contracts (Optional)

Optionally rename contracts to remove "Upgradeable" suffix for cleaner codebase.

**Tasks:**
- [ ] Rename `ModelRegistryUpgradeable.sol` → `ModelRegistry.sol`
- [ ] Rename `ProofSystemUpgradeable.sol` → `ProofSystem.sol`
- [ ] Rename `HostEarningsUpgradeable.sol` → `HostEarnings.sol`
- [ ] Rename `NodeRegistryWithModelsUpgradeable.sol` → `NodeRegistryWithModels.sol`
- [ ] Rename `JobMarketplaceWithModelsUpgradeable.sol` → `JobMarketplaceWithModels.sol`
- [ ] Update all import statements across codebase
- [ ] Update contract names inside files (remove "Upgradeable" suffix)
- [ ] Verify build succeeds
- [ ] Verify all tests pass
- [ ] Update deployment scripts with new names

**Note:** This step is optional. Keeping "Upgradeable" suffix clearly indicates the contracts use proxy pattern.

**Files After Cleanup (Option A - Keep suffix):**
```
src/
├── ModelRegistryUpgradeable.sol
├── ProofSystemUpgradeable.sol
├── HostEarningsUpgradeable.sol
├── NodeRegistryWithModelsUpgradeable.sol
└── JobMarketplaceWithModelsUpgradeable.sol
```

**Files After Cleanup (Option B - Remove suffix):**
```
src/
├── ModelRegistry.sol
├── ProofSystem.sol
├── HostEarnings.sol
├── NodeRegistryWithModels.sol
└── JobMarketplaceWithModels.sol
```

---

## Completion Criteria

All sub-phases marked with `[x]` and:
- [ ] All upgradeable contracts compile without warnings
- [ ] All tests passing (existing + new upgrade tests)
- [ ] Contracts deployed to Base Sepolia
- [ ] Contracts verified on BaseScan
- [ ] Integration tests pass on testnet
- [ ] Documentation updated with new addresses
- [ ] Upgrade guide created for future upgrades
- [ ] Original contracts deleted (Phase 8)
- [ ] Codebase clean and ready for audit

---

## Files Summary

### During Development (Phases 1-7)
```
src/
├── ModelRegistry.sol                        ← Original (kept for reference)
├── ModelRegistryUpgradeable.sol             ← NEW: UUPS version
├── ProofSystem.sol                          ← Original (kept for reference)
├── ProofSystemUpgradeable.sol               ← NEW: UUPS version
├── HostEarnings.sol                         ← Original (kept for reference)
├── HostEarningsUpgradeable.sol              ← NEW: UUPS version
├── NodeRegistryWithModels.sol               ← Original (kept for reference)
├── NodeRegistryWithModelsUpgradeable.sol    ← NEW: UUPS version
├── JobMarketplaceWithModels.sol             ← Original (kept for reference)
└── JobMarketplaceWithModelsUpgradeable.sol  ← NEW: UUPS + Pausable
```

### After Cleanup (Phase 8) - Ready for Audit
```
src/
├── ModelRegistryUpgradeable.sol             ← UUPS (originals deleted)
├── ProofSystemUpgradeable.sol               ← UUPS
├── HostEarningsUpgradeable.sol              ← UUPS
├── NodeRegistryWithModelsUpgradeable.sol    ← UUPS
└── JobMarketplaceWithModelsUpgradeable.sol  ← UUPS + Pausable
```

### New Test Files
```
test/Upgradeable/
├── TestSetupUpgradeable.t.sol
├── ModelRegistry/
│   ├── test_initialization.t.sol
│   └── test_upgrade.t.sol
├── ProofSystem/
│   ├── test_initialization.t.sol
│   └── test_upgrade.t.sol
├── HostEarnings/
│   ├── test_initialization.t.sol
│   └── test_upgrade.t.sol
├── NodeRegistry/
│   ├── test_initialization.t.sol
│   └── test_upgrade.t.sol
├── JobMarketplace/
│   ├── test_initialization.t.sol
│   ├── test_upgrade.t.sol
│   └── test_pause.t.sol
└── Integration/
    ├── test_full_flow.t.sol
    └── test_upgrade_flow.t.sol
```

### New Script Files
```
script/
├── DeployUpgradeable.s.sol (base helper)
├── DeployModelRegistryUpgradeable.s.sol
├── DeployProofSystemUpgradeable.s.sol
├── DeployHostEarningsUpgradeable.s.sol
├── DeployNodeRegistryUpgradeable.s.sol
├── DeployJobMarketplaceUpgradeable.s.sol
└── DeployAllUpgradeable.s.sol
```

---

## Notes

### TDD Approach
Each sub-phase follows strict TDD:
1. Write tests FIRST (show them failing)
2. Implement minimal code to pass tests
3. Verify tests pass
4. Mark sub-phase complete

### Storage Layout Critical
- **NEVER** reorder existing storage variables
- **ONLY** add new variables at the end (before __gap)
- **REDUCE** __gap size when adding new variables
- Use `forge inspect` to verify storage layout

### Upgrade Safety
```bash
# Check storage layout before upgrading
forge inspect src/upgradeable/JobMarketplaceUpgradeable.sol:JobMarketplaceUpgradeable storage-layout
```

### Security Considerations
- `_disableInitializers()` in constructor prevents implementation initialization
- `_authorizeUpgrade()` restricts who can upgrade
- Emergency pause allows quick response to issues
- All upgrades require owner/treasury authorization

### Backward Compatibility
- ABIs remain identical (proxy delegates to implementation)
- Existing SDK code works without changes
- Only contract addresses change (proxy addresses)
- All existing functionality preserved

### Gas Considerations
- UUPS is ~20% cheaper to deploy than Transparent Proxy
- Slight gas overhead per call (~200 gas for delegate call)
- Worth the cost for upgrade flexibility
