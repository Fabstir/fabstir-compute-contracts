// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {DeployJobMarketplaceUpgradeable} from "../../../script/DeployJobMarketplaceUpgradeable.s.sol";

/**
 * @title JobMarketplace Deployment Script Tests
 * @dev Tests the deployment script for JobMarketplaceWithModelsUpgradeable
 */
contract JobMarketplaceDeploymentScriptTest is Test {
    DeployJobMarketplaceUpgradeable public deployScript;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;

    address public owner = address(this);

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;

    function setUp() public {
        // Deploy mock token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry
        modelRegistry = new ModelRegistry(address(fabToken));

        // Deploy NodeRegistryWithModels
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));

        // Deploy HostEarnings
        hostEarnings = new HostEarnings();

        // Set environment variables for deployment script
        vm.setEnv("NODE_REGISTRY", vm.toString(address(nodeRegistry)));
        vm.setEnv("HOST_EARNINGS", vm.toString(address(hostEarnings)));
        vm.setEnv("FEE_BASIS_POINTS", vm.toString(FEE_BASIS_POINTS));
        vm.setEnv("DISPUTE_WINDOW", vm.toString(DISPUTE_WINDOW));

        // Create deployment script
        deployScript = new DeployJobMarketplaceUpgradeable();
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

        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxy));

        // Verify initialization
        assertTrue(marketplace.owner() != address(0), "Owner should be set");
        assertEq(address(marketplace.nodeRegistry()), address(nodeRegistry), "Node registry should match");
        assertEq(address(marketplace.hostEarnings()), address(hostEarnings), "Host earnings should match");
        assertEq(marketplace.FEE_BASIS_POINTS(), FEE_BASIS_POINTS, "Fee should match");
        assertEq(marketplace.DISPUTE_WINDOW(), DISPUTE_WINDOW, "Dispute window should match");
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

        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxy));
        address originalOwner = marketplace.owner();

        // Deploy new implementation
        JobMarketplaceWithModelsUpgradeable newImpl = new JobMarketplaceWithModelsUpgradeable();

        // Upgrade should work (as owner)
        vm.prank(originalOwner);
        marketplace.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, address(newImpl));
    }

    function test_DeployedContractCanCreateSessions() public {
        (address proxy, ) = deployScript.run();

        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxy));

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

        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host.com",
            models,
            227_273,  // MIN_PRICE_NATIVE
            1         // MIN_PRICE_STABLE
        );
        vm.stopPrank();

        // Create session
        address user = address(0x200);
        vm.deal(user, 10 ether);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host,
            227_273,
            1 days,
            1000
        );

        assertEq(sessionId, 1, "Session should be created");
        assertEq(marketplace.nextJobId(), 2, "Next job ID should be 2");
    }

    function test_DeployedContractCanBePaused() public {
        (address proxy, ) = deployScript.run();

        JobMarketplaceWithModelsUpgradeable marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxy));
        address marketplaceOwner = marketplace.owner();

        // Pause
        vm.prank(marketplaceOwner);
        marketplace.pause();

        assertTrue(marketplace.paused(), "Should be paused");

        // Unpause
        vm.prank(marketplaceOwner);
        marketplace.unpause();

        assertFalse(marketplace.paused(), "Should be unpaused");
    }
}
