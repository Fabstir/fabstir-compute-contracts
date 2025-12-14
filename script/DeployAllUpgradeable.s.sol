// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./DeployUpgradeable.s.sol";
import {ModelRegistryUpgradeable} from "../src/ModelRegistryUpgradeable.sol";
import {ProofSystemUpgradeable} from "../src/ProofSystemUpgradeable.sol";
import {HostEarningsUpgradeable} from "../src/HostEarningsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../src/NodeRegistryWithModelsUpgradeable.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../src/JobMarketplaceWithModelsUpgradeable.sol";

/**
 * @title DeployAllUpgradeable
 * @dev Master deployment script for all upgradeable contracts with UUPS proxies
 *
 * This script deploys all 5 core contracts in dependency order:
 * 1. ModelRegistryUpgradeable
 * 2. ProofSystemUpgradeable
 * 3. HostEarningsUpgradeable
 * 4. NodeRegistryWithModelsUpgradeable (needs FAB token and ModelRegistry)
 * 5. JobMarketplaceWithModelsUpgradeable (needs NodeRegistry and HostEarnings)
 *
 * Usage:
 *   FAB_TOKEN=0x... FEE_BASIS_POINTS=1000 DISPUTE_WINDOW=30 \
 *   forge script script/DeployAllUpgradeable.s.sol \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --legacy
 *
 * Environment Variables:
 *   FAB_TOKEN - The FAB governance token address
 *   FEE_BASIS_POINTS - Treasury fee in basis points (e.g., 1000 = 10%)
 *   DISPUTE_WINDOW - Dispute window duration in seconds
 */
contract DeployAllUpgradeable is DeployUpgradeable {
    // Deployment results struct
    struct DeploymentResult {
        address modelRegistryProxy;
        address modelRegistryImpl;
        address proofSystemProxy;
        address proofSystemImpl;
        address hostEarningsProxy;
        address hostEarningsImpl;
        address nodeRegistryProxy;
        address nodeRegistryImpl;
        address jobMarketplaceProxy;
        address jobMarketplaceImpl;
    }

    function run() external returns (DeploymentResult memory result) {
        // Get required addresses from environment
        address fabToken = vm.envAddress("FAB_TOKEN");
        uint256 feeBasisPoints = vm.envUint("FEE_BASIS_POINTS");
        uint256 disputeWindow = vm.envUint("DISPUTE_WINDOW");

        require(fabToken != address(0), "FAB_TOKEN not set");
        require(feeBasisPoints <= 10000, "Fee too high");
        require(disputeWindow > 0 && disputeWindow <= 7 days, "Invalid dispute window");

        console.log("");
        console.log("============================================================");
        console.log("  DEPLOYING ALL UPGRADEABLE CONTRACTS");
        console.log("============================================================");
        console.log("");
        console.log("Configuration:");
        console.log("  FAB Token:", fabToken);
        console.log("  Fee Basis Points:", feeBasisPoints);
        console.log("  Dispute Window:", disputeWindow);
        console.log("");

        vm.startBroadcast();

        // ============================================================
        // 1. Deploy ModelRegistryUpgradeable
        // ============================================================
        console.log("Step 1/5: Deploying ModelRegistryUpgradeable...");
        result.modelRegistryImpl = address(new ModelRegistryUpgradeable());
        result.modelRegistryProxy = deployProxy(
            result.modelRegistryImpl,
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (fabToken))
        );
        logDeployment("ModelRegistryUpgradeable", result.modelRegistryProxy, result.modelRegistryImpl);

        // ============================================================
        // 2. Deploy ProofSystemUpgradeable
        // ============================================================
        console.log("Step 2/5: Deploying ProofSystemUpgradeable...");
        result.proofSystemImpl = address(new ProofSystemUpgradeable());
        result.proofSystemProxy = deployProxy(
            result.proofSystemImpl,
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        );
        logDeployment("ProofSystemUpgradeable", result.proofSystemProxy, result.proofSystemImpl);

        // ============================================================
        // 3. Deploy HostEarningsUpgradeable
        // ============================================================
        console.log("Step 3/5: Deploying HostEarningsUpgradeable...");
        result.hostEarningsImpl = address(new HostEarningsUpgradeable());
        result.hostEarningsProxy = deployProxy(
            result.hostEarningsImpl,
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        );
        logDeployment("HostEarningsUpgradeable", result.hostEarningsProxy, result.hostEarningsImpl);

        // ============================================================
        // 4. Deploy NodeRegistryWithModelsUpgradeable
        // ============================================================
        console.log("Step 4/5: Deploying NodeRegistryWithModelsUpgradeable...");
        result.nodeRegistryImpl = address(new NodeRegistryWithModelsUpgradeable());
        result.nodeRegistryProxy = deployProxy(
            result.nodeRegistryImpl,
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (
                fabToken,
                result.modelRegistryProxy
            ))
        );
        logDeployment("NodeRegistryWithModelsUpgradeable", result.nodeRegistryProxy, result.nodeRegistryImpl);

        // ============================================================
        // 5. Deploy JobMarketplaceWithModelsUpgradeable
        // ============================================================
        console.log("Step 5/5: Deploying JobMarketplaceWithModelsUpgradeable...");
        result.jobMarketplaceImpl = address(new JobMarketplaceWithModelsUpgradeable());
        result.jobMarketplaceProxy = deployProxy(
            result.jobMarketplaceImpl,
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                result.nodeRegistryProxy,
                payable(result.hostEarningsProxy),
                feeBasisPoints,
                disputeWindow
            ))
        );
        logDeployment("JobMarketplaceWithModelsUpgradeable", result.jobMarketplaceProxy, result.jobMarketplaceImpl);

        // ============================================================
        // 6. Configure Cross-Contract References
        // ============================================================
        console.log("Step 6: Configuring cross-contract references...");

        // Authorize JobMarketplace in HostEarnings
        HostEarningsUpgradeable(payable(result.hostEarningsProxy)).setAuthorizedCaller(
            result.jobMarketplaceProxy,
            true
        );
        console.log("  HostEarnings: Authorized JobMarketplace");

        vm.stopBroadcast();

        // ============================================================
        // Print Summary
        // ============================================================
        console.log("");
        console.log("============================================================");
        console.log("  DEPLOYMENT SUMMARY");
        console.log("============================================================");
        console.log("");
        console.log("PROXY ADDRESSES (use these for interactions):");
        console.log("  ModelRegistry:  ", result.modelRegistryProxy);
        console.log("  ProofSystem:    ", result.proofSystemProxy);
        console.log("  HostEarnings:   ", result.hostEarningsProxy);
        console.log("  NodeRegistry:   ", result.nodeRegistryProxy);
        console.log("  JobMarketplace: ", result.jobMarketplaceProxy);
        console.log("");
        console.log("IMPLEMENTATION ADDRESSES (for verification):");
        console.log("  ModelRegistry:  ", result.modelRegistryImpl);
        console.log("  ProofSystem:    ", result.proofSystemImpl);
        console.log("  HostEarnings:   ", result.hostEarningsImpl);
        console.log("  NodeRegistry:   ", result.nodeRegistryImpl);
        console.log("  JobMarketplace: ", result.jobMarketplaceImpl);
        console.log("");
        console.log("CONFIGURATION:");
        console.log("  FAB Token:         ", fabToken);
        console.log("  Fee Basis Points:  ", feeBasisPoints);
        console.log("  Dispute Window:    ", disputeWindow);
        console.log("");
        console.log("POST-DEPLOYMENT STEPS:");
        console.log("  1. Add approved models to ModelRegistry");
        console.log("  2. Configure chain settings in JobMarketplace (if needed)");
        console.log("  3. Update CONTRACT_ADDRESSES.md with new addresses");
        console.log("  4. Update client-abis/ if ABIs changed");
        console.log("");
        console.log("============================================================");

        // Verify deployment
        _verifyDeployment(result, fabToken, feeBasisPoints, disputeWindow);
    }

    /**
     * @dev Verify all contracts are properly deployed and configured
     */
    function _verifyDeployment(
        DeploymentResult memory result,
        address fabToken,
        uint256 feeBasisPoints,
        uint256 disputeWindow
    ) internal view {
        console.log("Verifying deployment...");

        // Verify ModelRegistry
        ModelRegistryUpgradeable modelRegistry = ModelRegistryUpgradeable(result.modelRegistryProxy);
        require(address(modelRegistry.governanceToken()) == fabToken, "ModelRegistry: Invalid governance token");
        console.log("  ModelRegistry: OK");

        // Verify ProofSystem
        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(result.proofSystemProxy);
        require(proofSystem.owner() != address(0), "ProofSystem: No owner");
        console.log("  ProofSystem: OK");

        // Verify HostEarnings
        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(result.hostEarningsProxy));
        require(hostEarnings.owner() != address(0), "HostEarnings: No owner");
        require(hostEarnings.authorizedCallers(result.jobMarketplaceProxy), "HostEarnings: JobMarketplace not authorized");
        console.log("  HostEarnings: OK");

        // Verify NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(result.nodeRegistryProxy);
        require(address(nodeRegistry.fabToken()) == fabToken, "NodeRegistry: Invalid FAB token");
        require(address(nodeRegistry.modelRegistry()) == result.modelRegistryProxy, "NodeRegistry: Invalid ModelRegistry");
        console.log("  NodeRegistry: OK");

        // Verify JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(result.jobMarketplaceProxy));
        require(address(marketplace.nodeRegistry()) == result.nodeRegistryProxy, "JobMarketplace: Invalid NodeRegistry");
        require(address(marketplace.hostEarnings()) == result.hostEarningsProxy, "JobMarketplace: Invalid HostEarnings");
        require(marketplace.FEE_BASIS_POINTS() == feeBasisPoints, "JobMarketplace: Invalid fee");
        require(marketplace.DISPUTE_WINDOW() == disputeWindow, "JobMarketplace: Invalid dispute window");
        console.log("  JobMarketplace: OK");

        console.log("");
        console.log("All verifications passed!");
    }
}
