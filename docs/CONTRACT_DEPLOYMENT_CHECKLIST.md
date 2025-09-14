# Contract Deployment Checklist

## CRITICAL: Follow Every Step to Avoid Breaking the System

This document provides step-by-step instructions for deploying or redeploying any contract in the Fabstir ecosystem. Missing any step can cause hours of debugging for app developers.

---

## 🚨 CRITICAL: Post-Deployment Configuration Requirements

**⚠️ WARNING: These configuration steps are ESSENTIAL and often forgotten!**
**Missing these causes hours of debugging "mysterious" payment failures!**

After deploying JobMarketplace, you MUST:

1. **Configure ProofSystem** (without this, session jobs FAIL):
   ```bash
   cast send <MARKETPLACE_ADDRESS> "setProofSystem(address)" <PROOF_SYSTEM_ADDRESS> \
     --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy
   ```

2. **Authorize in HostEarnings** (without this, hosts get NOTHING):
   ```bash
   cast send <HOST_EARNINGS_ADDRESS> "setAuthorizedCaller(address,bool)" \
     <MARKETPLACE_ADDRESS> true \
     --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy
   ```

**VERIFY both configurations:**
```bash
# Should return ProofSystem address, NOT 0x000...
cast call <MARKETPLACE_ADDRESS> "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL

# Should return 0x0000...0001 (true), NOT 0x0000...0000 (false)
cast call <HOST_EARNINGS_ADDRESS> "authorizedCallers(address)" <MARKETPLACE_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

---

## 🚨 Pre-Deployment Checks

Before deploying ANY contract:

1. **Check Dependencies**
   ```bash
   # List all contracts that depend on the one you're changing
   grep -r "import.*ContractName" src/
   grep -r "ContractName public" src/
   ```

2. **Check Current Addresses**
   ```bash
   # Record the current deployed addresses
   cat CONTRACT_ADDRESSES.md | grep -A 5 "Active Contracts"
   ```

3. **Backup Current State**
   ```bash
   # Save current addresses for rollback if needed
   cp CONTRACT_ADDRESSES.md CONTRACT_ADDRESSES.backup.md
   cp .env .env.backup
   ```

---

## 📋 Contract-Specific Deployment Instructions

### 1. ModelRegistry Deployment

**When to redeploy**: Adding/removing approved models, changing governance rules

**Steps**:
1. **Deploy Contract**
   ```bash
   forge script script/DeployModelRegistry.s.sol:DeployModelRegistry \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast -vvv
   ```

2. **Add Approved Models**
   ```bash
   # Add each approved model
   cast send <REGISTRY_ADDRESS> "addTrustedModel(string,string,bytes32)" \
     "CohereForAI/TinyVicuna-1B-32k-GGUF" \
     "tiny-vicuna-1b.q4_k_m.gguf" \
     "0x329d002bc20d4e7baae25df802c9678b5a4340b3ce91f23e6a0644975e95935f"
   ```

3. **Update All References**
   - [ ] Update `CONTRACT_ADDRESSES.md`
   - [ ] Update `.env` - `MODEL_REGISTRY_ADDRESS`
   - [ ] Update `client-abis/DEPLOYMENT_INFO.json`
   - [ ] Update `client-abis/README.md`
   - [ ] Update `docs/MODEL_REGISTRY_DEPLOYMENT.md`

4. **Dependent Contracts to Redeploy**
   - NodeRegistryWithModels (uses ModelRegistry address in constructor)

---

### 2. NodeRegistryWithModels Deployment

**When to redeploy**: Changing staking requirements, updating model validation logic

**Steps**:
1. **Deploy Contract**
   ```bash
   forge script script/DeployNodeRegistryWithModels.s.sol:DeployNodeRegistryWithModels \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast -vvv
   ```

2. **Update All References**
   - [ ] Update `CONTRACT_ADDRESSES.md`
   - [ ] Update `.env` - `NODE_REGISTRY_ADDRESS`
   - [ ] Update `client-abis/DEPLOYMENT_INFO.json`
   - [ ] Update `client-abis/README.md`
   - [ ] Update `docs/HOST_REGISTRATION_GUIDE.md`

3. **Dependent Contracts to Redeploy**
   - JobMarketplaceWithModels (uses NodeRegistry address in constructor)

4. **Migration for Existing Hosts**
   ```javascript
   // Hosts need to re-register in new registry
   // Provide migration script or instructions
   ```

---

### 3. JobMarketplaceWithModels Deployment

**When to redeploy**: Changing fee structure, updating validation logic, fixing bugs

**Steps**:
1. **Deploy Contract**
   ```bash
   forge script script/DeployJobMarketplaceWithModels.s.sol:DeployJobMarketplaceWithModels \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast -vvv
   ```

2. **CRITICAL: Configure ProofSystem**
   ```bash
   # This MUST be done for session jobs to work properly!
   # Without this, hosts can't submit proofs and payments won't distribute correctly

   # First, verify ProofSystem is not set (should return 0x000...)
   cast call <MARKETPLACE_ADDRESS> "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL

   # Set the ProofSystem address
   cast send <MARKETPLACE_ADDRESS> "setProofSystem(address)" \
     <PROOF_SYSTEM_ADDRESS> \
     --private-key $PRIVATE_KEY \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --legacy

   # Verify it was set correctly (should return the ProofSystem address)
   cast call <MARKETPLACE_ADDRESS> "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL
   ```

   **⚠️ WARNING**: If ProofSystem is not configured:
   - Session jobs will fail to distribute payments
   - Hosts won't be able to submit proofs of work
   - Users will get full refunds instead of proper payment distribution
   - This is a common deployment mistake that causes SDK integration failures

3. **Update All References**
   - [ ] Update `CONTRACT_ADDRESSES.md`
   - [ ] Update `.env` - `JOB_MARKETPLACE_ADDRESS`
   - [ ] Update `client-abis/DEPLOYMENT_INFO.json`
   - [ ] Update `client-abis/README.md`
   - [ ] Generate new ABI: `forge build && jq -c '.abi' out/JobMarketplaceWithModels.sol/JobMarketplaceWithModels.json > client-abis/JobMarketplaceWithModels-CLIENT-ABI.json`

4. **Authorize in HostEarnings** (if new deployment)
   ```bash
   cast send <HOST_EARNINGS_ADDRESS> "setAuthorizedCaller(address,bool)" \
     <NEW_MARKETPLACE_ADDRESS> true \
     --private-key $PRIVATE_KEY \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --legacy
   ```

5. **SDK Updates Required**
   - Update contract address in SDK config
   - Update ABI reference if changed
   - Test all job creation functions
   - Verify session job payments work correctly

---

### 4. HostEarnings Deployment

**When to redeploy**: Changing withdrawal logic, adding new payment tokens

**Steps**:
1. **Deploy Contract**
   ```bash
   forge script script/DeployHostEarnings.s.sol:DeployHostEarnings \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast -vvv
   ```

2. **Authorize Marketplace**
   ```bash
   cast send <HOST_EARNINGS_ADDRESS> "authorizeCaller(address,bool)" \
     <MARKETPLACE_ADDRESS> true
   ```

3. **Update All References**
   - [ ] Update `CONTRACT_ADDRESSES.md`
   - [ ] Update `.env` - `HOST_EARNINGS_ADDRESS`
   - [ ] Update `client-abis/DEPLOYMENT_INFO.json`

4. **Dependent Contracts to Redeploy**
   - JobMarketplaceWithModels (uses HostEarnings address in constructor)

---

### 5. ProofSystem Deployment

**When to redeploy**: Updating proof verification logic

**Steps**:
1. **Deploy Contract**
   ```bash
   forge script script/DeployProofSystem.s.sol:DeployProofSystem \
     --rpc-url $BASE_SEPOLIA_RPC_URL \
     --private-key $PRIVATE_KEY \
     --broadcast -vvv
   ```

2. **Update JobMarketplace**
   ```bash
   cast send <MARKETPLACE_ADDRESS> "setProofSystem(address)" \
     <NEW_PROOF_SYSTEM_ADDRESS>
   ```

3. **Update All References**
   - [ ] Update `CONTRACT_ADDRESSES.md`
   - [ ] Update `.env` - `PROOF_SYSTEM_ADDRESS`
   - [ ] Update `client-abis/DEPLOYMENT_INFO.json`

---

## 🚀 Quick Deployment Script

For JobMarketplace deployments, use this script to avoid missing critical steps:

```bash
#!/bin/bash
# deploy-and-configure-marketplace.sh

# Deploy JobMarketplace
echo "Deploying JobMarketplace..."
MARKETPLACE_ADDRESS=$(forge create src/JobMarketplaceWithModels.sol:JobMarketplaceWithModels \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args $NODE_REGISTRY $HOST_EARNINGS $TREASURY $PLATFORM_FEE \
  --legacy --json | jq -r '.deployedTo')

echo "Deployed at: $MARKETPLACE_ADDRESS"

# CRITICAL CONFIG 1: Set ProofSystem
echo "Configuring ProofSystem..."
cast send $MARKETPLACE_ADDRESS "setProofSystem(address)" $PROOF_SYSTEM_ADDRESS \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy

# CRITICAL CONFIG 2: Authorize in HostEarnings
echo "Authorizing in HostEarnings..."
cast send $HOST_EARNINGS_ADDRESS "setAuthorizedCaller(address,bool)" \
  $MARKETPLACE_ADDRESS true \
  --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy

# Verify configurations
echo "Verifying configurations..."
PROOF_CHECK=$(cast call $MARKETPLACE_ADDRESS "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL)
AUTH_CHECK=$(cast call $HOST_EARNINGS_ADDRESS "authorizedCallers(address)" $MARKETPLACE_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL)

if [ "$PROOF_CHECK" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
  echo "❌ ERROR: ProofSystem not configured!"
  exit 1
fi

if [ "$AUTH_CHECK" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
  echo "❌ ERROR: Not authorized in HostEarnings!"
  exit 1
fi

echo "✅ JobMarketplace deployed and configured at: $MARKETPLACE_ADDRESS"
echo "✅ ProofSystem configured: $PROOF_CHECK"
echo "✅ HostEarnings authorized: true"
```

---

## 🔄 Post-Deployment Verification

After ANY contract deployment:

### 1. Verify Contract Code
```bash
# Check contract is deployed
cast code <CONTRACT_ADDRESS> --rpc-url $BASE_SEPOLIA_RPC_URL | head -c 100
# Should return bytecode, not 0x
```

### 2. Verify Contract Connections
```bash
# For JobMarketplace - check NodeRegistry
cast call <MARKETPLACE_ADDRESS> "nodeRegistry()" --rpc-url $BASE_SEPOLIA_RPC_URL

# For NodeRegistry - check ModelRegistry
cast call <NODE_REGISTRY_ADDRESS> "modelRegistry()" --rpc-url $BASE_SEPOLIA_RPC_URL

# For HostEarnings - check authorized callers
cast call <HOST_EARNINGS_ADDRESS> "authorizedCallers(address)" <MARKETPLACE_ADDRESS> --rpc-url $BASE_SEPOLIA_RPC_URL
```

### 3. Test Basic Functions
```bash
# ModelRegistry - check approved models
cast call <MODEL_REGISTRY_ADDRESS> "getAllModels()" --rpc-url $BASE_SEPOLIA_RPC_URL

# NodeRegistry - check MIN_STAKE
cast call <NODE_REGISTRY_ADDRESS> "MIN_STAKE()" --rpc-url $BASE_SEPOLIA_RPC_URL
```

### 4. Update Documentation Files

**MUST update ALL of these**:
- [ ] `CONTRACT_ADDRESSES.md` - Main reference
- [ ] `.env` - Environment variables
- [ ] `client-abis/DEPLOYMENT_INFO.json` - Client reference
- [ ] `client-abis/README.md` - Integration guide
- [ ] `docs/HOST_REGISTRATION_GUIDE.md` - If NodeRegistry changed
- [ ] `docs/MODEL_REGISTRY_DEPLOYMENT.md` - If ModelRegistry changed
- [ ] Generate new ABIs in `client-abis/`

### 5. Git Commit
```bash
git add -A
git commit -m "deploy: [ContractName] at [address] - [reason for deployment]

- Updated all documentation files
- Generated new ABI
- Verified contract connections
- [Any breaking changes]"
```

---

## ⚠️ Common Mistakes to Avoid

1. **Forgetting to update .env file**
   - Causes: SDK uses wrong contract address
   - Fix: Always update .env immediately after deployment

2. **Not generating new ABI**
   - Causes: Function calls fail with encoding errors
   - Fix: Always regenerate ABI after contract changes

3. **Not updating dependent contracts**
   - Causes: Contract calls fail due to address mismatch
   - Fix: Check dependency tree before deploying

4. **Using wrong NodeRegistry type**
   - Causes: ABI mismatch, "require(false)" errors
   - Fix: JobMarketplace must match NodeRegistry type (5 vs 6 fields)

5. **Not authorizing in HostEarnings**
   - Causes: Payment distributions fail
   - Fix: Always authorize new marketplace in HostEarnings

6. **Forgetting to add models to ModelRegistry**
   - Causes: Host registration fails
   - Fix: Add approved models immediately after deployment

---

## 📊 Deployment Order (Clean Slate)

If deploying everything from scratch:

1. **FAB Token** (if not exists)
2. **USDC Token** (if testnet)
3. **ModelRegistry**
   - Add approved models
4. **NodeRegistryWithModels**
   - Uses ModelRegistry address
5. **HostEarnings**
6. **ProofSystem**
7. **JobMarketplaceWithModels**
   - Uses NodeRegistry and HostEarnings addresses
   - Set ProofSystem after deployment
   - Authorize in HostEarnings

---

## 🔍 Troubleshooting

### "Host not registered" error
- Check: Is host registered in the NodeRegistry that JobMarketplace uses?
- Run: `cast call <MARKETPLACE> "nodeRegistry()"` to check which registry

### "Model not approved" error
- Check: Is model ID in ModelRegistry's approved list?
- Run: `cast call <MODEL_REGISTRY> "isModelApproved(bytes32)" <MODEL_ID>`

### "Not authorized" in HostEarnings
- Check: Is marketplace authorized?
- Run: `cast call <HOST_EARNINGS> "authorizedCallers(address)" <MARKETPLACE>`

### Transaction reverts with no reason
- Check: Contract address mismatch (5-field vs 6-field struct)
- Check: Contract not deployed (returns 0x for code)
- Check: Dependencies not set correctly

---

## 📝 Template for Deployment Notes

When deploying, document:
```markdown
## Deployment: [ContractName]
Date: [YYYY-MM-DD]
Deployer: [Address]
Network: Base Sepolia

### Reason for Deployment
[Why was this needed?]

### Contract Address
Old: [Previous address if redeployment]
New: [New deployed address]

### Changes Made
- [List all changes]

### Files Updated
- [ ] CONTRACT_ADDRESSES.md
- [ ] .env
- [ ] client-abis/DEPLOYMENT_INFO.json
- [ ] client-abis/README.md
- [ ] [Other files]

### Verification
- [ ] Contract code verified
- [ ] Dependencies connected
- [ ] Test transaction successful
- [ ] SDK updated and tested

### Breaking Changes
[Any breaking changes for SDK/clients]

### Migration Required
[Any migration steps for users/hosts]
```

---

## 🚀 Quick Reference Commands

```bash
# Deploy ModelRegistry
forge script script/DeployModelRegistry.s.sol:DeployModelRegistry --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast

# Deploy NodeRegistryWithModels
forge script script/DeployNodeRegistryWithModels.s.sol:DeployNodeRegistryWithModels --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast

# Deploy JobMarketplaceWithModels
forge script script/DeployJobMarketplaceWithModels.s.sol:DeployJobMarketplaceWithModels --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast

# Generate ABI
forge build && jq -c '.abi' out/[Contract].sol/[Contract].json > client-abis/[Contract]-CLIENT-ABI.json

# Verify deployment
cast code [ADDRESS] --rpc-url $BASE_SEPOLIA_RPC_URL
```

---

---

## 📚 Case Study: What Happens When Steps Are Missed

### January 14, 2025 - NodeRegistry Mismatch Issue

**What Happened**:
1. Deployed ModelRegistry and NodeRegistryWithModels
2. Host registered in NodeRegistryWithModels (6-field struct with model support)
3. JobMarketplace was still using old NodeRegistryFAB (5-field struct)
4. SDK tried to create session job → Transaction failed with "require(false)"

**Root Cause**:
- JobMarketplace wasn't redeployed to match new NodeRegistry type
- Documentation wasn't updated consistently
- SDK was using mismatched contracts

**Time Lost**:
- 2+ hours debugging the issue
- SDK developer couldn't figure out why valid transactions were failing

**Lesson**:
- When changing NodeRegistry structure, MUST redeploy JobMarketplace
- MUST update ALL documentation files
- MUST verify contract connections before telling SDK to use them

**Fix Applied**:
1. Created JobMarketplaceWithModels compatible with NodeRegistryWithModels
2. Updated ALL documentation files
3. Generated new ABI
4. Verified all connections
5. Created this checklist to prevent future occurrences

### January 14, 2025 - Missing ProofSystem Configuration

**What Happened**:
1. Deployed JobMarketplaceWithModels at `0x56431bDeA20339c40470eC86BC2E3c09B065AFFe`
2. SDK developer reported session jobs failing - payments not distributing correctly
3. Investigation revealed `proofSystem()` returned zero address (0x000...)
4. Hosts couldn't submit proofs, causing full refunds instead of proper payment distribution

**Root Cause**:
- JobMarketplace was deployed but `setProofSystem()` was never called
- This critical configuration step was missing from deployment process
- Without ProofSystem, the contract can't validate work completion

**Time Lost**:
- Hours of SDK debugging
- Developer traced through entire payment flow before identifying issue
- Could have been prevented with one configuration call

**Lesson**:
- ProofSystem configuration is CRITICAL for session jobs
- Must be set immediately after JobMarketplace deployment
- Should be verified as part of deployment checklist

**Fix Applied**:
```bash
# Set the ProofSystem address
cast send 0x56431bDeA20339c40470eC86BC2E3c09B065AFFe "setProofSystem(address)" \
  0x2ACcc60893872A499700908889B38C5420CBcFD1 \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --legacy
```

### January 14, 2025 - Missing HostEarnings Authorization

**What Happened**:
1. Same deployment as above - JobMarketplaceWithModels at `0x56431bDeA20339c40470eC86BC2E3c09B065AFFe`
2. After fixing ProofSystem, treasury was receiving fees but hosts got NOTHING
3. Investigation revealed JobMarketplace wasn't authorized in HostEarnings contract
4. `authorizedCallers(marketplace)` returned false (0x000...000)

**Root Cause**:
- JobMarketplace was deployed but never authorized in HostEarnings
- Without authorization, calls to credit host earnings silently fail
- Treasury gets paid but hosts receive nothing for their work

**Time Lost**:
- More hours of debugging after "fixing" the ProofSystem issue
- SDK developer thought payment logic was broken
- Two separate configuration issues compounded the debugging time

**Lesson**:
- BOTH ProofSystem AND HostEarnings authorization are required
- Missing either causes different payment failures
- Must verify ALL contract connections after deployment

**Fix Applied**:
```bash
# Authorize JobMarketplace in HostEarnings
cast send 0x908962e8c6CE72610021586f85ebDE09aAc97776 "setAuthorizedCaller(address,bool)" \
  0x56431bDeA20339c40470eC86BC2E3c09B065AFFe true \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --legacy
```

**Combined Impact**:
- Total debugging time: 4+ hours across multiple developers
- Root cause: 2 missing configuration calls that take 30 seconds each
- These configurations are NOT automatic - they MUST be done manually

---

**Remember**: Every shortcut taken during deployment creates hours of debugging later. Follow EVERY step, EVERY time.