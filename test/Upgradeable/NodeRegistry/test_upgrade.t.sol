// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryWithModelsUpgradeable V2 (Mock for testing upgrades)
 */
contract NodeRegistryWithModelsUpgradeableV2 is NodeRegistryWithModelsUpgradeable {
    string public registryName;

    function initializeV2(string memory _name) external reinitializer(2) {
        registryName = _name;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }

    function getActiveNodeCount() external view returns (uint256) {
        return activeNodesList.length;
    }
}

/**
 * @title NodeRegistryWithModelsUpgradeable Upgrade Tests
 */
contract NodeRegistryUpgradeTest is Test {
    NodeRegistryWithModelsUpgradeable public implementation;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public host1 = address(0x3);
    address public host2 = address(0x4);

    bytes32 public modelId1;
    bytes32 public modelId2;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry
        vm.prank(owner);
        modelRegistry = new ModelRegistry(address(fabToken));

        // Add approved models
        vm.startPrank(owner);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelRegistry.addTrustedModel("Model2/Repo", "model2.gguf", bytes32(uint256(2)));
        vm.stopPrank();

        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");
        modelId2 = modelRegistry.getModelId("Model2/Repo", "model2.gguf");

        // Deploy implementation
        implementation = new NodeRegistryWithModelsUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(proxyAddr);

        // Mint FAB tokens for hosts and approve
        fabToken.mint(host1, 10000 * 10**18);
        fabToken.mint(host2, 10000 * 10**18);

        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
        vm.prank(host2);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        // Register some nodes
        bytes32[] memory models1 = new bytes32[](1);
        models1[0] = modelId1;

        bytes32[] memory models2 = new bytes32[](2);
        models2[0] = modelId1;
        models2[1] = modelId2;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU A100"}',
            "https://api.host1.com",
            models1,
            MIN_PRICE_NATIVE * 2,
            MIN_PRICE_STABLE * 50
        );

        vm.prank(host2);
        nodeRegistry.registerNode(
            '{"hardware": "GPU H100"}',
            "https://api.host2.com",
            models2,
            MIN_PRICE_NATIVE * 3,
            MIN_PRICE_STABLE * 100
        );
    }

    // ============================================================
    // Pre-Upgrade State Verification
    // ============================================================

    function test_PreUpgradeStateIsCorrect() public view {
        // Verify nodes registered
        assertTrue(nodeRegistry.isActiveNode(host1));
        assertTrue(nodeRegistry.isActiveNode(host2));

        // Verify pricing
        assertEq(nodeRegistry.getNodePricing(host1, address(0)), MIN_PRICE_NATIVE * 2);
        assertEq(nodeRegistry.getNodePricing(host2, address(0)), MIN_PRICE_NATIVE * 3);

        // Verify models
        assertTrue(nodeRegistry.nodeSupportsModel(host1, modelId1));
        assertTrue(nodeRegistry.nodeSupportsModel(host2, modelId1));
        assertTrue(nodeRegistry.nodeSupportsModel(host2, modelId2));

        // Verify owner and tokens
        assertEq(nodeRegistry.owner(), owner);
        assertEq(address(nodeRegistry.fabToken()), address(fabToken));
        assertEq(address(nodeRegistry.modelRegistry()), address(modelRegistry));
    }

    // ============================================================
    // Upgrade Authorization Tests
    // ============================================================

    function test_OnlyOwnerCanUpgrade() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(user1);
        vm.expectRevert();
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");
    }

    function test_OwnerCanUpgrade() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));
        assertEq(nodeRegistryV2.version(), "v2");
    }

    // ============================================================
    // State Preservation Tests
    // ============================================================

    function test_UpgradePreservesOwner() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));
        assertEq(nodeRegistryV2.owner(), owner);
    }

    function test_UpgradePreservesFabToken() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));
        assertEq(address(nodeRegistryV2.fabToken()), address(fabToken));
    }

    function test_UpgradePreservesModelRegistry() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));
        assertEq(address(nodeRegistryV2.modelRegistry()), address(modelRegistry));
    }

    function test_UpgradePreservesRegisteredNodes() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Verify nodes still registered
        assertTrue(nodeRegistryV2.isActiveNode(host1));
        assertTrue(nodeRegistryV2.isActiveNode(host2));
        assertEq(nodeRegistryV2.getActiveNodeCount(), 2);
    }

    function test_UpgradePreservesNodePricing() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Verify pricing preserved
        assertEq(nodeRegistryV2.getNodePricing(host1, address(0)), MIN_PRICE_NATIVE * 2);
        assertEq(nodeRegistryV2.getNodePricing(host2, address(0)), MIN_PRICE_NATIVE * 3);
        assertEq(nodeRegistryV2.getNodePricing(host1, address(fabToken)), MIN_PRICE_STABLE * 50);
        assertEq(nodeRegistryV2.getNodePricing(host2, address(fabToken)), MIN_PRICE_STABLE * 100);
    }

    function test_UpgradePreservesNodeModels() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Verify models preserved
        assertTrue(nodeRegistryV2.nodeSupportsModel(host1, modelId1));
        assertFalse(nodeRegistryV2.nodeSupportsModel(host1, modelId2));
        assertTrue(nodeRegistryV2.nodeSupportsModel(host2, modelId1));
        assertTrue(nodeRegistryV2.nodeSupportsModel(host2, modelId2));
    }

    function test_UpgradePreservesModelToNodesMapping() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Both hosts support modelId1
        address[] memory nodesForModel1 = nodeRegistryV2.getNodesForModel(modelId1);
        assertEq(nodesForModel1.length, 2);

        // Only host2 supports modelId2
        address[] memory nodesForModel2 = nodeRegistryV2.getNodesForModel(modelId2);
        assertEq(nodesForModel2.length, 1);
        assertEq(nodesForModel2[0], host2);
    }

    // ============================================================
    // Upgrade With Initialization Tests
    // ============================================================

    function test_UpgradeWithV2Initialization() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(NodeRegistryWithModelsUpgradeableV2.initializeV2, ("Node Registry V2"))
        );

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Verify V2 initialization
        assertEq(nodeRegistryV2.registryName(), "Node Registry V2");
        assertEq(nodeRegistryV2.version(), "v2");

        // Verify V1 state preserved
        assertEq(nodeRegistryV2.owner(), owner);
        assertTrue(nodeRegistryV2.isActiveNode(host1));
        assertTrue(nodeRegistryV2.isActiveNode(host2));
    }

    function test_V2InitializationCannotBeCalledTwice() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(NodeRegistryWithModelsUpgradeableV2.initializeV2, ("Node Registry V2"))
        );

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        vm.expectRevert();
        nodeRegistryV2.initializeV2("Another Name");
    }

    // ============================================================
    // Post-Upgrade Functionality Tests
    // ============================================================

    function test_CanRegisterNodesAfterUpgrade() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        // Register new node after upgrade
        address newHost = address(0x100);
        fabToken.mint(newHost, 10000 * 10**18);
        vm.prank(newHost);
        fabToken.approve(address(nodeRegistryV2), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(newHost);
        nodeRegistryV2.registerNode(
            '{"hardware": "GPU"}',
            "https://api.newhost.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        assertTrue(nodeRegistryV2.isActiveNode(newHost));
        assertEq(nodeRegistryV2.getActiveNodeCount(), 3);
    }

    function test_CanUnregisterAfterUpgrade() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        uint256 balanceBefore = fabToken.balanceOf(host1);

        vm.prank(host1);
        nodeRegistryV2.unregisterNode();

        assertFalse(nodeRegistryV2.isActiveNode(host1));
        assertEq(fabToken.balanceOf(host1), balanceBefore + MIN_STAKE);
        assertEq(nodeRegistryV2.getActiveNodeCount(), 1);
    }

    function test_CanUpdatePricingAfterUpgrade() public {
        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        NodeRegistryWithModelsUpgradeableV2 nodeRegistryV2 = NodeRegistryWithModelsUpgradeableV2(address(nodeRegistry));

        vm.prank(host1);
        nodeRegistryV2.updatePricingNative(MIN_PRICE_NATIVE * 10);

        assertEq(nodeRegistryV2.getNodePricing(host1, address(0)), MIN_PRICE_NATIVE * 10);
    }

    // ============================================================
    // Implementation Slot Verification
    // ============================================================

    function test_ImplementationSlotUpdatedAfterUpgrade() public {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implBefore = address(uint160(uint256(vm.load(address(nodeRegistry), slot))));
        assertEq(implBefore, address(implementation));

        NodeRegistryWithModelsUpgradeableV2 implementationV2 = new NodeRegistryWithModelsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(nodeRegistry)).upgradeToAndCall(address(implementationV2), "");

        address implAfter = address(uint160(uint256(vm.load(address(nodeRegistry), slot))));
        assertEq(implAfter, address(implementationV2));
        assertTrue(implAfter != implBefore);
    }
}
