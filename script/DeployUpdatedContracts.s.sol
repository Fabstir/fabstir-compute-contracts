// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {NodeRegistryWithModels} from "../src/NodeRegistryWithModels.sol";
import {JobMarketplaceWithModels} from "../src/JobMarketplaceWithModels.sol";

/**
 * @title DeployUpdatedContracts
 * @notice Deploys updated NodeRegistry and JobMarketplace with corrected pricing
 * @dev Run with: forge script script/DeployUpdatedContracts.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployUpdatedContracts is Script {
    // Existing contract addresses (Base Sepolia)
    address constant FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    address constant MODEL_REGISTRY = 0x92b2De840bB2171203011A6dBA928d855cA8183E;
    address constant HOST_EARNINGS = 0x908962e8c6CE72610021586f85ebDE09aAc97776;
    address constant PROOF_SYSTEM = 0x2ACcc60893872A499700908889B38C5420CBcFD1;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30; // 30 seconds

    function run() external {
        vm.startBroadcast();

        console.log("Deploying updated contracts to Base Sepolia...");
        console.log("Deployer address:", msg.sender);

        // 1. Deploy NodeRegistryWithModels
        console.log("\n1. Deploying NodeRegistryWithModels...");
        NodeRegistryWithModels nodeRegistry = new NodeRegistryWithModels(
            FAB_TOKEN,
            MODEL_REGISTRY
        );
        console.log("NodeRegistryWithModels deployed at:", address(nodeRegistry));

        // 2. Deploy JobMarketplaceWithModels
        console.log("\n2. Deploying JobMarketplaceWithModels...");
        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(HOST_EARNINGS),
            FEE_BASIS_POINTS,
            DISPUTE_WINDOW
        );
        console.log("JobMarketplaceWithModels deployed at:", address(marketplace));

        // 3. Configure ProofSystem on marketplace
        console.log("\n3. Configuring ProofSystem on marketplace...");
        marketplace.setProofSystem(PROOF_SYSTEM);
        console.log("ProofSystem configured");

        // 4. Authorize marketplace in HostEarnings
        console.log("\n4. Authorizing marketplace in HostEarnings...");
        // Note: This requires calling HostEarnings.setAuthorizedCaller(marketplace, true)
        // You may need to do this separately if you're not the HostEarnings owner
        console.log("NOTE: You need to call HostEarnings.setAuthorizedCaller(", address(marketplace), ", true)");

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("NodeRegistryWithModels:", address(nodeRegistry));
        console.log("JobMarketplaceWithModels:", address(marketplace));
        console.log("\nNext steps:");
        console.log("1. Authorize marketplace in HostEarnings");
        console.log("2. Update CONTRACT_ADDRESSES.md");
        console.log("3. Extract and update client ABIs");
    }
}
