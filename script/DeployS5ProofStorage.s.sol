// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {JobMarketplaceWithModels} from "../src/JobMarketplaceWithModels.sol";

/**
 * @title DeployS5ProofStorage
 * @notice Deployment script for JobMarketplaceWithModels with S5 off-chain proof storage
 * @dev Updated submitProofOfWork to accept hash + CID instead of full proof bytes
 */
contract DeployS5ProofStorage is Script {
    // Existing deployed contracts on Base Sepolia
    address constant NODE_REGISTRY = 0xDFFDecDfa0CF5D6cbE299711C7e4559eB16F42D6;
    address constant HOST_EARNINGS = 0x908962e8c6CE72610021586f85ebDE09aAc97776;
    address constant PROOF_SYSTEM = 0x2ACcc60893872A499700908889B38C5420CBcFD1;

    // Configuration
    uint256 constant FEE_BASIS_POINTS = 1000; // 10% treasury fee
    uint256 constant DISPUTE_WINDOW = 30; // 30 seconds

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("NodeRegistry:", NODE_REGISTRY);
        console.log("HostEarnings:", HOST_EARNINGS);
        console.log("Fee Basis Points:", FEE_BASIS_POINTS);
        console.log("Dispute Window:", DISPUTE_WINDOW);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy JobMarketplaceWithModels with S5 proof storage support
        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            NODE_REGISTRY,
            payable(HOST_EARNINGS),
            FEE_BASIS_POINTS,
            DISPUTE_WINDOW
        );

        console.log("JobMarketplaceWithModels deployed at:", address(marketplace));
        console.log("");
        console.log("==========================================");
        console.log("CRITICAL: POST-DEPLOYMENT CONFIGURATION");
        console.log("==========================================");
        console.log("");
        console.log("1. Set ProofSystem:");
        console.log("   cast send", address(marketplace), "\"setProofSystem(address)\"", PROOF_SYSTEM);
        console.log("   --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy");
        console.log("");
        console.log("2. Authorize in HostEarnings:");
        console.log("   cast send", HOST_EARNINGS, "\"setAuthorizedCaller(address,bool)\"");
        console.log("  ", address(marketplace), "true");
        console.log("   --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL --legacy");
        console.log("");
        console.log("3. Verify ProofSystem:");
        console.log("   cast call", address(marketplace), "\"proofSystem()\" --rpc-url $BASE_SEPOLIA_RPC_URL");
        console.log("");
        console.log("4. Verify HostEarnings Authorization:");
        console.log("   cast call", HOST_EARNINGS, "\"authorizedCallers(address)\"", address(marketplace));
        console.log("   --rpc-url $BASE_SEPOLIA_RPC_URL");
        console.log("");

        vm.stopBroadcast();

        console.log("==========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("==========================================");
        console.log("Contract Address:", address(marketplace));
        console.log("");
        console.log("**IMPORTANT**: Follow post-deployment configuration steps above!");
    }
}
