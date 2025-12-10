// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryModelPricingSetterTest
 * @notice Tests for setModelPricing() function (Phase 1.2)
 * @dev Verifies that hosts can set per-model pricing overrides
 */
contract NodeRegistryModelPricingSetterTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredUser = address(3);

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"));
    bytes32 public unsupportedModelId = keccak256(abi.encodePacked("unsupported/model", "/", "unsupported.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    // With PRICE_PRECISION=1000: prices are 1000x for sub-cent granularity
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MAX_PRICE_NATIVE = 22_727_272_727_273_000;
    uint256 constant MAX_PRICE_STABLE = 100_000_000;

    // Valid test prices within range
    uint256 constant VALID_NATIVE_PRICE = 5_000_000; // ~$0.022/million
    uint256 constant VALID_STABLE_PRICE = 5000; // $5/million

    event ModelPricingUpdated(address indexed operator, bytes32 indexed modelId, uint256 nativePrice, uint256 stablePrice);

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
            MIN_PRICE_NATIVE,  // default native price
            MIN_PRICE_STABLE   // default stable price
        );
        vm.stopPrank();
    }

    /// @notice Test that registered host can set model pricing
    function test_RegisteredHostCanSetModelPricing() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);

        // Verify prices were stored
        uint256 storedNative = nodeRegistry.modelPricingNative(host, modelId1);
        uint256 storedStable = nodeRegistry.modelPricingStable(host, modelId1);

        assertEq(storedNative, VALID_NATIVE_PRICE, "Native price not stored correctly");
        assertEq(storedStable, VALID_STABLE_PRICE, "Stable price not stored correctly");
    }

    /// @notice Test that setting price to 0 clears the override (uses default)
    function test_SettingPriceToZeroClearsOverride() public {
        // First set a price
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);

        // Verify it was set
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), VALID_NATIVE_PRICE);

        // Now set to 0 to clear
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, 0, 0);

        // Verify it's cleared (back to 0, meaning use default)
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0, "Native price should be cleared");
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0, "Stable price should be cleared");
    }

    /// @notice Test that non-registered address cannot set model pricing
    function test_NonRegisteredCannotSetModelPricing() public {
        vm.prank(nonRegisteredUser);
        vm.expectRevert("Not registered");
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);
    }

    /// @notice Test that inactive host cannot set model pricing
    function test_InactiveHostCannotSetModelPricing() public {
        // Unregister to make inactive
        vm.prank(host);
        nodeRegistry.unregisterNode();

        vm.prank(host);
        vm.expectRevert("Not registered");
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);
    }

    /// @notice Test that cannot set pricing for unsupported model
    function test_CannotSetPricingForUnsupportedModel() public {
        vm.prank(host);
        vm.expectRevert("Model not supported");
        nodeRegistry.setModelPricing(unsupportedModelId, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);
    }

    /// @notice Test that invalid native prices are rejected (too low)
    function test_InvalidNativePriceTooLow() public {
        vm.prank(host);
        vm.expectRevert("Native price below minimum");
        nodeRegistry.setModelPricing(modelId1, MIN_PRICE_NATIVE - 1, VALID_STABLE_PRICE);
    }

    /// @notice Test that invalid native prices are rejected (too high)
    function test_InvalidNativePriceTooHigh() public {
        vm.prank(host);
        vm.expectRevert("Native price above maximum");
        nodeRegistry.setModelPricing(modelId1, MAX_PRICE_NATIVE + 1, VALID_STABLE_PRICE);
    }

    /// @notice Test that zero stable price is allowed (clears override to use default)
    /// @dev With MIN_PRICE_PER_TOKEN_STABLE=1, 0 is specifically allowed for clearing
    function test_ZeroStablePriceAllowedForClearing() public {
        // Set model pricing with 0 stable price (uses default)
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, 0);

        // Verify native price is set but stable falls back to default
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), VALID_NATIVE_PRICE, "Native price should be set");
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0, "Stable price should be 0 (use default)");
    }

    /// @notice Test that invalid stable prices are rejected (too high)
    function test_InvalidStablePriceTooHigh() public {
        vm.prank(host);
        vm.expectRevert("Stable price above maximum");
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, MAX_PRICE_STABLE + 1);
    }

    /// @notice Test that ModelPricingUpdated event is emitted correctly
    function test_ModelPricingUpdatedEventEmitted() public {
        vm.prank(host);

        vm.expectEmit(true, true, false, true);
        emit ModelPricingUpdated(host, modelId1, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);

        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, VALID_STABLE_PRICE);
    }

    /// @notice Test that host can set different prices for different models
    function test_DifferentPricesForDifferentModels() public {
        uint256 model1Native = 3_000_000_000;
        uint256 model1Stable = 3000;
        uint256 model2Native = 6_000_000_000;
        uint256 model2Stable = 6000;

        vm.startPrank(host);
        nodeRegistry.setModelPricing(modelId1, model1Native, model1Stable);
        nodeRegistry.setModelPricing(modelId2, model2Native, model2Stable);
        vm.stopPrank();

        // Verify model1 prices
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), model1Native);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), model1Stable);

        // Verify model2 prices (different)
        assertEq(nodeRegistry.modelPricingNative(host, modelId2), model2Native);
        assertEq(nodeRegistry.modelPricingStable(host, modelId2), model2Stable);
    }

    /// @notice Test that setting only native price works (stable = 0 means use default)
    function test_SetOnlyNativePrice() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, VALID_NATIVE_PRICE, 0);

        assertEq(nodeRegistry.modelPricingNative(host, modelId1), VALID_NATIVE_PRICE);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0); // Use default
    }

    /// @notice Test that setting only stable price works (native = 0 means use default)
    function test_SetOnlyStablePrice() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, 0, VALID_STABLE_PRICE);

        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0); // Use default
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), VALID_STABLE_PRICE);
    }

    /// @notice Test boundary values: minimum valid prices
    function test_MinimumValidPrices() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        assertEq(nodeRegistry.modelPricingNative(host, modelId1), MIN_PRICE_NATIVE);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), MIN_PRICE_STABLE);
    }

    /// @notice Test boundary values: maximum valid prices
    function test_MaximumValidPrices() public {
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MAX_PRICE_NATIVE, MAX_PRICE_STABLE);

        assertEq(nodeRegistry.modelPricingNative(host, modelId1), MAX_PRICE_NATIVE);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), MAX_PRICE_STABLE);
    }

    /// @notice Test that host can update model pricing multiple times
    function test_CanUpdateModelPricingMultipleTimes() public {
        vm.startPrank(host);

        // First update
        nodeRegistry.setModelPricing(modelId1, 3_000_000_000, 3000);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 3_000_000_000);

        // Second update
        nodeRegistry.setModelPricing(modelId1, 4_000_000_000, 4000);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 4_000_000_000);

        // Third update
        nodeRegistry.setModelPricing(modelId1, 5_000_000_000, 5000);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 5_000_000_000);

        vm.stopPrank();
    }
}
