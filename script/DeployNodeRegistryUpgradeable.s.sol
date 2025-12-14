// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./DeployUpgradeable.s.sol";
import {NodeRegistryWithModelsUpgradeable} from "../src/NodeRegistryWithModelsUpgradeable.sol";

/**
 * @title DeployNodeRegistryUpgradeable
 * @dev Deployment script for NodeRegistryWithModelsUpgradeable with UUPS proxy
 *
 * Usage:
 *   FAB_TOKEN=0x... MODEL_REGISTRY=0x... forge script script/DeployNodeRegistryUpgradeable.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   FAB_TOKEN - The FAB token address
 *   MODEL_REGISTRY - The ModelRegistry contract address
 */
contract DeployNodeRegistryUpgradeable is DeployUpgradeable {
    function run() external returns (address proxy, address implementation) {
        // Get required addresses from environment
        address fabToken = vm.envAddress("FAB_TOKEN");
        address modelRegistry = vm.envAddress("MODEL_REGISTRY");

        require(fabToken != address(0), "FAB_TOKEN not set");
        require(modelRegistry != address(0), "MODEL_REGISTRY not set");

        console.log("Deploying NodeRegistryWithModelsUpgradeable...");
        console.log("FAB Token:", fabToken);
        console.log("Model Registry:", modelRegistry);

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new NodeRegistryWithModelsUpgradeable());
        console.log("Implementation deployed at:", implementation);

        // Deploy proxy with initialization
        proxy = deployProxy(
            implementation,
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (fabToken, modelRegistry))
        );

        logDeployment("NodeRegistryWithModelsUpgradeable", proxy, implementation);

        vm.stopBroadcast();

        // Post-deployment verification
        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(proxy);
        console.log("Verification:");
        console.log("  Owner:", nodeRegistry.owner());
        console.log("  FAB Token:", address(nodeRegistry.fabToken()));
        console.log("  Model Registry:", address(nodeRegistry.modelRegistry()));
    }
}

/**
 * @title UpgradeNodeRegistry
 * @dev Upgrade script for NodeRegistryWithModelsUpgradeable
 *
 * Usage:
 *   PROXY_ADDRESS=0x... forge script script/DeployNodeRegistryUpgradeable.s.sol:UpgradeNodeRegistry \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   PROXY_ADDRESS - The existing proxy address to upgrade
 */
contract UpgradeNodeRegistry is DeployUpgradeable {
    function run() external returns (address newImplementation) {
        // Get proxy address from environment
        address proxy = vm.envAddress("PROXY_ADDRESS");
        require(proxy != address(0), "PROXY_ADDRESS not set");

        console.log("Upgrading NodeRegistryWithModelsUpgradeable...");
        console.log("Proxy:", proxy);

        // Get current implementation
        address currentImpl = getImplementation(proxy);
        console.log("Current implementation:", currentImpl);

        vm.startBroadcast();

        // Deploy new implementation
        newImplementation = address(new NodeRegistryWithModelsUpgradeable());
        console.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy
        upgradeProxy(proxy, newImplementation);

        vm.stopBroadcast();

        console.log("Upgrade complete!");
        console.log("  Proxy:", proxy);
        console.log("  New Implementation:", newImplementation);

        // Verify state preserved
        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(proxy);
        console.log("State verification:");
        console.log("  Owner:", nodeRegistry.owner());
        console.log("  FAB Token:", address(nodeRegistry.fabToken()));
        console.log("  Model Registry:", address(nodeRegistry.modelRegistry()));
    }
}
