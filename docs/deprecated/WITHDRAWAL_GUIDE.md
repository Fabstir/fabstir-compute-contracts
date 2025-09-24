# Withdrawal Process Guide - Two-Step Accumulation System

**Last Updated: January 14, 2025 (v2 - Refund Bug Fixed)**

## Overview

The Fabstir marketplace uses a **two-step accumulation and withdrawal pattern** for maximum gas efficiency. Instead of direct payments on each job completion, funds accumulate in smart contracts and are withdrawn in batch operations, saving ~80% in gas costs.

> **Important Update (Jan 14 v2)**: Fixed critical bug where users weren't receiving refunds for unused tokens when using `claimWithProof()`. Users now correctly receive automatic refunds for any unused deposit amount.

## The Two-Step Process

### Step 1: Automatic Accumulation (During Job Completion)
When a session job completes, payments are automatically split and accumulated:

```
User Payment (100%)
    ├── Host Payment (90%) → Accumulates in HostEarnings contract
    └── Treasury Fee (10%) → Accumulates in JobMarketplace contract
```

**This happens automatically** - no action required from hosts or treasury.

### Step 2: Manual Withdrawal (When You Want Funds)
Each party must manually withdraw their accumulated funds:

- **Hosts**: Call withdrawal functions on HostEarnings contract
- **Treasury**: Call withdrawal functions on JobMarketplace contract

## For Hosts - Withdrawing Your Earnings

### Contract Address
`HostEarnings`: `0x908962e8c6CE72610021586f85ebDE09aAc97776`

### Check Your Balance

```javascript
// Using ethers.js
const hostEarnings = new ethers.Contract(
  "0x908962e8c6CE72610021586f85ebDE09aAc97776",
  HostEarningsABI,
  provider
);

// Check USDC earnings
const usdcBalance = await hostEarnings.earnings(
  yourAddress,
  "0x036CbD53842c5426634e7929541eC2318f3dCF7e"  // USDC address
);

// Check ETH earnings
const ethBalance = await hostEarnings.earnings(
  yourAddress,
  "0x0000000000000000000000000000000000000000"  // ETH uses zero address
);
```

### Withdraw Your Funds

#### Option 1: Withdraw Single Token
```javascript
// Withdraw all USDC
await hostEarnings.withdrawAll("0x036CbD53842c5426634e7929541eC2318f3dCF7e");

// Withdraw all ETH
await hostEarnings.withdrawAll("0x0000000000000000000000000000000000000000");
```

#### Option 2: Withdraw Multiple Tokens (Save Gas)
```javascript
// Withdraw USDC and ETH in one transaction
await hostEarnings.withdrawMultiple([
  "0x036CbD53842c5426634e7929541eC2318f3dCF7e",  // USDC
  "0x0000000000000000000000000000000000000000"   // ETH
]);
```

### Using Cast CLI

```bash
# Check USDC balance
cast call 0x908962e8c6CE72610021586f85ebDE09aAc97776 \
  "earnings(address,address)" \
  $YOUR_ADDRESS 0x036CbD53842c5426634e7929541eC2318f3dCF7e \
  --rpc-url $RPC_URL

# Withdraw USDC
cast send 0x908962e8c6CE72610021586f85ebDE09aAc97776 \
  "withdrawAll(address)" \
  0x036CbD53842c5426634e7929541eC2318f3dCF7e \
  --private-key $YOUR_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

## For Treasury - Withdrawing Platform Fees

### Contract Address
`JobMarketplace`: `0xc5BACFC1d4399c161034bca106657c0e9A528256`

### Check Accumulated Fees

```javascript
// Check USDC fees
const usdcFees = await marketplace.accumulatedTreasuryTokens(
  "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
);

// Check ETH fees
const ethFees = await marketplace.accumulatedTreasuryETH();
```

### Withdraw Treasury Funds

#### Option 1: Withdraw Single Token
```javascript
// Withdraw USDC fees
await marketplace.withdrawTreasuryTokens("0x036CbD53842c5426634e7929541eC2318f3dCF7e");

// Withdraw ETH fees
await marketplace.withdrawTreasuryETH();
```

#### Option 2: Withdraw All (ETH + Tokens)
```javascript
// Withdraw ETH and all specified tokens
await marketplace.withdrawAllTreasuryFees([
  "0x036CbD53842c5426634e7929541eC2318f3dCF7e"  // USDC
]);
```

### Using Cast CLI

```bash
# Check USDC treasury fees
cast call 0xc5BACFC1d4399c161034bca106657c0e9A528256 \
  "accumulatedTreasuryTokens(address)" \
  0x036CbD53842c5426634e7929541eC2318f3dCF7e \
  --rpc-url $RPC_URL

# Withdraw USDC treasury fees
cast send 0xc5BACFC1d4399c161034bca106657c0e9A528256 \
  "withdrawTreasuryTokens(address)" \
  0x036CbD53842c5426634e7929541eC2318f3dCF7e \
  --private-key $TREASURY_PRIVATE_KEY \
  --rpc-url $RPC_URL
```

## Why Two-Step Process?

### Gas Savings
- **Old System**: ~70,000 gas per job (direct transfers)
- **New System**: ~14,000 gas per job (accumulation only)
- **Savings**: ~80% reduction per job

### Benefits
1. **Batch Processing**: Withdraw earnings from multiple jobs at once
2. **Flexible Timing**: Withdraw when gas prices are low
3. **Reduced Complexity**: Simpler job completion logic
4. **Better UX**: Jobs complete faster with less gas

## Common Issues & Solutions

### "No earnings to withdraw"
- **Cause**: No accumulated funds or already withdrawn
- **Solution**: Check your balance first using `earnings()` or `accumulatedTreasuryTokens()`

### "Not authorized to credit earnings"
- **Cause**: New marketplace not authorized in HostEarnings
- **Solution**: Owner must call `setAuthorizedCaller()` on HostEarnings

### "Only treasury can withdraw"
- **Cause**: Non-treasury address trying to withdraw treasury fees
- **Solution**: Use the correct treasury address (`0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11`)

### Funds appear stuck
- **Cause**: Funds are accumulated, not stuck - withdrawal needed
- **Solution**: Call the appropriate withdrawal function

## Best Practices

### For Hosts
1. **Monitor regularly**: Check accumulated earnings weekly
2. **Batch withdrawals**: Let earnings accumulate before withdrawing
3. **Low gas timing**: Withdraw during off-peak hours
4. **Multi-token**: Use `withdrawMultiple()` to save gas

### For Treasury
1. **Regular collection**: Withdraw fees monthly or quarterly
2. **Batch operations**: Use `withdrawAllTreasuryFees()` for efficiency
3. **Monitor accumulation**: Track total fees across all tokens
4. **Automate**: Consider automated withdrawal scripts

## Example: Complete Workflow

```javascript
// 1. User creates session job (automatic)
const tx = await marketplace.createSessionJob(details, requirements, {
  value: ethers.utils.parseEther("0.001")
});

// 2. Host completes job with proofs (automatic accumulation)
await marketplace.claimWithProof(jobId);
// → 90% accumulates in HostEarnings
// → 10% accumulates in JobMarketplace

// 3. Host withdraws earnings (manual - when ready)
await hostEarnings.withdrawAll(usdcAddress);

// 4. Treasury withdraws fees (manual - periodically)
await marketplace.withdrawTreasuryTokens(usdcAddress);
```

## Contract Addresses Reference

| Contract | Address | Purpose |
|----------|---------|---------|
| **JobMarketplace** | `0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0` | Treasury fee accumulation |
| **HostEarnings** | `0x908962e8c6CE72610021586f85ebDE09aAc97776` | Host earnings accumulation |
| **USDC Token** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Primary payment token |
| **Treasury** | `0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11` | Platform fee recipient |

## Additional Resources

- [HostEarnings Technical Docs](./technical/contracts/HostEarnings.md) - Detailed contract documentation
- [Treasury Accumulation](./TREASURY_ACCUMULATION_DEPLOYMENT.md) - Implementation details
- [Current Status](./CURRENT_STATUS.md) - Latest deployment information
- [Session Jobs Guide](./SESSION_JOB_COMPLETION_GUIDE.md) - Job completion process

## Support

For issues with withdrawals:
1. Verify contract addresses are correct
2. Check accumulated balances first
3. Ensure using correct account (host vs treasury)
4. Review transaction errors for specific issues

---

*Note: All addresses shown are for Base Sepolia testnet. Gas savings percentages are approximate and may vary based on network conditions.*