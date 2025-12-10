// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryModelPricingClearTest
 * @notice Tests for clearModelPricing() function (Phase 1.4)
 * @dev Verifies that hosts can clear model-specific pricing overrides
 */
contract NodeRegistryModelPricingClearTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredUser = address(3);

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"));

    address constant NATIVE_TOKEN = address(0);
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant DEFAULT_NATIVE_PRICE = 3_000_000_000;
    uint256 constant DEFAULT_STABLE_PRICE = 2000;
    uint256 constant MODEL_NATIVE_PRICE = 5_000_000_000;
    uint256 constant MODEL_STABLE_PRICE = 5000;

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
            DEFAULT_NATIVE_PRICE,
            DEFAULT_STABLE_PRICE
        );
        vm.stopPrank();
    }

    /// @notice Test that clearModelPricing clears both native and stable prices
    function test_ClearsModelPricingSuccessfully() public {
        // First set model pricing
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Verify pricing is set
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), MODEL_NATIVE_PRICE);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), MODEL_STABLE_PRICE);

        // Clear the pricing
        vm.prank(host);
        nodeRegistry.clearModelPricing(modelId1);

        // Verify pricing is cleared (set to 0)
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0, "Native price should be cleared");
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0, "Stable price should be cleared");
    }

    /// @notice Test that after clearing, getModelPricing returns default pricing
    function test_AfterClearingGetModelPricingReturnsDefault() public {
        // Set model pricing
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Verify override is active
        assertEq(nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN), MODEL_NATIVE_PRICE);
        assertEq(nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS), MODEL_STABLE_PRICE);

        // Clear the pricing
        vm.prank(host);
        nodeRegistry.clearModelPricing(modelId1);

        // getModelPricing should now return default prices
        assertEq(nodeRegistry.getModelPricing(host, modelId1, NATIVE_TOKEN), DEFAULT_NATIVE_PRICE, "Should return default native price");
        assertEq(nodeRegistry.getModelPricing(host, modelId1, USDC_ADDRESS), DEFAULT_STABLE_PRICE, "Should return default stable price");
    }

    /// @notice Test that non-registered address cannot clear model pricing
    function test_NonRegisteredCannotClear() public {
        vm.prank(nonRegisteredUser);
        vm.expectRevert("Not registered");
        nodeRegistry.clearModelPricing(modelId1);
    }

    /// @notice Test that ModelPricingUpdated event is emitted with zero prices
    function test_ModelPricingUpdatedEventEmittedOnClear() public {
        // First set model pricing
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);

        // Clear and expect event
        vm.prank(host);
        vm.expectEmit(true, true, false, true);
        emit ModelPricingUpdated(host, modelId1, 0, 0);
        nodeRegistry.clearModelPricing(modelId1);
    }

    /// @notice Test clearing one model doesn't affect other models
    function test_ClearingOneModelDoesNotAffectOthers() public {
        // Set pricing for both models
        vm.startPrank(host);
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);
        nodeRegistry.setModelPricing(modelId2, 6_000_000_000, 6000);
        vm.stopPrank();

        // Clear only modelId1
        vm.prank(host);
        nodeRegistry.clearModelPricing(modelId1);

        // modelId1 should be cleared
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0);

        // modelId2 should still have its pricing
        assertEq(nodeRegistry.modelPricingNative(host, modelId2), 6_000_000_000);
        assertEq(nodeRegistry.modelPricingStable(host, modelId2), 6000);
    }

    /// @notice Test clearing already-cleared pricing (no-op, should not revert)
    function test_ClearingAlreadyClearedPricingSucceeds() public {
        // Clear without ever setting (should work, just sets 0 to 0)
        vm.prank(host);
        nodeRegistry.clearModelPricing(modelId1);

        // Verify still 0
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0);
    }

    /// @notice Test that clearing works even for unsupported models (no validation needed for clear)
    function test_CanClearPricingForAnyModelId() public {
        bytes32 randomModelId = keccak256("random/model");

        // Should not revert even for unsupported model
        // (clearing non-existent data is a no-op)
        vm.prank(host);
        nodeRegistry.clearModelPricing(randomModelId);

        // Verify it's 0 (was never set anyway)
        assertEq(nodeRegistry.modelPricingNative(host, randomModelId), 0);
        assertEq(nodeRegistry.modelPricingStable(host, randomModelId), 0);
    }

    /// @notice Test multiple clear operations in sequence
    function test_MultipleClearOperations() public {
        vm.startPrank(host);

        // Set, clear, set again, clear again
        nodeRegistry.setModelPricing(modelId1, MODEL_NATIVE_PRICE, MODEL_STABLE_PRICE);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), MODEL_NATIVE_PRICE);

        nodeRegistry.clearModelPricing(modelId1);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0);

        nodeRegistry.setModelPricing(modelId1, 4_000_000_000, 4000);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 4_000_000_000);

        nodeRegistry.clearModelPricing(modelId1);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0);

        vm.stopPrank();
    }
}
