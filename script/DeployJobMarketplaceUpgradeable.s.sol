// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./DeployUpgradeable.s.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../src/JobMarketplaceWithModelsUpgradeable.sol";

/**
 * @title DeployJobMarketplaceUpgradeable
 * @dev Deployment script for JobMarketplaceWithModelsUpgradeable with UUPS proxy
 *
 * Usage:
 *   NODE_REGISTRY=0x... HOST_EARNINGS=0x... FEE_BASIS_POINTS=1000 DISPUTE_WINDOW=30 \
 *   forge script script/DeployJobMarketplaceUpgradeable.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   NODE_REGISTRY - The NodeRegistryWithModels contract address
 *   HOST_EARNINGS - The HostEarnings contract address
 *   FEE_BASIS_POINTS - Treasury fee in basis points (e.g., 1000 = 10%)
 *   DISPUTE_WINDOW - Dispute window duration in seconds
 */
contract DeployJobMarketplaceUpgradeable is DeployUpgradeable {
    function run() external returns (address proxy, address implementation) {
        // Get required addresses from environment
        address nodeRegistry = vm.envAddress("NODE_REGISTRY");
        address hostEarnings = vm.envAddress("HOST_EARNINGS");
        uint256 feeBasisPoints = vm.envUint("FEE_BASIS_POINTS");
        uint256 disputeWindow = vm.envUint("DISPUTE_WINDOW");

        require(nodeRegistry != address(0), "NODE_REGISTRY not set");
        require(hostEarnings != address(0), "HOST_EARNINGS not set");
        require(feeBasisPoints <= 10000, "Fee too high");
        require(disputeWindow > 0 && disputeWindow <= 7 days, "Invalid dispute window");

        console.log("Deploying JobMarketplaceWithModelsUpgradeable...");
        console.log("Node Registry:", nodeRegistry);
        console.log("Host Earnings:", hostEarnings);
        console.log("Fee Basis Points:", feeBasisPoints);
        console.log("Dispute Window:", disputeWindow);

        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new JobMarketplaceWithModelsUpgradeable());
        console.log("Implementation deployed at:", implementation);

        // Deploy proxy with initialization
        proxy = deployProxy(
            implementation,
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                nodeRegistry,
                payable(hostEarnings),
                feeBasisPoints,
                disputeWindow
            ))
        );

        logDeployment("JobMarketplaceWithModelsUpgradeable", proxy, implementation);

        vm.stopBroadcast();

        // Post-deployment verification
        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxy));
        console.log("Verification:");
        console.log("  Owner:", marketplace.owner());
        console.log("  Treasury:", marketplace.treasuryAddress());
        console.log("  Node Registry:", address(marketplace.nodeRegistry()));
        console.log("  Host Earnings:", address(marketplace.hostEarnings()));
        console.log("  Fee Basis Points:", marketplace.feeBasisPoints());
        console.log("  Dispute Window:", marketplace.disputeWindow());

        console.log("");
        console.log("IMPORTANT: After deployment, authorize this contract in HostEarnings:");
        console.log("  hostEarnings.setAuthorizedCaller(", proxy, ", true)");
    }
}

/**
 * @title UpgradeJobMarketplace
 * @dev Upgrade script for JobMarketplaceWithModelsUpgradeable
 *
 * Usage:
 *   PROXY_ADDRESS=0x... forge script script/DeployJobMarketplaceUpgradeable.s.sol:UpgradeJobMarketplace \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   PROXY_ADDRESS - The existing proxy address to upgrade
 */
contract UpgradeJobMarketplace is DeployUpgradeable {
    function run() external returns (address newImplementation) {
        // Get proxy address from environment
        address proxy = vm.envAddress("PROXY_ADDRESS");
        require(proxy != address(0), "PROXY_ADDRESS not set");

        console.log("Upgrading JobMarketplaceWithModelsUpgradeable...");
        console.log("Proxy:", proxy);

        // Get current implementation
        address currentImpl = getImplementation(proxy);
        console.log("Current implementation:", currentImpl);

        vm.startBroadcast();

        // Deploy new implementation
        newImplementation = address(new JobMarketplaceWithModelsUpgradeable());
        console.log("New implementation deployed at:", newImplementation);

        // Upgrade proxy
        upgradeProxy(proxy, newImplementation);

        vm.stopBroadcast();

        console.log("Upgrade complete!");
        console.log("  Proxy:", proxy);
        console.log("  New Implementation:", newImplementation);

        // Verify state preserved
        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxy));
        console.log("State verification:");
        console.log("  Owner:", marketplace.owner());
        console.log("  Treasury:", marketplace.treasuryAddress());
        console.log("  Node Registry:", address(marketplace.nodeRegistry()));
        console.log("  Fee Basis Points:", marketplace.feeBasisPoints());
        console.log("  Next Job ID:", marketplace.nextJobId());
    }
}
