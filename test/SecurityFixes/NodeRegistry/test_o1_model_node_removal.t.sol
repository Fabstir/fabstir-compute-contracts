// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title O1ModelNodeRemovalTest
 * @notice Tests for Phase 7: O(1) modelToNodes array removal
 * @dev Verifies that _removeNodeFromModel uses O(1) indexed removal
 */
contract O1ModelNodeRemovalTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;

    address public owner = address(this);
    address public node1 = address(0x1001);
    address public node2 = address(0x1002);
    address public node3 = address(0x1003);

    bytes32 public modelId1;
    bytes32 public modelId2;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 2272727273; // MIN_PRICE_PER_TOKEN_NATIVE
    uint256 constant MIN_PRICE_STABLE = 10; // MIN_PRICE_PER_TOKEN_STABLE

    function setUp() public {
        // Deploy FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry with proxy
        ModelRegistryUpgradeable modelImpl = new ModelRegistryUpgradeable();
        ERC1967Proxy modelProxy = new ERC1967Proxy(
            address(modelImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        modelRegistry = ModelRegistryUpgradeable(address(modelProxy));

        // Add trusted models
        modelRegistry.addTrustedModel("repo1", "model1.gguf", keccak256("hash1"));
        modelRegistry.addTrustedModel("repo2", "model2.gguf", keccak256("hash2"));
        modelId1 = modelRegistry.getModelId("repo1", "model1.gguf");
        modelId2 = modelRegistry.getModelId("repo2", "model2.gguf");

        // Deploy NodeRegistry with proxy
        NodeRegistryWithModelsUpgradeable nodeImpl = new NodeRegistryWithModelsUpgradeable();
        ERC1967Proxy nodeProxy = new ERC1967Proxy(
            address(nodeImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (
                address(fabToken),
                address(modelRegistry)
            ))
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(nodeProxy));
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    function _setupNodeWithTokens(address node) internal {
        fabToken.mint(node, MIN_STAKE * 2);
        vm.prank(node);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
    }

    function _registerNode(address node, bytes32[] memory models) internal {
        vm.prank(node);
        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    // ============================================================
    // Basic Functionality Tests
    // ============================================================

    function test_ModelToNodes_AddedOnRegister() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;
        _registerNode(node1, models);

        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 1);
        assertEq(nodesForModel[0], node1);
    }

    function test_ModelToNodes_MultipleNodesForModel() public {
        _setupNodeWithTokens(node1);
        _setupNodeWithTokens(node2);
        _setupNodeWithTokens(node3);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        _registerNode(node1, models);
        _registerNode(node2, models);
        _registerNode(node3, models);

        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 3);
    }

    function test_ModelToNodes_RemovedOnUnregister() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;
        _registerNode(node1, models);

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 1);

        vm.prank(node1);
        nodeRegistry.unregisterNode();

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 0);
    }

    function test_ModelToNodes_MiddleRemovalPreservesOthers() public {
        _setupNodeWithTokens(node1);
        _setupNodeWithTokens(node2);
        _setupNodeWithTokens(node3);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        _registerNode(node1, models);
        _registerNode(node2, models);
        _registerNode(node3, models);

        // Unregister middle node
        vm.prank(node2);
        nodeRegistry.unregisterNode();

        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 2);

        // Verify remaining nodes (order may change due to swap-remove)
        bool found1 = false;
        bool found3 = false;
        for (uint i = 0; i < nodesForModel.length; i++) {
            if (nodesForModel[i] == node1) found1 = true;
            if (nodesForModel[i] == node3) found3 = true;
        }
        assertTrue(found1, "Node 1 should still be in list");
        assertTrue(found3, "Node 3 should still be in list");
    }

    function test_ModelToNodes_FirstRemovalPreservesOthers() public {
        _setupNodeWithTokens(node1);
        _setupNodeWithTokens(node2);
        _setupNodeWithTokens(node3);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        _registerNode(node1, models);
        _registerNode(node2, models);
        _registerNode(node3, models);

        // Unregister first node
        vm.prank(node1);
        nodeRegistry.unregisterNode();

        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 2);

        bool found2 = false;
        bool found3 = false;
        for (uint i = 0; i < nodesForModel.length; i++) {
            if (nodesForModel[i] == node2) found2 = true;
            if (nodesForModel[i] == node3) found3 = true;
        }
        assertTrue(found2, "Node 2 should still be in list");
        assertTrue(found3, "Node 3 should still be in list");
    }

    function test_ModelToNodes_LastRemovalPreservesOthers() public {
        _setupNodeWithTokens(node1);
        _setupNodeWithTokens(node2);
        _setupNodeWithTokens(node3);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        _registerNode(node1, models);
        _registerNode(node2, models);
        _registerNode(node3, models);

        // Unregister last node
        vm.prank(node3);
        nodeRegistry.unregisterNode();

        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 2);

        bool found1 = false;
        bool found2 = false;
        for (uint i = 0; i < nodesForModel.length; i++) {
            if (nodesForModel[i] == node1) found1 = true;
            if (nodesForModel[i] == node2) found2 = true;
        }
        assertTrue(found1, "Node 1 should still be in list");
        assertTrue(found2, "Node 2 should still be in list");
    }

    // ============================================================
    // Update Supported Models Tests
    // ============================================================

    function test_UpdateModels_RemovesFromOldModel() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models1 = new bytes32[](1);
        models1[0] = modelId1;
        _registerNode(node1, models1);

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 1);

        // Update to different model
        bytes32[] memory models2 = new bytes32[](1);
        models2[0] = modelId2;
        vm.prank(node1);
        nodeRegistry.updateSupportedModels(models2);

        // Should be removed from model1 and added to model2
        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 0);
        assertEq(nodeRegistry.getNodesForModel(modelId2).length, 1);
    }

    function test_UpdateModels_AddsToNewModel() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models1 = new bytes32[](1);
        models1[0] = modelId1;
        _registerNode(node1, models1);

        // Update to support both models
        bytes32[] memory models2 = new bytes32[](2);
        models2[0] = modelId1;
        models2[1] = modelId2;
        vm.prank(node1);
        nodeRegistry.updateSupportedModels(models2);

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 1);
        assertEq(nodeRegistry.getNodesForModel(modelId2).length, 1);
    }

    // ============================================================
    // Gas Efficiency Tests
    // ============================================================

    function test_GasUsage_UnregisterNode_SingleModel() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;
        _registerNode(node1, models);

        uint256 gasBefore = gasleft();
        vm.prank(node1);
        nodeRegistry.unregisterNode();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("unregisterNode (1 model, 1 node) gas", gasUsed);
        assertLt(gasUsed, 150000, "Gas should be reasonable");
    }

    function test_GasUsage_UnregisterNode_MultipleNodes() public {
        // Register 5 nodes for same model
        address[] memory nodes = new address[](5);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        for (uint i = 0; i < 5; i++) {
            nodes[i] = address(uint160(0x2000 + i));
            _setupNodeWithTokens(nodes[i]);
            _registerNode(nodes[i], models);
        }

        // Unregister middle node and measure gas
        uint256 gasBefore = gasleft();
        vm.prank(nodes[2]);
        nodeRegistry.unregisterNode();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("unregisterNode (1 model, 5 nodes, middle) gas", gasUsed);
        // With O(1) removal, gas should be similar regardless of position
        assertLt(gasUsed, 150000, "Gas should be reasonable with O(1) removal");
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    function test_ModelToNodes_EmptyInitially() public {
        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 0);
    }

    function test_ModelToNodes_SingleAddRemove() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;
        _registerNode(node1, models);

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 1);

        vm.prank(node1);
        nodeRegistry.unregisterNode();

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 0);
    }

    function test_ModelToNodes_MultipleModelsPerNode() public {
        _setupNodeWithTokens(node1);

        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;
        _registerNode(node1, models);

        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 1);
        assertEq(nodeRegistry.getNodesForModel(modelId2).length, 1);

        vm.prank(node1);
        nodeRegistry.unregisterNode();

        // Should be removed from both models
        assertEq(nodeRegistry.getNodesForModel(modelId1).length, 0);
        assertEq(nodeRegistry.getNodesForModel(modelId2).length, 0);
    }
}
