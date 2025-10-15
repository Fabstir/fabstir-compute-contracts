# S5 Proof Storage Deployment Guide

**Date**: October 14, 2025
**Change**: Off-chain proof storage using S5
**Contract**: JobMarketplaceWithModels
**Deployed Address**: `0xc6D44D7f2DfA8fdbb1614a8b6675c78D3cfA376E`
**Network**: Base Sepolia (Chain ID: 84532)

---

## 📋 Overview

**Problem Solved**: STARK proofs (221KB) exceed RPC transaction limit (128KB), causing all proof submissions to fail.

**Solution**: Store full proofs off-chain in S5, submit only hash (32 bytes) + CID (string) on-chain.

**Benefits**:
- ✅ Transaction size: ~300 bytes (737x reduction from 221KB)
- ✅ Storage cost: ~$0.001 vs ~$50 for on-chain storage
- ✅ Proof integrity: SHA256 hash prevents tampering
- ✅ Proof availability: S5 decentralized storage

---

## 🔧 Contract Changes

### 1. SessionJob Struct - Added 2 Fields
```solidity
struct SessionJob {
    // ... existing 16 fields ...
    bytes32 lastProofHash;  // NEW: SHA256 hash of most recent proof
    string lastProofCID;    // NEW: S5 CID for proof retrieval
}
```

### 2. submitProofOfWork() Function Signature
**OLD**:
```solidity
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes calldata proof  // 221KB - exceeds RPC limit
) external
```

**NEW**:
```solidity
function submitProofOfWork(
    uint256 jobId,
    uint256 tokensClaimed,
    bytes32 proofHash,      // 32 bytes - SHA256 hash from node
    string calldata proofCID // S5 CID (e.g., "u8pDTQHOOY...")
) external
```

### 3. ProofSubmitted Event
**OLD**:
```solidity
event ProofSubmitted(
    uint256 indexed jobId,
    address indexed host,
    uint256 tokensClaimed,
    bytes32 proofHash
);
```

**NEW**:
```solidity
event ProofSubmitted(
    uint256 indexed jobId,
    address indexed host,
    uint256 tokensClaimed,
    bytes32 proofHash,
    string proofCID  // NEW: For off-chain indexing
);
```

### 4. Removed On-Chain Verification
- **Removed**: `proofSystem.verifyEKZL(proof, ...)` call
- **Reason**: No full proof available for on-chain verification
- **Trust Model**: Contract trusts host's hash; disputes fetch proof from S5

---

## 🚀 Deployment Steps

### Step 1: Deploy Contract

```bash
# Set environment
export PRIVATE_KEY="your_private_key"
export BASE_SEPOLIA_RPC_URL="https://sepolia.base.org"

# Deploy
forge script script/DeployS5ProofStorage.s.sol:DeployS5ProofStorage \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --legacy \
  -vvv
```

**Expected Output**:
```
JobMarketplaceWithModels deployed at: 0x[NEW_ADDRESS]
```

**SAVE THIS ADDRESS** - you'll need it for configuration!

---

### Step 2: ⚠️ CRITICAL Configuration

**WARNING**: Missing these steps causes payment failures!

#### 2a. Set ProofSystem
```bash
NEW_MARKETPLACE=0x[ADDRESS_FROM_STEP_1]
PROOF_SYSTEM=0x2ACcc60893872A499700908889B38C5420CBcFD1

cast send $NEW_MARKETPLACE "setProofSystem(address)" $PROOF_SYSTEM \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --legacy
```

#### 2b. Authorize in HostEarnings
```bash
HOST_EARNINGS=0x908962e8c6CE72610021586f85ebDE09aAc97776

cast send $HOST_EARNINGS "setAuthorizedCaller(address,bool)" \
  $NEW_MARKETPLACE true \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --legacy
```

---

### Step 3: Verify Configuration

#### 3a. Verify ProofSystem
```bash
cast call $NEW_MARKETPLACE "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL
```
**Expected**: `0x0000000000000000000000002accc60893872a499700908889b38c5420cbcfd1` (NOT all zeros!)

#### 3b. Verify HostEarnings Authorization
```bash
cast call $HOST_EARNINGS "authorizedCallers(address)" $NEW_MARKETPLACE \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```
**Expected**: `0x0000000000000000000000000000000000000000000000000000000000000001` (true, NOT false!)

---

### Step 4: Test Deployment

```bash
# Check contract is deployed
cast code $NEW_MARKETPLACE --rpc-url $BASE_SEPOLIA_RPC_URL | head -c 100
# Should return bytecode, NOT 0x

# Check NodeRegistry connection
cast call $NEW_MARKETPLACE "nodeRegistry()" --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: 0x000000000000000000000000dfffdecdfa0cf5d6cbe299711c7e4559eb16f42d6

# Check HostEarnings connection
cast call $NEW_MARKETPLACE "hostEarnings()" --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: 0x000000000000000000000000908962e8c6ce72610021586f85ebde09aac97776
```

---

## 📄 Documentation Updates

### Update CONTRACT_ADDRESSES.md

Add new deployment at the top:

```markdown
> **🚀 LATEST DEPLOYMENT**: S5 Off-Chain Proof Storage
>
> - **JobMarketplaceWithModels**: `0x[NEW_ADDRESS]` ✅ NEW - S5 proof storage (Jan 28, 2025)

| **JobMarketplaceWithModels** | `0x[NEW_ADDRESS]` | ✅ S5 off-chain proof storage - submitProofOfWork(hash, CID) |
| **JobMarketplaceWithModels** | `0xe169A4B57700080725f9553E3Cc69885fea13629` | ⚠️ DEPRECATED - Old proof storage |
```

### Update client-abis/README.md

Update JobMarketplace section:

```markdown
### JobMarketplaceWithModels (ACTIVE - S5 Proof Storage)

- **Address**: 0x[NEW_ADDRESS]
- **Network**: Base Sepolia
- **Status**: ✅ ACTIVE
- **Key Features**:
  - S5 off-chain proof storage (hash + CID)
  - Transaction size: ~300 bytes (vs 221KB)
  - Session-based streaming payments
  - Dual pricing support (native/stable)
  - Anyone-can-complete pattern

**BREAKING CHANGE**:
- `submitProofOfWork(uint256,uint256,bytes)` → `submitProofOfWork(uint256,uint256,bytes32,string)`
- Nodes must upload proofs to S5 and submit hash + CID
```

### Update CLAUDE.md

Update deployment section:

```markdown
**Contracts (January 28, 2025 - S5 Proof Storage)**:
- JobMarketplaceWithModels: `0x[NEW_ADDRESS]` ✅ S5 off-chain proof storage
- NodeRegistryWithModels: `0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6`
- ModelRegistry: `0x92b2De840bB2171203011A6dBA928d855cA8183E`
- HostEarnings: `0x908962e8c6CE72610021586f85ebDE09aAc97776`
- ProofSystem: `0x2ACcc60893872A499700908889B38C5420CBcFD1`
- USDC Token: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- FAB Token: `0xC78949004B4EB6dEf2D66e49Cd81231472612D62`
```

---

## 🔄 Node Integration Changes

### Old Flow (Failing)
1. Node generates 221KB STARK proof
2. Node calls `submitProofOfWork(jobId, tokens, proofBytes)`
3. ❌ RPC rejects: "transaction size 221715, limit 131072"

### New Flow (Working)
1. Node generates 221KB STARK proof
2. **Node uploads proof to S5** → gets CID
3. **Node calculates SHA256 hash** of proof
4. Node calls `submitProofOfWork(jobId, tokens, hash, cid)`
5. ✅ Transaction succeeds (~300 bytes)

### Node Developer Updates Required

**Pseudo-code for nodes**:
```javascript
// 1. Generate proof (existing)
const proof = await generateRisc0Proof(jobData);

// 2. Upload to S5 (NEW)
const proofCID = await s5.uploadBlob(proof);
console.log(`Proof uploaded: ${proofCID}`);

// 3. Calculate hash (NEW)
const proofHash = sha256(proof);

// 4. Submit to chain (UPDATED signature)
await marketplace.submitProofOfWork(
  jobId,
  tokensClaimed,
  proofHash,  // NEW parameter
  proofCID    // NEW parameter
);
```

---

## 📊 Testing Checklist

After deployment:

- [ ] Contract deployed successfully
- [ ] ProofSystem configured (verified with cast call)
- [ ] HostEarnings authorized (verified with cast call)
- [ ] Contract code verified on BaseScan
- [ ] NodeRegistry connection verified
- [ ] HostEarnings connection verified
- [ ] ABI exported to `client-abis/`
- [ ] `CONTRACT_ADDRESSES.md` updated
- [ ] `client-abis/README.md` updated
- [ ] `CLAUDE.md` updated
- [ ] Node developer notified
- [ ] Test transaction submitted

---

## 🐛 Troubleshooting

### "ProofSystem not set" error
```bash
# Check ProofSystem
cast call $MARKETPLACE "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL

# If returns 0x000...000, set it:
cast send $MARKETPLACE "setProofSystem(address)" 0x2ACcc60893872A499700908889B38C5420CBcFD1 \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy
```

### "Not authorized" in HostEarnings
```bash
# Check authorization
cast call 0x908962e8c6CE72610021586f85ebDE09aAc97776 "authorizedCallers(address)" $MARKETPLACE \
  --rpc-url $BASE_SEPOLIA_RPC_URL

# If returns 0x000...000, authorize:
cast send 0x908962e8c6CE72610021586f85ebDE09aAc97776 "setAuthorizedCaller(address,bool)" \
  $MARKETPLACE true --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy
```

### Node still getting "oversized data" error
- Check node is using NEW contract address
- Check node is calling NEW function signature
- Check node is uploading to S5 first

---

## 📝 Rollback Plan

If issues discovered:

1. **Old contract still works**: `0xe169A4B57700080725f9553E3Cc69885fea13629`
2. **Node can switch back**: Update contract address in config
3. **No data loss**: Old sessions remain on old contract
4. **Redeploy if needed**: Fix issues and redeploy

---

## ✅ Deployment Complete Checklist

- [ ] Contract deployed
- [ ] ProofSystem configured
- [ ] HostEarnings authorized
- [ ] Configurations verified
- [ ] CONTRACT_ADDRESSES.md updated
- [ ] client-abis/README.md updated
- [ ] CLAUDE.md updated
- [ ] ABI exported
- [ ] Node developer notified
- [ ] Test transaction successful
- [ ] Git commit created

---

## 📞 Contact

**Node Developer**: Update config with new contract address and implement S5 upload
**SDK Developer**: Update contract address, use new ABI
**Testing**: Node developer will validate end-to-end proof submission

---

**Remember**: Follow ALL steps in order. Missing configuration steps causes payment failures that take hours to debug!
