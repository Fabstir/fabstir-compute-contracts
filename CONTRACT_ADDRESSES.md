# Current Contract Addresses - Base Sepolia

Last Updated: September 1, 2025

> **⚠️ IMPORTANT**: This file contains TWO different JobMarketplaceFABWithS5 deployments:
> - **Session Jobs Enabled**: `0x445882e14b22E921c7d4Fe32a7736a32197578AF` ✅ USE THIS
> - **Old Single-Prompt Only**: `0x7ce861CC0188c260f3Ba58eb9a4d33e17Eb62304` ❌ OUTDATED

## ✅ Active Contracts for SESSION JOBS (Current)

These contracts support the latest session-based AI inference with proof checkpoints:

| Contract | Address | Description |
|----------|---------|-------------|
| **JobMarketplaceFABWithS5** | `0x445882e14b22E921c7d4Fe32a7736a32197578AF` | ✅ SESSION JOBS ENABLED |
| **ProofSystem** | `0x707B775933C4C4c89894EC516edad83b2De77A05` | EZKL proof verification |
| **NodeRegistryFAB** | `0x87516C13Ea2f99de598665e14cab64E191A0f8c4` | Node registration with FAB staking |

## ❌ Old Single-Prompt Contracts (DEPRECATED)

These contracts do NOT support session jobs:

| Contract | Address | Issue |
|----------|---------|-------|
| **JobMarketplaceFABWithS5** (old) | `0x7ce861CC0188c260f3Ba58eb9a4d33e17Eb62304` | No session job support |
| **HostEarnings** | `0xbFfCd6BAaCCa205d471bC52Bd37e1957B1A43d4a` | Not used for session jobs |
| **PaymentEscrowWithEarnings** | `0xa4C5599Ea3617060ce86Ff0916409e1fb4a0d2c6` | Not used for session jobs |

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

Update your configuration with the CORRECT session-enabled contracts:

```javascript
const config = {
  // Session Jobs Enabled Contracts (CURRENT)
  jobMarketplace: '0x445882e14b22E921c7d4Fe32a7736a32197578AF', // ✅ CORRECT for session jobs
  proofSystem: '0x707B775933C4C4c89894EC516edad83b2De77A05',
  nodeRegistry: '0x87516C13Ea2f99de598665e14cab64E191A0f8c4',
  
  // Tokens
  fabToken: '0xC78949004B4EB6dEf2D66e49Cd81231472612D62',
  usdcToken: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  
  // Platform
  treasury: '0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11',
  
  // Network
  chainId: 84532, // Base Sepolia
  rpcUrl: 'https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY'
  
  // NOT NEEDED for session jobs:
  // - paymentEscrow (direct payments used)
  // - hostEarnings (direct transfers used)
};
```

## 📝 Important Notes

- **S5 Integration Required**: Clients and hosts must integrate S5 for prompt/response storage
- **Job IDs**: Start from 1 in the fresh deployment
- **Payment**: Only USDC payments supported (no ETH)
- **Staking**: Requires FAB tokens, not ETH
- **Gas Savings**: Hosts accumulate earnings and withdraw in batches
- **Verification**: All contracts verified on [Base Sepolia Explorer](https://sepolia.basescan.org)