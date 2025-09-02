#!/bin/bash
set -a
source .env
set +a

echo "Deploying fresh test environment to Base Sepolia..."
echo "This will deploy new instances of all contracts for clean testing."
echo ""

# Deploy HostEarnings
echo "1. Deploying HostEarnings..."
HOST_EARNINGS=$(forge create src/HostEarnings.sol:HostEarnings \
    --rpc-url "$BASE_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --legacy \
    --broadcast \
    | grep "Deployed to:" | awk '{print $3}')

echo "   HostEarnings: $HOST_EARNINGS"

# Deploy PaymentEscrowWithEarnings
echo "2. Deploying PaymentEscrowWithEarnings..."
PAYMENT_ESCROW=$(forge create src/PaymentEscrowWithEarnings.sol:PaymentEscrowWithEarnings \
    --rpc-url "$BASE_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --constructor-args "0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078" "1000" \
    --legacy \
    --broadcast \
    | grep "Deployed to:" | awk '{print $3}')

echo "   PaymentEscrow: $PAYMENT_ESCROW"

# Deploy JobMarketplaceFABWithS5
echo "3. Deploying JobMarketplaceFABWithS5..."
JOB_MARKETPLACE=$(forge create src/JobMarketplaceFABWithS5.sol:JobMarketplaceFABWithS5 \
    --rpc-url "$BASE_SEPOLIA_RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --constructor-args "0x87516C13Ea2f99de598665e14cab64E191A0f8c4" "$HOST_EARNINGS" \
    --legacy \
    --broadcast \
    | grep "Deployed to:" | awk '{print $3}')

echo "   JobMarketplace: $JOB_MARKETPLACE"

# Configure contracts
echo "4. Configuring contracts..."
cast send "$HOST_EARNINGS" "setAuthorizedCaller(address,bool)" "$PAYMENT_ESCROW" true --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$PAYMENT_ESCROW" "setJobMarketplace(address)" "$JOB_MARKETPLACE" --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$JOB_MARKETPLACE" "setPaymentEscrow(address)" "$PAYMENT_ESCROW" --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
cast send "$JOB_MARKETPLACE" "setUsdcAddress(address)" "0x036CbD53842c5426634e7929541eC2318f3dCF7e" --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

echo ""
echo "✅ Fresh Deployment Complete!"
echo ""
echo "New contract addresses:"
echo "========================"
echo "HostEarnings:   $HOST_EARNINGS"
echo "PaymentEscrow:  $PAYMENT_ESCROW"
echo "JobMarketplace: $JOB_MARKETPLACE"
echo ""
echo "Update these addresses in your client application."
echo "Job IDs will start from 1 (clean slate)."