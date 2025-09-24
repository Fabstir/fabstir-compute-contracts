# Current Contract Addresses - Base Sepolia

Last Updated: January 24, 2025

## Active Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| **JobMarketplaceWithModels** | `0x1273E6358aa52Bb5B160c34Bf2e617B745e4A944` | Session jobs with model validation |
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

## Configuration Example

```javascript
const contracts = {
  jobMarketplace: "0x1273E6358aa52Bb5B160c34Bf2e617B745e4A944",
  modelRegistry: "0x92b2De840bB2171203011A6dBA928d855cA8183E",
  nodeRegistry: "0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218",
  proofSystem: "0x2ACcc60893872A499700908889B38C5420CBcFD1",
  hostEarnings: "0x908962e8c6CE72610021586f85ebDE09aAc97776",
  fabToken: "0xC78949004B4EB6dEf2D66e49Cd81231472612D62",
  usdcToken: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
};
```

## Network Information

- **Network**: Base Sepolia
- **Chain ID**: 84532
- **RPC URL**: https://sepolia.base.org
- **Block Explorer**: https://sepolia.basescan.org