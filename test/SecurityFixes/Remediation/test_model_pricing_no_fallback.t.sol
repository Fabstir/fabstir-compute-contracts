// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @notice Phase 18B: getModelPricing reads only from modelTokenPricing — no fallback chain
contract ModelPricingNoFallbackTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);

    bytes32 public modelId;

    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        vm.stopPrank();

        // Register host
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // -------------------------------------------------------
    // getModelPricing — reads from modelTokenPricing only
    // -------------------------------------------------------

    function test_GetModelPricing_ReturnsModelTokenPricingForERC20() public {
        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);

        uint256 price = nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
        assertEq(price, 50);
    }

    function test_GetModelPricing_ReturnsModelTokenPricingForNative() public {
        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);

        uint256 price = nodeRegistry.getModelPricing(host, modelId, address(0));
        assertEq(price, MIN_PRICE_NATIVE);
    }

    function test_GetModelPricing_RevertsWhenNativeNotSet() public {
        // No modelTokenPricing set for native — should revert, NOT fall back
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host, modelId, address(0));
    }

    function test_GetModelPricing_RevertsWhenERC20NotSet() public {
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
    }

    function test_GetModelPricing_DoesNotFallBackToModelPricingNative() public {
        // Set deprecated modelPricingNative but NOT modelTokenPricing
        // After Phase 18B.2, getModelPricing ignores modelPricingNative
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host, modelId, address(0));
    }

    function test_GetModelPricing_DoesNotFallBackToModelPricingStable() public {
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
    }

    function test_GetModelPricing_DoesNotFallBackToCustomTokenPricing() public {
        // Even if customTokenPricing was set, getModelPricing should NOT use it
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
    }

    function test_GetModelPricing_DoesNotFallBackToMinPricePerTokenNative() public {
        // minPricePerTokenNative is set via registerNode, but should NOT be used
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host, modelId, address(0));
    }

    function test_GetModelPricing_UnregisteredOperatorReturnsZero() public {
        address nonRegistered = address(0xDEAD);
        uint256 price = nodeRegistry.getModelPricing(nonRegistered, modelId, address(usdcToken));
        assertEq(price, 0);
    }

    // -------------------------------------------------------
    // getHostModelPrices — token-specific batch query
    // -------------------------------------------------------

    function test_GetHostModelPrices_ReturnsCorrectPricesForToken() public {
        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);

        (bytes32[] memory ids, uint256[] memory prices) = nodeRegistry.getHostModelPrices(host, address(usdcToken));
        assertEq(ids.length, 1);
        assertEq(ids[0], modelId);
        assertEq(prices[0], 50);
    }

    function test_GetHostModelPrices_ReturnsNativePrices() public {
        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);

        (bytes32[] memory ids, uint256[] memory prices) = nodeRegistry.getHostModelPrices(host, address(0));
        assertEq(ids.length, 1);
        assertEq(ids[0], modelId);
        assertEq(prices[0], MIN_PRICE_NATIVE);
    }

    function test_GetHostModelPrices_ReturnsEmptyForUnregistered() public {
        address nonRegistered = address(0xDEAD);
        (bytes32[] memory ids, uint256[] memory prices) = nodeRegistry.getHostModelPrices(nonRegistered, address(usdcToken));
        assertEq(ids.length, 0);
        assertEq(prices.length, 0);
    }

    function test_GetHostModelPrices_ReturnsZeroForUnsetPricing() public {
        // No modelTokenPricing set — batch query returns 0 (does not revert)
        (bytes32[] memory ids, uint256[] memory prices) = nodeRegistry.getHostModelPrices(host, address(usdcToken));
        assertEq(ids.length, 1);
        assertEq(prices[0], 0);
    }

    // -------------------------------------------------------
    // Removed NR functions — low-level call returns false
    // -------------------------------------------------------

    function test_GetNodePricing_FunctionRemoved() public {
        (bool success,) = address(nodeRegistry).call(
            abi.encodeWithSignature("getNodePricing(address,address)", host, address(usdcToken))
        );
        assertFalse(success, "getNodePricing should not exist");
    }

    function test_SetTokenPricing_FunctionRemoved() public {
        vm.prank(host);
        (bool success,) = address(nodeRegistry).call(
            abi.encodeWithSignature("setTokenPricing(address,uint256)", address(usdcToken), uint256(50))
        );
        assertFalse(success, "setTokenPricing should not exist");
    }

    function test_UpdatePricingNative_FunctionRemoved() public {
        vm.prank(host);
        (bool success,) = address(nodeRegistry).call(
            abi.encodeWithSignature("updatePricingNative(uint256)", MIN_PRICE_NATIVE)
        );
        assertFalse(success, "updatePricingNative should not exist");
    }

    function test_UpdatePricingStable_FunctionRemoved() public {
        vm.prank(host);
        (bool success,) = address(nodeRegistry).call(
            abi.encodeWithSignature("updatePricingStable(uint256)", MIN_PRICE_STABLE)
        );
        assertFalse(success, "updatePricingStable should not exist");
    }

    function test_SetModelPricing_FunctionRemoved() public {
        vm.prank(host);
        (bool success,) = address(nodeRegistry).call(
            abi.encodeWithSignature("setModelPricing(bytes32,uint256,uint256)", modelId, MIN_PRICE_NATIVE, MIN_PRICE_STABLE)
        );
        assertFalse(success, "setModelPricing should not exist");
    }

    function test_ClearModelPricing_FunctionRemoved() public {
        vm.prank(host);
        (bool success,) = address(nodeRegistry).call(
            abi.encodeWithSignature("clearModelPricing(bytes32)", modelId)
        );
        assertFalse(success, "clearModelPricing should not exist");
    }
}
