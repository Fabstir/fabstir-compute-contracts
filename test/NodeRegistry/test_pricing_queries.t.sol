// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract NodeRegistryPricingQueriesTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredHost = address(3);
    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    // With PRICE_PRECISION=1000: prices are 1000x for sub-cent granularity
    uint256 constant MIN_PRICE_STABLE = 1; // $0.001 per million tokens
    uint256 constant MIN_PRICE_NATIVE = 227_273; // ~$0.001 per million @ $4400 ETH
    uint256 constant MAX_PRICE_STABLE = 100_000_000; // $100,000 per million tokens
    uint256 constant MAX_PRICE_NATIVE = 22_727_272_727_273_000; // ~$100,000 per million @ $4400 ETH
    uint256 constant INITIAL_PRICE_NATIVE = 3_000_000; // ~$0.013/million - Above MIN_PRICE_NATIVE
    uint256 constant INITIAL_PRICE_STABLE = 1500; // $1.50/million - Above MIN_PRICE_STABLE

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

        vm.stopPrank();

        // Give host FAB tokens and register
        vm.startPrank(owner);
        fabToken.mint(host, MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            INITIAL_PRICE_NATIVE,  // Native price
            INITIAL_PRICE_STABLE   // Stable price
        );

        vm.stopPrank();
    }

    function test_GetPricingForRegisteredHost() public {
        uint256 price = nodeRegistry.getNodePricing(host, address(0));
        assertEq(price, INITIAL_PRICE_NATIVE, "Should return registered price");
    }

    function test_GetPricingForNonRegistered() public {
        uint256 price = nodeRegistry.getNodePricing(nonRegisteredHost, address(0));
        assertEq(price, 0, "Should return 0 for non-registered");
    }

    function test_GetPricingAfterUpdate() public {
        uint256 newPrice = 4_000_000_000;

        // Update pricing
        vm.prank(host);
        nodeRegistry.updatePricingNative(newPrice);

        // Query pricing
        uint256 price = nodeRegistry.getNodePricing(host, address(0));
        assertEq(price, newPrice, "Should return updated price");
    }

    function test_GetPricingMultipleHosts() public {
        // Setup second host
        address host2 = address(4);
        uint256 host2PriceNative = 3_500_000_000;
        uint256 host2PriceStable = 2500;

        vm.prank(owner);
        fabToken.mint(host2, MIN_STAKE);

        vm.startPrank(host2);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata2",
            "https://api2.example.com",
            models,
            host2PriceNative,  // Native price
            host2PriceStable   // Stable price
        );
        vm.stopPrank();

        // Query both hosts
        uint256 price1 = nodeRegistry.getNodePricing(host, address(0));
        uint256 price2 = nodeRegistry.getNodePricing(host2, address(0));

        assertEq(price1, INITIAL_PRICE_NATIVE, "Host1 price incorrect");
        assertEq(price2, host2PriceNative, "Host2 price incorrect");
    }

    function test_GetPricingConsistentWithFullInfo() public {
        // Get price via getNodePricing (native)
        uint256 priceDirect = nodeRegistry.getNodePricing(host, address(0));

        // Get price via getNodeFullInfo
        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);

        assertEq(priceDirect, nativePrice, "Native pricing should be consistent");
        assertEq(nativePrice, INITIAL_PRICE_NATIVE, "Native price should match initial value");
        assertEq(stablePrice, INITIAL_PRICE_STABLE, "Stable price should match initial value");
    }

    function test_GetPricingAfterMultipleUpdates() public {
        // First update
        vm.prank(host);
        nodeRegistry.updatePricingNative(4_000_000_000);
        assertEq(nodeRegistry.getNodePricing(host, address(0)), 4_000_000_000, "First update failed");

        // Second update
        vm.prank(host);
        nodeRegistry.updatePricingNative(5_500_000_000);
        assertEq(nodeRegistry.getNodePricing(host, address(0)), 5_500_000_000, "Second update failed");

        // Third update
        vm.prank(host);
        nodeRegistry.updatePricingNative(3_000_000_000);
        assertEq(nodeRegistry.getNodePricing(host, address(0)), 3_000_000_000, "Third update failed");
    }
}
