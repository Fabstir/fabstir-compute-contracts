// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title NodeRegistryDualPricingTest
 * @notice Tests for dual pricing (native token vs stablecoin)
 * @dev These tests verify that hosts can set separate prices for ETH and USDC
 */
contract NodeRegistryDualPricingTest is Test {
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

    /// @notice Test that Node struct now has 8 fields (added dual pricing)
    function test_NodeStructHas8Fields() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        uint256 priceNative = 3_000_000_000; // For ETH (18 decimals)
        uint256 priceStable = 2000; // For USDC (6 decimals)

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            priceNative,
            priceStable
        );

        vm.stopPrank();

        // Query the node and verify 8 fields are returned
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

    /// @notice Test registration with different prices for native and stable
    function test_DualPricing_Registration() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        uint256 ethPrice = 3_000_000_000; // Lower price for ETH
        uint256 usdcPrice = 5000; // Higher price for USDC

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            ethPrice,
            usdcPrice
        );

        vm.stopPrank();

        // Verify both prices are stored correctly
        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);

        assertEq(nativePrice, ethPrice, "ETH price mismatch");
        assertEq(stablePrice, usdcPrice, "USDC price mismatch");
        assertTrue(nativePrice != stablePrice, "Prices should be different");
    }

    /// @notice Test querying native pricing
    function test_GetNodePricing_Native() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        uint256 ethPrice = 3_500_000_000;
        uint256 usdcPrice = 3000;

        nodeRegistry.registerNode("metadata", "https://api.example.com", models, ethPrice, usdcPrice);

        vm.stopPrank();

        // Query native pricing (ETH = address(0))
        uint256 queriedPrice = nodeRegistry.getNodePricing(host, address(0));
        assertEq(queriedPrice, ethPrice, "Native price query failed");
    }

    /// @notice Test querying stable pricing
    function test_GetNodePricing_Stable() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        uint256 ethPrice = 4_000_000_000;
        uint256 usdcPrice = 3000;

        address usdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC

        nodeRegistry.registerNode("metadata", "https://api.example.com", models, ethPrice, usdcPrice);

        vm.stopPrank();

        // Query stable pricing (USDC address)
        uint256 queriedPrice = nodeRegistry.getNodePricing(host, usdcAddress);
        assertEq(queriedPrice, usdcPrice, "Stable price query failed");
    }

    /// @notice Test updating native pricing only
    function test_UpdatePricingNative() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("metadata", "https://api.example.com", models, 3_000_000_000, 2000);

        // Update native pricing
        uint256 newNativePrice = 4_500_000_000;
        nodeRegistry.updatePricingNative(newNativePrice);

        vm.stopPrank();

        // Verify native price changed, stable price unchanged
        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);

        assertEq(nativePrice, newNativePrice, "Native price not updated");
        assertEq(stablePrice, 2000, "Stable price should remain unchanged");
    }

    /// @notice Test updating stable pricing only
    function test_UpdatePricingStable() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("metadata", "https://api.example.com", models, 3_000_000_000, 2000);

        // Update stable pricing
        uint256 newStablePrice = 2500;
        nodeRegistry.updatePricingStable(newStablePrice);

        vm.stopPrank();

        // Verify stable price changed, native price unchanged
        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);

        assertEq(nativePrice, 3_000_000_000, "Native price should remain unchanged");
        assertEq(stablePrice, newStablePrice, "Stable price not updated");
    }

    /// @notice Test validation: native price too low
    function test_DualPricing_NativeTooLow() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.expectRevert("Native price below minimum");
        nodeRegistry.registerNode("metadata", "https://api.example.com", models, MIN_PRICE_NATIVE - 1, 2000);

        vm.stopPrank();
    }

    /// @notice Test validation: stable price too low
    function test_DualPricing_StableTooLow() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.expectRevert("Stable price below minimum");
        nodeRegistry.registerNode("metadata", "https://api.example.com", models, 3_000_000_000, MIN_PRICE_STABLE - 1);

        vm.stopPrank();
    }

    /// @notice Test validation: native price too high
    function test_DualPricing_NativeTooHigh() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.expectRevert("Native price above maximum");
        nodeRegistry.registerNode("metadata", "https://api.example.com", models, MAX_PRICE_NATIVE + 1, 2000);

        vm.stopPrank();
    }

    /// @notice Test validation: stable price too high
    function test_DualPricing_StableTooHigh() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.expectRevert("Stable price above maximum");
        nodeRegistry.registerNode("metadata", "https://api.example.com", models, 3_000_000_000, MAX_PRICE_STABLE + 1);

        vm.stopPrank();
    }

    /// @notice Test that both prices can be at minimum
    function test_DualPricing_BothAtMinimum() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("metadata", "https://api.example.com", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);

        vm.stopPrank();

        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);

        assertEq(nativePrice, MIN_PRICE_NATIVE, "Native price should be at minimum");
        assertEq(stablePrice, MIN_PRICE_STABLE, "Stable price should be at minimum");
    }

    /// @notice Test that both prices can be at maximum
    function test_DualPricing_BothAtMaximum() public {
        vm.startPrank(host);

        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("metadata", "https://api.example.com", models, MAX_PRICE_NATIVE, MAX_PRICE_STABLE);

        vm.stopPrank();

        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host);

        assertEq(nativePrice, MAX_PRICE_NATIVE, "Native price should be at maximum");
        assertEq(stablePrice, MAX_PRICE_STABLE, "Stable price should be at maximum");
    }
}
