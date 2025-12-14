// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {DeployModelRegistryUpgradeable} from "../../../script/DeployModelRegistryUpgradeable.s.sol";

/**
 * @title ModelRegistry Deployment Script Tests
 * @dev Tests the deployment script for ModelRegistryUpgradeable
 */
contract ModelRegistryDeploymentScriptTest is Test {
    DeployModelRegistryUpgradeable public deployScript;
    ERC20Mock public fabToken;

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Set environment variable
        vm.setEnv("FAB_TOKEN_ADDRESS", vm.toString(address(fabToken)));

        // Create deployment script
        deployScript = new DeployModelRegistryUpgradeable();
    }

    function test_DeploymentScriptWorks() public {
        // Run the deployment script
        (address proxy, address implementation) = deployScript.run();

        // Verify deployment
        assertTrue(proxy != address(0), "Proxy should be deployed");
        assertTrue(implementation != address(0), "Implementation should be deployed");
        assertTrue(proxy != implementation, "Proxy and implementation should be different");
    }

    function test_DeploymentInitializesCorrectly() public {
        (address proxy, ) = deployScript.run();

        ModelRegistryUpgradeable registry = ModelRegistryUpgradeable(proxy);

        // Verify initialization
        assertEq(address(registry.governanceToken()), address(fabToken));
        assertTrue(registry.owner() != address(0), "Owner should be set");
    }

    function test_DeploymentStoresCorrectImplementation() public {
        (address proxy, address implementation) = deployScript.run();

        // Get implementation address from ERC1967 storage slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, implementation, "Implementation addresses should match");
    }

    function test_DeployedContractIsUpgradeable() public {
        (address proxy, ) = deployScript.run();

        ModelRegistryUpgradeable registry = ModelRegistryUpgradeable(proxy);
        address originalOwner = registry.owner();

        // Deploy new implementation
        ModelRegistryUpgradeable newImpl = new ModelRegistryUpgradeable();

        // Upgrade should work (as owner)
        vm.prank(originalOwner);
        registry.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, address(newImpl));
    }

    function test_DeployedContractCanAddModels() public {
        (address proxy, ) = deployScript.run();

        ModelRegistryUpgradeable registry = ModelRegistryUpgradeable(proxy);
        address owner = registry.owner();

        // Add a model
        vm.prank(owner);
        registry.addTrustedModel("Test/Repo", "model.gguf", bytes32(uint256(1)));

        // Verify
        bytes32 modelId = registry.getModelId("Test/Repo", "model.gguf");
        assertTrue(registry.isModelApproved(modelId));
    }
}
