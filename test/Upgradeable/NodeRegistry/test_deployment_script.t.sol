// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {DeployNodeRegistryUpgradeable} from "../../../script/DeployNodeRegistryUpgradeable.s.sol";

/**
 * @title NodeRegistry Deployment Script Tests
 * @dev Tests the deployment script for NodeRegistryWithModelsUpgradeable
 */
contract NodeRegistryDeploymentScriptTest is Test {
    DeployNodeRegistryUpgradeable public deployScript;
    ERC20Mock public fabToken;
    ModelRegistryUpgradeable public modelRegistry;

    address public owner = address(this);

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry as proxy
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Set environment variables for deployment script
        vm.setEnv("FAB_TOKEN", vm.toString(address(fabToken)));
        vm.setEnv("MODEL_REGISTRY", vm.toString(address(modelRegistry)));

        // Create deployment script
        deployScript = new DeployNodeRegistryUpgradeable();
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

        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(proxy);

        // Verify initialization
        assertTrue(nodeRegistry.owner() != address(0), "Owner should be set");
        assertEq(address(nodeRegistry.fabToken()), address(fabToken), "FAB token should match");
        assertEq(address(nodeRegistry.modelRegistry()), address(modelRegistry), "Model registry should match");
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

        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(proxy);
        address originalOwner = nodeRegistry.owner();

        // Deploy new implementation
        NodeRegistryWithModelsUpgradeable newImpl = new NodeRegistryWithModelsUpgradeable();

        // Upgrade should work (as owner)
        vm.prank(originalOwner);
        nodeRegistry.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, address(newImpl));
    }

    function test_DeployedContractCanRegisterNodes() public {
        (address proxy, ) = deployScript.run();

        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(proxy);

        // Add an approved model
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        bytes32 modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        // Prepare host
        address host = address(0x100);
        fabToken.mint(host, 10000 * 10**18);

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Register node
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host.com",
            models,
            227_273,  // MIN_PRICE_NATIVE
            1         // MIN_PRICE_STABLE
        );
        vm.stopPrank();

        // Verify registration
        assertTrue(nodeRegistry.isActiveNode(host), "Host should be active");
    }

    function test_DeployedContractCanUnregister() public {
        (address proxy, ) = deployScript.run();

        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(proxy);

        // Add an approved model
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        bytes32 modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        // Prepare host
        address host = address(0x100);
        fabToken.mint(host, 10000 * 10**18);

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Register node
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host.com",
            models,
            227_273,
            1
        );

        uint256 balanceBefore = fabToken.balanceOf(host);

        // Unregister
        nodeRegistry.unregisterNode();
        vm.stopPrank();

        // Verify unregistration
        assertFalse(nodeRegistry.isActiveNode(host), "Host should not be active");
        assertEq(fabToken.balanceOf(host), balanceBefore + 1000 * 10**18, "Stake should be returned");
    }
}
