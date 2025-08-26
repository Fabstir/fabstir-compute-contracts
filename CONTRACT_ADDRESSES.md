# Current Contract Addresses - Base Sepolia

Last Updated: August 26, 2025

## ✅ Active Contracts (Use These)

These are the currently deployed and configured contracts on Base Sepolia:

| Contract | Address | Description |
|----------|---------|-------------|
| **JobMarketplaceFABWithS5** | `0x7ce861CC0188c260f3Ba58eb9a4d33e17Eb62304` | Job marketplace with S5 CID storage for prompts/responses |
| **NodeRegistryFAB** | `0x87516C13Ea2f99de598665e14cab64E191A0f8c4` | Node registration with FAB token staking (1000 FAB required) |
| **HostEarnings** | `0xbFfCd6BAaCCa205d471bC52Bd37e1957B1A43d4a` | Accumulates host earnings for gas-efficient withdrawals |
| **PaymentEscrowWithEarnings** | `0xa4C5599Ea3617060ce86Ff0916409e1fb4a0d2c6` | Payment escrow with earnings accumulation support |

## 📦 Token Contracts

| Token | Address | Description |
|-------|---------|-------------|
| **FAB Token** | `0xC78949004B4EB6dEf2D66e49Cd81231472612D62` | Governance and staking token |
| **USDC** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Base Sepolia USDC for job payments |

## 🏦 Platform Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Treasury** | `0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078` | Receives 10% platform fees |
| **Platform Fee** | 1000 basis points (10%) | Applied to all job completions |
| **Min Stake** | 1000 FAB tokens | Required for node registration |

## ❌ Deprecated Contracts (DO NOT USE)

These contracts are from earlier deployments and are no longer compatible with the current system:

| Contract | Address | Issue |
|----------|---------|-------|
| JobMarketplaceFABWithEarnings | `0x1A173A3703858D2F5EA4Bf48dDEb53FD4278187D` | No S5 CID support - hosts receive placeholder text |
| NodeRegistry (Original) | `0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3` | Used ETH staking instead of FAB |
| JobMarketplace (Original) | `0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6` | No earnings accumulation |
| PaymentEscrow (Original) | `0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894` | No earnings support |

## 🔄 System Evolution

1. **Phase 1**: Original system with ETH staking and direct payments
2. **Phase 2**: FAB token integration and USDC support  
3. **Phase 3**: Earnings accumulation system (40-46% gas savings)
4. **Phase 4** (Current): S5 CID storage system
   - Fixes critical issue: hosts now receive actual prompts via S5 CIDs
   - Unlimited prompt/response size (not limited by gas)
   - Maintains gas efficiency of earnings system
   - Clean job ID sequence (starts from 1)

## 🚀 For Your Client Application

Update your configuration with:

```javascript
const config = {
  // Active contracts (S5-enabled - Latest Deployment)
  jobMarketplace: '0x7ce861CC0188c260f3Ba58eb9a4d33e17Eb62304', // JobMarketplaceFABWithS5
  nodeRegistry: '0x87516C13Ea2f99de598665e14cab64E191A0f8c4',
  hostEarnings: '0xbFfCd6BAaCCa205d471bC52Bd37e1957B1A43d4a',
  paymentEscrow: '0xa4C5599Ea3617060ce86Ff0916409e1fb4a0d2c6',
  
  // Tokens
  fabToken: '0xC78949004B4EB6dEf2D66e49Cd81231472612D62',
  usdcToken: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  
  // Network
  chainId: 84532, // Base Sepolia
  rpcUrl: 'https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY'
};
```

## 📝 Important Notes

- **S5 Integration Required**: Clients and hosts must integrate S5 for prompt/response storage
- **Job IDs**: Start from 1 in the fresh deployment
- **Payment**: Only USDC payments supported (no ETH)
- **Staking**: Requires FAB tokens, not ETH
- **Gas Savings**: Hosts accumulate earnings and withdraw in batches
- **Verification**: All contracts verified on [Base Sepolia Explorer](https://sepolia.basescan.org)