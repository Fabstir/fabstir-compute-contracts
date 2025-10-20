#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1
set -a
source .env
set +a

echo "Deploying JobMarketplaceFABWithS5..."

# Deploy the contract
RESULT=$(forge create src/JobMarketplaceFABWithS5.sol:JobMarketplaceFABWithS5 \
    --rpc-url "$BASE_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --constructor-args "0x87516C13Ea2f99de598665e14cab64E191A0f8c4" "0xDfd6E9Bb2c39ed335FC5eFD18edD0C5B7aAF799f" \
    --legacy \
    --broadcast \
    2>&1)

# Extract the deployed address
DEPLOYED_ADDRESS=$(echo "$RESULT" | grep -A 1 "Deployed to:" | tail -1 | awk '{print $1}')

if [ -z "$DEPLOYED_ADDRESS" ]; then
    echo "Failed to deploy. Output:"
    echo "$RESULT"
else
    echo "Deployed to: $DEPLOYED_ADDRESS"
    
    # Configure USDC
    echo "Configuring USDC..."
    cast send "$DEPLOYED_ADDRESS" "setUsdcAddress(address)" "0x036CbD53842c5426634e7929541eC2318f3dCF7e" \
        --rpc-url "$BASE_SEPOLIA_RPC_URL" \
        --private-key "$PRIVATE_KEY"
    
    # Set payment escrow
    echo "Setting payment escrow..."
    cast send "$DEPLOYED_ADDRESS" "setPaymentEscrow(address)" "0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C" \
        --rpc-url "$BASE_SEPOLIA_RPC_URL" \
        --private-key "$PRIVATE_KEY"
    
    echo ""
    echo "✅ Deployment Complete!"
    echo "JobMarketplace: $DEPLOYED_ADDRESS"
fi