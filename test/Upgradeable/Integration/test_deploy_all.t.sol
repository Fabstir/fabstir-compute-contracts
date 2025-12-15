// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployAllUpgradeable} from "../../../script/DeployAllUpgradeable.s.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title DeployAllUpgradeable Script Tests
 * @dev Tests the master deployment script for all upgradeable contracts
 *
 * Note: These tests must be run in isolation because vm.setEnv persists
 * environment variables across the test process. Run with:
 *   forge test --match-contract DeployAllUpgradeableTest
 */
contract DeployAllUpgradeableTest is Test {
    DeployAllUpgradeable public deployScript;
    ERC20Mock public fabToken;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Set environment variables
        vm.setEnv("FAB_TOKEN", vm.toString(address(fabToken)));
        vm.setEnv("FEE_BASIS_POINTS", vm.toString(FEE_BASIS_POINTS));
        vm.setEnv("DISPUTE_WINDOW", vm.toString(DISPUTE_WINDOW));

        // Create deployment script
        deployScript = new DeployAllUpgradeable();
    }

    // ============================================================
    // Deployment Tests
    // ============================================================

    function test_DeployAllContractsSuccessfully() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        // Verify all addresses are set
        assertTrue(result.modelRegistryProxy != address(0), "ModelRegistry proxy deployed");
        assertTrue(result.modelRegistryImpl != address(0), "ModelRegistry impl deployed");
        assertTrue(result.proofSystemProxy != address(0), "ProofSystem proxy deployed");
        assertTrue(result.proofSystemImpl != address(0), "ProofSystem impl deployed");
        assertTrue(result.hostEarningsProxy != address(0), "HostEarnings proxy deployed");
        assertTrue(result.hostEarningsImpl != address(0), "HostEarnings impl deployed");
        assertTrue(result.nodeRegistryProxy != address(0), "NodeRegistry proxy deployed");
        assertTrue(result.nodeRegistryImpl != address(0), "NodeRegistry impl deployed");
        assertTrue(result.jobMarketplaceProxy != address(0), "JobMarketplace proxy deployed");
        assertTrue(result.jobMarketplaceImpl != address(0), "JobMarketplace impl deployed");
    }

    function test_ProxiesAreDistinctFromImplementations() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        assertTrue(result.modelRegistryProxy != result.modelRegistryImpl, "ModelRegistry proxy != impl");
        assertTrue(result.proofSystemProxy != result.proofSystemImpl, "ProofSystem proxy != impl");
        assertTrue(result.hostEarningsProxy != result.hostEarningsImpl, "HostEarnings proxy != impl");
        assertTrue(result.nodeRegistryProxy != result.nodeRegistryImpl, "NodeRegistry proxy != impl");
        assertTrue(result.jobMarketplaceProxy != result.jobMarketplaceImpl, "JobMarketplace proxy != impl");
    }

    function test_AllProxiesAreUnique() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        // All proxy addresses should be different
        assertTrue(result.modelRegistryProxy != result.proofSystemProxy, "MR != PS");
        assertTrue(result.modelRegistryProxy != result.hostEarningsProxy, "MR != HE");
        assertTrue(result.modelRegistryProxy != result.nodeRegistryProxy, "MR != NR");
        assertTrue(result.modelRegistryProxy != result.jobMarketplaceProxy, "MR != JM");
        assertTrue(result.proofSystemProxy != result.hostEarningsProxy, "PS != HE");
        assertTrue(result.proofSystemProxy != result.nodeRegistryProxy, "PS != NR");
        assertTrue(result.proofSystemProxy != result.jobMarketplaceProxy, "PS != JM");
        assertTrue(result.hostEarningsProxy != result.nodeRegistryProxy, "HE != NR");
        assertTrue(result.hostEarningsProxy != result.jobMarketplaceProxy, "HE != JM");
        assertTrue(result.nodeRegistryProxy != result.jobMarketplaceProxy, "NR != JM");
    }

    // ============================================================
    // Configuration Tests
    // ============================================================

    function test_ModelRegistryConfiguredCorrectly() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        ModelRegistryUpgradeable modelRegistry = ModelRegistryUpgradeable(result.modelRegistryProxy);
        assertEq(address(modelRegistry.governanceToken()), address(fabToken), "Governance token set");
        assertTrue(modelRegistry.owner() != address(0), "Owner set");
    }

    function test_ProofSystemConfiguredCorrectly() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(result.proofSystemProxy);
        assertTrue(proofSystem.owner() != address(0), "Owner set");
    }

    function test_HostEarningsConfiguredCorrectly() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(result.hostEarningsProxy));
        assertTrue(hostEarnings.owner() != address(0), "Owner set");
        assertTrue(hostEarnings.authorizedCallers(result.jobMarketplaceProxy), "JobMarketplace authorized");
    }

    function test_NodeRegistryConfiguredCorrectly() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(result.nodeRegistryProxy);
        assertEq(address(nodeRegistry.fabToken()), address(fabToken), "FAB token set");
        assertEq(address(nodeRegistry.modelRegistry()), result.modelRegistryProxy, "ModelRegistry set");
        assertTrue(nodeRegistry.owner() != address(0), "Owner set");
    }

    function test_JobMarketplaceConfiguredCorrectly() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(result.jobMarketplaceProxy));
        assertEq(address(marketplace.nodeRegistry()), result.nodeRegistryProxy, "NodeRegistry set");
        assertEq(address(marketplace.hostEarnings()), result.hostEarningsProxy, "HostEarnings set");
        assertEq(marketplace.FEE_BASIS_POINTS(), FEE_BASIS_POINTS, "Fee set");
        assertEq(marketplace.DISPUTE_WINDOW(), DISPUTE_WINDOW, "Dispute window set");
        assertTrue(marketplace.owner() != address(0), "Owner set");
    }

    // ============================================================
    // Implementation Slot Tests
    // ============================================================

    function test_ImplementationSlotsCorrect() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // Verify each proxy has correct implementation
        assertEq(
            address(uint160(uint256(vm.load(result.modelRegistryProxy, slot)))),
            result.modelRegistryImpl,
            "ModelRegistry impl slot"
        );
        assertEq(
            address(uint160(uint256(vm.load(result.proofSystemProxy, slot)))),
            result.proofSystemImpl,
            "ProofSystem impl slot"
        );
        assertEq(
            address(uint160(uint256(vm.load(result.hostEarningsProxy, slot)))),
            result.hostEarningsImpl,
            "HostEarnings impl slot"
        );
        assertEq(
            address(uint160(uint256(vm.load(result.nodeRegistryProxy, slot)))),
            result.nodeRegistryImpl,
            "NodeRegistry impl slot"
        );
        assertEq(
            address(uint160(uint256(vm.load(result.jobMarketplaceProxy, slot)))),
            result.jobMarketplaceImpl,
            "JobMarketplace impl slot"
        );
    }

    // ============================================================
    // End-to-End Flow Test
    // ============================================================

    function test_EndToEndFlowAfterDeployment() public {
        DeployAllUpgradeable.DeploymentResult memory result = deployScript.run();

        // Get contract instances
        ModelRegistryUpgradeable modelRegistry = ModelRegistryUpgradeable(result.modelRegistryProxy);
        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(result.nodeRegistryProxy);
        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(result.jobMarketplaceProxy));
        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(result.hostEarningsProxy));

        // Step 1: Add a model (as owner)
        address owner = modelRegistry.owner();
        vm.prank(owner);
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        bytes32 modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        // Step 2: Register a host
        address host = address(0x100);
        fabToken.mint(host, 10000 * 10**18);

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode('{"hardware": "GPU"}', "https://host.com", models, 227_273, 1);
        vm.stopPrank();

        assertTrue(nodeRegistry.isActiveNode(host), "Host registered");

        // Step 3: Create a session
        address user = address(0x200);
        vm.deal(user, 10 ether);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(host, 227_273, 1 days, 1000);
        assertEq(sessionId, 1, "Session created");

        // Step 4: Submit proof
        vm.warp(100);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 500, bytes32(uint256(1)), "QmProof");

        // Step 5: Complete session
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Step 6: Verify host earnings
        assertTrue(hostEarnings.getBalance(host, address(0)) > 0, "Host earned");
    }
}
