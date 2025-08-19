# USDC-Enabled Marketplace Deployment

## Base Sepolia Contracts (Deployed 2025-08-19)

### Active Contracts
- **JobMarketplace**: `0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6`
  - USDC payments enabled ✅
  - PaymentEscrow integrated ✅
  - Backward compatible with ETH ✅

- **PaymentEscrow**: `0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894`
  - Multi-token support ✅
  - Fee handling (1% = 100 basis points) ✅
  - Direct release functionality ✅

- **NodeRegistry**: `0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3`
  - ETH-based staking
  - 100 ETH minimum stake

- **USDC**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
  - Base Sepolia USDC
  - 6 decimals

### SDK Integration

Update the fabstir-llm-ui SDK with new addresses:
```javascript
const CONTRACTS = {
  JOB_MARKETPLACE: "0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6",  // NEW!
  PAYMENT_ESCROW: "0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894",
  NODE_REGISTRY: "0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3",
  USDC: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
};
```

### Frontend Usage

#### ETH Payments (unchanged)
```javascript
await jobMarketplace.postJob(details, requirements, { value: ethAmount });
```

#### USDC Payments (new)
```javascript
// 1. Approve USDC spending
await usdc.approve(JOB_MARKETPLACE, usdcAmount);

// 2. Post job with USDC
await jobMarketplace.postJobWithToken(
  details, 
  requirements, 
  USDC_ADDRESS, 
  usdcAmount
);
```

### Testing Commands

```bash
# Verify contracts are linked
cast call 0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6 "paymentEscrow()" --rpc-url base-sepolia
# Expected: 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894

# Check USDC configured
cast call 0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6 "usdcAddress()" --rpc-url base-sepolia
# Expected: 0x036CbD53842c5426634e7929541eC2318f3dCF7e

# Check NodeRegistry
cast call 0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6 "nodeRegistry()" --rpc-url base-sepolia
# Expected: 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3
```

### Contract Verification

JobMarketplace verified on Basescan:
https://sepolia.basescan.io/address/0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6

### Deployment Script

To redeploy if needed:
```bash
forge script script/DeployUSDCMarketplace.s.sol:DeployUSDCMarketplace \
  --rpc-url base-sepolia \
  --broadcast \
  --verify
```

### Key Changes from Previous Version

1. **New JobMarketplace Functions**:
   - `postJobWithToken()` - Create jobs with USDC payment
   - `completeJob()` - Now handles USDC release via PaymentEscrow

2. **PaymentEscrow Integration**:
   - `releasePaymentFor()` - Direct payment release with fee deduction
   - Automatic fee transfer to arbiter

3. **USDC Flow**:
   - User approves USDC → JobMarketplace
   - JobMarketplace transfers USDC → PaymentEscrow
   - On completion: PaymentEscrow → Host (minus fees)

### Migration Notes

- Old JobMarketplace: `0x66E590bfc36cf751E640F09Bbf778AaB542752D5` (deprecated)
- New JobMarketplace: `0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6` (use this)

All existing ETH jobs remain functional. New USDC functionality is additive.