// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryTokenPricingQueriesTest
 * @notice Tests for getNodePricing() with token fallback (Phase 2.3)
 * @dev Verifies token-specific pricing is returned with fallback to default
 */
contract NodeRegistryTokenPricingQueriesTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);

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

        // Mint FAB tokens for host
        fabToken.mint(host, MIN_STAKE * 2);

        vm.stopPrank();

        // Register host
        _registerHost(host);
    }

    function _registerHost(address _host) internal {
        vm.startPrank(_host);
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

    // ============ Token-Specific Pricing Tests ============

    /// @notice Test that getNodePricing returns token-specific price when set
    function test_ReturnsTokenSpecificPriceWhenSet() public {
        uint256 customUsdcPrice = 5000;

        // Set custom USDC price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, customUsdcPrice);

        // Query should return custom price
        uint256 returnedPrice = nodeRegistry.getNodePricing(host, USDC_ADDRESS);
        assertEq(returnedPrice, customUsdcPrice, "Should return token-specific price");
    }

    /// @notice Test that getNodePricing falls back to default when token price is 0
    function test_FallsBackToDefaultStableWhenTokenPriceZero() public {
        // No custom price set for DAI, should return default stable price
        uint256 returnedPrice = nodeRegistry.getNodePricing(host, DAI_ADDRESS);
        assertEq(returnedPrice, DEFAULT_STABLE_PRICE, "Should return default stable price");
    }

    /// @notice Test that native token returns minPricePerTokenNative (unchanged)
    function test_NativeTokenReturnsNativePrice() public {
        uint256 returnedPrice = nodeRegistry.getNodePricing(host, address(0));
        assertEq(returnedPrice, DEFAULT_NATIVE_PRICE, "Should return native price for address(0)");
    }

    /// @notice Test that existing default behavior is unchanged for stablecoins
    function test_ExistingBehaviorUnchangedForDefaultStable() public {
        // Without any custom token pricing, should return default stable
        uint256 returnedPrice = nodeRegistry.getNodePricing(host, USDC_ADDRESS);
        assertEq(returnedPrice, DEFAULT_STABLE_PRICE, "Should return default stable when no custom price");
    }

    // ============ Fallback Logic Tests ============

    /// @notice Test different tokens can have different custom prices
    function test_DifferentTokensHaveDifferentPrices() public {
        vm.startPrank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 3000);
        nodeRegistry.setTokenPricing(EUR_STABLE, 4500);
        vm.stopPrank();

        assertEq(nodeRegistry.getNodePricing(host, USDC_ADDRESS), 3000, "USDC should return 3000");
        assertEq(nodeRegistry.getNodePricing(host, EUR_STABLE), 4500, "EUR should return 4500");
        assertEq(nodeRegistry.getNodePricing(host, DAI_ADDRESS), DEFAULT_STABLE_PRICE, "DAI should return default");
    }

    /// @notice Test that clearing custom price reverts to default
    function test_ClearingCustomPriceRevertsToDefault() public {
        // Set custom price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);
        assertEq(nodeRegistry.getNodePricing(host, USDC_ADDRESS), 5000, "Should return custom price");

        // Clear custom price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 0);
        assertEq(nodeRegistry.getNodePricing(host, USDC_ADDRESS), DEFAULT_STABLE_PRICE, "Should return default after clearing");
    }

    /// @notice Test that native token is unaffected by token pricing
    function test_NativeTokenUnaffectedByTokenPricing() public {
        // Set custom stable price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);

        // Native should still return native price
        assertEq(nodeRegistry.getNodePricing(host, address(0)), DEFAULT_NATIVE_PRICE, "Native should be unaffected");
    }

    // ============ Edge Cases ============

    /// @notice Test returns 0 for non-registered operator
    function test_ReturnsZeroForNonRegisteredOperator() public view {
        address nonRegistered = address(99);
        assertEq(nodeRegistry.getNodePricing(nonRegistered, USDC_ADDRESS), 0, "Should return 0 for non-registered");
        assertEq(nodeRegistry.getNodePricing(nonRegistered, address(0)), 0, "Should return 0 for non-registered native");
    }

    /// @notice Test custom pricing is independent per operator
    function test_CustomPricingIndependentPerOperator() public {
        // Register another host
        address host2 = address(4);
        vm.prank(owner);
        fabToken.mint(host2, MIN_STAKE);

        vm.startPrank(host2);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;
        nodeRegistry.registerNode("host2 metadata", "https://api2.example.com", models, DEFAULT_NATIVE_PRICE, 3000);
        vm.stopPrank();

        // Set different USDC prices for each host
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);

        vm.prank(host2);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 7000);

        // Each host should return their own price
        assertEq(nodeRegistry.getNodePricing(host, USDC_ADDRESS), 5000, "Host1 should return 5000");
        assertEq(nodeRegistry.getNodePricing(host2, USDC_ADDRESS), 7000, "Host2 should return 7000");
    }

    /// @notice Test that updating default stable price doesn't affect custom token price
    function test_DefaultStablePriceUpdateDoesNotAffectCustom() public {
        // Set custom USDC price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);

        // Update default stable price
        vm.prank(host);
        nodeRegistry.updatePricingStable(8000);

        // Custom USDC price should be unchanged
        assertEq(nodeRegistry.getNodePricing(host, USDC_ADDRESS), 5000, "Custom price should be unchanged");
        // DAI (no custom) should use new default
        assertEq(nodeRegistry.getNodePricing(host, DAI_ADDRESS), 8000, "DAI should use new default");
    }

    // ============ Consistency Tests ============

    /// @notice Test consistency between customTokenPricing mapping and getNodePricing
    function test_ConsistencyBetweenMappingAndGetter() public {
        uint256 customPrice = 6000;

        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, customPrice);

        // Both should return the same value
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), customPrice, "Mapping should return custom price");
        assertEq(nodeRegistry.getNodePricing(host, USDC_ADDRESS), customPrice, "Getter should return custom price");
    }
}
