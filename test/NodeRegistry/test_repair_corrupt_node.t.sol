// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title RepairCorruptNodeTest
 * @notice Tests for the repairCorruptNode admin function
 * @dev Tests handling of corrupt node state from contract upgrades
 */
contract RepairCorruptNodeTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public host2 = address(0x3);
    address public host3 = address(0x4);
    address public corruptHost = address(0x5);

    bytes32 public modelId1;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry as proxy
        vm.startPrank(owner);
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        vm.stopPrank();

        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry as proxy
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(proxyAddr);

        // Mint and approve FAB tokens for hosts
        _setupHost(host);
        _setupHost(host2);
        _setupHost(host3);
        _setupHost(corruptHost);
    }

    function _setupHost(address _host) internal {
        fabToken.mint(_host, 10000 * 10**18);
        vm.prank(_host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
    }

    function _registerHost(address _host, string memory metadata) internal {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(_host);
        nodeRegistry.registerNode(
            metadata,
            "https://api.example.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    /**
     * @notice Test that repairCorruptNode reverts for unregistered nodes
     */
    function test_RepairCorruptNode_RevertsForUnregisteredNode() public {
        vm.prank(owner);
        vm.expectRevert("Node not registered");
        nodeRegistry.repairCorruptNode(corruptHost);
    }

    /**
     * @notice Test that repairCorruptNode reverts for non-corrupt nodes
     */
    function test_RepairCorruptNode_RevertsForNonCorruptNode() public {
        // Register a normal node
        _registerHost(host, "host-metadata");

        // Try to repair - should fail because node is not corrupt
        vm.prank(owner);
        vm.expectRevert("Node is not corrupt - use unregisterNode instead");
        nodeRegistry.repairCorruptNode(host);
    }

    /**
     * @notice Test that repairCorruptNode can only be called by owner
     */
    function test_RepairCorruptNode_RevertsForNonOwner() public {
        vm.prank(host);
        vm.expectRevert();
        nodeRegistry.repairCorruptNode(corruptHost);
    }

    /**
     * @notice Test that unregisterNode handles normal state correctly
     */
    function test_UnregisterNode_HandlesNormalStateCorrectly() public {
        // Register a normal node first
        _registerHost(host, "host-metadata");

        // Verify normal state
        assertTrue(nodeRegistry.isActiveNode(host));
        address[] memory activeNodes = nodeRegistry.getAllActiveNodes();
        assertEq(activeNodes.length, 1);
        assertEq(activeNodes[0], host);

        // Unregister should work normally
        uint256 hostBalanceBefore = fabToken.balanceOf(host);
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Verify unregistration worked
        assertFalse(nodeRegistry.isActiveNode(host));
        assertEq(nodeRegistry.getAllActiveNodes().length, 0);
        assertEq(fabToken.balanceOf(host), hostBalanceBefore + MIN_STAKE);
    }

    /**
     * @notice Test that multiple hosts can unregister without issues
     */
    function test_UnregisterNode_MultipleHostsUnregister() public {
        // Register multiple hosts
        _registerHost(host, "host-metadata");
        _registerHost(host2, "host2-metadata");
        _registerHost(host3, "host3-metadata");

        assertEq(nodeRegistry.getAllActiveNodes().length, 3);

        // Unregister middle one
        vm.prank(host2);
        nodeRegistry.unregisterNode();

        address[] memory activeNodes = nodeRegistry.getAllActiveNodes();
        assertEq(activeNodes.length, 2);

        // Unregister first one
        vm.prank(host);
        nodeRegistry.unregisterNode();

        activeNodes = nodeRegistry.getAllActiveNodes();
        assertEq(activeNodes.length, 1);
        assertEq(activeNodes[0], host3);

        // Unregister last one
        vm.prank(host3);
        nodeRegistry.unregisterNode();

        assertEq(nodeRegistry.getAllActiveNodes().length, 0);
    }

    /**
     * @notice Test swap-and-pop pattern works correctly when unregistering middle element
     */
    function test_UnregisterNode_SwapAndPopWorksCorrectly() public {
        // Register 3 hosts
        _registerHost(host, "host1");
        _registerHost(host2, "host2");
        _registerHost(host3, "host3");

        // Order should be [host, host2, host3]
        address[] memory nodes = nodeRegistry.getAllActiveNodes();
        assertEq(nodes[0], host);
        assertEq(nodes[1], host2);
        assertEq(nodes[2], host3);

        // Unregister host (index 0) - host3 should be swapped to index 0
        vm.prank(host);
        nodeRegistry.unregisterNode();

        nodes = nodeRegistry.getAllActiveNodes();
        assertEq(nodes.length, 2);
        // host3 was swapped to position 0
        assertEq(nodes[0], host3);
        assertEq(nodes[1], host2);

        // Verify indexes are correct after swap
        assertEq(nodeRegistry.activeNodesIndex(host3), 0);
        assertEq(nodeRegistry.activeNodesIndex(host2), 1);
    }
}
