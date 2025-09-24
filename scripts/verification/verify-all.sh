#!/bin/bash

# Source environment variables
source .env

echo "Verifying all contracts on Base Sepolia..."

# Verify GovernanceToken
echo "1. Verifying GovernanceToken..."
forge verify-contract 0xC78949004B4EB6dEf2D66e49Cd81231472612D62 \
    src/GovernanceToken.sol:GovernanceToken \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(string,string,uint256)" "Fabstir Governance" "FAB" 1000000000000000000000000)

# Verify NodeRegistry
echo "2. Verifying NodeRegistry..."
forge verify-contract 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3 \
    src/NodeRegistry.sol:NodeRegistry \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(uint256)" 100000000000000000)

# Verify JobMarketplace
echo "3. Verifying JobMarketplace..."
forge verify-contract 0x66E590bfc36cf751E640F09Bbf778AaB542752D5 \
    src/JobMarketplace.sol:JobMarketplace \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address)" 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3)

# Verify PaymentEscrow
echo "4. Verifying PaymentEscrow..."
forge verify-contract 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894 \
    src/PaymentEscrow.sol:PaymentEscrow \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address,uint256)" 0x0000000000000000000000000000000000000000 250)

# Verify ReputationSystem
echo "5. Verifying ReputationSystem..."
forge verify-contract 0x4504CC06C47a4E4d9a14Bd5eF9766395B7c76865 \
    src/ReputationSystem.sol:ReputationSystem \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3 0x66E590bfc36cf751E640F09Bbf778AaB542752D5 0x0000000000000000000000000000000000000000)

# Verify ProofSystem
echo "6. Verifying ProofSystem..."
forge verify-contract 0x2c15728e9E60fdB482F616f8A581E8a81f27CF0E \
    src/ProofSystem.sol:ProofSystem \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x66E590bfc36cf751E640F09Bbf778AaB542752D5 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894 0x4504CC06C47a4E4d9a14Bd5eF9766395B7c76865)

# Verify Governance
echo "7. Verifying Governance..."
forge verify-contract 0xB73B7f3a4abCD1dF7f925Ad287aE5EfC3dE63003 \
    src/Governance.sol:Governance \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address)" 0xC78949004B4EB6dEf2D66e49Cd81231472612D62 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3 0x66E590bfc36cf751E640F09Bbf778AaB542752D5 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894 0x4504CC06C47a4E4d9a14Bd5eF9766395B7c76865 0x2c15728e9E60fdB482F616f8A581E8a81f27CF0E)

# Verify BaseAccountIntegration
echo "8. Verifying BaseAccountIntegration..."
forge verify-contract 0xbd56DBcD39a1BDb437906221CA1cbb72556035E3 \
    src/BaseAccountIntegration.sol:BaseAccountIntegration \
    --etherscan-api-key $BASESCAN_API_KEY \
    --chain base-sepolia \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789 0x0000000000000000000000000000000000000000 0x66E590bfc36cf751E640F09Bbf778AaB542752D5 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3)

echo "All contracts submitted for verification!"