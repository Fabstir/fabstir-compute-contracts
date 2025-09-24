# Wallet Agnostic Guide

This guide explains how JobMarketplaceWithModels supports both Externally Owned Accounts (EOAs) and Smart Contract Accounts, enabling gasless transactions and improved user experience.

## Overview

The JobMarketplace smart contracts are designed to be wallet-agnostic, meaning they work seamlessly with:
- **EOA Wallets** (MetaMask, Rainbow, etc.)
- **Smart Contract Wallets** (Safe, Argent, Account Abstraction wallets)
- **ERC-4337 Smart Accounts**

## Key Features

### 1. Deposit/Withdrawal Pattern
Users pre-fund their accounts with deposits, enabling:
- Gas-efficient batch operations
- Gasless session endings
- Flexible payment management

### 2. Anyone-Can-Complete Pattern
Sessions can be completed by any address, not just the creator:
- Hosts can complete to claim payments
- Users can complete without paying gas
- Third parties can complete on behalf of users

### 3. Depositor Tracking
The system tracks the original depositor separately from transaction sender:
- Smart contracts can act on behalf of users
- Maintains proper accounting regardless of wallet type

## Wallet Patterns

### EOA Wallets (Traditional)

Standard Ethereum wallets where users directly sign and send transactions.

```javascript
// Direct interaction from user's EOA
const tx = await marketplace.depositNative({ value: ethers.parseEther("1.0") });
await tx.wait();

// Create session directly
const sessionTx = await marketplace.createSessionJob(
    hostAddress,
    ethers.parseEther("0.001"),  // price per token
    86400,                        // duration (1 day)
    10,                          // proof interval
    { value: ethers.parseEther("0.5") }
);
```

### Smart Contract Wallets

Wallets that use smart contracts for enhanced features like multi-sig, social recovery, or gasless transactions.

```javascript
// Smart wallet executes on behalf of user
const smartWallet = new SmartWallet(userAddress);

// Batch operations in single transaction
await smartWallet.executeBatch([
    {
        to: marketplace.address,
        data: marketplace.interface.encodeFunctionData("depositNative"),
        value: ethers.parseEther("1.0")
    },
    {
        to: marketplace.address,
        data: marketplace.interface.encodeFunctionData("createSessionFromDeposit", [
            hostAddress,
            ethers.ZeroAddress,  // native token
            ethers.parseEther("0.5"),
            ethers.parseEther("0.001"),
            86400,
            10
        ])
    }
]);
```

### ERC-4337 Account Abstraction

Full account abstraction with sponsored transactions and bundled operations.

```javascript
// User operation for account abstraction
const userOp = {
    sender: smartAccountAddress,
    nonce: await entryPoint.getNonce(smartAccountAddress, 0),
    initCode: "0x",
    callData: smartAccount.interface.encodeFunctionData("execute", [
        marketplace.address,
        0,
        marketplace.interface.encodeFunctionData("completeSessionJob", [sessionId, "ipfs://cid"])
    ]),
    // ... gas and signature fields
};

// Submit through bundler
await bundler.sendUserOperation(userOp);
```

## Usage Patterns

### Pattern 1: Pre-funded Operations

Users deposit funds once, then create multiple sessions without additional transactions.

```solidity
// 1. Initial deposit (requires gas)
depositNative() payable
depositToken(token, amount)

// 2. Create sessions from deposit (can be gasless)
createSessionFromDeposit(host, token, deposit, pricePerToken, duration, proofInterval)

// 3. Withdraw remaining balance (can be gasless)
withdrawNative(amount)
withdrawToken(token, amount)
```

### Pattern 2: Gasless Session Completion

Anyone can complete a session, enabling gasless endings for users.

```solidity
// Host completes to claim payment (host pays gas)
completeSessionJob(sessionId, conversationCID)

// Third party completes on user's behalf (third party pays gas)
completeSessionJob(sessionId, conversationCID)

// Result: User gets refund without paying gas
```

### Pattern 3: Batch Operations

Smart wallets can batch multiple operations in a single transaction.

```javascript
// Batch: Deposit + Create Session + Set Preferences
const calls = [
    marketplace.depositNative({ value: "1 ETH" }),
    marketplace.createSessionFromDeposit(...),
    marketplace.updatePreferences(...)
];

await smartWallet.multiCall(calls);
```

## Implementation Examples

### Example 1: EOA Creates, Host Completes

```javascript
// User (EOA) creates session
const user = new ethers.Wallet(privateKey, provider);
const marketplace = new Contract(MARKETPLACE_ADDRESS, ABI, user);

await marketplace.createSessionJob(
    hostAddress,
    pricePerToken,
    duration,
    proofInterval,
    { value: sessionDeposit }
);

// Host completes (host pays gas, user gets refund gaslessly)
const host = new ethers.Wallet(hostPrivateKey, provider);
const hostMarketplace = marketplace.connect(host);
await hostMarketplace.completeSessionJob(sessionId, "ipfs://conversation");
```

### Example 2: Smart Wallet Gasless Flow

```javascript
// Smart wallet creates session without user paying gas
const smartWallet = await SmartWallet.create({
    owner: userAddress,
    paymaster: paymasterAddress  // Sponsors gas
});

// User signs, paymaster pays gas
await smartWallet.execute(
    marketplace.address,
    marketplace.interface.encodeFunctionData("createSessionFromDeposit", [
        hostAddress,
        tokenAddress,
        depositAmount,
        pricePerToken,
        duration,
        proofInterval
    ])
);
```

### Example 3: Mixed Wallet Interaction

```javascript
// Smart wallet deposits for user
await smartWallet.execute(
    marketplace.address,
    marketplace.interface.encodeFunctionData("depositNative"),
    { value: ethers.parseEther("2.0") }
);

// EOA host serves the session
// ...AI inference happens...

// Random EOA completes the session
const randomWallet = new ethers.Wallet(randomKey, provider);
await marketplace.connect(randomWallet).completeSessionJob(sessionId, cid);

// Result: Smart wallet user gets refund, EOA host gets payment
```

## Benefits by Wallet Type

### For EOA Users
- ✅ Direct control and simplicity
- ✅ Can benefit from anyone-can-complete pattern
- ✅ Pre-funding reduces transaction count
- ⚠️ Must pay gas for deposits/withdrawals

### For Smart Wallet Users
- ✅ Gasless transactions via sponsorship
- ✅ Batch operations in single transaction
- ✅ Enhanced security features (multi-sig, limits)
- ✅ Social recovery options

### For Hosts (Any Wallet Type)
- ✅ Incentivized to complete sessions (get paid faster)
- ✅ Can serve users regardless of their wallet type
- ✅ Earnings accumulate in HostEarnings contract
- ✅ Batch withdrawal of accumulated earnings

## Query Functions

### Check Balances

```javascript
// Native token balance
const nativeBalance = await marketplace.userDepositsNative(userAddress);

// ERC20 token balance
const tokenBalance = await marketplace.userDepositsToken(userAddress, tokenAddress);

// Batch query multiple tokens
const balances = await marketplace.getUserBalances(
    userAddress,
    [ethers.ZeroAddress, usdcAddress, daiAddress]  // ZeroAddress = native
);
```

### Session Information

```javascript
// Get session details
const session = await marketplace.sessionJobs(sessionId);

// Check if user is depositor (works for both EOA and smart wallets)
const isDepositor = (session.depositor === userAddress);

// Get user's sessions
const userSessions = await marketplace.getUserSessions(userAddress);
```

## Best Practices

### 1. Always Track Depositor
When creating sessions, the contract tracks the depositor separately from msg.sender:
```solidity
session.depositor = depositor;  // Could be different from msg.sender
```

### 2. Support Both Patterns
Applications should support both inline payments and pre-funded operations:
```javascript
// Support both patterns
if (hasDeposit) {
    await marketplace.createSessionFromDeposit(...);
} else {
    await marketplace.createSessionJob(..., { value: amount });
}
```

### 3. Enable Gasless When Possible
Prefer operations that can be completed by others:
```javascript
// Good: Anyone can complete
await marketplace.completeSessionJob(sessionId, cid);

// Avoid: Only specific address can act
// await marketplace.userOnlyFunction();
```

### 4. Handle Events Properly
Listen for events that include depositor information:
```javascript
marketplace.on("SessionCreatedByDepositor", (sessionId, depositor, host, deposit) => {
    console.log(`Session ${sessionId} created by ${depositor}`);
});

marketplace.on("SessionCompletedWithCompletedBy", (sessionId, completedBy) => {
    console.log(`Session ${sessionId} completed by ${completedBy}`);
});
```

## Security Considerations

1. **Depositor Verification**: Always verify the depositor field, not msg.sender
2. **Reentrancy Protection**: Contract uses checks-effects-interactions pattern
3. **Balance Tracking**: Separate tracking for native and token balances
4. **Authorization**: Only authorized contracts can distribute host earnings

## Testing Wallet Compatibility

Test your integration with different wallet types:

```bash
# Test with EOA
forge test --match-test test_EOA

# Test with Smart Wallet simulation
forge test --match-test test_SmartAccount

# Test mixed interactions
forge test --match-test test_Mixed
```

## Conclusion

The wallet-agnostic design of JobMarketplaceWithModels enables:
- Broader user adoption through smart wallet support
- Better UX through gasless operations
- Flexibility in payment and session management
- Future-proof architecture for evolving wallet standards

Whether users prefer the simplicity of EOAs or the advanced features of smart wallets, the marketplace provides a seamless experience for AI inference services.