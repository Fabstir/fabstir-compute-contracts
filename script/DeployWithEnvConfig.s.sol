// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceWithModels.sol";
import "../src/NodeRegistryWithModels.sol";
import "../src/ModelRegistry.sol";
import "../src/HostEarnings.sol";

/**
 * @title DeployWithEnvConfig
 * @dev Deployment script that reads configuration from environment variables
 * @notice Deploys JobMarketplaceWithModels with configurable treasury fee
 *
 * Environment variables:
 * - TREASURY_FEE_PERCENTAGE: Treasury fee percentage (e.g., 10 for 10%)
 * - PRIVATE_KEY: Deployer private key
 * - BASE_SEPOLIA_RPC_URL: RPC URL for Base Sepolia
 *
 * Usage:
 * forge script script/DeployWithEnvConfig.s.sol:DeployWithEnvConfig \
 *   --rpc-url $BASE_SEPOLIA_RPC_URL \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify
 */
contract DeployWithEnvConfig is Script {
    // Existing contract addresses on Base Sepolia
    address constant NODE_REGISTRY = 0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218;
    address constant MODEL_REGISTRY = 0x92b2De840bB2171203011A6dBA928d855cA8183E;
    address constant PROOF_SYSTEM = 0x2ACcc60893872A499700908889B38C5420CBcFD1;
    address constant HOST_EARNINGS = 0x908962e8c6CE72610021586f85ebDE09aAc97776;

    function run() external {
        // Read treasury fee percentage from environment variable
        uint256 treasuryFeePercentage = vm.envUint("TREASURY_FEE_PERCENTAGE");

        // Validate percentage is reasonable
        require(treasuryFeePercentage <= 100, "Treasury fee cannot exceed 100%");

        // Convert percentage to basis points (multiply by 100)
        uint256 feeBasisPoints = treasuryFeePercentage * 100;

        console.log("Deploying with configuration:");
        console.log("- Treasury Fee Percentage:", treasuryFeePercentage, "%");
        console.log("- Fee Basis Points:", feeBasisPoints);
        console.log("- Node Registry:", NODE_REGISTRY);
        console.log("- Host Earnings:", HOST_EARNINGS);

        vm.startBroadcast();

        // Deploy JobMarketplaceWithModels with configurable fee
        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            NODE_REGISTRY,
            payable(HOST_EARNINGS),
            feeBasisPoints
        );

        console.log("JobMarketplaceWithModels deployed at:", address(marketplace));
        console.log("Treasury fee configured:", treasuryFeePercentage);
        console.log("Fee in basis points:", feeBasisPoints);

        // Verify configuration
        require(marketplace.FEE_BASIS_POINTS() == feeBasisPoints, "Fee configuration mismatch");

        vm.stopBroadcast();

        // Output deployment info for documentation
        console.log("\n=== Deployment Summary ===");
        console.log("JobMarketplaceWithModels:", address(marketplace));
        console.log("Treasury Fee:", treasuryFeePercentage, "%");
        console.log("Host Earnings:", 100 - treasuryFeePercentage, "%");
        console.log("Network: Base Sepolia");
        console.log("\nUpdate CONTRACT_ADDRESSES.md with the new address");
    }

    /**
     * @dev Deploy fresh test environment with custom fee
     * @notice Can be called with specific fee for testing
     */
    function deployWithCustomFee(uint256 _treasuryFeePercentage) external {
        require(_treasuryFeePercentage <= 100, "Treasury fee cannot exceed 100%");

        uint256 feeBasisPoints = _treasuryFeePercentage * 100;

        vm.startBroadcast();

        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            NODE_REGISTRY,
            payable(HOST_EARNINGS),
            feeBasisPoints
        );

        console.log("Test deployment with", _treasuryFeePercentage, "% treasury fee");
        console.log("Address:", address(marketplace));

        vm.stopBroadcast();
    }
}