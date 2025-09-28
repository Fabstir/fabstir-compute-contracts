# Current Contract Addresses - Multi-Chain Support

Last Updated: January 28, 2025

## 🌐 Multi-Chain Deployment Status

| Chain | Network | Status | Native Token | Contract Address |
|-------|---------|--------|--------------|------------------|
| **Base** | Sepolia (Testnet) | ✅ DEPLOYED | ETH | `0xdEa1B47872C27458Bb7331Ade99099761C4944Dc` |
| **opBNB** | Testnet | ⏳ PLANNED | BNB | Post-MVP deployment |
| **Base** | Mainnet | ⏳ FUTURE | ETH | TBD |
| **opBNB** | Mainnet | ⏳ FUTURE | BNB | TBD |

> **🚀 LATEST DEPLOYMENT**: Multi-Chain Support & Bug Fixes
>
> - **JobMarketplaceWithModels**: `0xdEa1B47872C27458Bb7331Ade99099761C4944Dc` ✅ NEW - 30s dispute window, ETH/USDC deposit parity, native token naming (Jan 28, 2025)
> - **Features**: Configurable dispute window, removed 10x ETH multiplier, accumulatedTreasuryNative for multi-chain

## Active Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **JobMarketplaceWithModels** | `0xdEa1B47872C27458Bb7331Ade99099761C4944Dc` | ✅ NEW - Multi-chain native support, 30s dispute, ETH/USDC parity |
| **ModelRegistry** | `0x92b2De840bB2171203011A6dBA928d855cA8183E` | Model governance (2 approved models) |
| **NodeRegistryWithModels** | `0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218` | Host registration with model validation |
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
    jobMarketplace: "0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f", // Multi-chain support
    modelRegistry: "0x92b2De840bB2171203011A6dBA928d855cA8183E",
    nodeRegistry: "0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218",
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

## Deprecated Contracts

| Contract | Address | Description | Deprecated Date |
|----------|---------|-------------|-----------------|
| **JobMarketplaceWithModels** | `0x1273E6358aa52Bb5B160c34Bf2e617B745e4A944` | ⚠️ DEPRECATED - Replaced with multi-chain version | Jan 24, 2025 |

## Network Information

- **Network**: Base Sepolia
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org