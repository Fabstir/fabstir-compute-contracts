#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1

# Setup script for enabling HostEarnings accumulation pattern
# This configures the JobMarketplace to use HostEarnings for gas-efficient payments

set -e

# Contract addresses (Base Sepolia)
MARKETPLACE="0xD937c594682Fe74E6e3d06239719805C04BE804A"
HOST_EARNINGS="0xcbD91249cC8A7634a88d437Eaa083496C459Ef4E"

echo "=== Setting up HostEarnings Integration ==="
echo "Marketplace: $MARKETPLACE"
echo "HostEarnings: $HOST_EARNINGS"
echo ""

# Step 1: Set HostEarnings address in JobMarketplace
echo "Step 1: Setting HostEarnings address in JobMarketplace..."
cast send $MARKETPLACE \
  "setHostEarnings(address)" \
  $HOST_EARNINGS \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY

echo "✓ HostEarnings address set"

# Step 2: Authorize JobMarketplace to credit earnings
echo ""
echo "Step 2: Authorizing JobMarketplace in HostEarnings contract..."
cast send $HOST_EARNINGS \
  "setAuthorizedCaller(address,bool)" \
  $MARKETPLACE \
  true \
  --rpc-url https://sepolia.base.org \
  --private-key $PRIVATE_KEY

echo "✓ JobMarketplace authorized to credit earnings"

# Step 3: Verify the setup
echo ""
echo "Step 3: Verifying setup..."

# Check if HostEarnings is set in marketplace
HOST_EARNINGS_CHECK=$(cast call $MARKETPLACE "hostEarnings()(address)" --rpc-url https://sepolia.base.org)
echo "HostEarnings in Marketplace: $HOST_EARNINGS_CHECK"

# Check if marketplace is authorized
IS_AUTHORIZED=$(cast call $HOST_EARNINGS "authorizedCallers(address)(bool)" $MARKETPLACE --rpc-url https://sepolia.base.org)
echo "Marketplace authorized: $IS_AUTHORIZED"

if [ "$HOST_EARNINGS_CHECK" = "$HOST_EARNINGS" ] && [ "$IS_AUTHORIZED" = "true" ]; then
  echo ""
  echo "✅ HostEarnings integration successfully configured!"
  echo ""
  echo "Benefits enabled:"
  echo "- Host payments now accumulate in HostEarnings contract"
  echo "- Hosts can batch withdraw multiple payments in one transaction"
  echo "- Significant gas savings for hosts completing multiple jobs"
  echo ""
  echo "Hosts can withdraw earnings by calling:"
  echo "- withdrawAll(address token) - withdraw all earnings for a token"
  echo "- withdraw(uint256 amount, address token) - withdraw specific amount"
  echo "- withdrawMultiple(address[] tokens) - withdraw multiple tokens at once"
else
  echo ""
  echo "❌ Setup verification failed!"
  exit 1
fi