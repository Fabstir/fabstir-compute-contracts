// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "../../mocks/ERC20Mock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title NodeRegistry Boundary Conditions Tests (Phase 18)
 * @notice Tests for min/max values, edge cases, and boundary conditions using setModelTokenPricing
 */
contract NodeRegistryBoundaryConditionsTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(this);
    address public host1 = address(0x1);
    address public host2 = address(0x2);

    bytes32 public modelId;
    uint256 public constant MIN_STAKE = 1000 * 10**18;

    // Price constants from contract
    uint256 public constant PRICE_PRECISION = 1000;
    uint256 public constant MIN_PRICE_PER_TOKEN_STABLE = 1;
    uint256 public constant MAX_PRICE_PER_TOKEN_STABLE = 100_000_000;
    uint256 public constant MIN_PRICE_PER_TOKEN_NATIVE = 227_273;
    uint256 public constant MAX_PRICE_PER_TOKEN_NATIVE = 22_727_272_727_273_000;

    function setUp() public {
        // Deploy FAB token and USDC mock
        fabToken = new ERC20Mock("FAB", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelImpl = new ModelRegistryUpgradeable();
        ERC1967Proxy modelProxy = new ERC1967Proxy(
            address(modelImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        modelRegistry = ModelRegistryUpgradeable(address(modelProxy));

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeImpl = new NodeRegistryWithModelsUpgradeable();
        ERC1967Proxy nodeProxy = new ERC1967Proxy(
            address(nodeImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(nodeProxy));

        // Add a trusted model
        modelRegistry.addTrustedModel("test/repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("test/repo", "model.gguf");

        // Fund hosts
        fabToken.mint(host1, MIN_STAKE * 10);
        fabToken.mint(host2, MIN_STAKE * 10);
    }

    // ============ Registration Price Boundaries ============

    function test_RegisterNode_RejectsNativePriceBelowMinimum() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        vm.expectRevert("Native price below minimum");
        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MIN_PRICE_PER_TOKEN_NATIVE - 1,  // Below minimum
            MIN_PRICE_PER_TOKEN_STABLE
        );
        vm.stopPrank();
    }

    function test_RegisterNode_RejectsNativePriceAboveMaximum() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        vm.expectRevert("Native price above maximum");
        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MAX_PRICE_PER_TOKEN_NATIVE + 1,  // Above maximum
            MIN_PRICE_PER_TOKEN_STABLE
        );
        vm.stopPrank();
    }

    function test_RegisterNode_RejectsStablePriceBelowMinimum() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        vm.expectRevert("Stable price below minimum");
        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MIN_PRICE_PER_TOKEN_NATIVE,
            0  // Below minimum (MIN is 1)
        );
        vm.stopPrank();
    }

    function test_RegisterNode_RejectsStablePriceAboveMaximum() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        vm.expectRevert("Stable price above maximum");
        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MIN_PRICE_PER_TOKEN_NATIVE,
            MAX_PRICE_PER_TOKEN_STABLE + 1  // Above maximum
        );
        vm.stopPrank();
    }

    function test_RegisterNode_AcceptsMinimumPrices() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MIN_PRICE_PER_TOKEN_NATIVE,
            MIN_PRICE_PER_TOKEN_STABLE
        );
        vm.stopPrank();

        assertTrue(nodeRegistry.isActiveNode(host1));
    }

    function test_RegisterNode_AcceptsMaximumPrices() public {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MAX_PRICE_PER_TOKEN_NATIVE,
            MAX_PRICE_PER_TOKEN_STABLE
        );
        vm.stopPrank();

        assertTrue(nodeRegistry.isActiveNode(host1));
    }

    // ============ setModelTokenPricing Boundaries (Native) ============

    function test_SetModelTokenPricing_Native_RejectsBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Native price below minimum");
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_PER_TOKEN_NATIVE - 1);
    }

    function test_SetModelTokenPricing_Native_RejectsAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Native price above maximum");
        nodeRegistry.setModelTokenPricing(modelId, address(0), MAX_PRICE_PER_TOKEN_NATIVE + 1);
    }

    function test_SetModelTokenPricing_Native_AcceptsMinimum() public {
        _registerHost1();

        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_PER_TOKEN_NATIVE);

        uint256 price = nodeRegistry.getModelPricing(host1, modelId, address(0));
        assertEq(price, MIN_PRICE_PER_TOKEN_NATIVE);
    }

    function test_SetModelTokenPricing_Native_AcceptsMaximum() public {
        _registerHost1();

        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MAX_PRICE_PER_TOKEN_NATIVE);

        uint256 price = nodeRegistry.getModelPricing(host1, modelId, address(0));
        assertEq(price, MAX_PRICE_PER_TOKEN_NATIVE);
    }

    // ============ setModelTokenPricing Boundaries (Stable) ============

    function test_SetModelTokenPricing_Stable_RejectsBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        // MIN is 1, so 0 should revert (setModelTokenPricing does NOT allow zero for stable)
        vm.expectRevert("Stable price below minimum");
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 0);
    }

    function test_SetModelTokenPricing_Stable_RejectsAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Stable price above maximum");
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MAX_PRICE_PER_TOKEN_STABLE + 1);
    }

    function test_SetModelTokenPricing_Stable_AcceptsMinimum() public {
        _registerHost1();

        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_PER_TOKEN_STABLE);

        uint256 price = nodeRegistry.getModelPricing(host1, modelId, address(usdcToken));
        assertEq(price, MIN_PRICE_PER_TOKEN_STABLE);
    }

    function test_SetModelTokenPricing_Stable_AcceptsMaximum() public {
        _registerHost1();

        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MAX_PRICE_PER_TOKEN_STABLE);

        uint256 price = nodeRegistry.getModelPricing(host1, modelId, address(usdcToken));
        assertEq(price, MAX_PRICE_PER_TOKEN_STABLE);
    }

    // ============ clearModelTokenPricing ============

    function test_ClearModelTokenPricing_MakesPricingRevertAgain() public {
        _registerHost1();

        vm.startPrank(host1);
        // Set then clear
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50_000);
        assertEq(nodeRegistry.getModelPricing(host1, modelId, address(usdcToken)), 50_000);

        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
        vm.stopPrank();

        // After clearing, getModelPricing should revert since no modelTokenPricing is set
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host1, modelId, address(usdcToken));
    }

    // ============ getHostModelPrices (new 2-arg signature) ============

    function test_GetHostModelPrices_ReturnsEmptyForNonRegistered() public view {
        (bytes32[] memory modelIds, uint256[] memory prices) =
            nodeRegistry.getHostModelPrices(address(0x999), address(usdcToken));

        assertEq(modelIds.length, 0);
        assertEq(prices.length, 0);
    }

    function test_GetHostModelPrices_ReturnsCorrectPrices() public {
        _registerHost1();

        // Set model-token pricing
        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_PER_TOKEN_STABLE * 5);

        (bytes32[] memory modelIds, uint256[] memory prices) =
            nodeRegistry.getHostModelPrices(host1, address(usdcToken));

        assertEq(modelIds.length, 1);
        assertEq(modelIds[0], modelId);
        assertEq(prices[0], MIN_PRICE_PER_TOKEN_STABLE * 5);
    }

    function test_GetHostModelPrices_ReturnsZeroWhenNoPricingSet() public {
        _registerHost1();

        // Don't set model-token pricing — should return 0
        (bytes32[] memory modelIds, uint256[] memory prices) =
            nodeRegistry.getHostModelPrices(host1, address(usdcToken));

        assertEq(modelIds.length, 1);
        assertEq(modelIds[0], modelId);
        assertEq(prices[0], 0);
    }

    // ============ getModelPricing fallback behavior ============

    function test_GetModelPricing_ReturnsZeroForNonRegistered() public view {
        uint256 result = nodeRegistry.getModelPricing(address(0x999), modelId, address(0));
        assertEq(result, 0);
    }

    function test_GetModelPricing_NativeRevertsWhenNoPricing() public {
        _registerHost1();

        // No modelTokenPricing set for native — should revert (no fallback)
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host1, modelId, address(0));
    }

    function test_GetModelPricing_StableRevertsWhenNoPricing() public {
        _registerHost1();

        // No modelTokenPricing set for stable — should revert
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host1, modelId, address(usdcToken));
    }

    // ============ Helper Functions ============

    function _registerHost1() internal {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        nodeRegistry.registerNode(
            "metadata",
            "http://api.url",
            models,
            MIN_PRICE_PER_TOKEN_NATIVE,
            MIN_PRICE_PER_TOKEN_STABLE
        );
        vm.stopPrank();
    }
}
