// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryWithModelsUpgradeable Initialization Tests
 * @dev Tests initialization, re-initialization protection, and basic proxy functionality
 */
contract NodeRegistryInitializationTest is Test {
    NodeRegistryWithModelsUpgradeable public implementation;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host1 = address(0x2);
    address public host2 = address(0x3);

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

        // Mint FAB tokens for hosts
        fabToken.mint(host1, 10000 * 10**18);
        fabToken.mint(host2, 10000 * 10**18);

        // Approve spending
        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
        vm.prank(host2);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
    }

    // ============================================================
    // Initialization Tests
    // ============================================================

    function test_InitializeSetsOwner() public view {
        assertEq(nodeRegistry.owner(), owner);
    }

    function test_InitializeSetsFabToken() public view {
        assertEq(address(nodeRegistry.fabToken()), address(fabToken));
    }

    function test_InitializeSetsModelRegistry() public view {
        assertEq(address(nodeRegistry.modelRegistry()), address(modelRegistry));
    }

    function test_InitializeCanOnlyBeCalledOnce() public {
        vm.expectRevert();
        nodeRegistry.initialize(address(fabToken), address(modelRegistry));
    }

    function test_InitializeRevertsWithZeroFabToken() public {
        NodeRegistryWithModelsUpgradeable newImpl = new NodeRegistryWithModelsUpgradeable();

        vm.expectRevert("Invalid FAB token address");
        address(new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(0), address(modelRegistry)))
        ));
    }

    function test_InitializeRevertsWithZeroModelRegistry() public {
        NodeRegistryWithModelsUpgradeable newImpl = new NodeRegistryWithModelsUpgradeable();

        vm.expectRevert("Invalid model registry address");
        address(new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(0)))
        ));
    }

    function test_ImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(address(fabToken), address(modelRegistry));
    }

    // ============================================================
    // Node Registration Tests
    // ============================================================

    function test_RegisterNodeWorks() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        assertTrue(nodeRegistry.isActiveNode(host1));
        assertEq(nodeRegistry.getNodeApiUrl(host1), "https://api.host1.com");
    }

    function test_RegisterNodeTransfersStake() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        uint256 balanceBefore = fabToken.balanceOf(host1);

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        assertEq(fabToken.balanceOf(host1), balanceBefore - MIN_STAKE);
        assertEq(fabToken.balanceOf(address(nodeRegistry)), MIN_STAKE);
    }

    function test_RegisterNodeRejectsUnapprovedModel() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = bytes32(uint256(0x9999)); // Unapproved model

        vm.prank(host1);
        vm.expectRevert("Model not approved");
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    function test_RegisterNodeRejectsEmptyMetadata() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        vm.expectRevert("Empty metadata");
        nodeRegistry.registerNode(
            '',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    function test_RegisterNodeRejectsDoubleRegistration() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.startPrank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        vm.expectRevert("Already registered");
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
        vm.stopPrank();
    }

    // ============================================================
    // Model Query Tests
    // ============================================================

    function test_GetNodeModels() public {
        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        bytes32[] memory nodeModels = nodeRegistry.getNodeModels(host1);
        assertEq(nodeModels.length, 2);
        assertEq(nodeModels[0], modelId1);
        assertEq(nodeModels[1], modelId2);
    }

    function test_NodeSupportsModel() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        assertTrue(nodeRegistry.nodeSupportsModel(host1, modelId1));
        assertFalse(nodeRegistry.nodeSupportsModel(host1, modelId2));
    }

    function test_GetNodesForModel() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        vm.prank(host2);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host2.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 2);
    }

    // ============================================================
    // Pricing Tests
    // ============================================================

    function test_GetNodePricingNative() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE * 2,
            MIN_PRICE_STABLE
        );

        assertEq(nodeRegistry.getNodePricing(host1, address(0)), MIN_PRICE_NATIVE * 2);
    }

    function test_GetNodePricingStable() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE * 100
        );

        assertEq(nodeRegistry.getNodePricing(host1, address(fabToken)), MIN_PRICE_STABLE * 100);
    }

    function test_UpdatePricingNative() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        vm.prank(host1);
        nodeRegistry.updatePricingNative(MIN_PRICE_NATIVE * 5);

        assertEq(nodeRegistry.getNodePricing(host1, address(0)), MIN_PRICE_NATIVE * 5);
    }

    // ============================================================
    // Unregister Tests
    // ============================================================

    function test_UnregisterNodeReturnsStake() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        uint256 balanceBefore = fabToken.balanceOf(host1);

        vm.prank(host1);
        nodeRegistry.unregisterNode();

        assertEq(fabToken.balanceOf(host1), balanceBefore + MIN_STAKE);
        assertFalse(nodeRegistry.isActiveNode(host1));
    }

    // ============================================================
    // Constants Tests
    // ============================================================

    function test_ConstantsAreCorrect() public view {
        assertEq(nodeRegistry.MIN_STAKE(), 1000 * 10**18);
        assertEq(nodeRegistry.PRICE_PRECISION(), 1000);
        assertEq(nodeRegistry.MIN_PRICE_PER_TOKEN_STABLE(), 1);
        assertEq(nodeRegistry.MAX_PRICE_PER_TOKEN_STABLE(), 100_000_000);
    }
}
