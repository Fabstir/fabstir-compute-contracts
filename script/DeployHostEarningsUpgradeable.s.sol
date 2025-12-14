// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./DeployUpgradeable.s.sol";
import {HostEarningsUpgradeable} from "../src/HostEarningsUpgradeable.sol";

/**
 * @title DeployHostEarningsUpgradeable
 * @dev Deployment script for HostEarningsUpgradeable with UUPS proxy
 *
 * Usage:
 *   forge script script/DeployHostEarningsUpgradeable.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 */
contract DeployHostEarningsUpgradeable is DeployUpgradeable {
    function run() external returns (address proxy, address implementation) {
        console.log("Deploying HostEarningsUpgradeable...");

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new HostEarningsUpgradeable());
        console.log("Implementation deployed at:", implementation);

        // Deploy proxy with initialization
        proxy = deployProxy(
            implementation,
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        );

        logDeployment("HostEarningsUpgradeable", proxy, implementation);

        vm.stopBroadcast();

        // Post-deployment verification
        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(proxy));
        console.log("Verification:");
        console.log("  Owner:", hostEarnings.owner());
    }
}

/**
 * @title UpgradeHostEarnings
 * @dev Upgrade script for HostEarningsUpgradeable
 *
 * Usage:
 *   forge script script/DeployHostEarningsUpgradeable.s.sol:UpgradeHostEarnings \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   PROXY_ADDRESS - The existing proxy address to upgrade
 */
contract UpgradeHostEarnings is DeployUpgradeable {
    function run() external returns (address newImplementation) {
        // Get proxy address from environment
        address proxy = vm.envAddress("PROXY_ADDRESS");
        require(proxy != address(0), "PROXY_ADDRESS not set");

        console.log("Upgrading HostEarningsUpgradeable...");
        console.log("Proxy:", proxy);

        // Get current implementation
        address currentImpl = getImplementation(proxy);
        console.log("Current implementation:", currentImpl);

        vm.startBroadcast();

        // Deploy new implementation
        newImplementation = address(new HostEarningsUpgradeable());
        console.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy
        upgradeProxy(proxy, newImplementation);

        vm.stopBroadcast();

        console.log("Upgrade complete!");
        console.log("  Proxy:", proxy);
        console.log("  New Implementation:", newImplementation);

        // Verify state preserved
        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(proxy));
        console.log("State verification:");
        console.log("  Owner:", hostEarnings.owner());
    }
}
