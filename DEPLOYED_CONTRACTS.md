# Deployed Contract Addresses - Base Sepolia

## Fixed USDC Session Creation Deployment
**Date**: 2025-09-02

### New JobMarketplace Contract (with USDC validation fix)
- **JobMarketplaceFABWithS5**: `0xC6E3B618E2901b1b2c1beEB4E2BB86fc87d48D2d`
  - Fixed `createSessionJobWithToken` function
  - Added host validation through NodeRegistry
  - Added parameter validation (price, duration, proof interval)
  - Moved token transfer after validations
  - Contract size: 24,564 bytes (under limit)

### Existing Contracts (unchanged)
- **NodeRegistry**: `0x87516C13Ea2f99de598665e14cab64E191A0f8c4`
- **PaymentEscrowWithEarnings**: `0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C`
- **HostEarnings**: `0xcbD91249cC8A7634a88d437Eaa083496C459Ef4E`
- **FAB Token**: `0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078`
- **USDC (Base Sepolia)**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

## Configuration Completed
- ✅ USDC address configured in JobMarketplace
- ✅ PaymentEscrow address configured in JobMarketplace
- ✅ All contracts properly linked

## Testing the Fix
To test USDC session creation, use the `createSessionJobWithToken` function with:
- Token address: `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (USDC)
- Ensure host is registered in NodeRegistry with sufficient stake
- Provide valid parameters (pricePerToken > 0, duration > 0, proofInterval > 0)

## Client Update Required
Update your client application to use the new JobMarketplace address:
```javascript
const JOB_MARKETPLACE_ADDRESS = "0xC6E3B618E2901b1b2c1beEB4E2BB86fc87d48D2d";
```