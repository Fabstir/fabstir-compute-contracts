#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1

# Deploy new JobMarketplace with USDC session support
# This script deploys ProofSystem and JobMarketplaceFABWithS5

set -e

echo "🚀 Deploying new JobMarketplace with USDC session support..."
echo ""

# Configuration
NETWORK="base-sepolia"
RPC_URL="https://sepolia.base.org"

# Existing contracts to reuse
NODE_REGISTRY="0x87516C13Ea2f99de598665e14cab64E191A0f8c4"
TREASURY="0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078"
PAYMENT_ESCROW="0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C"
HOST_EARNINGS="0x0000000000000000000000000000000000000000" # Optional, using zero address
USDC_ADDRESS="0x036CbD53842c5426634e7929541eC2318f3dCF7e"

echo "📦 Compiling contracts..."
forge build

echo ""
echo "🔧 Deploying ProofSystem..."
PROOF_SYSTEM=$(forge create src/ProofSystem.sol:ProofSystem \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --json | jq -r '.deployedTo')

echo "✅ ProofSystem deployed to: $PROOF_SYSTEM"

echo ""
echo "🏪 Deploying JobMarketplaceFABWithS5..."
MARKETPLACE=$(forge create src/JobMarketplaceFABWithS5.sol:JobMarketplaceFABWithS5 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $NODE_REGISTRY $PROOF_SYSTEM $HOST_EARNINGS $TREASURY \
    --json | jq -r '.deployedTo')

echo "✅ JobMarketplaceFABWithS5 deployed to: $MARKETPLACE"

echo ""
echo "⚙️ Configuring USDC address..."
cast send $MARKETPLACE "setUsdcAddress(address)" $USDC_ADDRESS \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

echo "✅ USDC configured"

echo ""
echo "⚙️ Configuring PaymentEscrow (for legacy jobs)..."
cast send $MARKETPLACE "setPaymentEscrow(address)" $PAYMENT_ESCROW \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

echo "✅ PaymentEscrow configured"

echo ""
echo "========================================="
echo "🎉 DEPLOYMENT COMPLETE!"
echo "========================================="
echo ""
echo "📍 Contract Addresses:"
echo "  ProofSystem:              $PROOF_SYSTEM"
echo "  JobMarketplaceFABWithS5:  $MARKETPLACE"
echo ""
echo "📍 Configuration:"
echo "  NodeRegistry:    $NODE_REGISTRY"
echo "  Treasury:        $TREASURY"
echo "  USDC:            $USDC_ADDRESS"
echo "  PaymentEscrow:   $PAYMENT_ESCROW"
echo ""
echo "🔧 Update your client configuration with:"
echo "  jobMarketplace: '$MARKETPLACE'"
echo "  proofSystem: '$PROOF_SYSTEM'"
echo ""
echo "✨ Test with:"
echo "  cast call $MARKETPLACE 'nextSessionId()' --rpc-url $RPC_URL"
echo ""