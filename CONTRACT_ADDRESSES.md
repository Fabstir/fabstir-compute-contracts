# Current Contract Addresses - Base Sepolia

Last Updated: January 4, 2025

> **🚀 LATEST DEPLOYMENT**: USDC Payment Settlement Fixed and Verified
> - **Current Version**: `0xD937c594682Fe74E6e3d06239719805C04BE804A` ✅ USE THIS (January 4, 2025)
> - **ProofSystem Fixed**: `0x2ACcc60893872A499700908889B38C5420CBcFD1` ✅ FIXED (January 4, 2025)
> - **Previous (STUCK)**: `0xf5e0b435180013b6a7B23280CB77C5E1C3aB921e` ❌ Session 9 stuck/corrupted
> - **Previous Attempt**: `0xC6E3B618E2901b1b2c1beEB4E2BB86fc87d48D2d` ❌ Not deployed (insufficient funds)
> - **December 2024**: `0xebD3bbc24355d05184C7Af753d9d631E2b3aAF7A` ⚠️ Missing USDC validations
> - **Older Session Jobs**: `0x445882e14b22E921c7d4Fe32a7736a32197578AF` ❌ HAS PAYMENT BUG

## ✅ Active Contracts - FIXED USDC VERIFICATION (Current)

These contracts include all fixes for payment distribution AND USDC session verification:

| Contract | Address | Description |
|----------|---------|-------------|
| **JobMarketplaceFABWithS5** | `0xD937c594682Fe74E6e3d06239719805C04BE804A` | ✅ USDC PAYMENTS WORKING - 90/10 VERIFIED |
| **ProofSystem** | `0x2ACcc60893872A499700908889B38C5420CBcFD1` | ✅ FIXED internal verification for USDC |
| **PaymentEscrowWithEarnings** | `0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C` | Payment handling with earnings |
| **HostEarnings** | `0xcbD91249cC8A7634a88d437Eaa083496C459Ef4E` | Host earnings accumulation |
| **NodeRegistryFAB** | `0x87516C13Ea2f99de598665e14cab64E191A0f8c4` | Node registration with FAB staking |

## ⚠️ Previous Deployments with Issues

### Missing USDC Validations (December 2024)
| Contract | Address | Issue |
|----------|---------|-------|
| **JobMarketplaceFABWithS5** | `0xebD3bbc24355d05184C7Af753d9d631E2b3aAF7A` | No host/parameter validation for USDC sessions |

### Session Jobs with Payment Bug (November 2024)
| Contract | Address | Issue |
|----------|---------|-------|
| **JobMarketplaceFABWithS5** | `0x445882e14b22E921c7d4Fe32a7736a32197578AF` | transfer() fails silently |
| **ProofSystem** | `0x707B775933C4C4c89894EC516edad83b2De77A05` | Works but paired with buggy marketplace |

### Old Single-Prompt Contracts (DEPRECATED)
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

Update your configuration with the FIXED contracts:

```javascript
const config = {
  // USDC Payment Settlement Fixed (CURRENT - January 4, 2025)
  jobMarketplace: '0xD937c594682Fe74E6e3d06239719805C04BE804A', // ✅ USDC WORKING - 90/10 VERIFIED
  proofSystem: '0x2ACcc60893872A499700908889B38C5420CBcFD1',     // ✅ FIXED internal verification
  paymentEscrow: '0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C',  // ✅ Earnings accumulation
  hostEarnings: '0xcbD91249cC8A7634a88d437Eaa083496C459Ef4E',   // ✅ Host earnings tracker
  nodeRegistry: '0x87516C13Ea2f99de598665e14cab64E191A0f8c4',
  
  // Tokens
  fabToken: '0xC78949004B4EB6dEf2D66e49Cd81231472612D62',
  usdcToken: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  
  // Platform
  treasury: '0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078',
  
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