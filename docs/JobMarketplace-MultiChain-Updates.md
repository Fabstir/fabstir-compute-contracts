# JobMarketplace Multi-Chain/Multi-Wallet Updates

## Contract Update Specification

**Current Contract**: JobMarketplaceWithModels (`0x1273E6358aa52Bb5B160c34Bf2e617B745e4A944`)
**Target Networks**: Base Sepolia (existing), opBNB Testnet (new)
**Goal**: Make contract wallet-agnostic while maintaining full backward compatibility

## Executive Summary

Update the JobMarketplace contract to be completely wallet-agnostic, treating all addresses equally whether they are EOAs, Smart Accounts (Base Account Kit), or future wallet types. The contract should work identically across multiple chains with minimal modifications.

## Supported Chains and Native Tokens

| Chain | Network Type | Native Token | Wrapped Token | Notes |
|-------|--------------|--------------|---------------|-------|
| Base Sepolia | Ethereum L2 Testnet | ETH | WETH | Uses Ethereum's ETH as native token |
| opBNB Testnet | BNB Chain L2 Testnet | BNB | WBNB | Uses BNB as native token |

**Important**: Base is an Ethereum Layer 2 that uses ETH as its native token, while opBNB is BNB Chain's Layer 2 that uses BNB as its native token.

## Required Contract Changes

### 1. Deposit Tracking Updates

**Current Implementation**:
```solidity
mapping(uint256 => Job) public jobs;
mapping(uint256 => Session) public sessions;
```

**Add New Mapping** (maintains compatibility):
```solidity
// Track deposits by address (wallet-agnostic)
mapping(address => uint256) public userDepositsNative; // Native token (ETH on Base, BNB on opBNB)
mapping(address => mapping(address => uint256)) public userDepositsToken; // depositor => token => amount

// Keep existing mappings for backward compatibility
mapping(uint256 => Job) public jobs;
mapping(uint256 => Session) public sessions;
```

### 2. Update Session Creation Functions

**Current**:
```solidity
function createSessionJob(
    address host,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external payable returns (uint256 jobId)
```

**Updated** (backward compatible):
```solidity
function createSessionJob(
    address host,
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external payable returns (uint256 jobId) {
    require(msg.value >= deposit, "Insufficient payment");

    // Track deposit for msg.sender (works for EOA and Smart Account)
    userDepositsNative[msg.sender] += msg.value;

    // Create session - msg.sender is the "depositor"
    uint256 sessionId = _createSession(
        msg.sender,  // depositor (EOA or Smart Account)
        host,
        deposit,
        pricePerToken,
        maxDuration,
        proofInterval
    );

    // Store depositor reference
    sessions[sessionId].depositor = msg.sender;

    return sessionId;
}
```

### 3. Add Unified Deposit Functions

**New Functions** (for explicit deposit pattern):
```solidity
/**
 * @notice Deposit native token (ETH on Base, BNB on opBNB) to user's account
 * @dev Works identically for EOA and Smart Account wallets
 */
function depositNative() external payable {
    require(msg.value > 0, "Zero deposit");
    userDepositsNative[msg.sender] += msg.value;
    emit DepositReceived(msg.sender, msg.value, address(0));
}

/**
 * @notice Deposit ERC20 tokens to user's account
 * @dev msg.sender can be EOA or Smart Account
 * @param token Token address (USDC, etc.)
 * @param amount Amount to deposit
 */
function depositToken(address token, uint256 amount) external {
    require(amount > 0, "Zero deposit");
    require(token != address(0), "Invalid token");

    // Transfer from depositor (EOA or Smart Account)
    IERC20(token).transferFrom(msg.sender, address(this), amount);

    userDepositsToken[msg.sender][token] += amount;
    emit DepositReceived(msg.sender, amount, token);
}

/**
 * @notice Create session using deposited funds
 * @dev Uses pre-deposited funds instead of requiring payment
 */
function createSessionFromDeposit(
    address host,
    address paymentToken, // address(0) for native token (ETH/BNB)
    uint256 deposit,
    uint256 pricePerToken,
    uint256 maxDuration,
    uint256 proofInterval
) external returns (uint256 sessionId) {
    // Check depositor has sufficient balance
    if (paymentToken == address(0)) {
        require(userDepositsNative[msg.sender] >= deposit, "Insufficient native token deposit");
        userDepositsNative[msg.sender] -= deposit;
    } else {
        require(userDepositsToken[msg.sender][paymentToken] >= deposit, "Insufficient token deposit");
        userDepositsToken[msg.sender][paymentToken] -= deposit;
    }

    // Create session with depositor as owner
    sessionId = _createSession(
        msg.sender,  // depositor
        host,
        deposit,
        pricePerToken,
        maxDuration,
        proofInterval
    );

    sessions[sessionId].paymentToken = paymentToken;
}
```

### 4. Update Payment Processing

**Updated completeSessionJob** (CRITICAL - Anyone Can Call):
```solidity
/**
 * @notice Complete a session and distribute payments
 * @dev Can be called by ANYONE (user, host, or automated service)
 * @dev The host node automatically calls this when WebSocket disconnects (v5+)
 * @dev This design enables gasless session ending for users
 * @param jobId The session ID to complete
 */
function completeSessionJob(uint256 jobId) external nonReentrant {
    Session storage session = sessions[jobId];
    require(session.status == SessionStatus.ACTIVE, "Session not active");

    // Get depositor address (works for both EOA and Smart Account)
    address depositor = session.depositor;

    // Calculate payments (existing logic)
    uint256 tokensUsed = session.tokensProven;
    uint256 paymentDue = (tokensUsed * session.pricePerToken) / 1e18;
    uint256 refund = session.deposit > paymentDue ? session.deposit - paymentDue : 0;

    // Distribute payments
    uint256 treasuryFee = (paymentDue * TREASURY_FEE_PERCENT) / 100;
    uint256 hostPayment = paymentDue - treasuryFee;

    // Credit host earnings (existing)
    hostEarnings.creditEarnings(session.host, hostPayment, session.paymentToken);

    // Process refund to depositor (EOA or Smart Account)
    if (refund > 0) {
        if (session.paymentToken == address(0)) {
            // Refund native token to depositor
            payable(depositor).transfer(refund);
        } else {
            // Refund tokens to depositor
            IERC20(session.paymentToken).transfer(depositor, refund);
        }
    }

    // Update session status
    session.status = SessionStatus.COMPLETED;

    emit SessionCompleted(jobId, msg.sender, tokensUsed, paymentDue, refund);
}
```

### 5. Add Withdrawal Functions

**New Functions** (for deposit pattern):
```solidity
/**
 * @notice Withdraw deposited native token (ETH on Base, BNB on opBNB)
 * @dev Returns funds to depositor (EOA or Smart Account)
 */
function withdrawNative(uint256 amount) external nonReentrant {
    require(userDepositsNative[msg.sender] >= amount, "Insufficient balance");

    userDepositsNative[msg.sender] -= amount;
    payable(msg.sender).transfer(amount);

    emit WithdrawalProcessed(msg.sender, amount, address(0));
}

/**
 * @notice Withdraw deposited tokens
 * @dev Returns tokens to depositor (EOA or Smart Account)
 */
function withdrawToken(address token, uint256 amount) external nonReentrant {
    require(userDepositsToken[msg.sender][token] >= amount, "Insufficient balance");

    userDepositsToken[msg.sender][token] -= amount;
    IERC20(token).transfer(msg.sender, amount);

    emit WithdrawalProcessed(msg.sender, amount, token);
}

/**
 * @notice Get deposit balance for an account
 * @dev Works for any address type
 */
function getDepositBalance(address account, address token) external view returns (uint256) {
    if (token == address(0)) {
        return userDepositsNative[account]; // Returns ETH balance on Base, BNB on opBNB
    }
    return userDepositsToken[account][token];
}
```

### 6. Multi-Chain Token Support

**Add Chain-Specific Configuration**:
```solidity
// Token configuration per chain (set in constructor or initialization)
struct ChainConfig {
    address nativeWrapper;     // WETH on Base, WBNB on opBNB
    address stablecoin;        // USDC on both Base and opBNB
    uint256 minDeposit;        // Chain-specific minimums
}

ChainConfig public chainConfig;

// Set during deployment
constructor(ChainConfig memory _config) {
    chainConfig = _config;
}
```

### 7. Events Updates

**Add New Events**:
```solidity
// Wallet-agnostic deposit events
event DepositReceived(address indexed depositor, uint256 amount, address token);
event WithdrawalProcessed(address indexed depositor, uint256 amount, address token);

// Session events using depositor terminology
event SessionCreatedByDepositor(
    uint256 indexed sessionId,
    address indexed depositor,  // EOA or Smart Account
    address indexed host,
    uint256 deposit
);
```

## Deployment Strategy

### Phase 1: Base Sepolia Update
1. Deploy updated contract with wallet-agnostic functions
2. Maintain all existing functions for backward compatibility
3. Test with both EOA and Base Account Kit wallets
4. Verify ETH and USDC flows work identically

### Phase 2: opBNB Deployment
1. Deploy same contract code to opBNB testnet
2. Configure with BNB as native token
3. Set appropriate token addresses (WBNB, USDC)
4. Test BNB deposit flows

### Phase 3: Cross-Chain Verification
1. Ensure contract addresses are documented per chain
2. Verify same ABI across all deployments
3. Test SDK integration with both chains

## Gas Fee Considerations (CRITICAL)

### Session Ending Pattern

The contract MUST allow **anyone** to call `completeSessionJob()`, not just the depositor or host. This enables a gasless ending experience for users:

1. **User Action**: User clicks "End Session" → SDK closes WebSocket connection
2. **Host Node Action**: Detects disconnect → Automatically calls `completeSessionJob()`
3. **Gas Payment**: Host pays gas (they're incentivized to get their payment)
4. **Result**: User gets refund without paying any gas fees

### Why This Works

- **Host Incentive**: Hosts want to call `completeSessionJob()` to receive payment
- **No Gaming**: Users can't avoid payment by closing browser - host still settles
- **Better UX**: Users only pay gas to start sessions, not to end them
- **Failsafe**: If host fails, user can still call `completeSessionJob()` as emergency fallback

### Implementation Notes

```solidity
// ✅ CORRECT - Anyone can call
function completeSessionJob(uint256 jobId) external nonReentrant {
    // No restriction on msg.sender
    // Host typically calls this, but anyone can
}

// ❌ WRONG - Don't restrict caller
function completeSessionJob(uint256 jobId) external nonReentrant {
    require(msg.sender == session.depositor || msg.sender == session.host, "Unauthorized");
    // This would break gasless ending!
}
```

### Events for Gas Tracking

Consider emitting who paid for completion:

```solidity
event SessionCompleted(
    uint256 indexed jobId,
    address indexed completedBy,  // Who called the function (paid gas)
    address indexed depositor,    // Who gets the refund
    uint256 tokensUsed,
    uint256 paymentAmount,
    uint256 refundAmount
);
```

This allows tracking whether users or hosts are paying for session completion.

## Critical Requirements

### 1. Backward Compatibility
- ✅ Keep all existing function signatures
- ✅ Maintain existing event structures
- ✅ Preserve session/job ID schemes
- ✅ Support existing integrations

### 2. Wallet Agnosticism
- ✅ Never check if address is EOA or contract
- ✅ Treat all msg.sender addresses equally
- ✅ Use "depositor" terminology consistently
- ✅ Let SDK handle wallet differences

### 3. Multi-Chain Support
- ✅ Same contract code on all chains
- ✅ Configure token addresses per deployment
- ✅ Maintain consistent function signatures
- ✅ Use chain-agnostic event structures

## Testing Checklist

### EOA Wallet Tests
```javascript
// Test with MetaMask/RainbowKit on Base
const tx = await jobMarketplace.connect(eoaSigner).depositNative({ value: parseEther("0.1") }); // ETH on Base
const balance = await jobMarketplace.getDepositBalance(eoaAddress, ZERO_ADDRESS);
assert(balance.eq(parseEther("0.1")));
```

### Smart Account Tests
```javascript
// Test with Base Account Kit on Base
const smartAccount = await createSmartAccount();
const tx = await jobMarketplace.connect(smartAccount).depositNative({ value: parseEther("0.1") }); // ETH on Base
const balance = await jobMarketplace.getDepositBalance(smartAccount.address, ZERO_ADDRESS);
assert(balance.eq(parseEther("0.1")));
```

### Multi-Chain Tests
```javascript
// Test on Base Sepolia (ETH as native token)
const baseTx = await baseMarketplace.depositNative({ value: parseEther("0.1") }); // Deposits ETH

// Test on opBNB (BNB as native token)
const bnbTx = await opBNBMarketplace.depositNative({ value: parseEther("0.1") }); // Deposits BNB

// Both use same function name but handle their respective native tokens
```

## Security Considerations

1. **Reentrancy Protection**: Maintain ReentrancyGuard on all withdrawal functions
2. **Balance Tracking**: Always update balances before external calls
3. **Token Validation**: Verify token addresses are not zero address
4. **Overflow Protection**: Use SafeMath or Solidity 0.8+ built-in protections
5. **Access Control**: No special permissions based on wallet type

## Migration Notes

### For Existing Users
- Existing sessions continue working unchanged
- New deposit functions are optional
- Can still use direct payment methods

### For SDK Integration
- SDK determines which functions to call based on wallet type
- Contract remains agnostic to these decisions
- Same events emitted regardless of path

## Gas Optimization Notes

The wallet-agnostic design actually REDUCES gas costs:
- No conditional logic checking address types
- Simple balance mappings
- Direct transfers without routing logic

## Summary of Changes

| Feature | Current | Updated | Impact |
|---------|---------|---------|---------|
| Deposit Tracking | Session-specific | Address-based mapping | More flexible |
| Wallet Support | EOA assumed | EOA + Smart Accounts | Broader compatibility |
| Token Support | ETH + USDC | Native (ETH/BNB) + Multiple tokens | Multi-chain ready |
| Function Signatures | Unchanged | Backward compatible | No breaking changes |
| Events | Session-focused | Depositor-focused | Better tracking |

## Implementation Priority

1. **HIGH**: Add deposit/withdrawal functions
2. **HIGH**: Update session creation to use depositor mapping
3. **MEDIUM**: Add multi-token support structure
4. **LOW**: Add view functions for balance queries

## Contract Diff Summary

```diff
contract JobMarketplaceWithModels {
+   // Wallet-agnostic deposit tracking
+   mapping(address => uint256) public userDepositsNative; // ETH on Base, BNB on opBNB
+   mapping(address => mapping(address => uint256)) public userDepositsToken;

    // Existing mappings remain
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => Session) public sessions;

+   // New deposit functions (chain-agnostic)
+   function depositNative() external payable { ... } // ETH on Base, BNB on opBNB
+   function depositToken(address token, uint256 amount) external { ... }
+   function withdrawNative(uint256 amount) external { ... } // ETH on Base, BNB on opBNB
+   function withdrawToken(address token, uint256 amount) external { ... }

    // Existing functions updated to be wallet-agnostic
    // but maintain same signatures for compatibility
}
```

## Questions for Implementation

1. Should deposit balances be queryable by anyone or only the depositor?
2. Should there be a global emergency pause for deposits?
3. Should we emit different events for EOA vs Smart Account (No - stay agnostic)?
4. Should deposit minimums vary by chain or stay consistent?

## Final Notes

This update makes JobMarketplace truly wallet and chain agnostic while maintaining 100% backward compatibility. The contract treats all addresses equally, enabling support for current and future wallet innovations without further contract changes.