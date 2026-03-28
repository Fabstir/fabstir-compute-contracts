# Architecture Documentation

**Version:** 3.0
**Last Updated:** March 28, 2026
**Network:** Base Sepolia (Testnet)

---

## 1. Contract Addresses (UUPS Proxies)

| Contract | Proxy Address | Implementation |
|----------|---------------|----------------|
| JobMarketplace | `0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4` | `0xCCd2426A644Ef5Ef69B128b31a0A42Ecb3855c86` |
| NodeRegistry | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | `0xAd2D3F0E5364fD122acea081d91130FB3C0AA3e0` |
| ModelRegistry | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | `0xF12a0A07d4230E0b045dB22057433a9826d21652` |
| ProofSystem | `0xE8DCa89e1588bbbdc4F7D5F78263632B35401B31` | `0xC46C84a612Cbf4C2eAaf5A9D1411aDA6309EC963` |
| HostEarnings | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | (unchanged from initial deployment) |

**Tokens:**
- FAB Token: `0xC78949004B4EB6dEf2D66e49Cd81231472612D62`
- USDC: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

---

## 2. Contract Dependency Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FABSTIR COMPUTE ARCHITECTURE                         │
└─────────────────────────────────────────────────────────────────────────────┘

                          ┌───────────────────────┐
                          │    ModelRegistry      │
                          │  ─────────────────    │
                          │  • Model whitelist    │
                          │  • Community voting   │
                          │  • Trusted models     │
                          └───────────┬───────────┘
                                      │ validates models
                                      ▼
                          ┌───────────────────────┐
                          │    NodeRegistry       │
                          │  ─────────────────    │
                          │  • Host registration  │
                          │  • FAB staking        │
                          │  • Per-model pricing  │
                          │  • Model support      │
                          │  • Stake slashing     │
                          └───────────┬───────────┘
                                      │ validates hosts
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        JobMarketplaceWithModels                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│  • Session management          • Deposit handling                           │
│  • Proof submission            • Payment settlement                         │
│  • Timeout enforcement         • Treasury collection                        │
│  • Delegate session support                                                 │
└────────────────┬────────────────────────────────────┬───────────────────────┘
                 │                                    │
                 │ marks proofs used                  │ credits earnings
                 ▼                                    ▼
    ┌───────────────────────┐            ┌───────────────────────┐
    │     ProofSystem       │            │    HostEarnings       │
    │  ─────────────────    │            │  ─────────────────    │
    │  • Replay prevention  │            │  • Earnings ledger    │
    │  • Proof recording    │            │  • Batch withdrawals  │
    │  • Authorized callers │            │  • Multi-token        │
    └───────────────────────┘            └───────────────────────┘
```

### Dependency Matrix

| Contract | Depends On | Depended By |
|----------|------------|-------------|
| ModelRegistry | OpenZeppelin | NodeRegistry |
| NodeRegistry | ModelRegistry, FAB Token | JobMarketplace |
| JobMarketplace | NodeRegistry, ProofSystem, HostEarnings | - |
| ProofSystem | OpenZeppelin | JobMarketplace |
| HostEarnings | OpenZeppelin | JobMarketplace |

---

## 3. Session Lifecycle State Machine

```
                              ┌─────────────────────────────────────┐
                              │         SESSION LIFECYCLE           │
                              └─────────────────────────────────────┘

    ┌──────────────────┐
    │  (Not Exists)    │
    └────────┬─────────┘
             │
             │ createSessionJobForModel()
             │ createSessionJobForModelWithToken()
             │ createSessionFromDepositForModel()
             │ createSessionForModelAsDelegate()
             │
             ▼
    ┌──────────────────┐
    │                  │◄──────────────────────────────────────────┐
    │     ACTIVE       │                                           │
    │                  │──── submitProofOfWork() ───────────────────┘
    │  status = 0      │     (updates tokensUsed, stores deltaCID)
    │                  │
    └────────┬─────────┘
             │
             ├─────────────────────────┬────────────────────────────┐
             │                         │                            │
             │ completeSessionJob()    │ triggerSessionTimeout()    │
             │ (host or depositor)     │ (anyone, after timeout)    │
             │ + conversationCID       │                            │
             ▼                         ▼                            │
    ┌──────────────────┐    ┌──────────────────┐                   │
    │    COMPLETED     │    │    TIMED_OUT     │                   │
    │                  │    │                  │                   │
    │  status = 1      │    │  status = 2      │                   │
    │                  │    │                  │                   │
    │  Payment:        │    │  Payment:        │                   │
    │  • Host: 90%     │    │  • Host: 90%     │                   │
    │  • Treasury: 10% │    │    (of proven)   │                   │
    │  • Refund: rest  │    │  • Treasury: 10% │                   │
    └──────────────────┘    │  • Refund: rest  │                   │
                            └──────────────────┘                   │
                                                                   │
    ┌─────────────────────────────────────────────────────────────┐│
    │                    STATE TRANSITIONS                         ││
    ├─────────────────────────────────────────────────────────────┤│
    │  ACTIVE → ACTIVE      : submitProofOfWork() [tokensUsed++]  ││
    │  ACTIVE → COMPLETED   : completeSessionJob(conversationCID)  │
    │  ACTIVE → TIMED_OUT   : triggerSessionTimeout() [timeout]   ││
    │                                                              ││
    │  COMPLETED → *        : BLOCKED (immutable)                 ││
    │  TIMED_OUT → *        : BLOCKED (immutable)                 ││
    └─────────────────────────────────────────────────────────────┘│
```

---

## 4. Data Flow Diagrams

### 4.1 Session Creation Flow

```
┌─────────┐                  ┌─────────────────┐                  ┌──────────────┐
│Depositor│                  │  JobMarketplace │                  │ NodeRegistry │
└────┬────┘                  └────────┬────────┘                  └──────┬───────┘
     │                                │                                  │
     │  1. getModelPricing(host,      │                                  │
     │     modelId, token)            │                                  │
     │ ──────────────────────────────────────────────────────────────────>
     │                                │                                  │
     │  2. (modelTokenPrice)          │                                  │
     │ <──────────────────────────────────────────────────────────────────
     │                                │                                  │
     │  3. createSessionJobForModel() │                                  │
     │    + ETH deposit               │                                  │
     │ ──────────────────────────────>│                                  │
     │                                │                                  │
     │                                │  4. isActiveNode(host)?          │
     │                                │ ────────────────────────────────>│
     │                                │                                  │
     │                                │  5. true                         │
     │                                │ <────────────────────────────────│
     │                                │                                  │
     │                                │  6. nodeSupportsModel()?         │
     │                                │ ────────────────────────────────>│
     │                                │                                  │
     │                                │  7. true                         │
     │                                │ <────────────────────────────────│
     │                                │                                  │
     │  8. SessionJobCreated event    │                                  │
     │ <──────────────────────────────│                                  │
     │                                │                                  │
```

### 4.2 Proof Submission Flow

```
┌──────┐                  ┌─────────────────┐                  ┌─────────────┐
│ Host │                  │  JobMarketplace │                  │ ProofSystem │
└──┬───┘                  └────────┬────────┘                  └──────┬──────┘
   │                               │                                  │
   │  1. Generate inference        │                                  │
   │     (off-chain)               │                                  │
   │                               │                                  │
   │  2. Upload proof to S5        │                                  │
   │     → get proofCID, deltaCID  │                                  │
   │                               │                                  │
   │  3. submitProofOfWork(        │                                  │
   │       jobId, tokensClaimed,   │                                  │
   │       proofHash,              │                                  │
   │       proofCID, deltaCID)     │                                  │
   │ ─────────────────────────────>│                                  │
   │                               │                                  │
   │                               │  4. markProofUsed()              │
   │                               │     (replay prevention)          │
   │                               │ ────────────────────────────────>│
   │                               │                                  │
   │                               │  5. true (not replayed)          │
   │                               │ <────────────────────────────────│
   │                               │                                  │
   │                               │  6. Update tokensUsed            │
   │                               │     Store proofHash, deltaCID    │
   │                               │                                  │
   │  7. ProofSubmitted event      │                                  │
   │     (includes deltaCID)       │                                  │
   │ <─────────────────────────────│                                  │
   │                               │                                  │
```

### 4.3 Payment Settlement Flow

```
┌────────────┐        ┌─────────────────┐        ┌──────────────┐        ┌──────────┐
│Host/Depos. │        │  JobMarketplace │        │ HostEarnings │        │ Treasury │
└─────┬──────┘        └────────┬────────┘        └──────┬───────┘        └────┬─────┘
      │                        │                        │                     │
      │ 1. completeSessionJob()│                        │                     │
      │ ──────────────────────>│                        │                     │
      │                        │                        │                     │
      │                        │ 2. Calculate:          │                     │
      │                        │    hostPayment = 90%   │                     │
      │                        │    treasuryFee = 10%   │                     │
      │                        │    refund = remainder  │                     │
      │                        │                        │                     │
      │                        │ 3. creditEarnings()    │                     │
      │                        │ ──────────────────────>│                     │
      │                        │                        │                     │
      │                        │ 4. Accumulate fee      │                     │
      │                        │    (accumulatedTreasury│                     │
      │                        │     Native/Tokens)     │                     │
      │                        │                        │                     │
      │                        │ 5. Refund to depositor │                     │
      │ <──────────────────────│    (or credit deposit) │                     │
      │                        │                        │                     │
      │ 6. SessionCompleted    │                        │                     │
      │ <──────────────────────│                        │                     │
      │                        │                        │                     │

      [Later: Treasury withdraws accumulated fees]

┌──────────┐        ┌─────────────────┐
│ Treasury │        │  JobMarketplace │
└────┬─────┘        └────────┬────────┘
     │                       │
     │ withdrawTreasury*()   │
     │ ─────────────────────>│
     │                       │
     │ ETH/USDC transfer     │
     │ <─────────────────────│
     │                       │

      [Later: Host withdraws from HostEarnings]

┌──────┐        ┌──────────────┐
│ Host │        │ HostEarnings │
└──┬───┘        └──────┬───────┘
   │                   │
   │ withdraw()        │
   │ ─────────────────>│
   │                   │
   │ ETH/USDC transfer │
   │ <─────────────────│
   │                   │
```

### 4.4 Model Governance Flow

```
┌──────────┐        ┌───────────────┐        ┌───────────┐
│ Proposer │        │ ModelRegistry │        │  Voters   │
└────┬─────┘        └───────┬───────┘        └─────┬─────┘
     │                      │                      │
     │ 1. proposeModel()    │                      │
     │    + 100 FAB fee     │                      │
     │ ────────────────────>│                      │
     │                      │                      │
     │ 2. ModelProposed     │                      │
     │ <────────────────────│                      │
     │                      │                      │
     │                      │ 3. voteOnProposal()  │
     │                      │    + FAB tokens      │
     │                      │ <────────────────────│
     │                      │                      │
     │                      │  [3 days pass...]    │
     │                      │                      │
     │                      │ 4. executeProposal() │
     │                      │ <────────────────────│
     │                      │                      │
     │                      │ 5. If approved:      │
     │                      │    - Add model       │
     │                      │    - Refund fee      │
     │                      │                      │
     │                      │ 6. withdrawVotes()   │
     │                      │ <────────────────────│
     │                      │                      │
```

---

## 5. Storage Layout Documentation

### 5.1 JobMarketplaceWithModelsUpgradeable

```solidity
// OZ v5 uses ERC-7201 namespaced storage for inherited contracts.
// Contract-specific storage starts at slot 0.

uint256 public disputeWindow;                              // Slot 0
uint256 public feeBasisPoints;                             // Slot 1

mapping(uint256 => SessionJob) public sessionJobs;         // Slot 2
mapping(address => uint256[]) public userSessions;         // Slot 3
mapping(address => uint256[]) public hostSessions;         // Slot 4
mapping(uint256 => bytes32) public sessionModel;           // Slot 5

uint256 public nextJobId;                                  // Slot 6
address public treasuryAddress;                            // Slot 7
address public usdcAddress;                                // Slot 8

NodeRegistryWithModelsUpgradeable public nodeRegistry;     // Slot 9
IProofSystemUpgradeable public proofSystem;                // Slot 10
HostEarningsUpgradeable public hostEarnings;               // Slot 11

mapping(address => bool) public acceptedTokens;            // Slot 12
mapping(address => uint256) public tokenMinDeposits;       // Slot 13
mapping(address => uint256) public tokenMaxDeposits;       // Slot 14

uint256 public accumulatedTreasuryNative;                  // Slot 15
mapping(address => uint256) public accumulatedTreasuryTokens; // Slot 16

mapping(address => uint256) public userDepositsNative;     // Slot 17
mapping(address => mapping(address => uint256)) public userDepositsToken; // Slot 18

ChainConfig public chainConfig;                            // Slots 19-22 (128 bytes)
uint256 public minTokensFee;                               // Slot 23

mapping(address => mapping(address => bool)) public _isAuthorizedDelegate; // Slot 24 (deprecated)
mapping(address => mapping(address => DelegateConfig)) public delegateConfigs; // Slot 25

uint256[32] private __gap;                                 // Slots 26-57
```

### 5.2 SessionJob Struct Layout

```solidity
struct SessionJob {
    uint256 id;                    // Session identifier
    address depositor;             // Tracks who deposited and who receives refunds
    address host;                  // Host serving inference
    address paymentToken;          // address(0) for ETH, otherwise ERC20
    uint256 deposit;               // Total deposit amount
    uint256 pricePerToken;         // Price per token with PRICE_PRECISION
    uint256 tokensUsed;            // Cumulative tokens proven
    uint256 maxDuration;           // Maximum session duration (seconds)
    uint256 startTime;             // Session creation timestamp
    uint256 lastProofTime;         // Last proof submission timestamp
    uint256 proofInterval;         // Minimum tokens between proofs
    uint256 proofTimeoutWindow;    // Time in seconds before timeout
    SessionStatus status;          // enum: Active=0, Completed=1, TimedOut=2
    ProofSubmission[] proofs;      // Array of proof submissions
    uint256 withdrawnByHost;       // Track settled host payment
    uint256 refundedToUser;        // Track settled user refund
    string conversationCID;        // S5 CID set on completion
    bytes32 lastProofHash;         // Hash of most recent proof
    string lastProofCID;           // S5 CID of most recent proof
}
```

### 5.3 NodeRegistryWithModelsUpgradeable

```solidity
// OZ v5 uses ERC-7201 namespaced storage for inherited contracts.
// Contract-specific storage starts at slot 0.

IERC20 public fabToken;                            // Slot 0
ModelRegistryUpgradeable public modelRegistry;     // Slot 1

mapping(address => Node) public nodes;             // Slot 2
mapping(address => uint256) public activeNodesIndex; // Slot 3
mapping(bytes32 => address[]) public modelToNodes;   // Slot 4
mapping(bytes32 => mapping(address => uint256)) private modelNodeIndex; // Slot 5

mapping(address => mapping(bytes32 => uint256)) public modelPricingNative;  // Slot 6 (deprecated)
mapping(address => mapping(bytes32 => uint256)) public modelPricingStable;  // Slot 7 (deprecated)
mapping(address => mapping(address => uint256)) public customTokenPricing;  // Slot 8 (deprecated)

address[] public activeNodesList;                  // Slot 9

address public slashingAuthority;                  // Slot 10
address public treasury;                           // Slot 11
mapping(address => uint256) public lastSlashTime;  // Slot 12

mapping(address => mapping(bytes32 => mapping(address => uint256))) public modelTokenPricing; // Slot 13

uint256[35] private __gap;                         // Slots 14-48
```

### 5.4 Storage Gap Strategy

All upgradeable contracts reserve storage gaps for future additions:

| Contract | Gap Size | Slots |
|----------|----------|-------|
| JobMarketplaceWithModelsUpgradeable | 32 | 26-57 |
| NodeRegistryWithModelsUpgradeable | 35 | 14-48 |
| ModelRegistryUpgradeable | 45 | 11-55 |
| ProofSystemUpgradeable | 46 | 4-49 |
| HostEarningsUpgradeable | 46 | 4-49 |

---

## 6. External Dependencies

### 6.1 OpenZeppelin Contracts (v5.x)

| Contract | Usage | Import Path |
|----------|-------|-------------|
| OwnableUpgradeable | Access control | `@openzeppelin/contracts-upgradeable/access/` |
| PausableUpgradeable | Emergency stop | `@openzeppelin/contracts-upgradeable/utils/` |
| Initializable | Proxy initialization | `@openzeppelin/contracts-upgradeable/proxy/utils/` |
| UUPSUpgradeable | Upgrade pattern | `@openzeppelin/contracts-upgradeable/proxy/utils/` |
| SafeERC20 | Safe token transfers | `@openzeppelin/contracts/token/ERC20/utils/` |
| Address | Safe ETH transfers | `@openzeppelin/contracts/utils/` |
| ReentrancyGuardTransient | EIP-1153 reentrancy guard | `@openzeppelin/contracts/utils/` |

### 6.2 Token Interfaces

| Interface | Standard | Usage |
|-----------|----------|-------|
| IERC20 | ERC-20 | USDC, FAB token interactions |

### 6.3 Upgrade Pattern: UUPS

```
┌─────────────────────────────────────────────────────────────┐
│                    UUPS Proxy Pattern                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐         ┌─────────────────────┐          │
│   │   Proxy     │────────>│   Implementation    │          │
│   │  (Storage)  │         │   (Logic Only)      │          │
│   │             │         │                     │          │
│   │ • State     │         │ • Functions         │          │
│   │ • Balance   │         │ • _authorizeUpgrade │          │
│   └─────────────┘         └─────────────────────┘          │
│         │                           │                       │
│         │ delegatecall              │                       │
│         └───────────────────────────┘                       │
│                                                             │
│   Upgrade: owner calls proxy.upgradeToAndCall(newImpl)     │
│   Authorization: _authorizeUpgrade() checks onlyOwner      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Security Architecture

### 7.1 Reentrancy Protection

```solidity
// OpenZeppelin ReentrancyGuardTransient (EIP-1153 transient storage)
// Gas-efficient: ~4,900 gas savings per nonReentrant call
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract JobMarketplaceUpgradeable is ReentrancyGuardTransient {
    // Uses transient storage (TSTORE/TLOAD) instead of contract storage
    // Status is automatically cleared at end of transaction
    // No storage slot consumed - works seamlessly with UUPS proxies
}
```

**Benefits of EIP-1153 Transient Storage:**
- ~4,900 gas savings per `nonReentrant` call
- No storage slot collision concerns with proxies
- Automatic cleanup at transaction end

**Protected Functions:**
- `registerNode()`, `unregisterNode()`, `stake()`, `slashStake()` (NodeRegistry)
- `withdraw()`, `withdrawAll()`, `withdrawMultiple()`, `creditEarnings()` (HostEarnings)
- Session creation, completion, and timeout functions (JobMarketplace)
- `withdrawTreasuryNative()`, `withdrawTreasuryTokens()`, `withdrawAllTreasuryFees()` (JobMarketplace)
- `createSessionForModelAsDelegate()` (JobMarketplace)

### 7.2 Safe Transfer Patterns

```solidity
// ERC20: SafeERC20 library
token.safeTransfer(recipient, amount);
token.safeTransferFrom(sender, recipient, amount);

// ETH: Address library
Address.sendValue(payable(recipient), amount);
```

### 7.3 Access Control Hierarchy

```
┌─────────────────────────────────────────────┐
│              Access Control                  │
├─────────────────────────────────────────────┤
│                                             │
│  OWNER (Highest)                            │
│  └── upgradeToAndCall()                     │
│  └── pause(), unpause()                     │
│  └── setTreasury(), setMinTokensFee()       │
│  └── addTrustedModel()                      │
│  └── setAuthorizedCaller()                  │
│  └── setSlashingAuthority()                 │
│  └── initializeSlashing()                   │
│                                             │
│  TREASURY (High)                            │
│  └── withdrawTreasuryNative()               │
│  └── withdrawTreasuryTokens()               │
│  └── withdrawAllTreasuryFees()              │
│  └── pause(), unpause() [shared w/ OWNER]   │
│                                             │
│  SLASHING_AUTHORITY (Medium-High)           │
│  └── slashStake() [any active host]         │
│                                             │
│  AUTHORIZED_CALLER (Medium)                 │
│  └── creditEarnings()                       │
│  └── markProofUsed()                        │
│                                             │
│  HOST (Medium - Economically Bonded)        │
│  └── submitProofOfWork() [own sessions]     │
│  └── completeSessionJob() [own sessions]    │
│  └── update*() [own node]                   │
│                                             │
│  DELEGATE (Medium-Low)                      │
│  └── createSessionForModelAsDelegate()      │
│      [depositor's funds, within config]     │
│                                             │
│  DEPOSITOR (Low)                            │
│  └── completeSessionJob() [own sessions]    │
│  └── session creation                       │
│  └── authorizeDelegate()                    │
│  └── configureDelegate()                    │
│                                             │
│  ANYONE (Lowest)                            │
│  └── triggerSessionTimeout()                │
│  └── View functions                         │
│  └── proposeModel(), voteOnProposal()       │
│                                             │
└─────────────────────────────────────────────┘
```

---

## 8. Gas Optimization Patterns

### 8.1 O(1) Array Removal

```solidity
// Swap-and-pop pattern for efficient removal
function _removeNodeFromModel(bytes32 modelId, address node) private {
    uint256 index = modelNodeIndex[modelId][node];
    uint256 lastIndex = modelToNodes[modelId].length - 1;

    if (index != lastIndex) {
        address lastNode = modelToNodes[modelId][lastIndex];
        modelToNodes[modelId][index] = lastNode;
        modelNodeIndex[modelId][lastNode] = index;
    }

    modelToNodes[modelId].pop();
    delete modelNodeIndex[modelId][node];
}
```

### 8.2 Batch Operations

- `batchAddTrustedModels()` - Add multiple models in one transaction
- HostEarnings accumulation - Batch withdrawals vs per-session payments

### 8.3 Storage Efficiency

- Struct packing for session data
- Enum for status (1 byte vs 32 bytes)
- Mapping-based lookups vs array iterations

---

## 9. Event Architecture

### 9.1 Key Events for Indexing

| Contract | Event | Purpose |
|----------|-------|---------|
| JobMarketplace | `SessionJobCreated` | Track session starts |
| JobMarketplace | `SessionJobCreatedForModel` | Track model-specific session starts |
| JobMarketplace | `SessionCreatedByDepositor` | Track deposit-funded sessions |
| JobMarketplace | `SessionCompleted` | Track completions, payments |
| JobMarketplace | `SessionCompletedBy` | Track who completed a session |
| JobMarketplace | `SessionTimedOut` | Track forced timeouts |
| JobMarketplace | `ProofSubmitted` | Track proof history (includes deltaCID) |
| JobMarketplace | `DelegateAuthorized` | Track delegate authorization changes |
| JobMarketplace | `DelegateConfigured` | Track delegate config with spending limits |
| JobMarketplace | `SessionCreatedByDelegate` | Track delegate-created sessions |
| JobMarketplace | `MinTokensFeeUpdated` | Track early-cancel fee changes |
| JobMarketplace | `RefundCreditedToDeposit` | Track pull-pattern refund fallbacks |
| JobMarketplace | `DepositReceived` | Track pre-deposits |
| JobMarketplace | `WithdrawalProcessed` | Track withdrawals |
| JobMarketplace | `TreasuryWithdrawal` | Track treasury fee withdrawals |
| JobMarketplace | `ContractPaused` / `ContractUnpaused` | Track pause state |
| JobMarketplace | `TokenAccepted` | Track new accepted tokens |
| JobMarketplace | `PaymentSent` | Track ETH payments |
| NodeRegistry | `NodeRegistered` | Track host onboarding |
| NodeRegistry | `ModelTokenPricingUpdated` | Track per-model per-token price changes |
| NodeRegistry | `SlashExecuted` | Track stake slashing |
| NodeRegistry | `HostAutoUnregistered` | Track auto-deregistration on slash |
| ModelRegistry | `ModelProposed` | Track governance |
| ModelRegistry | `ModelRateLimitUpdated` | Track rate limit changes |
| HostEarnings | `EarningsCredited` | Track host income |
| HostEarnings | `EarningsWithdrawn` | Track host withdrawals |
| ProofSystem | `ProofVerified` | Track proof usage (replay prevention) |

### 9.2 Event Indexing Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                  Off-Chain Indexing                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Events ────────> TheGraph/Custom Indexer ────────> API     │
│                                                             │
│  Indexed Fields:                                            │
│  • jobId (SessionJobCreated, ProofSubmitted)               │
│  • host (NodeRegistered, EarningsCredited)                 │
│  • depositor (SessionJobCreated)                           │
│  • modelId (ModelProposed, SessionJobCreated)              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```
