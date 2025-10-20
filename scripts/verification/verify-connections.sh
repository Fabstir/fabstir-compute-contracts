#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1

# Source environment variables
source .env

echo "========================================="
echo "Verifying Contract Connections"
echo "========================================="
echo ""

# 1. Check NodeRegistry governance
echo "1. NodeRegistry Governance:"
GOVERNANCE_SET=$(cast call $NODE_REGISTRY_ADDRESS "getGovernance()(address)" --rpc-url $BASE_SEPOLIA_RPC_URL)
echo "   Expected: $GOVERNANCE_ADDRESS"
echo "   Actual:   $GOVERNANCE_SET"
if [ "$GOVERNANCE_SET" = "$GOVERNANCE_ADDRESS" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

# 2. Check JobMarketplace reputationSystem
echo "2. JobMarketplace ReputationSystem:"
REP_SYSTEM=$(cast call $JOB_MARKETPLACE_ADDRESS "reputationSystem()(address)" --rpc-url $BASE_SEPOLIA_RPC_URL)
echo "   Expected: $REPUTATION_SYSTEM_ADDRESS"
echo "   Actual:   $REP_SYSTEM"
if [ "$REP_SYSTEM" = "$REPUTATION_SYSTEM_ADDRESS" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

# 3. Check if JobMarketplace is authorized in ReputationSystem
echo "3. JobMarketplace authorized in ReputationSystem:"
IS_AUTHORIZED=$(cast call $REPUTATION_SYSTEM_ADDRESS "authorizedContracts(address)(bool)" $JOB_MARKETPLACE_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL)
echo "   Expected: true"
echo "   Actual:   $IS_AUTHORIZED"
if [ "$IS_AUTHORIZED" = "true" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

# 4. Check if JobMarketplace has verifier role in ProofSystem
echo "4. JobMarketplace has VERIFIER_ROLE in ProofSystem:"
VERIFIER_ROLE=$(cast keccak "VERIFIER_ROLE")
HAS_ROLE=$(cast call $PROOF_SYSTEM_ADDRESS "hasRole(bytes32,address)(bool)" $VERIFIER_ROLE $JOB_MARKETPLACE_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL)
echo "   Expected: true"
echo "   Actual:   $HAS_ROLE"
if [ "$HAS_ROLE" = "true" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

# 5. Check PaymentEscrow fee basis points
echo "5. PaymentEscrow Fee Configuration:"
FEE_BASIS=$(cast call $PAYMENT_ESCROW_ADDRESS "feeBasisPoints()(uint256)" --rpc-url $BASE_SEPOLIA_RPC_URL)
echo "   Expected: 250"
echo "   Actual:   $FEE_BASIS"
if [ "$FEE_BASIS" = "250" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

# 6. Check GovernanceToken total supply
echo "6. GovernanceToken Total Supply:"
TOTAL_SUPPLY=$(cast call $GOVERNANCE_TOKEN_ADDRESS "totalSupply()(uint256)" --rpc-url $BASE_SEPOLIA_RPC_URL)
EXPECTED_SUPPLY="1000000000000000000000000" # 1M tokens with 18 decimals
echo "   Expected: $EXPECTED_SUPPLY (1M FAB)"
echo "   Actual:   $TOTAL_SUPPLY"
if [ "$TOTAL_SUPPLY" = "$EXPECTED_SUPPLY" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

# 7. Check BaseAccountIntegration entryPoint
echo "7. BaseAccountIntegration EntryPoint:"
ENTRY_POINT=$(cast call $BASE_ACCOUNT_INTEGRATION_ADDRESS "entryPoint()(address)" --rpc-url $BASE_SEPOLIA_RPC_URL)
EXPECTED_ENTRY="0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
echo "   Expected: $EXPECTED_ENTRY"
echo "   Actual:   $ENTRY_POINT"
if [ "$ENTRY_POINT" = "$EXPECTED_ENTRY" ]; then
    echo "   ✅ CORRECT"
else
    echo "   ❌ INCORRECT"
fi
echo ""

echo "========================================="
echo "Configuration Verification Complete!"
echo "========================================="