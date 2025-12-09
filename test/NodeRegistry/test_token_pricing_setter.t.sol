// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryTokenPricingSetterTest
 * @notice Tests for setTokenPricing() function (Phase 2.2)
 * @dev Verifies token-specific pricing can be set by registered hosts
 */
contract NodeRegistryTokenPricingSetterTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredUser = address(3);

    // Sample token addresses for testing
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant DAI_ADDRESS = 0x1111111111111111111111111111111111111111;
    address constant EUR_STABLE = 0x2222222222222222222222222222222222222222;

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant DEFAULT_NATIVE_PRICE = 3_000_000_000;
    uint256 constant DEFAULT_STABLE_PRICE = 2000;

    // Price range constants (same as contract)
    uint256 constant MIN_PRICE_PER_TOKEN_STABLE = 10;
    uint256 constant MAX_PRICE_PER_TOKEN_STABLE = 100_000;

    // Event to test
    event TokenPricingUpdated(address indexed operator, address indexed token, uint256 price);

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

    // ============ Basic Functionality Tests ============

    /// @notice Test that registered host can set token pricing
    function test_RegisteredHostCanSetTokenPricing() public {
        uint256 newPrice = 5000;

        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, newPrice);

        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), newPrice, "Token pricing should be set");
    }

    /// @notice Test that setting price to 0 clears override (uses default)
    function test_SettingPriceToZeroClearsOverride() public {
        // First set a price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 5000, "Price should be set");

        // Then clear it
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 0);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 0, "Price should be cleared");
    }

    /// @notice Test that can set different prices for different tokens
    function test_DifferentPricesForDifferentTokens() public {
        vm.startPrank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 3000);
        nodeRegistry.setTokenPricing(DAI_ADDRESS, 3500);
        nodeRegistry.setTokenPricing(EUR_STABLE, 4000);
        vm.stopPrank();

        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 3000, "USDC price should be 3000");
        assertEq(nodeRegistry.customTokenPricing(host, DAI_ADDRESS), 3500, "DAI price should be 3500");
        assertEq(nodeRegistry.customTokenPricing(host, EUR_STABLE), 4000, "EUR price should be 4000");
    }

    /// @notice Test that can update token pricing multiple times
    function test_CanUpdateTokenPricingMultipleTimes() public {
        vm.startPrank(host);

        nodeRegistry.setTokenPricing(USDC_ADDRESS, 3000);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 3000, "First price");

        nodeRegistry.setTokenPricing(USDC_ADDRESS, 4000);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 4000, "Second price");

        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 5000, "Third price");

        vm.stopPrank();
    }

    // ============ Validation Tests ============

    /// @notice Test that non-registered address cannot set token pricing
    function test_NonRegisteredCannotSetTokenPricing() public {
        vm.prank(nonRegisteredUser);
        vm.expectRevert("Not registered");
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);
    }

    /// @notice Test that inactive host cannot set token pricing
    function test_InactiveHostCannotSetTokenPricing() public {
        // Deactivate host by unregistering
        vm.prank(host);
        nodeRegistry.unregisterNode();

        vm.prank(host);
        vm.expectRevert("Not registered");
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);
    }

    /// @notice Test that cannot set pricing for native token address(0)
    function test_CannotSetPricingForNativeToken() public {
        vm.prank(host);
        vm.expectRevert("Use updatePricingNative for native token");
        nodeRegistry.setTokenPricing(address(0), 5000);
    }

    /// @notice Test that price below minimum is rejected
    function test_InvalidPriceTooLow() public {
        vm.prank(host);
        vm.expectRevert("Price below minimum");
        nodeRegistry.setTokenPricing(USDC_ADDRESS, MIN_PRICE_PER_TOKEN_STABLE - 1);
    }

    /// @notice Test that price above maximum is rejected
    function test_InvalidPriceTooHigh() public {
        vm.prank(host);
        vm.expectRevert("Price above maximum");
        nodeRegistry.setTokenPricing(USDC_ADDRESS, MAX_PRICE_PER_TOKEN_STABLE + 1);
    }

    /// @notice Test that minimum valid price is accepted
    function test_MinimumValidPrice() public {
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, MIN_PRICE_PER_TOKEN_STABLE);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), MIN_PRICE_PER_TOKEN_STABLE, "Min price should be accepted");
    }

    /// @notice Test that maximum valid price is accepted
    function test_MaximumValidPrice() public {
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, MAX_PRICE_PER_TOKEN_STABLE);
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), MAX_PRICE_PER_TOKEN_STABLE, "Max price should be accepted");
    }

    // ============ Event Tests ============

    /// @notice Test that TokenPricingUpdated event is emitted correctly
    function test_TokenPricingUpdatedEventEmitted() public {
        uint256 newPrice = 5000;

        vm.prank(host);
        vm.expectEmit(true, true, false, true);
        emit TokenPricingUpdated(host, USDC_ADDRESS, newPrice);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, newPrice);
    }

    /// @notice Test that event is emitted when clearing price
    function test_TokenPricingUpdatedEventEmittedOnClear() public {
        // First set a price
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);

        // Then clear it and verify event
        vm.prank(host);
        vm.expectEmit(true, true, false, true);
        emit TokenPricingUpdated(host, USDC_ADDRESS, 0);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 0);
    }

    // ============ Independence Tests ============

    /// @notice Test that token pricing is independent per operator
    function test_TokenPricingIndependentPerOperator() public {
        // Register another host
        address host2 = address(4);
        vm.prank(owner);
        fabToken.mint(host2, MIN_STAKE);

        vm.startPrank(host2);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;
        nodeRegistry.registerNode("host2 metadata", "https://api2.example.com", models, DEFAULT_NATIVE_PRICE, DEFAULT_STABLE_PRICE);
        vm.stopPrank();

        // Set different prices for each host
        vm.prank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 3000);

        vm.prank(host2);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 6000);

        // Verify independence
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 3000, "Host1 price should be 3000");
        assertEq(nodeRegistry.customTokenPricing(host2, USDC_ADDRESS), 6000, "Host2 price should be 6000");
    }

    /// @notice Test that token pricing does not affect model pricing
    function test_TokenPricingDoesNotAffectModelPricing() public {
        // Set both token pricing and model pricing
        vm.startPrank(host);
        nodeRegistry.setTokenPricing(USDC_ADDRESS, 5000);
        nodeRegistry.setModelPricing(modelId1, 5_000_000_000, 6000);
        vm.stopPrank();

        // Verify both are independent
        assertEq(nodeRegistry.customTokenPricing(host, USDC_ADDRESS), 5000, "Token pricing should be set");
        assertEq(nodeRegistry.modelPricingStable(host, modelId1), 6000, "Model pricing should be set");
    }
}
