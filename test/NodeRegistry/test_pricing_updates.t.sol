// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract NodeRegistryPricingUpdatesTest is Test {
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public nonRegisteredHost = address(3);
    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_STABLE = 10; // 0.00001 USDC per token
    uint256 constant MIN_PRICE_NATIVE = 2_272_727_273; // ~0.00001 USD @ $4400 ETH
    uint256 constant MAX_PRICE_STABLE = 100_000; // 0.1 USDC per token
    uint256 constant MAX_PRICE_NATIVE = 22_727_272_727_273; // ~0.1 USD @ $4400 ETH

    event PricingUpdated(address indexed operator, uint256 newMinPrice);

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
            3_000_000_000,  // Native price
            1000   // Stable price
        );

        vm.stopPrank();
    }

    function test_RegisteredHostCanUpdatePricing() public {
        vm.prank(host);
        nodeRegistry.updatePricingNative(4_000_000_000);

        // Verify update succeeded
        (, , , , , , uint256 nativePrice, ) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice, 4_000_000_000, "Price should be updated");
    }

    function test_UpdateWithValidPrice() public {
        uint256 newPrice = 5_000_000_000;

        vm.prank(host);
        nodeRegistry.updatePricingNative(newPrice);

        (, , , , , , uint256 nativePrice, ) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice, newPrice, "Price should match new price");
    }

    function test_UpdateWithTooLowPrice() public {
        vm.prank(host);
        vm.expectRevert("Price below minimum");
        nodeRegistry.updatePricingNative(MIN_PRICE_NATIVE - 1);
    }

    function test_UpdateWithTooHighPrice() public {
        vm.prank(host);
        vm.expectRevert("Price above maximum");
        nodeRegistry.updatePricingNative(MAX_PRICE_NATIVE + 1);
    }

    function test_UpdateWithMinValidPrice() public {
        vm.prank(host);
        nodeRegistry.updatePricingNative(MIN_PRICE_NATIVE);

        (, , , , , , uint256 nativePrice, ) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice, MIN_PRICE_NATIVE, "Min price should be accepted");
    }

    function test_UpdateWithMaxValidPrice() public {
        vm.prank(host);
        nodeRegistry.updatePricingNative(MAX_PRICE_NATIVE);

        (, , , , , , uint256 nativePrice, ) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice, MAX_PRICE_NATIVE, "Max price should be accepted");
    }

    function test_NonRegisteredCannotUpdate() public {
        vm.prank(nonRegisteredHost);
        vm.expectRevert("Not registered");
        nodeRegistry.updatePricingNative(3_000_000_000);
    }

    function test_InactiveHostCannotUpdate() public {
        // Unregister host to make inactive (deletes node struct)
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Try to update pricing as unregistered host
        vm.prank(host);
        vm.expectRevert("Not registered");
        nodeRegistry.updatePricingNative(3_000_000_000);
    }

    function test_PricingUpdatedEventEmitted() public {
        uint256 newPrice = 4_000_000_000;

        vm.expectEmit(true, false, false, true);
        emit PricingUpdated(host, newPrice);

        vm.prank(host);
        nodeRegistry.updatePricingNative(newPrice);
    }

    function test_PriceStoredAfterUpdate() public {
        uint256 firstUpdate = 3_500_000_000;
        uint256 secondUpdate = 5_000_000_000;

        // First update
        vm.prank(host);
        nodeRegistry.updatePricingNative(firstUpdate);

        (, , , , , , uint256 nativePrice1, ) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice1, firstUpdate, "First price update failed");

        // Second update
        vm.prank(host);
        nodeRegistry.updatePricingNative(secondUpdate);

        (, , , , , , uint256 nativePrice2, ) = nodeRegistry.getNodeFullInfo(host);
        assertEq(nativePrice2, secondUpdate, "Second price update failed");
    }

    function test_MultipleHostsUpdateIndependently() public {
        // Setup second host
        address host2 = address(4);
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
            3_500_000_000,  // Native price
            1500   // Stable price
        );
        vm.stopPrank();

        // Update host1
        vm.prank(host);
        nodeRegistry.updatePricingNative(4_000_000_000);

        // Update host2
        vm.prank(host2);
        nodeRegistry.updatePricingNative(5_000_000_000);

        // Verify independent updates
        (, , , , , , uint256 nativePrice1, ) = nodeRegistry.getNodeFullInfo(host);
        (, , , , , , uint256 nativePrice2, ) = nodeRegistry.getNodeFullInfo(host2);

        assertEq(nativePrice1, 4_000_000_000, "Host1 price incorrect");
        assertEq(nativePrice2, 5_000_000_000, "Host2 price incorrect");
    }
}
