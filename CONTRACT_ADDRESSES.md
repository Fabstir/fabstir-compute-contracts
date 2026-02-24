# CONTRACT_ADDRESSES.md

**Last Updated:** February 22, 2026
**Network:** Base Sepolia (Chain ID: 84532)

---

## Active Contracts (Post-Audit Remediation - Feb 22, 2026)

> **USE THESE FOR SDK DEVELOPMENT.** All 20 audit findings addressed. Fresh JM proxy deployed for clean storage layout.

| Contract | Proxy Address | Implementation | Status |
|----------|---------------|----------------|--------|
| **JobMarketplaceWithModelsUpgradeable** | `0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4` | `0x51C3F60D2e3756Cc3F119f9aE1876e2B947347ba` | FRESH PROXY (Feb 22, 2026) |
| **ProofSystemUpgradeable** | `0xE8DCa89e1588bbbdc4F7D5F78263632B35401B31` | `0xC46C84a612Cbf4C2eAaf5A9D1411aDA6309EC963` | Upgraded (Feb 22, 2026) |
| **NodeRegistryWithModelsUpgradeable** | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | unchanged | Unchanged |
| **HostEarningsUpgradeable** | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | unchanged | Unchanged |
| **ModelRegistryUpgradeable** | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | `0xF12a0A07d4230E0b045dB22057433a9826d21652` | Upgraded (Feb 22, 2026) |

### Tokens (unchanged)

| Token | Address |
|-------|---------|
| USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| FAB | `0xC78949004B4EB6dEf2D66e49Cd81231472612D62` |

### Configuration (JavaScript)

```javascript
// Post-audit remediation addresses — Updated February 22, 2026
const CONTRACTS = {
  jobMarketplace: "0xD067719Ee4c514B5735d1aC0FfB46FECf2A9adA4",  // FRESH PROXY (Feb 22, 2026)
  proofSystem: "0xE8DCa89e1588bbbdc4F7D5F78263632B35401B31",
  nodeRegistry: "0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22",
  hostEarnings: "0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0",
  modelRegistry: "0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2",
  fabToken: "0xC78949004B4EB6dEf2D66e49Cd81231472612D62",
  usdcToken: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
};
```

---

## Previous Remediation Contracts (Feb 5, 2026 - DEPRECATED)

| Contract | Proxy Address | Status |
|----------|---------------|--------|
| **JobMarketplaceWithModelsUpgradeable** | `0x95132177F964FF053C1E874b53CF74d819618E06` | DEPRECATED — replaced by fresh proxy `0xD067...adA4` |

---

## Frozen Audit Contracts (January 2026 - DO NOT MODIFY)

> FROZEN FOR SECURITY AUDIT. Do not upgrade or modify these contracts.

| Contract | Proxy Address | Status |
|----------|---------------|--------|
| **JobMarketplaceWithModelsUpgradeable** | `0x3CaCbf3f448B420918A93a88706B26Ab27a3523E` | FROZEN |
| **NodeRegistryWithModelsUpgradeable** | `0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22` | FROZEN |
| **ModelRegistryUpgradeable** | `0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2` | FROZEN |
| **HostEarningsUpgradeable** | `0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0` | FROZEN |
| **ProofSystemUpgradeable** | `0x5afB91977e69Cc5003288849059bc62d47E7deeb` | FROZEN |

---

## Legacy Non-Upgradeable Contracts (December 10, 2025 - DEPRECATED)

| Contract | Address | Status |
|----------|---------|--------|
| JobMarketplaceWithModels | `0x75C72e8C3eC707D8beF5Ba9b9C4f75CbB5bced97` | DEPRECATED |
| NodeRegistryWithModels | `0x906F4A8Cb944E4fe12Fb85Be7E627CeDAA8B8999` | DEPRECATED |
| ModelRegistry | `0x92b2De840bB2171203011A6dBA928d855cA8183E` | DEPRECATED |
| HostEarnings | `0x908962e8c6CE72610021586f85ebDE09aAc97776` | DEPRECATED |
| ProofSystem | `0x2ACcc60893872A499700908889B38C5420CBcFD1` | DEPRECATED |
