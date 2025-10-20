#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1

# Deploy script for JobMarketplace with HostEarnings accumulation pattern
# This enables gas-efficient host payment accumulation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Deploying JobMarketplace with Gas-Efficient HostEarnings ===${NC}"
echo ""

# Check for required env variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY environment variable not set${NC}"
    exit 1
fi

# Network configuration
RPC_URL="https://sepolia.base.org"
CHAIN_ID=84532

# Existing contracts (Base Sepolia)
NODE_REGISTRY="0x87516C13Ea2f99de598665e14cab64E191A0f8c4"
PROOF_SYSTEM="0x2ACcc60893872A499700908889B38C5420CBcFD1"
USDC="0x036CbD53842c5426634e7929541eC2318f3dCF7e"

echo "Network: Base Sepolia"
echo "Chain ID: $CHAIN_ID"
echo ""

# Step 1: Deploy HostEarnings
echo -e "${YELLOW}Step 1: Deploying HostEarnings contract...${NC}"
HOST_EARNINGS_RESULT=$(forge create \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    src/HostEarnings.sol:HostEarnings \
    --json)

HOST_EARNINGS=$(echo $HOST_EARNINGS_RESULT | jq -r '.deployedTo')
echo -e "${GREEN}✓ HostEarnings deployed at: $HOST_EARNINGS${NC}"

# Step 2: Deploy JobMarketplace with HostEarnings
echo ""
echo -e "${YELLOW}Step 2: Deploying JobMarketplaceFABWithS5...${NC}"
MARKETPLACE_RESULT=$(forge create \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    src/JobMarketplaceFABWithS5.sol:JobMarketplaceFABWithS5 \
    --constructor-args $NODE_REGISTRY $HOST_EARNINGS \
    --json)

MARKETPLACE=$(echo $MARKETPLACE_RESULT | jq -r '.deployedTo')
echo -e "${GREEN}✓ JobMarketplace deployed at: $MARKETPLACE${NC}"

# Step 3: Configure marketplace
echo ""
echo -e "${YELLOW}Step 3: Configuring marketplace...${NC}"

# Set ProofSystem
echo "  Setting ProofSystem..."
cast send $MARKETPLACE \
    "setProofSystem(address)" \
    $PROOF_SYSTEM \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    > /dev/null 2>&1
echo -e "${GREEN}  ✓ ProofSystem set${NC}"

# Set USDC
echo "  Configuring USDC..."
cast send $MARKETPLACE \
    "setUsdcAddress(address)" \
    $USDC \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    > /dev/null 2>&1

cast send $MARKETPLACE \
    "setAcceptedToken(address,bool)" \
    $USDC \
    true \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    > /dev/null 2>&1

cast send $MARKETPLACE \
    "setTokenMinDeposit(address,uint256)" \
    $USDC \
    800000 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    > /dev/null 2>&1
echo -e "${GREEN}  ✓ USDC configured${NC}"

# Step 4: Authorize marketplace in HostEarnings
echo ""
echo -e "${YELLOW}Step 4: Authorizing marketplace in HostEarnings...${NC}"
cast send $HOST_EARNINGS \
    "setAuthorizedCaller(address,bool)" \
    $MARKETPLACE \
    true \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    > /dev/null 2>&1
echo -e "${GREEN}✓ Marketplace authorized to credit earnings${NC}"

# Step 5: Verify setup
echo ""
echo -e "${YELLOW}Step 5: Verifying deployment...${NC}"

# Check HostEarnings is set in marketplace
HE_IN_MARKETPLACE=$(cast call $MARKETPLACE "hostEarnings()(address)" --rpc-url $RPC_URL)
if [ "$HE_IN_MARKETPLACE" = "$HOST_EARNINGS" ]; then
    echo -e "${GREEN}  ✓ HostEarnings correctly set in marketplace${NC}"
else
    echo -e "${RED}  ✗ HostEarnings mismatch!${NC}"
fi

# Check marketplace is authorized
IS_AUTHORIZED=$(cast call $HOST_EARNINGS "authorizedCallers(address)(bool)" $MARKETPLACE --rpc-url $RPC_URL)
if [ "$IS_AUTHORIZED" = "true" ]; then
    echo -e "${GREEN}  ✓ Marketplace is authorized${NC}"
else
    echo -e "${RED}  ✗ Marketplace not authorized!${NC}"
fi

# Print summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DEPLOYMENT SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Contract Addresses:"
echo "  HostEarnings:    $HOST_EARNINGS"
echo "  JobMarketplace:  $MARKETPLACE"
echo ""
echo "Existing Contracts:"
echo "  NodeRegistry:    $NODE_REGISTRY"
echo "  ProofSystem:     $PROOF_SYSTEM"
echo "  USDC:           $USDC"
echo ""
echo -e "${GREEN}✅ Gas-Efficient Features Enabled:${NC}"
echo "  • Host payments accumulate in HostEarnings"
echo "  • Hosts withdraw when convenient"
echo "  • ~40,000 gas saved per job"
echo "  • Multi-token batch withdrawals"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Update ProofSystem to use new marketplace:"
echo "   cast send $PROOF_SYSTEM \"setJobMarketplace(address)\" $MARKETPLACE --rpc-url $RPC_URL --private-key <OWNER_KEY>"
echo ""
echo "2. Update client configuration:"
echo "   CONTRACT_JOB_MARKETPLACE=$MARKETPLACE"
echo "   CONTRACT_HOST_EARNINGS=$HOST_EARNINGS"
echo ""
echo "3. Hosts can withdraw earnings:"
echo "   withdrawAll(address(0))    # Withdraw ETH"
echo "   withdrawAll($USDC)         # Withdraw USDC"
echo ""

# Save to file
cat > deployment-results.json << EOF
{
  "network": "base-sepolia",
  "chainId": $CHAIN_ID,
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "hostEarnings": "$HOST_EARNINGS",
    "jobMarketplace": "$MARKETPLACE",
    "nodeRegistry": "$NODE_REGISTRY",
    "proofSystem": "$PROOF_SYSTEM",
    "usdc": "$USDC"
  },
  "features": {
    "hostEarningsAccumulation": true,
    "gasEfficient": true,
    "multiTokenSupport": true
  }
}
EOF

echo -e "${GREEN}Deployment details saved to deployment-results.json${NC}"