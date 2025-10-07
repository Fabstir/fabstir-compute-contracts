// SPDX-License-Identifier: MIT
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
    uint256 constant INITIAL_PRICE = 1500;

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
            INITIAL_PRICE
        );

        vm.stopPrank();
    }

    function test_GetPricingForRegisteredHost() public {
        uint256 price = nodeRegistry.getNodePricing(host);
        assertEq(price, INITIAL_PRICE, "Should return registered price");
    }

    function test_GetPricingForNonRegistered() public {
        uint256 price = nodeRegistry.getNodePricing(nonRegisteredHost);
        assertEq(price, 0, "Should return 0 for non-registered");
    }

    function test_GetPricingAfterUpdate() public {
        uint256 newPrice = 3000;

        // Update pricing
        vm.prank(host);
        nodeRegistry.updatePricing(newPrice);

        // Query pricing
        uint256 price = nodeRegistry.getNodePricing(host);
        assertEq(price, newPrice, "Should return updated price");
    }

    function test_GetPricingMultipleHosts() public {
        // Setup second host
        address host2 = address(4);
        uint256 host2Price = 2500;

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
            host2Price
        );
        vm.stopPrank();

        // Query both hosts
        uint256 price1 = nodeRegistry.getNodePricing(host);
        uint256 price2 = nodeRegistry.getNodePricing(host2);

        assertEq(price1, INITIAL_PRICE, "Host1 price incorrect");
        assertEq(price2, host2Price, "Host2 price incorrect");
    }

    function test_GetPricingConsistentWithFullInfo() public {
        // Get price via getNodePricing
        uint256 priceDirect = nodeRegistry.getNodePricing(host);

        // Get price via getNodeFullInfo
        (, , , , , , uint256 priceFromFullInfo) = nodeRegistry.getNodeFullInfo(host);

        assertEq(priceDirect, priceFromFullInfo, "Pricing should be consistent");
    }

    function test_GetPricingAfterMultipleUpdates() public {
        // First update
        vm.prank(host);
        nodeRegistry.updatePricing(2000);
        assertEq(nodeRegistry.getNodePricing(host), 2000, "First update failed");

        // Second update
        vm.prank(host);
        nodeRegistry.updatePricing(3500);
        assertEq(nodeRegistry.getNodePricing(host), 3500, "Second update failed");

        // Third update
        vm.prank(host);
        nodeRegistry.updatePricing(1000);
        assertEq(nodeRegistry.getNodePricing(host), 1000, "Third update failed");
    }
}
