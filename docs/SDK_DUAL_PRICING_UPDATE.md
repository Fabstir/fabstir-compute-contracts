# SDK Dual Pricing System Update - Integration Guide

**Last Updated**: January 28, 2025
**Status**: ✅ DEPLOYED TO BASE SEPOLIA

## Overview

The Fabstir Marketplace has been updated with a **corrected dual pricing system** that supports separate pricing for native tokens (ETH/BNB) and stablecoins (USDC). This guide helps SDK developers integrate the new pricing system correctly.

## What Changed

### Critical Fix: 10,000x Price Range

**Previous Issue**: MAX_PRICE values only had 10x multiplier instead of 10,000x
**Resolution**: Both native and stable pricing now properly support 10,000x range

### New Contract Addresses

| Contract | Address | Changes |
|----------|---------|---------|
| **NodeRegistryWithModels** | `0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6` | ✅ Corrected dual pricing ranges |
| **JobMarketplaceWithModels** | `0xe169A4B57700080725f9553E3Cc69885fea13629` | ✅ Validates against corrected ranges |

### Pricing Ranges (Corrected)

| Pricing Type | Minimum | Maximum | Range |
|--------------|---------|---------|-------|
| **Native (ETH)** | 2,272,727,273 wei | 22,727,272,727,273 wei | 10,000x |
| **Stable (USDC)** | 10 | 100,000 | 10,000x |

**USD Equivalent** (@ $4400 ETH):
- Native: ~$0.00001 to $0.1 per token
- Stable: $0.00001 to $0.1 per token

---

## Integration Guide

### 1. Update Contract Addresses in SDK

Update your SDK configuration with the new contract addresses:

```typescript
// sdk/config/contracts.ts
export const CONTRACTS = {
  nodeRegistry: '0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6', // NEW
  jobMarketplace: '0xe169A4B57700080725f9553E3Cc69885fea13629', // NEW
  modelRegistry: '0x92b2De840bB2171203011A6dBA928d855cA8183E',
  proofSystem: '0x2ACcc60893872A499700908889B38C5420CBcFD1',
  hostEarnings: '0x908962e8c6CE72610021586f85ebDE09aAc97776',
  usdc: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  fab: '0xC78949004B4EB6dEf2D66e49Cd81231472612D62'
};
```

### 2. Update ABIs

The NodeRegistry ABI now includes dual pricing fields:

```typescript
// Update your ABI imports
import NodeRegistryABI from './abis/NodeRegistryWithModels-CLIENT-ABI.json';
import JobMarketplaceABI from './abis/JobMarketplaceWithModels-CLIENT-ABI.json';
```

**New ABI Functions**:
```solidity
// Query dual pricing (returns tuple)
function getNodePricing(address node)
    external view
    returns (uint256 minPricePerTokenNative, uint256 minPricePerTokenStable)

// Update native pricing
function updatePricingNative(uint256 newMinPricePerTokenNative) external

// Update stable pricing
function updatePricingStable(uint256 newMinPricePerTokenStable) external

// Get full node info (8 fields now, not 7!)
function getNodeFullInfo(address node)
    external view
    returns (
        address operator,
        string memory endpoint,
        bool active,
        uint256 stakedAmount,
        string[] memory supportedModels,
        uint256 totalJobsCompleted,
        uint256 minPricePerTokenNative,  // NEW
        uint256 minPricePerTokenStable   // NEW
    )
```

### 3. Query Host Pricing Before Creating Sessions

**CRITICAL**: Always query dual pricing before creating sessions to avoid transaction reverts.

```typescript
// sdk/pricing.ts
import { ethers } from 'ethers';

export async function getHostPricing(
  nodeRegistryContract: ethers.Contract,
  hostAddress: string
): Promise<{ nativePrice: bigint; stablePrice: bigint }> {
  try {
    // Query dual pricing (returns tuple)
    const [nativePrice, stablePrice] = await nodeRegistryContract.getNodePricing(hostAddress);

    return {
      nativePrice: BigInt(nativePrice.toString()),
      stablePrice: BigInt(stablePrice.toString())
    };
  } catch (error) {
    throw new Error(`Failed to query host pricing: ${error.message}`);
  }
}
```

### 4. Create ETH Sessions with Native Pricing

```typescript
// sdk/sessions.ts
export async function createETHSession(
  marketplaceContract: ethers.Contract,
  nodeRegistryContract: ethers.Contract,
  hostAddress: string,
  depositETH: bigint,
  maxDuration: number,
  proofInterval: number
): Promise<string> {

  // STEP 1: Query host's dual pricing
  const { nativePrice, stablePrice } = await getHostPricing(
    nodeRegistryContract,
    hostAddress
  );

  console.log(`Host native minimum: ${nativePrice.toString()} wei`);
  console.log(`Host stable minimum: ${stablePrice.toString()}`);

  // STEP 2: Ensure your price meets or exceeds host's native minimum
  const yourPricePerToken = nativePrice; // Or higher if you want

  // STEP 3: Create ETH session
  // This will REVERT if yourPricePerToken < nativePrice
  const tx = await marketplaceContract.createSessionJob(
    hostAddress,
    yourPricePerToken,
    maxDuration,
    proofInterval,
    { value: depositETH }
  );

  const receipt = await tx.wait();
  const jobId = receipt.events?.find(e => e.event === 'SessionJobCreated')?.args?.jobId;

  return jobId.toString();
}
```

### 5. Create USDC Sessions with Stable Pricing

```typescript
export async function createUSDCSession(
  marketplaceContract: ethers.Contract,
  nodeRegistryContract: ethers.Contract,
  usdcContract: ethers.Contract,
  hostAddress: string,
  depositUSDC: bigint,
  maxDuration: number,
  proofInterval: number
): Promise<string> {

  // STEP 1: Query host's dual pricing
  const { nativePrice, stablePrice } = await getHostPricing(
    nodeRegistryContract,
    hostAddress
  );

  console.log(`Host stable minimum: ${stablePrice.toString()}`);

  // STEP 2: Ensure your price meets or exceeds host's stable minimum
  const yourPricePerToken = stablePrice; // Or higher if you want

  // STEP 3: Approve USDC first
  const approveTx = await usdcContract.approve(
    marketplaceContract.address,
    depositUSDC
  );
  await approveTx.wait();

  // STEP 4: Create USDC session
  // This will REVERT if yourPricePerToken < stablePrice
  const tx = await marketplaceContract.createSessionJobWithToken(
    hostAddress,
    usdcContract.address,
    depositUSDC,
    yourPricePerToken,
    maxDuration,
    proofInterval
  );

  const receipt = await tx.wait();
  const jobId = receipt.events?.find(e => e.event === 'SessionJobCreated')?.args?.jobId;

  return jobId.toString();
}
```

### 6. Host: Update Pricing

Hosts can update their pricing independently for native and stable tokens:

```typescript
// sdk/host.ts
export async function updateHostNativePricing(
  nodeRegistryContract: ethers.Contract,
  newMinPriceNative: bigint
): Promise<void> {
  // Validate range: 2,272,727,273 to 22,727,272,727,273 wei
  const MIN = BigInt('2272727273');
  const MAX = BigInt('22727272727273');

  if (newMinPriceNative < MIN || newMinPriceNative > MAX) {
    throw new Error(`Native price must be between ${MIN} and ${MAX} wei`);
  }

  const tx = await nodeRegistryContract.updatePricingNative(newMinPriceNative);
  await tx.wait();
}

export async function updateHostStablePricing(
  nodeRegistryContract: ethers.Contract,
  newMinPriceStable: number
): Promise<void> {
  // Validate range: 10 to 100,000
  const MIN = 10;
  const MAX = 100000;

  if (newMinPriceStable < MIN || newMinPriceStable > MAX) {
    throw new Error(`Stable price must be between ${MIN} and ${MAX}`);
  }

  const tx = await nodeRegistryContract.updatePricingStable(newMinPriceStable);
  await tx.wait();
}
```

---

## Error Handling

### Common Errors and Solutions

#### 1. "Price below host minimum (native)"

**Cause**: Your `pricePerToken` is less than the host's `minPricePerTokenNative` for an ETH session.

**Solution**:
```typescript
// Query pricing first
const { nativePrice } = await getHostPricing(nodeRegistry, hostAddress);

// Ensure your price >= host's minimum
const myPrice = nativePrice; // Or higher
```

#### 2. "Price below host minimum (stable)"

**Cause**: Your `pricePerToken` is less than the host's `minPricePerTokenStable` for a USDC session.

**Solution**:
```typescript
// Query pricing first
const { stablePrice } = await getHostPricing(nodeRegistry, hostAddress);

// Ensure your price >= host's minimum
const myPrice = stablePrice; // Or higher
```

#### 3. "Price exceeds maximum"

**Cause**: Your price is outside the allowed range.

**Ranges**:
- Native: 2,272,727,273 to 22,727,272,727,273 wei
- Stable: 10 to 100,000

#### 4. Wrong number of return values from getNodeFullInfo()

**Cause**: Contract now returns **8 fields** instead of 7.

**Solution**:
```typescript
// CORRECT (8 fields)
const [
  operator,
  endpoint,
  active,
  stakedAmount,
  supportedModels,
  totalJobsCompleted,
  minPriceNative,   // NEW
  minPriceStable    // NEW
] = await nodeRegistry.getNodeFullInfo(hostAddress);
```

---

## Testing Your Integration

### 1. Test Dual Pricing Queries

```typescript
import { expect } from 'chai';

describe('Dual Pricing Integration', () => {
  it('should query dual pricing correctly', async () => {
    const { nativePrice, stablePrice } = await getHostPricing(
      nodeRegistry,
      testHostAddress
    );

    expect(nativePrice).to.be.gte(BigInt('2272727273'));
    expect(nativePrice).to.be.lte(BigInt('22727272727273'));
    expect(stablePrice).to.be.gte(10);
    expect(stablePrice).to.be.lte(100000);
  });
});
```

### 2. Test ETH Session Creation

```typescript
it('should create ETH session with valid native pricing', async () => {
  const { nativePrice } = await getHostPricing(nodeRegistry, hostAddress);

  const depositETH = ethers.utils.parseEther('0.1');
  const jobId = await createETHSession(
    marketplace,
    nodeRegistry,
    hostAddress,
    depositETH,
    3600,
    100
  );

  expect(jobId).to.exist;
});

it('should revert ETH session with price below minimum', async () => {
  const { nativePrice } = await getHostPricing(nodeRegistry, hostAddress);
  const tooLowPrice = nativePrice - BigInt(1);

  await expect(
    marketplace.createSessionJob(
      hostAddress,
      tooLowPrice,
      3600,
      100,
      { value: ethers.utils.parseEther('0.1') }
    )
  ).to.be.revertedWith('Price below host minimum (native)');
});
```

### 3. Test USDC Session Creation

```typescript
it('should create USDC session with valid stable pricing', async () => {
  const { stablePrice } = await getHostPricing(nodeRegistry, hostAddress);

  const depositUSDC = ethers.utils.parseUnits('10', 6);
  const jobId = await createUSDCSession(
    marketplace,
    nodeRegistry,
    usdc,
    hostAddress,
    depositUSDC,
    3600,
    100
  );

  expect(jobId).to.exist;
});

it('should revert USDC session with price below minimum', async () => {
  const { stablePrice } = await getHostPricing(nodeRegistry, hostAddress);
  const tooLowPrice = stablePrice - 1;

  await expect(
    marketplace.createSessionJobWithToken(
      hostAddress,
      usdc.address,
      ethers.utils.parseUnits('10', 6),
      tooLowPrice,
      3600,
      100
    )
  ).to.be.revertedWith('Price below host minimum (stable)');
});
```

---

## Migration Checklist

### For SDK Developers

- [ ] Update contract addresses in configuration
- [ ] Update NodeRegistry and JobMarketplace ABIs
- [ ] Implement `getHostPricing()` function to query dual pricing
- [ ] Update `createETHSession()` to validate against native pricing
- [ ] Update `createUSDCSession()` to validate against stable pricing
- [ ] Handle 8-field return from `getNodeFullInfo()` (not 7)
- [ ] Update error handling for new error messages
- [ ] Add pricing range validation
- [ ] Write tests for dual pricing queries
- [ ] Write tests for session creation with both pricing types
- [ ] Update documentation with dual pricing examples

### For Host Operators

- [ ] Update to new NodeRegistry contract address
- [ ] Set native pricing via `updatePricingNative()`
- [ ] Set stable pricing via `updatePricingStable()`
- [ ] Monitor ETH price to adjust native pricing
- [ ] Consider gas costs when setting native pricing
- [ ] Test session creation with both ETH and USDC

### For Client Applications

- [ ] Update contract ABIs in frontend
- [ ] Query and display both native and stable pricing to users
- [ ] Allow users to choose payment method (ETH vs USDC)
- [ ] Show USD equivalent for native pricing (based on current ETH price)
- [ ] Handle validation errors gracefully with user-friendly messages

---

## Best Practices

### 1. Always Query Pricing First

```typescript
// ❌ WRONG - Don't assume pricing
const tx = await marketplace.createSessionJob(
  host,
  someHardcodedPrice, // This will likely revert!
  ...
);

// ✅ CORRECT - Query pricing first
const { nativePrice } = await getHostPricing(nodeRegistry, host);
const tx = await marketplace.createSessionJob(
  host,
  nativePrice, // Guaranteed to work
  ...
);
```

### 2. Handle Both Pricing Types

```typescript
interface HostPricing {
  nativePrice: bigint;   // For ETH sessions
  stablePrice: bigint;   // For USDC sessions
  ethPriceUSD?: number;  // Optional: for USD conversion
}

// Always return both prices
async function getHostPricingWithUSD(
  nodeRegistry: Contract,
  host: string,
  ethPriceUSD: number
): Promise<HostPricing> {
  const [nativePrice, stablePrice] = await nodeRegistry.getNodePricing(host);

  return {
    nativePrice: BigInt(nativePrice.toString()),
    stablePrice: BigInt(stablePrice.toString()),
    ethPriceUSD
  };
}
```

### 3. Validate Pricing Ranges

```typescript
export const PRICING_RANGES = {
  native: {
    min: BigInt('2272727273'),
    max: BigInt('22727272727273')
  },
  stable: {
    min: 10,
    max: 100000
  }
};

export function validateNativePrice(price: bigint): void {
  if (price < PRICING_RANGES.native.min || price > PRICING_RANGES.native.max) {
    throw new Error(
      `Native price must be between ${PRICING_RANGES.native.min} and ${PRICING_RANGES.native.max} wei`
    );
  }
}

export function validateStablePrice(price: number): void {
  if (price < PRICING_RANGES.stable.min || price > PRICING_RANGES.stable.max) {
    throw new Error(
      `Stable price must be between ${PRICING_RANGES.stable.min} and ${PRICING_RANGES.stable.max}`
    );
  }
}
```

### 4. Cache Pricing Data (with TTL)

```typescript
interface CachedPricing {
  nativePrice: bigint;
  stablePrice: bigint;
  timestamp: number;
}

const pricingCache = new Map<string, CachedPricing>();
const CACHE_TTL = 60000; // 1 minute

export async function getCachedHostPricing(
  nodeRegistry: Contract,
  host: string
): Promise<{ nativePrice: bigint; stablePrice: bigint }> {
  const cached = pricingCache.get(host);
  const now = Date.now();

  if (cached && (now - cached.timestamp) < CACHE_TTL) {
    return { nativePrice: cached.nativePrice, stablePrice: cached.stablePrice };
  }

  const [nativePrice, stablePrice] = await nodeRegistry.getNodePricing(host);

  pricingCache.set(host, {
    nativePrice: BigInt(nativePrice.toString()),
    stablePrice: BigInt(stablePrice.toString()),
    timestamp: now
  });

  return {
    nativePrice: BigInt(nativePrice.toString()),
    stablePrice: BigInt(stablePrice.toString())
  };
}
```

---

## Complete Example: SDK Integration

Here's a complete example showing how to integrate dual pricing into your SDK:

```typescript
// sdk/marketplace.ts
import { ethers } from 'ethers';
import NodeRegistryABI from './abis/NodeRegistryWithModels-CLIENT-ABI.json';
import JobMarketplaceABI from './abis/JobMarketplaceWithModels-CLIENT-ABI.json';
import USDCABI from './abis/USDC-ABI.json';

export class FabstirMarketplaceSDK {
  private nodeRegistry: ethers.Contract;
  private marketplace: ethers.Contract;
  private usdc: ethers.Contract;
  private signer: ethers.Signer;

  constructor(signer: ethers.Signer) {
    this.signer = signer;

    this.nodeRegistry = new ethers.Contract(
      '0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6',
      NodeRegistryABI,
      signer
    );

    this.marketplace = new ethers.Contract(
      '0xe169A4B57700080725f9553E3Cc69885fea13629',
      JobMarketplaceABI,
      signer
    );

    this.usdc = new ethers.Contract(
      '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
      USDCABI,
      signer
    );
  }

  /**
   * Query host's dual pricing
   */
  async getHostPricing(hostAddress: string): Promise<{
    nativePrice: bigint;
    stablePrice: bigint;
  }> {
    const [nativePrice, stablePrice] = await this.nodeRegistry.getNodePricing(hostAddress);

    return {
      nativePrice: BigInt(nativePrice.toString()),
      stablePrice: BigInt(stablePrice.toString())
    };
  }

  /**
   * Create ETH session
   */
  async createETHSession(
    hostAddress: string,
    depositETH: string, // e.g., "0.1" for 0.1 ETH
    maxDurationSeconds: number,
    proofIntervalTokens: number
  ): Promise<string> {
    // Query host's native pricing
    const { nativePrice } = await this.getHostPricing(hostAddress);

    // Create session
    const deposit = ethers.utils.parseEther(depositETH);
    const tx = await this.marketplace.createSessionJob(
      hostAddress,
      nativePrice,
      maxDurationSeconds,
      proofIntervalTokens,
      { value: deposit }
    );

    const receipt = await tx.wait();
    const event = receipt.events?.find(e => e.event === 'SessionJobCreated');

    return event?.args?.jobId.toString();
  }

  /**
   * Create USDC session
   */
  async createUSDCSession(
    hostAddress: string,
    depositUSDC: string, // e.g., "10" for 10 USDC
    maxDurationSeconds: number,
    proofIntervalTokens: number
  ): Promise<string> {
    // Query host's stable pricing
    const { stablePrice } = await this.getHostPricing(hostAddress);

    // Approve USDC
    const deposit = ethers.utils.parseUnits(depositUSDC, 6);
    const approveTx = await this.usdc.approve(this.marketplace.address, deposit);
    await approveTx.wait();

    // Create session
    const tx = await this.marketplace.createSessionJobWithToken(
      hostAddress,
      this.usdc.address,
      deposit,
      stablePrice,
      maxDurationSeconds,
      proofIntervalTokens
    );

    const receipt = await tx.wait();
    const event = receipt.events?.find(e => e.event === 'SessionJobCreated');

    return event?.args?.jobId.toString();
  }
}

// Usage example
async function example() {
  const provider = new ethers.providers.JsonRpcProvider('https://sepolia.base.org');
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

  const sdk = new FabstirMarketplaceSDK(wallet);

  const hostAddress = '0x...';

  // Check host pricing
  const pricing = await sdk.getHostPricing(hostAddress);
  console.log(`Native: ${pricing.nativePrice} wei`);
  console.log(`Stable: ${pricing.stablePrice}`);

  // Create ETH session
  const jobId1 = await sdk.createETHSession(hostAddress, '0.1', 3600, 100);
  console.log(`Created ETH session: ${jobId1}`);

  // Create USDC session
  const jobId2 = await sdk.createUSDCSession(hostAddress, '10', 3600, 100);
  console.log(`Created USDC session: ${jobId2}`);
}
```

---

## Troubleshooting

### Issue: Getting "undefined" from getNodePricing()

**Cause**: Wrong contract address or ABI

**Solution**:
- Verify you're using `0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6`
- Ensure you have the latest ABI with dual pricing functions

### Issue: Transaction reverts with no error message

**Cause**: Likely a pricing validation failure

**Solution**:
```typescript
try {
  const tx = await marketplace.createSessionJob(...);
  await tx.wait();
} catch (error) {
  console.error('Transaction failed:', error);

  // Query pricing to debug
  const pricing = await getHostPricing(nodeRegistry, hostAddress);
  console.log('Host requires:', pricing);
  console.log('You provided:', yourPricePerToken);
}
```

### Issue: Getting 7 fields instead of 8 from getNodeFullInfo()

**Cause**: Old ABI cached

**Solution**:
- Clear your build cache
- Re-download the latest ABI from `client-abis/NodeRegistryWithModels-CLIENT-ABI.json`

---

## Additional Resources

- **Contract Source Code**: `/workspace/src/NodeRegistryWithModels.sol`
- **Contract Tests**: `/workspace/test/NodeRegistry/test_dual_pricing.t.sol`
- **JobMarketplace Docs**: `/workspace/docs/technical/contracts/JobMarketplace.md`
- **NodeRegistry Docs**: `/workspace/docs/technical/contracts/NodeRegistry.md`
- **Contract Addresses**: `/workspace/CONTRACT_ADDRESSES.md`
- **Client ABIs**: `/workspace/client-abis/README.md`

## Support

For questions or issues:
1. Check the contract documentation in `/workspace/docs/technical/contracts/`
2. Review test files in `/workspace/test/` for usage examples
3. Verify contract addresses in `CONTRACT_ADDRESSES.md`
4. Check ABIs in `/workspace/client-abis/`

---

**Remember**: Always query dual pricing before creating sessions to avoid transaction reverts!
