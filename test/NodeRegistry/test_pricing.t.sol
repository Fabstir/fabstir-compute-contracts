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
    uint256 constant MIN_PRICE_STABLE = 10; // 0.00001 USDC per token
    uint256 constant MIN_PRICE_NATIVE = 2_272_727_273; // ~0.00001 USD @ $4400 ETH
    uint256 constant MAX_PRICE_STABLE = 100_000; // 0.1 USDC per token
    uint256 constant MAX_PRICE_NATIVE = 22_727_272_727_273; // ~0.1 USD @ $4400 ETH

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

        uint256 priceNative = 3_000_000_000; // Price for native
        uint256 priceStable = 1000; // Price for stable

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            priceNative,  // Native price
            priceStable   // Stable price
        );

        vm.stopPrank();

        // Query the node and verify pricing is stored (8 fields now)
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
        assertEq(minPricePerTokenNative, priceNative, "Native pricing not stored correctly");
        assertEq(minPricePerTokenStable, priceStable, "Stable pricing not stored correctly");
    }

    function test_PricingValidation_TooLow() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Try to register with native price below minimum
        vm.expectRevert("Native price below minimum");
        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MIN_PRICE_NATIVE - 1,  // Native price too low
            MIN_PRICE_STABLE       // Stable price OK
        );

        vm.stopPrank();
    }

    function test_PricingValidation_TooHigh() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Try to register with native price above maximum
        vm.expectRevert("Native price above maximum");
        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            MAX_PRICE_NATIVE + 1,  // Native price too high
            MAX_PRICE_STABLE       // Stable price OK
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
            MIN_PRICE_NATIVE,  // Native price
            MIN_PRICE_STABLE   // Stable price
        );

        vm.stopPrank();

        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice, MIN_PRICE_NATIVE, "Minimum native price not accepted");
        assertEq(stablePrice, MIN_PRICE_STABLE, "Minimum stable price not accepted");
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
            MAX_PRICE_NATIVE,  // Native price
            MAX_PRICE_STABLE   // Stable price
        );

        vm.stopPrank();

        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice, MAX_PRICE_NATIVE, "Maximum native price not accepted");
        assertEq(stablePrice, MAX_PRICE_STABLE, "Maximum stable price not accepted");
    }
}
