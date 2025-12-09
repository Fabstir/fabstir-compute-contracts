// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryModelPricingQueriesTest
 * @notice Tests for getModelPricing() view function (Phase 1.3)
 * @dev Verifies model-specific pricing queries with fallback to default
 */
contract NodeRegistryModelPricingQueriesTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredUser = address(3);

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"));

    // Token addresses for testing
    address constant NATIVE_TOKEN = address(0);
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant DEFAULT_NATIVE_PRICE = 3_000_000_000;
    uint256 constant DEFAULT_STABLE_PRICE = 2000;
    uint256 constant MODEL_NATIVE_PRICE = 5_000_000_000;
    uint256 constant MODEL_STABLE_PRICE = 5000;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));

        // Add approved models
        modelRegistry.addTrustedModel(
            "CohereForAI/TinyVicuna-1B-32k-GGUF",
            "tiny-vicuna-1b.q4_k_m.gguf",
            bytes32(0)
        );
        modelRegistry.addTrustedModel(
            "TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF",
            "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            bytes32(0)
        );

        vm.stopPrank();

        // Give host FAB tokens and register
        vm.prank(owner);
        fabToken.mint(host, MIN_STAKE);

        _registerHost();
    }

    function _registerHost() internal {
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;

        nodeRegistry.registerNode(
            "test metadata",
            "https://api.example.com",
            models,
            DEFAULT_NATIVE_PRICE,
            DEFAULT_STABLE_PRICE
        );
        vm.stopPrank();
    }

    /// @notice Test that getModelPricing returns model-specific price when set (native)
    function test_ReturnsModelSpecificNativePriceWhenSet() public {
        // Set model-specific pricing
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Query should return model-specific price
        uint256 price = nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN);
        assertEq(price, MODEL_NATIVE_PRICE, "Should return model-specific native price");
    }

    /// @notice Test that getModelPricing returns model-specific price when set (stable)
    function test_ReturnsModelSpecificStablePriceWhenSet() public {
        // Set model-specific pricing
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Query should return model-specific price
        uint256 price = nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS);
        assertEq(price, MODEL_STABLE_PRICE, "Should return model-specific stable price");
    }

    /// @notice Test that getModelPricing falls back to default when model price is 0 (native)
    function test_FallsBackToDefaultNativeWhenModelPriceZero() public {
        // No model-specific pricing set, should return default
        uint256 price = nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN);
        assertEq(price, DEFAULT_NATIVE_PRICE, "Should fall back to default native price");
    }

    /// @notice Test that getModelPricing falls back to default when model price is 0 (stable)
    function test_FallsBackToDefaultStableWhenModelPriceZero() public {
        // No model-specific pricing set, should return default
        uint256 price = nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS);
        assertEq(price, DEFAULT_STABLE_PRICE, "Should fall back to default stable price");
    }

    /// @notice Test correct price for native token (address(0))
    function test_ReturnsCorrectPriceForNativeToken() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Native token = address(0)
        uint256 nativePrice = nodeRegistry.getModelPricing(host, modelId1, address(0));
        assertEq(nativePrice, MODEL_NATIVE_PRICE, "address(0) should return native price");
    }

    /// @notice Test correct price for stable token (non-zero address)
    function test_ReturnsCorrectPriceForStableToken() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Any non-zero address should return stable price
        uint256 stablePrice = nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS);
        assertEq(stablePrice, MODEL_STABLE_PRICE, "Non-zero address should return stable price");
    }

    /// @notice Test returns 0 for non-registered operator
    function test_ReturnsZeroForNonRegisteredOperator() public view {
        uint256 nativePrice = nodeRegistry.getModelPricing(nonRegisteredUser, modelId1, NATIVE_TOKEN);
        uint256 stablePrice = nodeRegistry.getModelPricing(nonRegisteredUser, modelId1, USDC_ADDRESS);

        assertEq(nativePrice, 0, "Should return 0 for non-registered operator (native)");
        assertEq(stablePrice, 0, "Should return 0 for non-registered operator (stable)");
    }

    /// @notice Test different models can have different prices
    function test_DifferentModelsReturnDifferentPrices() public {
        uint256 model1Native = 4_000_000_000;
        uint256 model1Stable = 4000;
        uint256 model2Native = 6_000_000_000;
        uint256 model2Stable = 6000;

        vm.startPrank(host);
        nodeRegistry.setModelPricing(modelId1, model1Native, model1Stable);
        nodeRegistry.setModelPricing(modelId2, model2Native, model2Stable);
        vm.stopPrank();

        // Query model1
        assertEq(nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN), model1Native);
        assertEq(nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS), model1Stable);

        // Query model2 (different prices)
        assertEq(nodeRegistry.getModelPricing(host, modelId2, NATIVE_TOKEN), model2Native);
        assertEq(nodeRegistry.getModelPricing(host, modelId2, USDC_ADDRESS), model2Stable);
    }

    /// @notice Test partial override: only native set, stable falls back to default
    function test_PartialOverrideNativeOnly() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, 0); // Only set native

        uint256 nativePrice = nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN);
        uint256 stablePrice = nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS);

        assertEq(nativePrice, MODEL_NATIVE_PRICE, "Should return model-specific native price");
        assertEq(stablePrice, DEFAULT_STABLE_PRICE, "Should fall back to default stable price");
    }

    /// @notice Test partial override: only stable set, native falls back to default
    function test_PartialOverrideStableOnly() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, 0, MODEL_STABLE_PRICE); // Only set stable

        uint256 nativePrice = nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN);
        uint256 stablePrice = nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS);

        assertEq(nativePrice, DEFAULT_NATIVE_PRICE, "Should fall back to default native price");
        assertEq(stablePrice, MODEL_STABLE_PRICE, "Should return model-specific stable price");
    }

    /// @notice Test clearing override returns to default
    function test_ClearingOverrideReturnsToDefault() public {
        // Set model pricing
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Verify override is active
        assertEq(nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN), MODEL_NATIVE_PRICE);

        // Clear override (set to 0)
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, 0, 0);

        // Should now return default
        assertEq(nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN), DEFAULT_NATIVE_PRICE);
        assertEq(nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS), DEFAULT_STABLE_PRICE);
    }

    /// @notice Test querying with any stablecoin address returns stable price
    function test_AnyStablecoinAddressReturnsStablePrice() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Different stablecoin addresses should all return stable price
        address dai = address(0x1111111111111111111111111111111111111111);
        address usdt = address(0x2222222222222222222222222222222222222222);

        assertEq(nodeRegistry.getModelPricing(host, modelId1, dai), MODEL_STABLE_PRICE);
        assertEq(nodeRegistry.getModelPricing(host, modelId1, usdt), MODEL_STABLE_PRICE);
        assertEq(nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS), MODEL_STABLE_PRICE);
    }

    /// @notice Test consistency with existing getNodePricing when no model override
    function test_ConsistencyWithGetNodePricingWhenNoOverride() public view {
        // getModelPricing with no override should match getNodePricing
        uint256 modelNative = nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN);
        uint256 modelStable = nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS);

        uint256 nodeNative = nodeRegistry.getNodePricing(host, NATIVE_TOKEN);
        uint256 nodeStable = nodeRegistry.getNodePricing(host, USDC_ADDRESS);

        assertEq(modelNative, nodeNative, "Model pricing should match node pricing when no override");
        assertEq(modelStable, nodeStable, "Model pricing should match node pricing when no override");
    }
}
