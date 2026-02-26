// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @notice Phase 18A: Per-model per-token pricing via modelTokenPricing mapping
contract ModelTokenPricingTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public daiToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public nonHost = address(0x3);

    bytes32 public modelId;
    bytes32 public modelId2;

    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MAX_PRICE_NATIVE = 22_727_272_727_273_000;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MAX_PRICE_STABLE = 100_000_000;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");
        daiToken = new ERC20Mock("DAI", "DAI");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");
        modelRegistry.addTrustedModel("TestModel2/Repo", "model2.gguf", bytes32(uint256(2)));
        modelId2 = modelRegistry.getModelId("TestModel2/Repo", "model2.gguf");

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        vm.stopPrank();

        // Register host with both models
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId;
        models[1] = modelId2;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // -------------------------------------------------------
    // setModelTokenPricing — basic functionality
    // -------------------------------------------------------

    function test_SetModelTokenPricing_StoresERC20Price() public {
        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);

        uint256 price = nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken));
        assertEq(price, 50);
    }

    function test_SetModelTokenPricing_StoresNativePrice() public {
        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);

        uint256 price = nodeRegistry.modelTokenPricing(host, modelId, address(0));
        assertEq(price, MIN_PRICE_NATIVE);
    }

    function test_SetModelTokenPricing_EmitsEvent() public {
        vm.prank(host);
        vm.expectEmit(true, true, true, true);
        emit NodeRegistryWithModelsUpgradeable.ModelTokenPricingUpdated(host, modelId, address(usdcToken), 50);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
    }

    // -------------------------------------------------------
    // setModelTokenPricing — access control
    // -------------------------------------------------------

    function test_SetModelTokenPricing_RevertsForUnregisteredNode() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
    }

    function test_SetModelTokenPricing_RevertsForUnsupportedModel() public {
        bytes32 unsupportedModel = bytes32(uint256(999));
        vm.prank(host);
        vm.expectRevert("Model not supported");
        nodeRegistry.setModelTokenPricing(unsupportedModel, address(usdcToken), 50);
    }

    // -------------------------------------------------------
    // setModelTokenPricing — native price validation
    // -------------------------------------------------------

    function test_SetModelTokenPricing_RevertsForNativePriceBelowMin() public {
        vm.prank(host);
        vm.expectRevert("Native price below minimum");
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE - 1);
    }

    function test_SetModelTokenPricing_RevertsForNativePriceAboveMax() public {
        vm.prank(host);
        vm.expectRevert("Native price above maximum");
        nodeRegistry.setModelTokenPricing(modelId, address(0), MAX_PRICE_NATIVE + 1);
    }

    // -------------------------------------------------------
    // setModelTokenPricing — stable price validation
    // -------------------------------------------------------

    function test_SetModelTokenPricing_RevertsForStablePriceBelowMin() public {
        vm.prank(host);
        vm.expectRevert("Stable price below minimum");
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 0);
    }

    function test_SetModelTokenPricing_RevertsForStablePriceAboveMax() public {
        vm.prank(host);
        vm.expectRevert("Stable price above maximum");
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MAX_PRICE_STABLE + 1);
    }

    function test_SetModelTokenPricing_ZeroPriceRevertsForNative() public {
        vm.prank(host);
        vm.expectRevert("Native price below minimum");
        nodeRegistry.setModelTokenPricing(modelId, address(0), 0);
    }

    // -------------------------------------------------------
    // clearModelTokenPricing
    // -------------------------------------------------------

    function test_ClearModelTokenPricing_SetsPriceToZero() public {
        vm.startPrank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken)), 50);

        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken)), 0);
        vm.stopPrank();
    }

    function test_ClearModelTokenPricing_RevertsForUnregisteredNode() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
    }

    function test_ClearModelTokenPricing_EmitsEventWithZeroPrice() public {
        vm.startPrank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);

        vm.expectEmit(true, true, true, true);
        emit NodeRegistryWithModelsUpgradeable.ModelTokenPricingUpdated(host, modelId, address(usdcToken), 0);
        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
        vm.stopPrank();
    }

    // -------------------------------------------------------
    // Overwrite and re-set behavior
    // -------------------------------------------------------

    function test_SetModelTokenPricing_OverwritesPreviousPrice() public {
        vm.startPrank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 75);
        vm.stopPrank();

        uint256 price = nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken));
        assertEq(price, 75, "Should overwrite, not accumulate");
    }

    function test_SetClearSetCycle_Works() public {
        vm.startPrank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken)), 0);

        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 99);
        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken)), 99);
        vm.stopPrank();
    }

    // -------------------------------------------------------
    // Multi-model and multi-token independence
    // -------------------------------------------------------

    function test_DifferentTokensSameModel_IndependentPrices() public {
        vm.startPrank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
        nodeRegistry.setModelTokenPricing(modelId, address(daiToken), 75);
        vm.stopPrank();

        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken)), 50);
        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(daiToken)), 75);
    }

    function test_DifferentModelsSameToken_IndependentPrices() public {
        vm.startPrank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), 50);
        nodeRegistry.setModelTokenPricing(modelId2, address(usdcToken), 100);
        vm.stopPrank();

        assertEq(nodeRegistry.modelTokenPricing(host, modelId, address(usdcToken)), 50);
        assertEq(nodeRegistry.modelTokenPricing(host, modelId2, address(usdcToken)), 100);
    }
}
