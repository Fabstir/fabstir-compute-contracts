# Current Contract Addresses - Multi-Chain Support

Last Updated: January 28, 2025

## 🌐 Multi-Chain Deployment Status

| Chain | Network | Status | Native Token | Contract Address |
|-------|---------|--------|--------------|------------------|
| **Base** | Sepolia (Testnet) | ✅ DEPLOYED | ETH | `0xe169A4B57700080725f9553E3Cc69885fea13629` |
| **opBNB** | Testnet | ⏳ PLANNED | BNB | Post-MVP deployment |
| **Base** | Mainnet | ⏳ FUTURE | ETH | TBD |
| **opBNB** | Mainnet | ⏳ FUTURE | BNB | TBD |

> **🚀 LATEST DEPLOYMENT**: Corrected Dual Pricing (10,000x Range)
>
> - **NodeRegistryWithModels**: `0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6` ✅ NEW - Dual pricing with 10,000x range (Jan 28, 2025)
> - **JobMarketplaceWithModels**: `0xe169A4B57700080725f9553E3Cc69885fea13629` ✅ NEW - Validates corrected pricing ranges (Jan 28, 2025)
> - **Features**: Separate native/stable pricing, 10,000x range (MIN to MAX), Native: 2.27B-22.7T wei, Stable: 10-100,000, 8-field Node struct

## Active Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **JobMarketplaceWithModels** | `0xe169A4B57700080725f9553E3Cc69885fea13629` | ✅ NEW - Corrected dual pricing validation (10,000x range) |
| **NodeRegistryWithModels** | `0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6` | ✅ NEW - Dual pricing with 8-field struct, 10,000x range |
| **ModelRegistry** | `0x92b2De840bB2171203011A6dBA928d855cA8183E` | Model governance (2 approved models) |
| **ProofSystem** | `0x2ACcc60893872A499700908889B38C5420CBcFD1` | EZKL proof verification |
| **HostEarnings** | `0x908962e8c6CE72610021586f85ebDE09aAc97776` | Host earnings accumulation |

## Approved Models

| Model | HuggingFace Repo | File |
|-------|------------------|------|
| **TinyVicuna-1B** | CohereForAI/TinyVicuna-1B-32k-GGUF | tiny-vicuna-1b.q4_k_m.gguf |
| **TinyLlama-1.1B** | TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF | tinyllama-1b.Q4_K_M.gguf |

## Token Contracts

| Token | Address | Description |
|-------|---------|-------------|
| **FAB Token** | `0xC78949004B4EB6dEf2D66e49Cd81231472612D62` | Governance and staking |
| **USDC** | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` | Job payments |

## Platform Configuration

| Parameter | Value |
|-----------|-------|
| **Treasury** | `0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11` |
| **Treasury Fee** | Configurable via TREASURY_FEE_PERCENTAGE env var |
| **Min Stake** | 1000 FAB tokens |
| **Min Deposit (ETH)** | 0.0002 ETH |
| **Min Deposit (USDC)** | 0.80 USDC |

## Chain-Specific Configuration

### Base Sepolia (ETH)
```javascript
const baseSepoliaConfig = {
  chainId: 84532,
  nativeToken: "ETH",
  contracts: {
    jobMarketplace: "0xe169A4B57700080725f9553E3Cc69885fea13629", // Corrected dual pricing
    modelRegistry: "0x92b2De840bB2171203011A6dBA928d855cA8183E",
    nodeRegistry: "0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6", // 10,000x range dual pricing
    proofSystem: "0x2ACcc60893872A499700908889B38C5420CBcFD1",
    hostEarnings: "0x908962e8c6CE72610021586f85ebDE09aAc97776",
    fabToken: "0xC78949004B4EB6dEf2D66e49Cd81231472612D62",
    usdcToken: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    weth: "0x4200000000000000000000000000000000000006"
  },
  rpcUrl: "https://sepolia.base.org",
  explorer: "https://sepolia.basescan.org"
};
```

### opBNB Testnet (BNB) - Future Deployment
```javascript
const opBNBConfig = {
  chainId: 5611, // opBNB testnet
  nativeToken: "BNB",
  contracts: {
    // To be deployed post-MVP
    jobMarketplace: "TBD",
    // Supporting contracts will need deployment
  },
  rpcUrl: "https://opbnb-testnet-rpc.bnbchain.org",
  explorer: "https://testnet.opbnbscan.com"
};
```

## Network Information

- **Network**: Base Sepolia
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org