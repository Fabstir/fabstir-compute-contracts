#!/bin/bash

echo "Loading environment variables..."
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

if [ -z "$DEPLOYER_ADDRESS" ]; then
    echo "Error: DEPLOYER_ADDRESS not set in .env"
    exit 1
fi

echo "Deployer address: $DEPLOYER_ADDRESS"
echo "Checking balance..."
BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url https://sepolia.base.org)
echo "Balance: $BALANCE"

echo ""
echo "Deploying contracts..."
forge script script/DeployNew.s.sol:DeployNew \
    --rpc-url https://sepolia.base.org \
    --broadcast \
    --private-key "$PRIVATE_KEY" \
    -vv