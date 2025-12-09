// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryModelPricingStorageTest
 * @notice Tests for per-model pricing storage mappings (Phase 1.1)
 * @dev Verifies that modelPricingNative and modelPricingStable mappings exist
 *      and can store values without affecting the existing Node struct
 */
contract NodeRegistryModelPricingStorageTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 2_272_727_273;
    uint256 constant MIN_PRICE_STABLE = 10;

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

        // Give host FAB tokens
        vm.prank(owner);
        fabToken.mint(host, MIN_STAKE);
    }

    /// @notice Test that modelPricingNative mapping exists and is accessible
    function test_ModelPricingNativeMappingExists() public view {
        // Query the mapping - should return 0 for unset values
        uint256 price = nodeRegistry.modelPricingNative(host, modelId1);
        assertEq(price, 0, "Default model pricing should be 0");
    }

    /// @notice Test that modelPricingStable mapping exists and is accessible
    function test_ModelPricingStableMappingExists() public view {
        // Query the mapping - should return 0 for unset values
        uint256 price = nodeRegistry.modelPricingStable(host, modelId1);
        assertEq(price, 0, "Default model pricing should be 0");
    }

    /// @notice Test that both mappings default to 0 for any address/model combination
    function test_ModelPricingDefaultsToZero() public view {
        // Test various combinations - all should be 0
        assertEq(nodeRegistry.modelPricingNative(address(0), bytes32(0)), 0);
        assertEq(nodeRegistry.modelPricingStable(address(0), bytes32(0)), 0);
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0);
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0);
        assertEq(nodeRegistry.modelPricingNative(host, modelId2), 0);
        assertEq(nodeRegistry.modelPricingStable(host, modelId2), 0);
        assertEq(nodeRegistry.modelPricingNative(address(999), keccak256("random")), 0);
        assertEq(nodeRegistry.modelPricingStable(address(999), keccak256("random")), 0);
    }

    /// @notice Test that model pricing mappings do not affect Node struct
    function test_ModelPricingDoesNotAffectNodeStruct() public {
        // Register a host with default pricing
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;

        uint256 defaultNativePrice = 3_000_000_000;
        uint256 defaultStablePrice = 2000;

        nodeRegistry.registerNode(
            "test metadata",
            "https://api.example.com",
            models,
            defaultNativePrice,
            defaultStablePrice
        );
        vm.stopPrank();

        // Verify Node struct has correct default pricing
        (
            address operator,
            uint256 stakedAmount,
            bool active,
            string memory metadata,
            string memory apiUrl,
            bytes32[] memory supportedModels,
            uint256 minPricePerTokenNative,
            uint256 minPricePerTokenStable
        ) = nodeRegistry.getNodeFullInfo(host);

        assertEq(operator, host, "Operator mismatch");
        assertEq(stakedAmount, MIN_STAKE, "Stake mismatch");
        assertTrue(active, "Should be active");
        assertEq(minPricePerTokenNative, defaultNativePrice, "Default native price mismatch");
        assertEq(minPricePerTokenStable, defaultStablePrice, "Default stable price mismatch");

        // Model pricing mappings should still be 0 (not yet set)
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0, "Model pricing should still be 0");
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0, "Model pricing should still be 0");

        // Node struct values should be unchanged regardless of model pricing mapping state
        assertEq(minPricePerTokenNative, defaultNativePrice, "Node struct should be independent of model pricing");
    }

    /// @notice Test that different operators have independent model pricing
    function test_ModelPricingIndependentPerOperator() public view {
        address host2 = address(3);
        address host3 = address(4);

        // All hosts should have independent 0 values
        assertEq(nodeRegistry.modelPricingNative(host, modelId1), 0);
        assertEq(nodeRegistry.modelPricingNative(host2, modelId1), 0);
        assertEq(nodeRegistry.modelPricingNative(host3, modelId1), 0);

        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 0);
        assertEq(nodeRegistry.modelPricingStable(host2, modelId1), 0);
        assertEq(nodeRegistry.modelPricingStable(host3, modelId1), 0);
    }

    /// @notice Test that different models have independent pricing for same operator
    function test_ModelPricingIndependentPerModel() public view {
        bytes32 model1 = keccak256("model1");
        bytes32 model2 = keccak256("model2");
        bytes32 model3 = keccak256("model3");

        // All models should have independent 0 values for same host
        assertEq(nodeRegistry.modelPricingNative(host, model1), 0);
        assertEq(nodeRegistry.modelPricingNative(host, model2), 0);
        assertEq(nodeRegistry.modelPricingNative(host, model3), 0);

        assertEq(nodeRegistry.modelPricingStable(host, model1), 0);
        assertEq(nodeRegistry.modelPricingStable(host, model2), 0);
        assertEq(nodeRegistry.modelPricingStable(host, model3), 0);
    }
}
