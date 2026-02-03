// test/SecurityFixes/RateLimit/test_model_rate_limit_getter.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract ModelRateLimitGetterTest is Test {
    ModelRegistryUpgradeable modelRegistry;
    MockERC20 fabToken;
    address owner;
    bytes32 testModelId;

    uint256 constant DEFAULT_RATE_LIMIT = 2000;

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

    function test_GetModelRateLimit_ReturnsConfiguredValue() public {
        vm.prank(owner);
        modelRegistry.setModelRateLimit(testModelId, 3000);

        uint256 rate = modelRegistry.getModelRateLimit(testModelId);
        assertEq(rate, 3000);
    }

    function test_GetModelRateLimit_ReturnsDefaultWhenNotConfigured() public view {
        uint256 rate = modelRegistry.getModelRateLimit(testModelId);
        assertEq(rate, DEFAULT_RATE_LIMIT);
    }

    function test_GetModelRateLimit_ReturnsDefaultForNonExistentModel() public view {
        bytes32 fakeModelId = keccak256("fake/model");
        uint256 rate = modelRegistry.getModelRateLimit(fakeModelId);
        assertEq(rate, DEFAULT_RATE_LIMIT);
    }
}
