# Multi-Chain Deployment Guide

This guide covers deploying JobMarketplaceWithModels across multiple blockchain networks with proper configuration for each chain's native token.

## Supported Chains

### Currently Deployed
- **Base Sepolia** (Testnet) - ETH native token
  - Deployed: January 2025
  - Contract: `0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f`

### Planned Support
- **opBNB** (Post-MVP) - BNB native token
- **Base Mainnet** - ETH native token
- **opBNB Mainnet** - BNB native token

## Deployment Process

### Prerequisites

1. **Environment Setup**
```bash
# .env file configuration
PRIVATE_KEY=your_deployer_private_key
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
TREASURY_PRIVATE_KEY=treasury_wallet_private_key
```

2. **Required Contracts**
Before deploying JobMarketplaceWithModels, ensure these contracts are deployed:
- NodeRegistryWithModels
- HostEarnings
- ProofSystem
- ModelRegistry (with approved models)

### Step 1: Deploy JobMarketplaceWithModels

```bash
# Deploy to Base Sepolia
forge script script/DeployJobMarketplaceMultiChain.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

The deployment script will:
1. Deploy the JobMarketplaceWithModels contract
2. Output post-deployment configuration commands
3. Attempt to initialize ChainConfig (if permissions allow)

### Step 2: Post-Deployment Configuration

After deployment, the following configurations must be applied:

#### 2.1 Set ProofSystem (Treasury Only)
```bash
cast send <MARKETPLACE> "setProofSystem(address)" <PROOF_SYSTEM> \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $TREASURY_PRIVATE_KEY
```

#### 2.2 Authorize in HostEarnings
```bash
cast send <HOST_EARNINGS> "setAuthorizedCaller(address,bool)" <MARKETPLACE> true \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

#### 2.3 Initialize Chain Configuration
```bash
# For Base Sepolia (ETH)
cast send <MARKETPLACE> "initializeChainConfig((address,address,uint256,string))" \
  "(0x4200000000000000000000000000000000000006,0x036CbD53842c5426634e7929541eC2318f3dCF7e,200000000000000,\"ETH\")" \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

### Step 3: Verify Deployment

Run the verification script to ensure proper configuration:

```bash
MARKETPLACE_ADDRESS=<deployed_address> \
forge script script/deploy/MultiChain/VerifyContracts.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

Expected output:
- [OK] ProofSystem configured
- [OK] HostEarnings configured
- [OK] Marketplace authorized in HostEarnings
- [OK] ChainConfig verified
- [OK] Treasury configured
- [OK] Fee basis points configured

### Step 4: Test Basic Functionality

```bash
# Test native token deposit
cast send <MARKETPLACE> "depositNative()" \
  --value 0.001ether \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Check deposit balance
cast call <MARKETPLACE> "userDepositsNative(address)(uint256)" <YOUR_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Chain-Specific Configurations

### Base Sepolia (ETH)
```solidity
ChainConfig {
    nativeWrapper: 0x4200000000000000000000000000000000000006, // WETH
    stablecoin: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,    // USDC
    minDeposit: 0.0002 ether,
    nativeTokenSymbol: "ETH"
}
```

### opBNB Testnet (BNB) - Future
```solidity
ChainConfig {
    nativeWrapper: <WBNB_ADDRESS>,
    stablecoin: <USDC_ON_OPBNB>,
    minDeposit: 0.01 ether,  // Adjust for BNB value
    nativeTokenSymbol: "BNB"
}
```

## Important Addresses

### Base Sepolia Contracts
- **JobMarketplaceWithModels**: `0xaa38e7fcf5d7944ef7c836e8451f3bf93b98364f`
- **NodeRegistryWithModels**: `0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218`
- **ModelRegistry**: `0x92b2De840bB2171203011A6dBA928d855cA8183E`
- **HostEarnings**: `0x908962e8c6CE72610021586f85ebDE09aAc97776`
- **ProofSystem**: `0x2ACcc60893872A499700908889B38C5420CBcFD1`
- **Treasury**: `0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11`
- **WETH**: `0x4200000000000000000000000000000000000006`
- **USDC**: `0x036CbD53842c5426634e7929541eC2318f3dCF7e`

## Troubleshooting

### Common Issues

1. **"Only treasury" error during setProofSystem**
   - Solution: Use treasury wallet private key, not deployer key

2. **"Chain config already initialized" error**
   - Solution: Chain config can only be set once. Deploy new contract if changes needed.

3. **Verification script fails**
   - Ensure all post-deployment steps were completed
   - Check contract addresses are correct
   - Verify RPC URL is accessible

### Checking Configuration

```bash
# Check ProofSystem
cast call <MARKETPLACE> "proofSystem()" --rpc-url $BASE_SEPOLIA_RPC_URL

# Check ChainConfig
cast call <MARKETPLACE> "chainConfig()" --rpc-url $BASE_SEPOLIA_RPC_URL

# Check HostEarnings authorization
cast call <HOST_EARNINGS> "authorizedCallers(address)" <MARKETPLACE> --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Security Considerations

1. **Private Key Management**
   - Never commit private keys to version control
   - Use hardware wallets for mainnet deployments
   - Rotate keys regularly

2. **Access Control**
   - ProofSystem can only be set by treasury
   - ChainConfig can only be initialized once
   - HostEarnings authorization required for payment processing

3. **Verification**
   - Always verify contracts on block explorers
   - Run verification script after deployment
   - Test all critical functions before production use

## Next Steps

After successful deployment:

1. Register nodes in NodeRegistryWithModels
2. Add approved models to ModelRegistry (if not already done)
3. Test session creation and completion flows
4. Monitor contract events for activity
5. Set up monitoring and alerting systems

For SDK integration, see the [Wallet Agnostic Guide](./WALLET_AGNOSTIC_GUIDE.md).