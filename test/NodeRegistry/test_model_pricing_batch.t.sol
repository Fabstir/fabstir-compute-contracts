// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryModelPricingBatchTest
 * @notice Tests for getHostModelPrices() batch query function (Phase 1.5)
 * @dev Verifies efficient batch retrieval of all model prices for a host
 */
contract NodeRegistryModelPricingBatchTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredUser = address(3);

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant DEFAULT_NATIVE_PRICE = 3_000_000_000;
    uint256 constant DEFAULT_STABLE_PRICE = 2000;
    uint256 constant MODEL1_NATIVE_PRICE = 5_000_000_000;
    uint256 constant MODEL1_STABLE_PRICE = 5000;
    uint256 constant MODEL2_NATIVE_PRICE = 7_000_000_000;
    uint256 constant MODEL2_STABLE_PRICE = 7000;

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

    /// @notice Test that getHostModelPrices returns all supported models
    function test_ReturnsAllSupportedModels() public view {
        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        assertEq(modelIds.length, 2, "Should return 2 models");
        assertEq(nativePrices.length, 2, "Should return 2 native prices");
        assertEq(stablePrices.length, 2, "Should return 2 stable prices");

        // Verify model IDs
        assertEq(modelIds[0], modelId1, "First model ID should match");
        assertEq(modelIds[1], modelId2, "Second model ID should match");
    }

    /// @notice Test that returns default prices when no model overrides set
    function test_ReturnsDefaultPricesWhenNoOverrides() public view {
        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // All prices should be defaults since no overrides set
        for (uint i = 0; i < modelIds.length; i++) {
            assertEq(nativePrices[i], DEFAULT_NATIVE_PRICE, "Should return default native price");
            assertEq(stablePrices[i], DEFAULT_STABLE_PRICE, "Should return default stable price");
        }
    }

    /// @notice Test that returns effective price (override when set, default otherwise)
    function test_ReturnsEffectivePriceOverrideOrDefault() public {
        // Set override for model1 only
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL1_NATIVE_PRICE, MODEL1_STABLE_PRICE);

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // Model1 should have override prices
        assertEq(nativePrices[0], MODEL1_NATIVE_PRICE, "Model1 should have override native price");
        assertEq(stablePrices[0], MODEL1_STABLE_PRICE, "Model1 should have override stable price");

        // Model2 should have default prices (no override)
        assertEq(nativePrices[1], DEFAULT_NATIVE_PRICE, "Model2 should have default native price");
        assertEq(stablePrices[1], DEFAULT_STABLE_PRICE, "Model2 should have default stable price");
    }

    /// @notice Test that returns empty arrays for non-registered operator
    function test_ReturnsEmptyArraysForNonRegisteredOperator() public view {
        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(nonRegisteredUser);

        assertEq(modelIds.length, 0, "Should return empty model IDs array");
        assertEq(nativePrices.length, 0, "Should return empty native prices array");
        assertEq(stablePrices.length, 0, "Should return empty stable prices array");
    }

    /// @notice Test with all models having overrides
    function test_AllModelsWithOverrides() public {
        // Set overrides for both models
        vm.startPrank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL1_NATIVE_PRICE, MODEL1_STABLE_PRICE);
        nodeRegistry.setModelPricing(modelId2, MODEL2_NATIVE_PRICE, MODEL2_STABLE_PRICE);
        vm.stopPrank();

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        assertEq(nativePrices[0], MODEL1_NATIVE_PRICE, "Model1 native price mismatch");
        assertEq(stablePrices[0], MODEL1_STABLE_PRICE, "Model1 stable price mismatch");
        assertEq(nativePrices[1], MODEL2_NATIVE_PRICE, "Model2 native price mismatch");
        assertEq(stablePrices[1], MODEL2_STABLE_PRICE, "Model2 stable price mismatch");
    }

    /// @notice Test partial override (only native set for one model)
    function test_PartialOverrideOnlyNative() public {
        // Set only native price for model1
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL1_NATIVE_PRICE, 0);

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // Model1: native override, stable default
        assertEq(nativePrices[0], MODEL1_NATIVE_PRICE, "Model1 should have override native price");
        assertEq(stablePrices[0], DEFAULT_STABLE_PRICE, "Model1 should have default stable price");

        // Model2: both default
        assertEq(nativePrices[1], DEFAULT_NATIVE_PRICE, "Model2 should have default native price");
        assertEq(stablePrices[1], DEFAULT_STABLE_PRICE, "Model2 should have default stable price");
    }

    /// @notice Test partial override (only stable set for one model)
    function test_PartialOverrideOnlyStable() public {
        // Set only stable price for model2
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId2, 0, MODEL2_STABLE_PRICE);

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // Model1: both default
        assertEq(nativePrices[0], DEFAULT_NATIVE_PRICE, "Model1 should have default native price");
        assertEq(stablePrices[0], DEFAULT_STABLE_PRICE, "Model1 should have default stable price");

        // Model2: native default, stable override
        assertEq(nativePrices[1], DEFAULT_NATIVE_PRICE, "Model2 should have default native price");
        assertEq(stablePrices[1], MODEL2_STABLE_PRICE, "Model2 should have override stable price");
    }

    /// @notice Test consistency with getModelPricing for individual queries
    function test_ConsistencyWithGetModelPricing() public {
        // Set override for model1
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL1_NATIVE_PRICE, MODEL1_STABLE_PRICE);

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // Verify batch results match individual queries
        for (uint i = 0; i < modelIds.length; i++) {
            uint256 expectedNative = nodeRegistry.getModelPricing(host, modelIds[i], address(0));
            uint256 expectedStable = nodeRegistry.getModelPricing(host, modelIds[i], address(1));

            assertEq(nativePrices[i], expectedNative, "Batch native price should match individual query");
            assertEq(stablePrices[i], expectedStable, "Batch stable price should match individual query");
        }
    }

    /// @notice Test after clearing model pricing
    function test_AfterClearingModelPricing() public {
        // Set and then clear override for model1
        vm.startPrank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL1_NATIVE_PRICE, MODEL1_STABLE_PRICE);
        nodeRegistry.clearModelPricing(modelId1);
        vm.stopPrank();

        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // Model1 should now return default (override was cleared)
        assertEq(nativePrices[0], DEFAULT_NATIVE_PRICE, "Model1 should return default after clear");
        assertEq(stablePrices[0], DEFAULT_STABLE_PRICE, "Model1 should return default after clear");
    }

    /// @notice Test gas efficiency - batch query should be cheaper than multiple individual queries
    function test_BatchQueryIsEfficient() public view {
        // This test verifies the function works correctly
        // Gas comparison would be done in gas reports
        (bytes32[] memory modelIds, uint256[] memory nativePrices, uint256[] memory stablePrices) =
            nodeRegistry.getHostModelPrices(host);

        // Just verify it returns valid data
        assertEq(modelIds.length, 2);
        assertEq(nativePrices.length, 2);
        assertEq(stablePrices.length, 2);
    }
}
