// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./DeployUpgradeable.s.sol";
import {ModelRegistryUpgradeable} from "../src/ModelRegistryUpgradeable.sol";

/**
 * @title DeployModelRegistryUpgradeable
 * @dev Deployment script for ModelRegistryUpgradeable with UUPS proxy
 *
 * Usage:
 *   forge script script/DeployModelRegistryUpgradeable.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   FAB_TOKEN_ADDRESS - The FAB governance token address (required)
 */
contract DeployModelRegistryUpgradeable is DeployUpgradeable {
    function run() external returns (address proxy, address implementation) {
        // Get FAB token address from environment
        address fabToken = vm.envAddress("FAB_TOKEN_ADDRESS");
        require(fabToken != address(0), "FAB_TOKEN_ADDRESS not set");

        console.log("Deploying ModelRegistryUpgradeable...");
        console.log("FAB Token:", fabToken);

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new ModelRegistryUpgradeable());
        console.log("Implementation deployed at:", implementation);

        // Deploy proxy with initialization
        proxy = deployProxy(
            implementation,
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (fabToken))
        );

        logDeployment("ModelRegistryUpgradeable", proxy, implementation);

        vm.stopBroadcast();

        // Post-deployment verification
        ModelRegistryUpgradeable registry = ModelRegistryUpgradeable(proxy);
        console.log("Verification:");
        console.log("  Owner:", registry.owner());
        console.log("  Governance Token:", address(registry.governanceToken()));
    }
}

/**
 * @title UpgradeModelRegistry
 * @dev Upgrade script for ModelRegistryUpgradeable
 *
 * Usage:
 *   forge script script/DeployModelRegistryUpgradeable.s.sol:UpgradeModelRegistry \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   PROXY_ADDRESS - The existing proxy address to upgrade
 */
contract UpgradeModelRegistry is DeployUpgradeable {
    function run() external returns (address newImplementation) {
        // Get proxy address from environment
        address proxy = vm.envAddress("PROXY_ADDRESS");
        require(proxy != address(0), "PROXY_ADDRESS not set");

        console.log("Upgrading ModelRegistryUpgradeable...");
        console.log("Proxy:", proxy);

        // Get current implementation
        address currentImpl = getImplementation(proxy);
        console.log("Current implementation:", currentImpl);

        vm.startBroadcast();

        // Deploy new implementation
        newImplementation = address(new ModelRegistryUpgradeable());
        console.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy
        upgradeProxy(proxy, newImplementation);

        vm.stopBroadcast();

        console.log("Upgrade complete!");
        console.log("  Proxy:", proxy);
        console.log("  New Implementation:", newImplementation);

        // Verify state preserved
        ModelRegistryUpgradeable registry = ModelRegistryUpgradeable(proxy);
        console.log("State verification:");
        console.log("  Owner:", registry.owner());
        console.log("  Governance Token:", address(registry.governanceToken()));
        console.log("  Model count:", registry.getAllModels().length);
    }
}
