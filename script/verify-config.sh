#!/bin/bash
# Copyright (c) 2025 Fabstir
# SPDX-License-Identifier: BUSL-1.1

# Base Sepolia RPC URL
RPC_URL="https://base-sepolia.g.alchemy.com/v2/1pZoccdtgU8CMyxXzE3l_ghnBBaJABMR"

# Contract addresses
JOB_MARKETPLACE="0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6"
PAYMENT_ESCROW="0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894"
USDC_ADDRESS="0x036CbD53842c5426634e7929541eC2318f3dCF7e"

echo "========================================="
echo "Verifying Contract Configuration"
echo "========================================="
echo ""

# Check if JobMarketplace exists
echo "Checking JobMarketplace deployment..."
CODE=$(cast code $JOB_MARKETPLACE --rpc-url $RPC_URL)
if [[ "$CODE" == "0x" ]]; then
    echo "❌ JobMarketplace NOT deployed at $JOB_MARKETPLACE"
    echo "   Deployment needs to be completed first!"
    exit 1
else
    echo "✅ JobMarketplace found at $JOB_MARKETPLACE"
fi

# Check JobMarketplace.paymentEscrow()
echo ""
echo "Checking JobMarketplace.paymentEscrow()..."
ESCROW=$(cast call $JOB_MARKETPLACE "paymentEscrow()" --rpc-url $RPC_URL 2>/dev/null)
if [[ "$ESCROW" == "0x0000000000000000000000003b96fbd7b463e94463ae4d0f2629e08cf1f25894" ]]; then
    echo "✅ PaymentEscrow correctly set to $PAYMENT_ESCROW"
elif [[ "$ESCROW" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "❌ PaymentEscrow NOT configured (returns 0x0)"
else
    echo "⚠️  PaymentEscrow set to unexpected value: $ESCROW"
fi

# Check JobMarketplace.usdcAddress()
echo ""
echo "Checking JobMarketplace.usdcAddress()..."
USDC=$(cast call $JOB_MARKETPLACE "usdcAddress()" --rpc-url $RPC_URL 2>/dev/null)
if [[ "$USDC" == "0x000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e" ]]; then
    echo "✅ USDC address correctly set to $USDC_ADDRESS"
elif [[ "$USDC" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "❌ USDC address NOT configured (returns 0x0)"
else
    echo "⚠️  USDC set to unexpected value: $USDC"
fi

# Check PaymentEscrow.jobMarketplace()
echo ""
echo "Checking PaymentEscrow.jobMarketplace()..."
MARKETPLACE=$(cast call $PAYMENT_ESCROW "jobMarketplace()" --rpc-url $RPC_URL 2>/dev/null)
if [[ "$MARKETPLACE" == "0x0000000000000000000000006c4283a2aaee2f94bcd2eb04e951efea1c35b0b6" ]]; then
    echo "✅ JobMarketplace correctly set in PaymentEscrow"
elif [[ "$MARKETPLACE" == "0x0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "❌ JobMarketplace NOT configured in PaymentEscrow (returns 0x0)"
else
    echo "⚠️  JobMarketplace set to unexpected value: $MARKETPLACE"
fi

echo ""
echo "========================================="
echo "Configuration Status Summary"
echo "========================================="

if [[ "$CODE" != "0x" ]] && \
   [[ "$ESCROW" == "0x0000000000000000000000003b96fbd7b463e94463ae4d0f2629e08cf1f25894" ]] && \
   [[ "$USDC" == "0x000000000000000000000000036cbd53842c5426634e7929541ec2318f3dcf7e" ]] && \
   [[ "$MARKETPLACE" == "0x0000000000000000000000006c4283a2aaee2f94bcd2eb04e951efea1c35b0b6" ]]; then
    echo "✅ ALL CONFIGURATIONS CORRECT - USDC payments will work!"
else
    echo "❌ CONFIGURATION INCOMPLETE - USDC payments will NOT work!"
    echo ""
    echo "To fix, run:"
    echo "forge script script/ConfigureContracts.s.sol:ConfigureContracts --rpc-url base-sepolia --broadcast"
fi