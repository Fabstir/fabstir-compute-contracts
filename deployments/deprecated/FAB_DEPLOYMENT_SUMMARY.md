# FAB-Based Staking System Deployment Summary

## Deployment Date: 2025-08-24
## Network: Base Sepolia

## 🚀 Deployed Contracts

### 1. NodeRegistryFAB
- **Address**: `0x87516C13Ea2f99de598665e14cab64E191A0f8c4`
- **Purpose**: Host registration with FAB token staking
- **Minimum Stake**: 1000 FAB tokens
- **FAB Token**: `0xC78949004B4EB6dEf2D66e49Cd81231472612D62`

### 2. JobMarketplace (FAB-Enabled)
- **Address**: `0x4CD10EaBAc400760528EA4a88112B42dbf74aa71`
- **Purpose**: Job lifecycle management with FAB staking and USDC payments
- **NodeRegistry**: `0x87516C13Ea2f99de598665e14cab64E191A0f8c4` (NodeRegistryFAB)
- **PaymentEscrow**: `0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894` (Existing)
- **USDC Token**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

### 3. PaymentEscrow (Existing)
- **Address**: `0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894`
- **Purpose**: USDC escrow and payment release
- **Fee**: 1% (100 basis points)
- **Status**: Updated to accept new JobMarketplace

## 📋 Contract Configuration

```javascript
// Frontend Integration
const CONTRACTS = {
  // New FAB-based contracts
  NODE_REGISTRY_FAB: "0x87516C13Ea2f99de598665e14cab64E191A0f8c4",
  JOB_MARKETPLACE: "0x4CD10EaBAc400760528EA4a88112B42dbf74aa71",
  
  // Existing contracts still in use
  PAYMENT_ESCROW: "0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894",
  
  // Token addresses
  FAB_TOKEN: "0xC78949004B4EB6dEf2D66e49Cd81231472612D62",
  USDC_TOKEN: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
};
```

## 🔄 System Flow

1. **Host Registration**:
   - Host approves 1000 FAB tokens to NodeRegistryFAB
   - Host calls `registerNode()` with metadata
   - FAB tokens are staked in the contract

2. **Job Posting** (by Renters):
   - Renter approves USDC to JobMarketplace
   - Renter calls `postJobWithToken()` with job details
   - USDC is transferred to PaymentEscrow

3. **Job Claiming** (by Hosts):
   - Registered host calls `claimJob(jobId)`
   - Job is assigned to the host

4. **Job Completion** (by Hosts):
   - Host calls `completeJob(jobId, resultHash, proof)`
   - PaymentEscrow releases USDC to host (minus 1% fee)
   - Fee goes to arbiter address

## ✅ Verification Status

All contracts verified on-chain:
- NodeRegistryFAB MIN_STAKE: 1000 FAB ✓
- JobMarketplace nodeRegistry: Points to NodeRegistryFAB ✓
- JobMarketplace paymentEscrow: Points to PaymentEscrow ✓
- JobMarketplace USDC: Configured correctly ✓
- PaymentEscrow: Accepts new JobMarketplace ✓

## 🔐 Security Notes

- FAB tokens are used for staking (security deposit)
- USDC is used for job payments
- 1000 FAB minimum stake prevents Sybil attacks
- PaymentEscrow handles all USDC transfers securely
- 1% platform fee on successful jobs

## 📝 Next Steps for Testing

1. **Fund test host with FAB tokens**:
   - TEST_HOST_1 needs 1000 FAB to register

2. **Register host**:
   ```bash
   NODE_REGISTRY_FAB=0x87516C13Ea2f99de598665e14cab64E191A0f8c4 \
   HOST_PRIVATE_KEY=<key> \
   forge script script/RegisterHostWithFAB.s.sol --broadcast
   ```

3. **Claim and complete jobs**:
   ```bash
   JOB_MARKETPLACE=0x4CD10EaBAc400760528EA4a88112B42dbf74aa71 \
   HOST_PRIVATE_KEY=<key> \
   JOB_ID=<id> \
   forge script script/TestCompleteJobFlow.s.sol --broadcast
   ```

## 🔗 Block Explorer Links

- [NodeRegistryFAB](https://sepolia.basescan.io/address/0x87516C13Ea2f99de598665e14cab64E191A0f8c4)
- [JobMarketplace](https://sepolia.basescan.io/address/0x4CD10EaBAc400760528EA4a88112B42dbf74aa71)
- [PaymentEscrow](https://sepolia.basescan.io/address/0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894)

## 💰 Payment Split Note

Currently, the system takes 1% fee (100 basis points). To achieve your desired 90/10 split:
- Would need to update PaymentEscrow `feeBasisPoints` to 1000 (10%)
- Current: Host gets 99%, Platform gets 1%
- Desired: Host gets 90%, Treasury gets 10%