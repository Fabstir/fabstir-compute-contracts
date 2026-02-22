// test/SecurityFixes/RateLimit/test_model_rate_limit_config.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/// @notice F202614913: Per-model rate limit configuration tests
contract ModelRateLimitConfigTest is Test {
    ModelRegistryUpgradeable modelRegistry;
    MockERC20 fabToken;
    address owner;
    bytes32 testModelId;

    uint256 constant DEFAULT_RATE_LIMIT = 2000;
    uint256 constant MIN_RATE_LIMIT = 100;
    uint256 constant MAX_RATE_LIMIT = 10000;

    function setUp() public {
        owner = makeAddr("owner");
        fabToken = new MockERC20("FAB", "FAB", 18);

        vm.startPrank(owner);
        ModelRegistryUpgradeable impl = new ModelRegistryUpgradeable();
        bytes memory initData = abi.encodeCall(impl.initialize, (address(fabToken)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        modelRegistry = ModelRegistryUpgradeable(address(proxy));

        modelRegistry.addTrustedModel("test/repo", "model.gguf", bytes32(uint256(123)));
        testModelId = modelRegistry.getModelId("test/repo", "model.gguf");
        vm.stopPrank();
    }

    /// @notice Owner can set a custom rate limit for a model
    function test_SetModelRateLimit() public {
        vm.prank(owner);
        modelRegistry.setModelRateLimit(testModelId, 5000);
        assertEq(modelRegistry.getModelRateLimit(testModelId), 5000);
    }

    /// @notice Returns default when no rate is configured
    function test_GetModelRateLimit_ReturnsDefaultWhenNotConfigured() public view {
        uint256 rate = modelRegistry.getModelRateLimit(testModelId);
        assertEq(rate, DEFAULT_RATE_LIMIT);
    }

    /// @notice Returns default for non-existent model (getModelRateLimit is permissive)
    function test_GetModelRateLimit_ReturnsDefaultForNonExistentModel() public view {
        bytes32 fakeModelId = keccak256("fake/model");
        uint256 rate = modelRegistry.getModelRateLimit(fakeModelId);
        assertEq(rate, DEFAULT_RATE_LIMIT);
    }

    /// @notice Rate below MIN_RATE_LIMIT reverts
    function test_SetModelRateLimit_BelowMinimum_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("Rate below minimum");
        modelRegistry.setModelRateLimit(testModelId, MIN_RATE_LIMIT - 1);
    }

    /// @notice Rate above MAX_RATE_LIMIT reverts
    function test_SetModelRateLimit_AboveMaximum_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("Rate above maximum");
        modelRegistry.setModelRateLimit(testModelId, MAX_RATE_LIMIT + 1);
    }

    /// @notice Non-owner cannot set rate limits
    function test_SetModelRateLimit_NonOwner_Reverts() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert();
        modelRegistry.setModelRateLimit(testModelId, 3000);
    }

    /// @notice Cannot set rate limit for non-existent model
    function test_SetModelRateLimit_NonExistentModel_Reverts() public {
        bytes32 fakeModelId = keccak256("fake/model");
        vm.prank(owner);
        vm.expectRevert("Model does not exist");
        modelRegistry.setModelRateLimit(fakeModelId, 3000);
    }

    /// @notice Rate limit at boundaries (MIN and MAX) succeeds
    function test_SetModelRateLimit_AtBoundaries() public {
        vm.startPrank(owner);
        modelRegistry.setModelRateLimit(testModelId, MIN_RATE_LIMIT);
        assertEq(modelRegistry.getModelRateLimit(testModelId), MIN_RATE_LIMIT);

        modelRegistry.setModelRateLimit(testModelId, MAX_RATE_LIMIT);
        assertEq(modelRegistry.getModelRateLimit(testModelId), MAX_RATE_LIMIT);
        vm.stopPrank();
    }
}
