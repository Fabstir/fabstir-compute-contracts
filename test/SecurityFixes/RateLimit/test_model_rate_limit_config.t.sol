// test/SecurityFixes/RateLimit/test_model_rate_limit_config.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract ModelRateLimitConfigTest is Test {
    ModelRegistryUpgradeable modelRegistry;
    MockERC20 fabToken;
    address owner;
    address nonOwner;
    bytes32 testModelId;

    uint256 constant MIN_RATE_LIMIT = 100;
    uint256 constant MAX_RATE_LIMIT = 10000;
    uint256 constant DEFAULT_RATE_LIMIT = 2000;

    event ModelRateLimitUpdated(bytes32 indexed modelId, uint256 maxTokensPerSecond);

    function setUp() public {
        owner = makeAddr("owner");
        nonOwner = makeAddr("nonOwner");

        // Deploy FAB token mock
        fabToken = new MockERC20("FAB", "FAB", 18);

        // Deploy ModelRegistry
        vm.startPrank(owner);
        ModelRegistryUpgradeable impl = new ModelRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(impl.initialize, (address(fabToken)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        modelRegistry = ModelRegistryUpgradeable(address(proxy));

        // Add a test model
        modelRegistry.addTrustedModel("test/repo", "model.gguf", bytes32(uint256(123)));
        testModelId = modelRegistry.getModelId("test/repo", "model.gguf");
        vm.stopPrank();
    }

    function test_SetModelRateLimit_Success() public {
        vm.prank(owner);
        modelRegistry.setModelRateLimit(testModelId, 3000);
        assertEq(modelRegistry.getModelRateLimit(testModelId), 3000);
    }

    function test_SetModelRateLimit_NonExistentModel_Reverts() public {
        bytes32 fakeModelId = keccak256("fake/model");
        vm.prank(owner);
        vm.expectRevert("Model does not exist");
        modelRegistry.setModelRateLimit(fakeModelId, 3000);
    }

    function test_SetModelRateLimit_BelowMinimum_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("Rate below minimum");
        modelRegistry.setModelRateLimit(testModelId, 99);
    }

    function test_SetModelRateLimit_AboveMaximum_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("Rate above maximum");
        modelRegistry.setModelRateLimit(testModelId, 10001);
    }

    function test_SetModelRateLimit_NonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        modelRegistry.setModelRateLimit(testModelId, 3000);
    }

    function test_SetModelRateLimit_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ModelRateLimitUpdated(testModelId, 3000);
        modelRegistry.setModelRateLimit(testModelId, 3000);
    }

    function test_SetModelRateLimit_UpdatesExistingValue() public {
        vm.startPrank(owner);
        modelRegistry.setModelRateLimit(testModelId, 3000);
        assertEq(modelRegistry.getModelRateLimit(testModelId), 3000);

        modelRegistry.setModelRateLimit(testModelId, 5000);
        assertEq(modelRegistry.getModelRateLimit(testModelId), 5000);
        vm.stopPrank();
    }

    function test_SetModelRateLimit_AtMinimumBoundary() public {
        vm.prank(owner);
        modelRegistry.setModelRateLimit(testModelId, MIN_RATE_LIMIT);
        assertEq(modelRegistry.getModelRateLimit(testModelId), MIN_RATE_LIMIT);
    }

    function test_SetModelRateLimit_AtMaximumBoundary() public {
        vm.prank(owner);
        modelRegistry.setModelRateLimit(testModelId, MAX_RATE_LIMIT);
        assertEq(modelRegistry.getModelRateLimit(testModelId), MAX_RATE_LIMIT);
    }
}
