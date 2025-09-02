#!/bin/bash

# Deploy Fixed JobMarketplace with Payment Distribution Fixes
# This script deploys a new JobMarketplace contract that fixes the payment distribution issue

set -e

echo "========================================="
echo "Deploying Fixed JobMarketplace Contract"
echo "========================================="

# Load environment variables from .env if it exists
if [ -f .env ]; then
    source .env
fi

# Check required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set"
    echo "Please set PRIVATE_KEY in .env file or environment"
    exit 1
fi

# Set network-specific variables based on chain
CHAIN_ID=${CHAIN_ID:-84532}  # Default to Base Sepolia

if [ "$CHAIN_ID" = "8453" ]; then
    # Base Mainnet
    echo "Deploying to Base Mainnet"
    RPC_URL=${RPC_URL:-"https://mainnet.base.org"}
    NODE_REGISTRY=${MAINNET_NODE_REGISTRY:-"0x0"}
    HOST_EARNINGS=${MAINNET_HOST_EARNINGS:-"0x0"}  # Optional, can be 0x0
    TREASURY=${MAINNET_TREASURY:-"0x0"}
    ETHERSCAN_API_KEY=${BASESCAN_API_KEY}
elif [ "$CHAIN_ID" = "84532" ]; then
    # Base Sepolia (default)
    echo "Deploying to Base Sepolia"
    RPC_URL=${RPC_URL:-"https://sepolia.base.org"}
    # Use existing deployed contracts from CONTRACT_ADDRESSES.md
    NODE_REGISTRY=${TESTNET_NODE_REGISTRY:-"0x87516C13Ea2f99de598665e14cab64E191A0f8c4"}
    HOST_EARNINGS=${TESTNET_HOST_EARNINGS:-"0x0000000000000000000000000000000000000000"}  # Set to 0x0 since it's optional
    TREASURY=${TESTNET_TREASURY:-"0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078"}
    ETHERSCAN_API_KEY=${BASESCAN_API_KEY}
else
    echo "Unsupported chain ID: $CHAIN_ID"
    echo "Supported chains: 8453 (Base Mainnet), 84532 (Base Sepolia)"
    exit 1
fi

# Validate addresses
if [ "$NODE_REGISTRY" = "0x0" ] || [ -z "$NODE_REGISTRY" ]; then
    echo "Error: NODE_REGISTRY address not set"
    echo "Please set TESTNET_NODE_REGISTRY or MAINNET_NODE_REGISTRY in .env"
    exit 1
fi

if [ "$TREASURY" = "0x0" ] || [ -z "$TREASURY" ]; then
    echo "Error: TREASURY address not set"
    echo "Please set TESTNET_TREASURY or MAINNET_TREASURY in .env"
    exit 1
fi

echo "Configuration:"
echo "  Chain ID: $CHAIN_ID"
echo "  RPC URL: $RPC_URL"
echo "  Node Registry: $NODE_REGISTRY"
echo "  Host Earnings: $HOST_EARNINGS"
echo "  Treasury: $TREASURY"
echo ""

# Build contracts first
echo "Building contracts..."
forge build

# Run deployment script
echo "Deploying contracts..."
forge script script/DeploySessionJobs.s.sol:DeploySessionJobs \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    ${ETHERSCAN_API_KEY:+--etherscan-api-key $ETHERSCAN_API_KEY} \
    -vvvv

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "IMPORTANT: Update CONTRACT_ADDRESSES.md with the new addresses"
echo ""
echo "The new JobMarketplace includes these fixes:"
echo "1. ✅ Uses call{value:}() instead of transfer() for ETH payments"
echo "2. ✅ Emergency withdrawal functions for stuck funds"
echo "3. ✅ HostEarnings is optional (checks != address(0))"
echo "4. ✅ Treasury properly set during deployment"
echo ""
echo "To recover stuck funds from old contract:"
echo "1. Call emergencyWithdrawETH() on new contract if any ETH gets stuck"
echo "2. Only treasury or hostEarnings addresses can call emergency functions"
echo ""