# Deployment Guide & Current Status

**Last Updated: January 14, 2025**

## 🚀 Current Live Deployment (Base Sepolia)

### ✅ Production Contracts (LATEST - January 14, 2025)

| Contract | Address | Status | Notes |
|----------|---------|--------|-------|
| **JobMarketplaceFABWithS5** | `0xc5BACFC1d4399c161034bca106657c0e9A528256` | ✅ LIVE | Fixed jobs mapping, authorized |
| **ProofSystem** | `0x2ACcc60893872A499700908889B38C5420CBcFD1` | ✅ LIVE | Internal verification fixed |
| **HostEarnings** | `0x908962e8c6CE72610021586f85ebDE09aAc97776` | ✅ LIVE | Accumulation working |
| **NodeRegistryFAB** | `0x039AB5d5e8D5426f9963140202F506A2Ce6988F9` | ✅ LIVE | Re-registration fixed |

### Supporting Infrastructure

| Component | Address/Value | Description |
|-----------|---------------|-------------|
| **Treasury** | `0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11` | Receives 10% platform fees |
| **FAB Token** | `0xC78949004B4EB6dEf2D66e49Cd81231472612D62` | Staking (1000 FAB minimum) |
| **USDC** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Base Sepolia USDC |
| **Chain ID** | 84532 | Base Sepolia |

### Recent Successful Operations
- ✅ Job 28 completed with USDC payment
- ✅ HostEarnings authorized for new marketplace
- ✅ Multiple session jobs created and completed
- ✅ Proof submissions verified

## 📦 Deployment Instructions

### Prerequisites
```bash
# Install dependencies
npm install
forge install

# Set up environment
cp .env.example .env
# Edit .env with your keys and addresses
```

### Deploy Fresh Contracts
```bash
# Using Forge script (recommended)
forge script script/DeployOptimizedMarketplace.s.sol:DeployOptimizedMarketplace \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY \
  --slow

# Verify on BaseScan
forge verify-contract <ADDRESS> JobMarketplaceFABWithS5 \
  --chain-id 84532 \
  --etherscan-api-key $BASESCAN_API_KEY
```

### Post-Deployment Setup

1. **Authorize Marketplace in HostEarnings**
```bash
cast send $HOST_EARNINGS_ADDRESS \
  "setAuthorizedCaller(address,bool)" \
  $NEW_MARKETPLACE_ADDRESS true \
  --private-key $OWNER_KEY \
  --rpc-url $RPC_URL
```

2. **Configure USDC**
```bash
cast send $MARKETPLACE_ADDRESS \
  "setAcceptedToken(address,bool,uint256)" \
  $USDC_ADDRESS true 800000 \
  --private-key $OWNER_KEY \
  --rpc-url $RPC_URL
```

3. **Set ProofSystem**
```bash
cast send $MARKETPLACE_ADDRESS \
  "setProofSystem(address)" \
  $PROOF_SYSTEM_ADDRESS \
  --private-key $OWNER_KEY \
  --rpc-url $RPC_URL
```

## 🔧 Client Configuration

```javascript
const CONTRACTS = {
  // Core Contracts (LATEST - Jan 14, 2025)
  jobMarketplace: '0xc5BACFC1d4399c161034bca106657c0e9A528256',
  proofSystem: '0x2ACcc60893872A499700908889B38C5420CBcFD1',
  hostEarnings: '0x908962e8c6CE72610021586f85ebDE09aAc97776',
  nodeRegistry: '0x039AB5d5e8D5426f9963140202F506A2Ce6988F9',
  
  // Tokens
  fabToken: '0xC78949004B4EB6dEf2D66e49Cd81231472612D62',
  usdcToken: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  
  // Platform
  treasury: '0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11',
  
  // Network
  chainId: 84532,
  rpcUrl: 'https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY'
};
```

## 💰 Economic Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Platform Fee | 10% (1000 basis points) | Treasury fee on all payments |
| Min ETH Deposit | 0.0002 ETH | Minimum for ETH sessions |
| Min USDC Deposit | 0.8 USDC | Minimum for USDC sessions |
| Min Proven Tokens | 10 | Minimum per proof submission |
| Min Stake | 1000 FAB | Required for host registration |
| Abandonment Timeout | 7 days | Inactivity before abandonment |
| Dispute Window | 1 day | Time to dispute after completion |

## 🏗️ Architecture Overview

### Payment Flow
```
User → JobMarketplace → HostEarnings/Treasury
```

### Session Job Lifecycle
1. **Create**: User deposits ETH/USDC for session
2. **Active**: Host processes requests
3. **Proof**: Host submits EZKL proofs
4. **Complete**: Host claims payment or user finalizes
5. **Settled**: Payments distributed

### Key Features
- ✅ Gas-optimized with accumulation patterns
- ✅ Multi-token support (ETH, USDC)
- ✅ EZKL proof verification
- ✅ FAB token staking for hosts
- ✅ Treasury fee accumulation
- ✅ Host earnings accumulation

## 📊 Deployment Costs

| Operation | Gas Used | Cost (ETH) |
|-----------|----------|------------|
| Deploy JobMarketplace | ~4,000,000 | ~0.004 |
| Deploy ProofSystem | ~2,000,000 | ~0.002 |
| Deploy HostEarnings | ~1,500,000 | ~0.0015 |
| Total Deployment | ~7,500,000 | ~0.0075 |

## 🔍 Verification Links

- JobMarketplace: [View on BaseScan](https://sepolia.basescan.org/address/0xc5BACFC1d4399c161034bca106657c0e9A528256)
- ProofSystem: [View on BaseScan](https://sepolia.basescan.org/address/0x2ACcc60893872A499700908889B38C5420CBcFD1)
- HostEarnings: [View on BaseScan](https://sepolia.basescan.org/address/0x908962e8c6CE72610021586f85ebDE09aAc97776)
- NodeRegistry: [View on BaseScan](https://sepolia.basescan.org/address/0x039AB5d5e8D5426f9963140202F506A2Ce6988F9)

## ⚠️ Previous Deployments (Deprecated)

| Date | Address | Issue |
|------|---------|-------|
| Jan 9, 2025 | `0x6b4D28bD09Ba31394972B55E8870CFD4F835Acb6` | Jobs mapping bug |
| Jan 5, 2025 | `0x55A702Ab5034810F5B9720Fe15f83CFcf914F56b` | Wrong NodeRegistry |
| Sept 4, 2024 | `0x9A945fFBe786881AaD92C462Ad0bd8aC177A8069` | No accumulation |
| Sept 4, 2024 | `0xEB646BF2323a441698B256623F858c8787d70f9F` | Treasury not initialized |

## 🚀 Quick Start

1. **Clone Repository**
```bash
git clone <repo-url>
cd fabstir-contracts
```

2. **Install Dependencies**
```bash
npm install
forge install
```

3. **Configure Environment**
```bash
cp .env.example .env
# Add your private keys and RPC URLs
```

4. **Run Tests**
```bash
forge test
```

5. **Deploy**
```bash
./scripts/deploy.sh
```

## 📝 Notes

- Always verify contracts on BaseScan after deployment
- Test on testnet before mainnet deployment
- Ensure HostEarnings authorization before using new marketplace
- Keep private keys secure and never commit them

---

*For detailed integration guide, see [SESSION_JOB_COMPLETION_GUIDE.md](./SESSION_JOB_COMPLETION_GUIDE.md)*