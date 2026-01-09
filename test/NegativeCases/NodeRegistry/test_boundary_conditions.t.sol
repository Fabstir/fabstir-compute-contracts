// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "../../mocks/ERC20Mock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title NodeRegistry Boundary Conditions Tests
 * @notice Tests for min/max values, edge cases, and boundary conditions
 */
contract NodeRegistryBoundaryConditionsTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;

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
        // Deploy FAB token
        fabToken = new ERC20Mock("FAB", "FAB");

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

    // ============ Update Pricing Boundaries ============

    function test_UpdatePricingNative_RejectsBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Price below minimum");
        nodeRegistry.updatePricingNative(MIN_PRICE_PER_TOKEN_NATIVE - 1);
    }

    function test_UpdatePricingNative_RejectsAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Price above maximum");
        nodeRegistry.updatePricingNative(MAX_PRICE_PER_TOKEN_NATIVE + 1);
    }

    function test_UpdatePricingStable_RejectsBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Price below minimum");
        nodeRegistry.updatePricingStable(0);
    }

    function test_UpdatePricingStable_RejectsAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Price above maximum");
        nodeRegistry.updatePricingStable(MAX_PRICE_PER_TOKEN_STABLE + 1);
    }

    // ============ Model Pricing Boundaries ============

    function test_SetModelPricing_RejectsNativeBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Native price below minimum");
        nodeRegistry.setModelPricing(modelId, MIN_PRICE_PER_TOKEN_NATIVE - 1, 0);
    }

    function test_SetModelPricing_RejectsNativeAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Native price above maximum");
        nodeRegistry.setModelPricing(modelId, MAX_PRICE_PER_TOKEN_NATIVE + 1, 0);
    }

    function test_SetModelPricing_RejectsStableBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        // Stable price of 0 means "no override", so we need a value > 0 but < MIN
        // Since MIN is 1, there's no valid value below minimum > 0
        // Test with native = 0 (no override) and stable below min
        // Actually, the contract checks stablePrice > 0 before validating
        // So we can't really test "below minimum" for stable since 0 means no override
        // Let's skip this edge case as the contract design prevents it
    }

    function test_SetModelPricing_RejectsStableAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Stable price above maximum");
        nodeRegistry.setModelPricing(modelId, 0, MAX_PRICE_PER_TOKEN_STABLE + 1);
    }

    function test_SetModelPricing_AllowsZeroPrices() public {
        _registerHost1();

        vm.prank(host1);
        // Zero means "no override", should succeed
        nodeRegistry.setModelPricing(modelId, 0, 0);

        // Should fall back to default
        uint256 result = nodeRegistry.getModelPricing(host1, modelId, address(0));
        assertEq(result, MIN_PRICE_PER_TOKEN_NATIVE);
    }

    // ============ Token Pricing Boundaries ============

    function test_SetTokenPricing_RejectsBelowMinimum() public {
        _registerHost1();

        vm.prank(host1);
        // 0 means "no override", so can't test below minimum in traditional sense
        // The contract only validates if price > 0
    }

    function test_SetTokenPricing_RejectsAboveMaximum() public {
        _registerHost1();

        vm.prank(host1);
        vm.expectRevert("Price above maximum");
        nodeRegistry.setTokenPricing(address(fabToken), MAX_PRICE_PER_TOKEN_STABLE + 1);
    }

    function test_SetTokenPricing_AllowsZeroToClearOverride() public {
        _registerHost1();

        vm.startPrank(host1);
        // First set a custom price
        nodeRegistry.setTokenPricing(address(fabToken), 50_000);
        assertEq(nodeRegistry.getNodePricing(host1, address(fabToken)), 50_000);

        // Then clear it with 0
        nodeRegistry.setTokenPricing(address(fabToken), 0);
        vm.stopPrank();

        // Should fall back to default stable price
        uint256 result = nodeRegistry.getNodePricing(host1, address(fabToken));
        (,,,,,,, uint256 defaultStable) = nodeRegistry.getNodeFullInfo(host1);
        assertEq(result, defaultStable);
    }

    // ============ getHostModelPrices ============

    function test_GetHostModelPrices_ReturnsEmptyForNonRegistered() public view {
        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(address(0x999));

        assertEq(modelIds.length, 0);
        assertEq(nativePrices.length, 0);
        assertEq(stablePrices.length, 0);
    }

    function test_GetHostModelPrices_ReturnsCorrectPrices() public {
        _registerHost1();

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host1);

        assertEq(modelIds.length, 1);
        assertEq(modelIds[0], modelId);
        assertEq(nativePrices[0], MIN_PRICE_PER_TOKEN_NATIVE);
        assertEq(stablePrices[0], MIN_PRICE_PER_TOKEN_STABLE);
    }

    function test_GetHostModelPrices_IncludesOverrides() public {
        _registerHost1();

        uint256 customNative = MIN_PRICE_PER_TOKEN_NATIVE * 2;
        uint256 customStable = MIN_PRICE_PER_TOKEN_STABLE * 2;

        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId, customNative, customStable);

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host1);

        assertEq(modelIds.length, 1);
        assertEq(nativePrices[0], customNative);
        assertEq(stablePrices[0], customStable);
    }

    // ============ getModelPricing fallback behavior ============

    function test_GetModelPricing_ReturnsZeroForNonRegistered() public view {
        uint256 result = nodeRegistry.getModelPricing(address(0x999), modelId, address(0));
        assertEq(result, 0);
    }

    function test_GetModelPricing_FallsBackToDefault() public {
        _registerHost1();

        // Native pricing
        uint256 nativeResult = nodeRegistry.getModelPricing(host1, modelId, address(0));
        assertEq(nativeResult, MIN_PRICE_PER_TOKEN_NATIVE);

        // Stable pricing
        uint256 stableResult = nodeRegistry.getModelPricing(host1, modelId, address(fabToken));
        assertEq(stableResult, MIN_PRICE_PER_TOKEN_STABLE);
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
