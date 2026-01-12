// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {DeployJobMarketplaceUpgradeable} from "../../../script/DeployJobMarketplaceUpgradeable.s.sol";

/**
 * @title JobMarketplace Deployment Script Tests
 * @dev Tests the deployment script for JobMarketplaceWithModelsUpgradeable
 */
contract JobMarketplaceDeploymentScriptTest is Test {
    DeployJobMarketplaceUpgradeable public deployScript;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;

    address public owner = address(this);

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;

    function setUp() public {
        // Deploy mock token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry as proxy
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Deploy NodeRegistry as proxy
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings as proxy
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Set environment variables for deployment script
        vm.setEnv("NODE_REGISTRY", vm.toString(address(nodeRegistry)));
        vm.setEnv("HOST_EARNINGS", vm.toString(address(hostEarnings)));
        vm.setEnv("feeBasisPoints", vm.toString(feeBasisPoints));
        vm.setEnv("disputeWindow", vm.toString(disputeWindow));

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
        assertEq(marketplace.feeBasisPoints(), feeBasisPoints, "Fee should match");
        assertEq(marketplace.disputeWindow(), disputeWindow, "Dispute window should match");
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
