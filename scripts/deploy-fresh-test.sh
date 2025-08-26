  #!/bin/bash
  source .env

  echo "Completing fresh deployment to Base Sepolia..."
  HOST_EARNINGS="0x4050FaDdd250dB75B0B4242B0748EB8681C72F41"

  # Deploy PaymentEscrowWithEarnings
  echo "1. Deploying PaymentEscrowWithEarnings..."
  PAYMENT_ESCROW=$(forge create src/PaymentEscrowWithEarnings.sol:PaymentEscrowWithEarnings \
      --rpc-url "$BASE_SEPOLIA_RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --constructor-args "0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078" "1000" \
      --broadcast \
      --verify \
      --etherscan-api-key "$BASESCAN_API_KEY" \
      | grep "Deployed to:" | awk '{print $3}')

  echo "   PaymentEscrow: $PAYMENT_ESCROW"

  # Deploy JobMarketplaceFABWithEarnings  
  echo "2. Deploying JobMarketplaceFABWithEarnings..."
  JOB_MARKETPLACE=$(forge create src/JobMarketplaceFABWithEarnings.sol:JobMarketplaceFABWithEarnings \
      --rpc-url "$BASE_SEPOLIA_RPC_URL" \
      --private-key "$PRIVATE_KEY" \
      --constructor-args "0x87516C13Ea2f99de598665e14cab64E191A0f8c4" "$HOST_EARNINGS" \
      --broadcast \
      --verify \
      --etherscan-api-key "$BASESCAN_API_KEY" \
      | grep "Deployed to:" | awk '{print $3}')

  echo "   JobMarketplace: $JOB_MARKETPLACE"

  # Configure contracts
  echo "3. Configuring contracts..."
  cast send "$HOST_EARNINGS" "setAuthorizedCaller(address,bool)" "$PAYMENT_ESCROW" true --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
  cast send "$PAYMENT_ESCROW" "setJobMarketplace(address)" "$JOB_MARKETPLACE" --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
  cast send "$JOB_MARKETPLACE" "setPaymentEscrow(address)" "$PAYMENT_ESCROW" --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"
  cast send "$JOB_MARKETPLACE" "setUsdcAddress(address)" "0x036CbD53842c5426634e7929541eC2318f3dCF7e" --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY"

  echo "✅ Deployment Complete!"
  echo "HostEarnings: $HOST_EARNINGS"
  echo "PaymentEscrow: $PAYMENT_ESCROW"
  echo "JobMarketplace: $JOB_MARKETPLACE"