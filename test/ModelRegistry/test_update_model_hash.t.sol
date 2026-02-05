// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ModelRegistryUpgradeable} from "../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract UpdateModelHashTest is Test {
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public notOwner = address(0x2);

    bytes32 public modelId;

    function setUp() public {
        fabToken = new ERC20Mock("FAB Token", "FAB");

        vm.startPrank(owner);
        ModelRegistryUpgradeable impl = new ModelRegistryUpgradeable();
        address proxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(proxy);

        // Add a model with zero hash (simulating the bug)
        modelRegistry.addTrustedModel("test/repo", "model.gguf", bytes32(0));
        modelId = modelRegistry.getModelId("test/repo", "model.gguf");
        vm.stopPrank();
    }

    function test_UpdateModelHash_Success() public {
        bytes32 newHash = bytes32(uint256(0x1234567890abcdef));
        
        vm.prank(owner);
        modelRegistry.updateModelHash(modelId, newHash);
        
        assertEq(modelRegistry.getModelHash(modelId), newHash);
    }

    function test_UpdateModelHash_EmitsEvent() public {
        bytes32 newHash = bytes32(uint256(0x1234567890abcdef));
        bytes32 oldHash = modelRegistry.getModelHash(modelId);
        
        vm.expectEmit(true, false, false, true);
        emit ModelRegistryUpgradeable.ModelHashUpdated(modelId, oldHash, newHash);
        
        vm.prank(owner);
        modelRegistry.updateModelHash(modelId, newHash);
    }

    function test_UpdateModelHash_OnlyOwner() public {
        bytes32 newHash = bytes32(uint256(0x1234567890abcdef));
        
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", notOwner));
        modelRegistry.updateModelHash(modelId, newHash);
    }

    function test_UpdateModelHash_NonexistentModel() public {
        bytes32 fakeModelId = bytes32(uint256(0x999));
        bytes32 newHash = bytes32(uint256(0x1234567890abcdef));
        
        vm.prank(owner);
        vm.expectRevert("Model does not exist");
        modelRegistry.updateModelHash(fakeModelId, newHash);
    }
}
