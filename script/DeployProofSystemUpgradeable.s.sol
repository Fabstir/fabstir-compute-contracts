// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./DeployUpgradeable.s.sol";
import {ProofSystemUpgradeable} from "../src/ProofSystemUpgradeable.sol";

/**
 * @title DeployProofSystemUpgradeable
 * @dev Deployment script for ProofSystemUpgradeable with UUPS proxy
 *
 * Usage:
 *   forge script script/DeployProofSystemUpgradeable.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 */
contract DeployProofSystemUpgradeable is DeployUpgradeable {
    function run() external returns (address proxy, address implementation) {
        console.log("Deploying ProofSystemUpgradeable...");

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new ProofSystemUpgradeable());
        console.log("Implementation deployed at:", implementation);

        // Deploy proxy with initialization
        proxy = deployProxy(
            implementation,
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        );

        logDeployment("ProofSystemUpgradeable", proxy, implementation);

        vm.stopBroadcast();

        // Post-deployment verification
        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);
        console.log("Verification:");
        console.log("  Owner:", proofSystem.owner());
    }
}

/**
 * @title UpgradeProofSystem
 * @dev Upgrade script for ProofSystemUpgradeable
 *
 * Usage:
 *   forge script script/DeployProofSystemUpgradeable.s.sol:UpgradeProofSystem \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   PROXY_ADDRESS - The existing proxy address to upgrade
 */
contract UpgradeProofSystem is DeployUpgradeable {
    function run() external returns (address newImplementation) {
        // Get proxy address from environment
        address proxy = vm.envAddress("PROXY_ADDRESS");
        require(proxy != address(0), "PROXY_ADDRESS not set");

        console.log("Upgrading ProofSystemUpgradeable...");
        console.log("Proxy:", proxy);

        // Get current implementation
        address currentImpl = getImplementation(proxy);
        console.log("Current implementation:", currentImpl);

        vm.startBroadcast();

        // Deploy new implementation
        newImplementation = address(new ProofSystemUpgradeable());
        console.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy
        upgradeProxy(proxy, newImplementation);

        vm.stopBroadcast();

        console.log("Upgrade complete!");
        console.log("  Proxy:", proxy);
        console.log("  New Implementation:", newImplementation);

        // Verify state preserved
        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);
        console.log("State verification:");
        console.log("  Owner:", proofSystem.owner());
    }
}
