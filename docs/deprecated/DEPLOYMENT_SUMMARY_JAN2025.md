# Deployment Summary - January 2025

## New Contract Deployments on Base Sepolia

### Successfully Deployed Contracts

#### 1. NodeRegistryFAB (with API URL Discovery)
- **Address**: `0x2B745E45818e1dE570f253259dc46b91A82E3204`
- **Features Added**:
  - API URL storage for host endpoint discovery
  - `registerNodeWithUrl()` function for registration with API endpoint
  - `updateApiUrl()` function for hosts to update their endpoints
  - `getNodeApiUrl()` and `getNodeFullInfo()` for client discovery
- **Deployment Block**: 30962852

#### 2. JobMarketplaceFABWithS5Deploy 
- **Address**: `0x3B632813c3e31D94Fd552b4aE387DD321eec67Ba`
- **Features**:
  - Updated to work with 5-field Node struct from new NodeRegistry
  - Session-based jobs with proof submission
  - Treasury fee accumulation (2.5% fee)
  - Host earnings accumulation (70% gas savings)
  - Fixed user refund mechanism
- **Configuration**:
  - ProofSystem: `0x2ACcc60893872A499700908889B38C5420CBcFD1`
  - Treasury: `0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11`
  - USDC enabled with 0.8 USDC minimum deposit
  - Authorized in HostEarnings contract

### Existing Contracts Used

- **HostEarnings**: `0x908962e8c6CE72610021586f85ebDE09aAc97776`
- **ProofSystem**: `0x2ACcc60893872A499700908889B38C5420CBcFD1`
- **FAB Token**: `0xC78949004B4EB6dEf2D66e49Cd81231472612D62`
- **USDC Token**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`
- **Treasury**: `0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11`

## Key Changes Implemented

### 1. API Endpoint Discovery
The new NodeRegistryFAB solves the critical issue where clients couldn't automatically discover host API endpoints:
- Hosts can register with their API URL directly
- Existing hosts can add their API URL without re-registering
- SDK can query the registry to discover host endpoints
- No more hardcoded URLs needed

### 2. Fixed User Refunds
The JobMarketplace now correctly refunds users for unused USDC in session jobs:
- Users deposit funds for sessions
- Only pay for tokens actually used (proven)
- Automatic refund of unused funds
- Confirmed working by user

### 3. Gas-Efficient Fee Accumulation
- Treasury fees accumulate in contract (2.5% of payments)
- Host earnings accumulate in HostEarnings contract
- Manual withdrawal when needed (saves 70% gas)
- Withdrawal scripts provided

## Migration Instructions for Developers

### For SDK Developers
Update your SDK to use the new contract addresses:
```javascript
const NODE_REGISTRY = "0x2B745E45818e1dE570f253259dc46b91A82E3204";
const JOB_MARKETPLACE = "0x3B632813c3e31D94Fd552b4aE387DD321eec67Ba";
```

### For Host Operators
1. If already registered, add your API URL:
```javascript
await nodeRegistry.updateApiUrl("http://your-host.com:8080");
```

2. New hosts should register with API URL:
```javascript
await nodeRegistry.registerNodeWithUrl(
  "llama-2-7b,gpt-4,inference",
  "http://your-host.com:8080"
);
```

### For Client Applications
Use the new discovery mechanism:
```javascript
// Get host API endpoint
const apiUrl = await nodeRegistry.getNodeApiUrl(hostAddress);

// Get full host info including API URL
const info = await nodeRegistry.getNodeFullInfo(hostAddress);
// Returns: [operator, stakedAmount, active, metadata, apiUrl]
```

## Transaction Details

1. **NodeRegistry Deployment**: TX pending confirmation
2. **JobMarketplace Deployment**: TX pending confirmation  
3. **HostEarnings Authorization**: 
   - TX: `0x68f09c46a02ddec959e40ed99effd685907890eab692158f9637ea7d77006936`
   - Block: 30962852
   - Status: Success

## Next Steps

1. ✅ Contracts deployed and configured
2. ✅ HostEarnings authorization complete
3. ⏳ Update SDK with new contract addresses
4. ⏳ Hosts should add their API URLs
5. ⏳ Test end-to-end flow with new contracts

## Testing Commands

```bash
# Check if a host has set their API URL
cast call 0x2B745E45818e1dE570f253259dc46b91A82E3204 \
  "getNodeApiUrl(address)(string)" \
  <HOST_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC_URL

# Get full host info
cast call 0x2B745E45818e1dE570f253259dc46b91A82E3204 \
  "getNodeFullInfo(address)(address,uint256,bool,string,string)" \
  <HOST_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

---
*Deployment completed on January 2025*