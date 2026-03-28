// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "../../mocks/ERC20Mock.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title NodeRegistry Access Control Negative Tests (Phase 18)
 * @notice Tests for access control violations and unauthorized operations
 */
contract NodeRegistryAccessControlTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(this);
    address public host1 = address(0x1);
    address public host2 = address(0x2);
    address public nonHost = address(0x3);

    bytes32 public modelId;
    uint256 public constant MIN_STAKE = 1000 * 10**18;
    uint256 public constant MIN_PRICE_NATIVE = 227_273;
    uint256 public constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy FAB token and USDC mock
        fabToken = new ERC20Mock("FAB", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelImpl = new ModelRegistryUpgradeable();
        ERC1967Proxy modelProxy = new ERC1967Proxy(
            address(modelImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        modelRegistry = ModelRegistryUpgradeable(address(modelProxy));

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeImpl = new NodeRegistryWithModelsUpgradeable();
        ERC1967Proxy nodeProxy = new ERC1967Proxy(
            address(nodeImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(nodeProxy));

        // Add a trusted model
        modelRegistry.addTrustedModel("test/repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("test/repo", "model.gguf");

        // Fund hosts
        fabToken.mint(host1, MIN_STAKE * 10);
        fabToken.mint(host2, MIN_STAKE * 10);

        // Host1 registers
        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("metadata", "http://api.url", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // ============ updateMetadata ============

    function test_UpdateMetadata_RejectsUnregistered() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.updateMetadata("new metadata");
    }

    function test_UpdateMetadata_SucceedsForRegisteredHost() public {
        vm.prank(host1);
        nodeRegistry.updateMetadata("new metadata");

        (,,, string memory metadata,,,,) = nodeRegistry.getNodeFullInfo(host1);
        assertEq(metadata, "new metadata");
    }

    function test_UpdateMetadata_RejectsEmptyMetadata() public {
        vm.prank(host1);
        vm.expectRevert("Empty metadata");
        nodeRegistry.updateMetadata("");
    }

    // ============ updateApiUrl ============

    function test_UpdateApiUrl_RejectsUnregistered() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.updateApiUrl("http://new.url");
    }

    function test_UpdateApiUrl_SucceedsForRegisteredHost() public {
        vm.prank(host1);
        nodeRegistry.updateApiUrl("http://new.url");

        (,,,, string memory apiUrl,,,) = nodeRegistry.getNodeFullInfo(host1);
        assertEq(apiUrl, "http://new.url");
    }

    function test_UpdateApiUrl_RejectsEmptyUrl() public {
        vm.prank(host1);
        vm.expectRevert("Empty API URL");
        nodeRegistry.updateApiUrl("");
    }

    // ============ setModelTokenPricing ============

    function test_SetModelTokenPricing_RejectsUnregistered() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);
    }

    function test_SetModelTokenPricing_RejectsUnsupportedModel() public {
        bytes32 unsupportedModel = keccak256("unsupported");
        vm.prank(host1);
        vm.expectRevert("Model not supported");
        nodeRegistry.setModelTokenPricing(unsupportedModel, address(usdcToken), MIN_PRICE_STABLE);
    }

    function test_SetModelTokenPricing_SucceedsForSupportedModel() public {
        uint256 stablePrice = MIN_PRICE_STABLE * 2;

        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), stablePrice);

        uint256 result = nodeRegistry.getModelPricing(host1, modelId, address(usdcToken));
        assertEq(result, stablePrice);
    }

    function test_SetModelTokenPricing_Native_SucceedsForSupportedModel() public {
        uint256 nativePrice = MIN_PRICE_NATIVE * 2;

        vm.prank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(0), nativePrice);

        uint256 result = nodeRegistry.getModelPricing(host1, modelId, address(0));
        assertEq(result, nativePrice);
    }

    // ============ clearModelTokenPricing ============

    function test_ClearModelTokenPricing_RejectsUnregistered() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
    }

    function test_ClearModelTokenPricing_SucceedsForRegisteredHost() public {
        // First set model-token pricing
        vm.startPrank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE * 2);

        // Then clear it
        nodeRegistry.clearModelTokenPricing(modelId, address(usdcToken));
        vm.stopPrank();

        // Should revert since no modelTokenPricing is set
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host1, modelId, address(usdcToken));
    }

    function test_ClearModelTokenPricing_NativeRevertsAfterClear() public {
        // Set then clear native model-token pricing
        vm.startPrank(host1);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE * 3);
        nodeRegistry.clearModelTokenPricing(modelId, address(0));
        vm.stopPrank();

        // Should revert since no modelTokenPricing is set (no fallback)
        vm.expectRevert("No model pricing");
        nodeRegistry.getModelPricing(host1, modelId, address(0));
    }

    // ============ stake ============

    function test_Stake_RejectsUnregistered() public {
        vm.prank(nonHost);
        vm.expectRevert("Not registered");
        nodeRegistry.stake(100);
    }

    function test_Stake_RejectsZeroAmount() public {
        vm.prank(host1);
        vm.expectRevert("Zero amount");
        nodeRegistry.stake(0);
    }

    function test_Stake_SucceedsWithValidAmount() public {
        uint256 additionalStake = 500 * 10**18;

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), additionalStake);
        nodeRegistry.stake(additionalStake);
        vm.stopPrank();

        (, uint256 stakedAmount,,,,,,) = nodeRegistry.getNodeFullInfo(host1);
        assertEq(stakedAmount, MIN_STAKE + additionalStake);
    }

    // ============ updateModelRegistry (owner only) ============

    function test_UpdateModelRegistry_RejectsNonOwner() public {
        vm.prank(host1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", host1));
        nodeRegistry.updateModelRegistry(address(0x999));
    }

    function test_UpdateModelRegistry_RejectsZeroAddress() public {
        vm.expectRevert("Invalid registry address");
        nodeRegistry.updateModelRegistry(address(0));
    }

    function test_UpdateModelRegistry_SucceedsForOwner() public {
        address newRegistry = address(0x999);
        nodeRegistry.updateModelRegistry(newRegistry);

        assertEq(address(nodeRegistry.modelRegistry()), newRegistry);
    }

    // ============ View functions ============

    function test_IsActiveNode_ReturnsFalseForNonRegistered() public view {
        assertFalse(nodeRegistry.isActiveNode(nonHost));
    }

    function test_IsActiveNode_ReturnsTrueForRegistered() public view {
        assertTrue(nodeRegistry.isActiveNode(host1));
    }

    function test_GetNodeApiUrl_ReturnsEmptyForNonRegistered() public view {
        string memory url = nodeRegistry.getNodeApiUrl(nonHost);
        assertEq(bytes(url).length, 0);
    }

    function test_GetAllActiveNodes_ReturnsCorrectList() public view {
        address[] memory nodes = nodeRegistry.getAllActiveNodes();
        assertEq(nodes.length, 1);
        assertEq(nodes[0], host1);
    }
}
