# IMPLEMENTATION-MULTI.md - Multi-Chain/Multi-Wallet JobMarketplace Update

## Overview
Update JobMarketplaceWithModels contract to be completely wallet-agnostic and multi-chain compatible, treating all addresses equally whether they are EOAs, Smart Accounts, or future wallet types.

## Repository
fabstir-compute-contracts

## Goals
- Make contract wallet-agnostic (EOA, Smart Account, future wallets)
- Support multiple chains (Base Sepolia, opBNB Testnet)
- Maintain 100% backward compatibility
- Enable gasless session ending via anyone-can-complete pattern
- Add deposit/withdrawal pattern for better UX
- Support native tokens per chain (ETH on Base, BNB on opBNB)

## Critical Design Decisions
- **Treasury Fee**: 10% (NOT 2.5%) - FEE_BASIS_POINTS = 1000
- **Host Earnings**: 90% of payment
- **Anyone Can Complete**: Enable gasless ending for users
- **Chain Agnostic**: Same code on all chains

---

## Phase 0: Environment Variable Configuration ⬜

Make contract parameters configurable from environment variables at deployment time.

### Sub-phase 0.1: Configurable Treasury Fee ⬜
Make FEE_BASIS_POINTS configurable from TREASURY_FEE_PERCENTAGE environment variable.

**Tasks:**
- [ ] Change FEE_BASIS_POINTS from constant to immutable in JobMarketplaceWithModels
- [ ] Update constructor to accept _feeBasisPoints parameter
- [ ] Add validation: require(_feeBasisPoints <= 10000, "Fee cannot exceed 100%")
- [ ] Create deployment script that reads TREASURY_FEE_PERCENTAGE from .env
- [ ] Convert percentage to basis points (multiply by 100)
- [ ] Update deployment documentation

**Implementation:**
```solidity
// Change from:
uint256 public constant FEE_BASIS_POINTS = 1000;

// To:
uint256 public immutable FEE_BASIS_POINTS;

constructor(address _nodeRegistry, address payable _hostEarnings, uint256 _feeBasisPoints) {
    require(_feeBasisPoints <= 10000, "Fee cannot exceed 100%");
    FEE_BASIS_POINTS = _feeBasisPoints;
    nodeRegistry = NodeRegistryWithModels(_nodeRegistry);
    hostEarnings = HostEarnings(_hostEarnings);
    // ... rest of constructor
}
```

**Deployment Script:**
```javascript
// scripts/deploy-with-env-config.js
require('dotenv').config();

const treasuryFeePercentage = process.env.TREASURY_FEE_PERCENTAGE || 10;
const feeBasisPoints = treasuryFeePercentage * 100;

const marketplace = await deploy("JobMarketplaceWithModels", [
    nodeRegistryAddress,
    hostEarningsAddress,
    feeBasisPoints
]);

console.log(`Deployed with ${treasuryFeePercentage}% treasury fee (${feeBasisPoints} basis points)`);
```

**Tests:**
- [ ] `test/JobMarketplace/Config/test_fee_configuration.t.sol`
- [ ] Test deployment with various fee percentages
- [ ] Test fee calculation with configured values
- [ ] Test validation (reject > 100% fees)

---

## Phase 1: Wallet-Agnostic Deposit System

### Sub-phase 1.1: Core Deposit Tracking ⬜
Add wallet-agnostic deposit tracking mappings alongside existing structures.

**Tasks:**
- [ ] Add `userDepositsNative` mapping for native token (ETH/BNB)
- [ ] Add `userDepositsToken` nested mapping for ERC20 tokens
- [ ] Add deposit events for tracking
- [ ] Keep existing job/session mappings for compatibility
- [ ] Test with multiple addresses

**Updates to `src/JobMarketplaceWithModels.sol`**:
```solidity
// New deposit tracking (line ~115, after existing mappings)
mapping(address => uint256) public userDepositsNative;
mapping(address => mapping(address => uint256)) public userDepositsToken;

// Events
event DepositReceived(address indexed depositor, uint256 amount, address token);
event WithdrawalProcessed(address indexed depositor, uint256 amount, address token);
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_deposit_mappings.t.sol`
- `test/JobMarketplace/MultiChain/test_deposit_events.t.sol`
- `test/JobMarketplace/MultiChain/test_wallet_agnostic.t.sol`

---

### Sub-phase 1.2: Deposit Functions Implementation ⬜
Implement deposit and withdrawal functions for native and ERC20 tokens.

**Tasks:**
- [ ] Implement `depositNative()` for ETH/BNB deposits
- [ ] Implement `depositToken()` for ERC20 deposits
- [ ] Add balance validation checks
- [ ] Emit proper events
- [ ] Test with zero amounts (should revert)

**New Functions**:
```solidity
function depositNative() external payable {
    require(msg.value > 0, "Zero deposit");
    userDepositsNative[msg.sender] += msg.value;
    emit DepositReceived(msg.sender, msg.value, address(0));
}

function depositToken(address token, uint256 amount) external {
    require(amount > 0, "Zero deposit");
    require(token != address(0), "Invalid token");

    IERC20(token).transferFrom(msg.sender, address(this), amount);
    userDepositsToken[msg.sender][token] += amount;
    emit DepositReceived(msg.sender, amount, token);
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_deposit_native.t.sol`
- `test/JobMarketplace/MultiChain/test_deposit_token.t.sol`
- `test/JobMarketplace/MultiChain/test_deposit_validation.t.sol`

---

### Sub-phase 1.3: Withdrawal Functions ⬜
Implement withdrawal functions with reentrancy protection.

**Tasks:**
- [ ] Implement `withdrawNative()` for ETH/BNB withdrawals
- [ ] Implement `withdrawToken()` for ERC20 withdrawals
- [ ] Add reentrancy guards
- [ ] Validate sufficient balance
- [ ] Test withdrawal limits

**New Functions**:
```solidity
function withdrawNative(uint256 amount) external nonReentrant {
    require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");

    userDepositsNative[msg.sender] -= amount;
    payable(msg.sender).transfer(amount);

    emit WithdrawalProcessed(msg.sender, amount, address(0));
}

function withdrawToken(address token, uint256 amount) external nonReentrant {
    require(userDepositsToken[msg.sender][token] >= amount, "Insufficient balance");

    userDepositsToken[msg.sender][token] -= amount;
    IERC20(token).transfer(msg.sender, amount);

    emit WithdrawalProcessed(msg.sender, amount, token);
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_withdraw_native.t.sol`
- `test/JobMarketplace/MultiChain/test_withdraw_token.t.sol`
- `test/JobMarketplace/MultiChain/test_reentrancy_protection.t.sol`

---

### Sub-phase 1.4: Balance Query Functions ⬜
Add view functions for checking deposit balances.

**Tasks:**
- [ ] Implement `getDepositBalance()` for unified balance queries
- [ ] Add batch balance query function
- [ ] Test with various token addresses
- [ ] Test with zero balances

**New Functions**:
```solidity
function getDepositBalance(address account, address token) external view returns (uint256) {
    if (token == address(0)) {
        return userDepositsNative[account];
    }
    return userDepositsToken[account][token];
}

function getDepositBalances(address account, address[] calldata tokens)
    external view returns (uint256[] memory) {
    uint256[] memory balances = new uint256[](tokens.length);
    for (uint256 i = 0; i < tokens.length; i++) {
        balances[i] = token == address(0)
            ? userDepositsNative[account]
            : userDepositsToken[account][tokens[i]];
    }
    return balances;
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_balance_queries.t.sol`
- `test/JobMarketplace/MultiChain/test_batch_queries.t.sol`

---

## Phase 2: Session Management Updates

### Sub-phase 2.1: Update SessionJob Structure ⬜
Add depositor field to track session owner regardless of wallet type.

**Tasks:**
- [ ] Add `depositor` field to SessionJob struct
- [ ] Update struct initialization
- [ ] Maintain backward compatibility
- [ ] Test struct updates

**Updates to SessionJob struct**:
```solidity
struct SessionJob {
    uint256 jobId;
    address depositor;      // NEW: tracks who deposited (EOA or Smart Account)
    address requester;      // DEPRECATED but kept for compatibility
    address host;
    address paymentToken;
    uint256 deposit;
    // ... rest of fields remain unchanged
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_session_struct_update.t.sol`
- `test/JobMarketplace/MultiChain/test_depositor_field.t.sol`

---

### Sub-phase 2.2: createSessionFromDeposit Function ⬜
Implement session creation using pre-deposited funds.

**Tasks:**
- [ ] Implement `createSessionFromDeposit()` function
- [ ] Deduct from deposit balance
- [ ] Set depositor field correctly
- [ ] Validate sufficient deposit
- [ ] Support both native and token payments

**New Function**:
```solidity
function createSessionFromDeposit(
    address host,
    address paymentToken,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external returns (uint256 sessionId) {
    // Check and deduct deposit
    if (paymentToken == address(0)) {
        require(userDepositsNative[msg.sender] >= deposit, "Insufficient native deposit");
        userDepositsNative[msg.sender] -= deposit;
    } else {
        require(userDepositsToken[msg.sender][paymentToken] >= deposit, "Insufficient token deposit");
        userDepositsToken[msg.sender][paymentToken] -= deposit;
    }

    // Create session with msg.sender as depositor
    sessionId = nextJobId++;
    SessionJob storage session = sessionJobs[sessionId];
    session.jobId = sessionId;
    session.depositor = msg.sender;  // Wallet-agnostic
    session.requester = msg.sender;  // Keep for compatibility
    session.host = host;
    session.paymentToken = paymentToken;
    session.deposit = deposit;
    session.pricePerToken = pricePerToken;
    session.maxDuration = maxDuration;
    session.startTime = block.timestamp;
    session.status = SessionStatus.Active;

    emit SessionCreatedByDepositor(sessionId, msg.sender, host, deposit);
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_create_from_deposit.t.sol`
- `test/JobMarketplace/MultiChain/test_deposit_deduction.t.sol`
- `test/JobMarketplace/MultiChain/test_session_creation_events.t.sol`

---

### Sub-phase 2.3: Update Existing Session Creation ⬜
Update existing `postJobWithToken` to track depositor.

**Tasks:**
- [ ] Update `postJobWithToken` to set depositor field
- [ ] Track inline deposits in userDepositsToken
- [ ] Maintain backward compatibility
- [ ] Test with existing integrations

**Update existing function**:
```solidity
function postJobWithToken(
    JobDetails memory details,
    JobRequirements memory requirements,
    address paymentToken,
    uint256 paymentAmount
) external returns (bytes32) {
    // ... existing validation ...

    // Track deposit for msg.sender
    if (paymentToken == address(0)) {
        userDepositsNative[msg.sender] += paymentAmount;
    } else {
        userDepositsToken[msg.sender][paymentToken] += paymentAmount;
    }

    // ... rest of existing logic ...

    // Set depositor when creating session
    session.depositor = msg.sender;  // NEW
    session.requester = msg.sender;  // Keep for compatibility
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_backward_compatibility.t.sol`
- `test/JobMarketplace/MultiChain/test_inline_deposit_tracking.t.sol`

---

## Phase 3: Payment Processing Updates

### Sub-phase 3.1: Anyone-Can-Complete Pattern ⬜
Update `completeSessionJob` to allow anyone to call it.

**Tasks:**
- [ ] Remove caller restrictions from completeSessionJob
- [ ] Add completedBy tracking in event
- [ ] Ensure refunds go to depositor
- [ ] Test with various callers

**Update completeSessionJob**:
```solidity
function completeSessionJob(uint256 jobId) external nonReentrant {
    SessionJob storage session = sessionJobs[jobId];
    require(session.status == SessionStatus.Active, "Session not active");

    // NO RESTRICTION on msg.sender - anyone can complete

    address depositor = session.depositor != address(0)
        ? session.depositor
        : session.requester; // Fallback for old sessions

    // Calculate payments
    uint256 tokensUsed = session.tokensUsed;
    uint256 paymentDue = (tokensUsed * session.pricePerToken);
    uint256 refund = session.deposit > paymentDue ? session.deposit - paymentDue : 0;

    // Distribute with 10% treasury fee (NOT 2.5%)
    uint256 treasuryFee = (paymentDue * FEE_BASIS_POINTS) / 10000; // FEE_BASIS_POINTS = 1000
    uint256 hostPayment = paymentDue - treasuryFee;

    // Credit host earnings
    if (session.paymentToken == address(0)) {
        // ... existing ETH logic ...
    } else {
        // ... existing token logic ...
    }

    // Refund to depositor (wallet-agnostic)
    if (refund > 0) {
        if (session.paymentToken == address(0)) {
            payable(depositor).transfer(refund);
        } else {
            IERC20(session.paymentToken).transfer(depositor, refund);
        }
    }

    session.status = SessionStatus.Completed;

    emit SessionCompleted(jobId, msg.sender, depositor, tokensUsed, paymentDue, refund);
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_anyone_can_complete.t.sol`
- `test/JobMarketplace/MultiChain/test_gasless_ending.t.sol`
- `test/JobMarketplace/MultiChain/test_refund_to_depositor.t.sol`
- `test/JobMarketplace/MultiChain/test_treasury_fee_10_percent.t.sol`

---

### Sub-phase 3.2: Host Payment with Configurable Split ⬜
Ensure host receives HOST_EARNINGS_PERCENTAGE and treasury gets TREASURY_FEE_PERCENTAGE.

**Tasks:**
- [ ] Update FEE_BASIS_POINTS to match TREASURY_FEE_PERCENTAGE from env
- [ ] Verify host payment calculations
- [ ] Test treasury accumulation
- [ ] Verify with multiple payment amounts

**Update constant**:
```solidity
// Line 112 in JobMarketplaceWithModels.sol
uint256 public constant FEE_BASIS_POINTS = 1000; // Should match TREASURY_FEE_PERCENTAGE from env
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_payment_split_90_10.t.sol`
- `test/JobMarketplace/MultiChain/test_treasury_accumulation.t.sol`
- `test/JobMarketplace/MultiChain/test_host_earnings_90_percent.t.sol`

---

### Sub-phase 3.3: Update Event Signatures ⬜
Add new events with depositor terminology.

**Tasks:**
- [ ] Add SessionCreatedByDepositor event
- [ ] Update SessionCompleted to include completedBy
- [ ] Add deposit/withdrawal events
- [ ] Maintain old events for compatibility

**New Events**:
```solidity
event SessionCreatedByDepositor(
    uint256 indexed sessionId,
    address indexed depositor,
    address indexed host,
    uint256 deposit
);

event SessionCompleted(
    uint256 indexed jobId,
    address indexed completedBy,  // Who paid gas
    address indexed depositor,    // Who gets refund
    uint256 tokensUsed,
    uint256 paymentAmount,
    uint256 refundAmount
);
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_new_events.t.sol`
- `test/JobMarketplace/MultiChain/test_event_compatibility.t.sol`

---

## Phase 4: Multi-Chain Configuration

### Sub-phase 4.1: Chain Configuration Structure ⬜
Add chain-specific configuration support.

**Tasks:**
- [ ] Add ChainConfig struct
- [ ] Add initialization function
- [ ] Store native wrapper address (WETH/WBNB)
- [ ] Store chain-specific stablecoin addresses

**Add ChainConfig**:
```solidity
struct ChainConfig {
    address nativeWrapper;     // WETH on Base, WBNB on opBNB
    address stablecoin;        // USDC address per chain
    uint256 minDeposit;        // Chain-specific minimum
    string nativeTokenSymbol;  // "ETH" or "BNB"
}

ChainConfig public chainConfig;

function initializeChainConfig(ChainConfig memory _config) external {
    require(msg.sender == owner(), "Only owner");
    require(chainConfig.nativeWrapper == address(0), "Already initialized");
    chainConfig = _config;
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_chain_config.t.sol`
- `test/JobMarketplace/MultiChain/test_multi_chain_support.t.sol`

---

### Sub-phase 4.2: Native Token Handling ⬜
Ensure proper handling of ETH on Base and BNB on opBNB.

**Tasks:**
- [ ] Test native token deposits on both chains
- [ ] Verify withdrawal of native tokens
- [ ] Test wrapped token interactions
- [ ] Ensure chain-agnostic function names

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_eth_on_base.t.sol`
- `test/JobMarketplace/MultiChain/test_bnb_on_opbnb.t.sol`
- `test/JobMarketplace/MultiChain/test_native_token_agnostic.t.sol`

---

## Phase 5: Integration and Migration

### Sub-phase 5.1: Comprehensive Integration Tests ⬜
Test complete flows with different wallet types.

**Tasks:**
- [ ] Test EOA wallet full flow
- [ ] Test Smart Account full flow
- [ ] Test mixed wallet interactions
- [ ] Test backward compatibility

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_eoa_integration.t.sol`
- `test/JobMarketplace/MultiChain/test_smart_account_integration.t.sol`
- `test/JobMarketplace/MultiChain/test_mixed_wallets.t.sol`

---

### Sub-phase 5.2: Migration Helpers ⬜
Add helper functions for existing users.

**Tasks:**
- [ ] Add migration view functions
- [ ] Create deposit converter for existing balances
- [ ] Add emergency withdrawal function
- [ ] Document migration process

**Helper Functions**:
```solidity
// View function to check if user has legacy sessions
function hasLegacySessions(address user) external view returns (bool) {
    return userSessions[user].length > 0;
}

// Emergency withdrawal for owner
function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
    if (token == address(0)) {
        payable(owner()).transfer(amount);
    } else {
        IERC20(token).transfer(owner(), amount);
    }
}
```

**Test Files** (50-75 lines each):
- `test/JobMarketplace/MultiChain/test_migration_helpers.t.sol`
- `test/JobMarketplace/MultiChain/test_emergency_functions.t.sol`

---

## Phase 7: Final Deployment and Documentation

### Sub-phase 7.1: Deployment Scripts ⬜
Create deployment scripts for both chains.

**Tasks:**
- [ ] Create Base Sepolia deployment script
- [ ] Create opBNB deployment script
- [ ] Add verification scripts
- [ ] Test deployment process

**Deployment Scripts**:
- `script/deploy/MultiChain/DeployBaseSepolia.s.sol`
- `script/deploy/MultiChain/DeployOpBNB.s.sol`
- `script/deploy/MultiChain/VerifyContracts.s.sol`

---

### Sub-phase 7.2: Documentation Update ⬜
Update all documentation for multi-chain support.

**Tasks:**
- [ ] Update CONTRACT_ADDRESSES.md
- [ ] Update technical documentation
- [ ] Create migration guide
- [ ] Add multi-chain usage examples

**Documentation Files**:
- `docs/MULTI_CHAIN_DEPLOYMENT.md`
- `docs/WALLET_AGNOSTIC_GUIDE.md`
- `docs/MIGRATION_FROM_SINGLE_CHAIN.md`

---

## Testing Strategy

### Unit Tests
- Each function tested in isolation
- Multiple scenarios per function
- Edge cases and error conditions
- 85% minimum coverage

### Integration Tests
- Full user flows
- Cross-function interactions
- Multi-wallet scenarios
- Chain-specific behaviors

### Gas Optimization Tests
- Measure gas costs before/after
- Compare wallet types
- Optimize storage patterns

---

## Implementation Notes

### Bounded Autonomy Rules
1. Each sub-phase limited to 200-300 lines of code
2. Test files limited to 50-75 lines each
3. Must show failing tests before implementation
4. Cannot proceed if tests are failing
5. Each sub-phase must be atomic and complete

### Development Sequence
1. Write all tests for sub-phase first
2. Run tests and verify they fail
3. Implement minimal code to pass tests
4. Refactor if needed (keeping tests green)
5. Commit with clear message
6. Move to next sub-phase only when current is complete

### Critical Invariants
- NEVER break backward compatibility
- ALWAYS maintain wallet agnosticism
- ENSURE 10% treasury / 90% host split
- ALLOW anyone to complete sessions
- TRACK all deposits properly

---

## Risk Mitigation

### Security Considerations
1. Reentrancy guards on all external calls
2. Check-effects-interactions pattern
3. Proper access controls
4. Overflow protection with Solidity 0.8+

### Testing Requirements
1. Unit tests for each new function
2. Integration tests for user flows
3. Fuzz testing for numeric inputs
4. Invariant testing for critical properties

### Deployment Safety
1. Deploy to testnet first
2. Verify all functions work
3. Test with real wallets
4. Monitor initial transactions

---

## Success Criteria

### Phase Completion
- [ ] All tests passing
- [ ] 85%+ code coverage
- [ ] No compiler warnings
- [ ] Documentation complete

### Overall Success
- [ ] Works with EOA wallets
- [ ] Works with Smart Accounts
- [ ] Supports Base Sepolia (ETH)
- [ ] Supports opBNB (BNB)
- [ ] 100% backward compatible
- [ ] Anyone can complete sessions
- [ ] 10% treasury fee implemented

---

## Appendix: File Structure

```
src/
└── JobMarketplaceMultiChain.sol (new, inherits from JobMarketplaceWithModels)

test/JobMarketplace/MultiChain/
├── Phase1/
│   ├── test_deposit_*.t.sol
│   └── test_withdraw_*.t.sol
├── Phase2/
│   └── test_session_*.t.sol
├── Phase3/
│   └── test_payment_*.t.sol
├── Phase4/
│   └── test_chain_*.t.sol
└── Phase5/
    └── test_integration_*.t.sol

script/deploy/MultiChain/
├── DeployBaseSepolia.s.sol
└── DeployOpBNB.s.sol

docs/
├── MULTI_CHAIN_DEPLOYMENT.md
├── WALLET_AGNOSTIC_GUIDE.md
└── MIGRATION_FROM_SINGLE_CHAIN.md
```

---

## Notes for Implementation

This plan follows strict TDD bounded autonomy approach:
- Each sub-phase is self-contained
- Tests written before implementation
- Clear boundaries and limits
- Incremental progress
- No scope creep

The implementation should be done in order, completing each sub-phase fully before moving to the next. This ensures a stable, well-tested multi-chain/multi-wallet solution.