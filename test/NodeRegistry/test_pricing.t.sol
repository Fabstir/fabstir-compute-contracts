// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract NodeRegistryPricingTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE = 100; // 0.0001 USDC per token
    uint256 constant MAX_PRICE = 100_000; // 0.1 USDC per token

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

        // Give host FAB tokens
        vm.prank(owner);
        fabToken.mint(host, MIN_STAKE);
    }

    function test_NodeStructHasPricingField() public {
        // Test that Node struct has minPricePerToken field
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        uint256 pricePerToken = 1000; // 0.001 USDC per token

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            pricePerToken
        );

        vm.stopPrank();

        // Query the node and verify pricing is stored
        (
            address operator,
            uint256 stakedAmount,
            bool active,
            string memory metadata,
            string memory apiUrl,
            bytes32[] memory supportedModels,
            uint256 minPricePerToken
        ) = nodeRegistry.getNodeFullInfo(host);

        assertEq(operator, host, "Operator mismatch");
        assertEq(minPricePerToken, pricePerToken, "Pricing not stored correctly");
    }

    function test_PricingValidation_TooLow() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Try to register with price below minimum
        vm.expectRevert("Price below minimum");
        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MIN_PRICE - 1
        );

        vm.stopPrank();
    }

    function test_PricingValidation_TooHigh() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Try to register with price above maximum
        vm.expectRevert("Price above maximum");
        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MAX_PRICE + 1
        );

        vm.stopPrank();
    }

    function test_PricingValidation_AtMinimum() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MIN_PRICE
        );

        vm.stopPrank();

        (, , , , , , uint256 minPricePerToken) = nodeRegistry.getNodeFullInfo(host);
        assertEq(minPricePerToken, MIN_PRICE, "Minimum price not accepted");
    }

    function test_PricingValidation_AtMaximum() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MAX_PRICE
        );

        vm.stopPrank();

        (, , , , , , uint256 minPricePerToken) = nodeRegistry.getNodeFullInfo(host);
        assertEq(minPricePerToken, MAX_PRICE, "Maximum price not accepted");
    }
}
