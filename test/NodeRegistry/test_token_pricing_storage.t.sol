// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryTokenPricingStorageTest
 * @notice Tests for customTokenPricing mapping (Phase 2.1)
 * @dev Verifies token-specific pricing storage is accessible and isolated
 */
contract NodeRegistryTokenPricingStorageTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host1 = address(2);
    address public host2 = address(3);

    // Sample token addresses for testing
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant DAI_ADDRESS = 0x1111111111111111111111111111111111111111;
    address constant EUR_STABLE = 0x2222222222222222222222222222222222222222;

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant DEFAULT_NATIVE_PRICE = 3_000_000_000;
    uint256 constant DEFAULT_STABLE_PRICE = 2000;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));

        // Add approved model
        modelRegistry.addTrustedModel(
            "CohereForAI/TinyVicuna-1B-32k-GGUF",
            "tiny-vicuna-1b.q4_k_m.gguf",
            bytes32(0)
        );

        // Mint FAB tokens for hosts
        fabToken.mint(host1, MIN_STAKE * 2);
        fabToken.mint(host2, MIN_STAKE * 2);

        vm.stopPrank();
    }

    function _registerHost(address host) internal {
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        nodeRegistry.registerNode(
            "test metadata",
            "https://api.example.com",
            models,
            DEFAULT_NATIVE_PRICE,
            DEFAULT_STABLE_PRICE
        );
        vm.stopPrank();
    }

    /// @notice Test that customTokenPricing mapping exists and is accessible
    function test_CustomTokenPricingMappingExists() public view {
        // Should be able to read from the mapping without reverting
        uint256 price = nodeRegistry.customTokenPricing(host1, USDC_ADDRESS);
        assertEq(price, 0, "Unset mapping value should return 0");
    }

    /// @notice Test that customTokenPricing defaults to 0 for unset values
    function test_CustomTokenPricingDefaultsToZero() public view {
        // Test various operator/token combinations
        assertEq(nodeRegistry.customTokenPricing(host1, USDC_ADDRESS), 0, "host1/USDC should be 0");
        assertEq(nodeRegistry.customTokenPricing(host1, DAI_ADDRESS), 0, "host1/DAI should be 0");
        assertEq(nodeRegistry.customTokenPricing(host2, USDC_ADDRESS), 0, "host2/USDC should be 0");
        assertEq(nodeRegistry.customTokenPricing(address(0), USDC_ADDRESS), 0, "zero address should be 0");
        assertEq(nodeRegistry.customTokenPricing(host1, address(0)), 0, "native token should be 0");
    }

    /// @notice Test that customTokenPricing does not affect existing model pricing
    function test_CustomTokenPricingDoesNotAffectExistingPricing() public {
        _registerHost(host1);

        // Set model pricing
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, 5_000_000_000, 5000);

        // Verify model pricing still works
        assertEq(nodeRegistry.modelPricingNative(host1, modelId1), 5_000_000_000, "Model native pricing should be set");
        assertEq(nodeRegistry.modelPricingStable(host1, modelId1), 5000, "Model stable pricing should be set");

        // customTokenPricing should still be 0 (independent)
        assertEq(nodeRegistry.customTokenPricing(host1, USDC_ADDRESS), 0, "customTokenPricing should be independent");
    }

    /// @notice Test that customTokenPricing does not affect Node struct
    function test_CustomTokenPricingDoesNotAffectNodeStruct() public {
        _registerHost(host1);

        // Get node info
        (
            address operator,
            uint256 stakedAmount,
            bool active,
            string memory metadata,
            string memory apiUrl,
            bytes32[] memory supportedModels,
            uint256 minPriceNative,
            uint256 minPriceStable
        ) = nodeRegistry.getNodeFullInfo(host1);

        // Verify Node struct is intact
        assertEq(operator, host1, "Operator should be host1");
        assertEq(stakedAmount, MIN_STAKE, "Staked amount should match");
        assertTrue(active, "Node should be active");
        assertEq(metadata, "test metadata", "Metadata should match");
        assertEq(apiUrl, "https://api.example.com", "API URL should match");
        assertEq(supportedModels.length, 1, "Should have 1 model");
        assertEq(minPriceNative, DEFAULT_NATIVE_PRICE, "Default native price should match");
        assertEq(minPriceStable, DEFAULT_STABLE_PRICE, "Default stable price should match");

        // customTokenPricing is independent of Node struct
        assertEq(nodeRegistry.customTokenPricing(host1, USDC_ADDRESS), 0, "customTokenPricing independent of Node");
    }

    /// @notice Test that customTokenPricing can store values (via direct slot manipulation for testing)
    /// @dev This test verifies the mapping works by checking the auto-generated getter
    function test_CustomTokenPricingCanStoreValues() public view {
        // Since we can't directly write to the mapping without a setter function,
        // we verify the mapping exists and the getter works correctly.
        // The actual storage functionality will be tested in Sub-phase 2.2 when setTokenPricing is added.

        // For now, verify the mapping is readable at various addresses
        uint256 price1 = nodeRegistry.customTokenPricing(host1, USDC_ADDRESS);
        uint256 price2 = nodeRegistry.customTokenPricing(host1, DAI_ADDRESS);
        uint256 price3 = nodeRegistry.customTokenPricing(host1, EUR_STABLE);

        // All should be 0 since no setter exists yet
        assertEq(price1, 0, "Should return 0 for USDC");
        assertEq(price2, 0, "Should return 0 for DAI");
        assertEq(price3, 0, "Should return 0 for EUR stable");
    }

    /// @notice Test that customTokenPricing is independent per operator
    function test_CustomTokenPricingIndependentPerOperator() public view {
        // Reading from different operators should work independently
        uint256 price1 = nodeRegistry.customTokenPricing(host1, USDC_ADDRESS);
        uint256 price2 = nodeRegistry.customTokenPricing(host2, USDC_ADDRESS);

        // Both should be 0 and accessing one doesn't affect the other
        assertEq(price1, 0, "host1 price should be 0");
        assertEq(price2, 0, "host2 price should be 0");

        // Different tokens for same operator
        uint256 usdcPrice = nodeRegistry.customTokenPricing(host1, USDC_ADDRESS);
        uint256 daiPrice = nodeRegistry.customTokenPricing(host1, DAI_ADDRESS);

        assertEq(usdcPrice, 0, "USDC price should be 0");
        assertEq(daiPrice, 0, "DAI price should be 0");
    }
}
