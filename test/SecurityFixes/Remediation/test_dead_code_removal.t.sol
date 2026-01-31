// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Dead Code Removal Tests (AUDIT-F1)
 * @notice Tests for Phase 1: Remove unused onlyRegisteredHost modifier
 *
 * Finding: AUDIT-F1
 * Slack Ref: slack-C0A61FZC8SH-p1769545156133729
 *
 * Issue: The onlyRegisteredHost modifier is defined but never used.
 * It's dead code that should be removed. Host validation is already
 * handled by _validateHostRegistration() internal function.
 *
 * These tests verify that:
 * 1. Host validation works correctly via _validateHostRegistration()
 * 2. Contract functions correctly without the dead modifier
 * 3. No regression after modifier removal
 */
contract DeadCodeRemovalTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public registeredHost = address(0x2);
    address public unregisteredHost = address(0x3);
    address public user = address(0x4);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(
                address(modelRegistryImpl),
                abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
            )
        );
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(
            new ERC1967Proxy(
                address(nodeRegistryImpl),
                abi.encodeCall(
                    NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry))
                )
            )
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(
            new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
        );
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(
            new ERC1967Proxy(
                address(marketplaceImpl),
                abi.encodeCall(
                    JobMarketplaceWithModelsUpgradeable.initialize,
                    (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW)
                )
            )
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register a valid host
        _registerHost(registeredHost);

        // Fund users
        vm.deal(user, 100 ether);
        vm.deal(unregisteredHost, 100 ether);
    }

    function _registerHost(address host) internal {
        fabToken.mint(host, MIN_STAKE);

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // ============================================================
    // Test: Host validation works via _validateHostRegistration()
    // ============================================================

    /**
     * @notice Verify registered host can create sessions
     * @dev This confirms _validateHostRegistration() works correctly
     */
    function test_RegisteredHostCanCreateSession() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            registeredHost,
            MIN_PRICE_NATIVE,
            1 hours,
            100 // proofInterval
        );

        assertGt(sessionId, 0, "Session should be created");
    }

    /**
     * @notice Verify unregistered host is rejected
     * @dev This confirms _validateHostRegistration() properly validates hosts
     */
    function test_UnregisteredHostRejected() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 0.01 ether}(unregisteredHost, MIN_PRICE_NATIVE, 1 hours, 100);
    }

    /**
     * @notice Verify zero address is rejected
     * @dev Tests edge case of zero address host
     */
    function test_ZeroAddressHostRejected() public {
        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionJob{value: 0.01 ether}(address(0), MIN_PRICE_NATIVE, 1 hours, 100);
    }

    // ============================================================
    // Test: Contract compiles and functions without dead modifier
    // ============================================================

    /**
     * @notice Verify contract is deployed and functional
     * @dev Basic sanity check that contract works
     */
    function test_ContractIsDeployedAndFunctional() public view {
        // Contract should be deployed
        assertTrue(address(marketplace) != address(0), "Marketplace deployed");
        assertTrue(address(nodeRegistry) != address(0), "NodeRegistry deployed");

        // State should be initialized
        assertEq(marketplace.feeBasisPoints(), FEE_BASIS_POINTS, "Fee configured");
    }

    /**
     * @notice Verify model session creation validates host
     * @dev Tests createSessionJobForModel path
     */
    function test_ModelSessionCreationValidatesHost() public {
        // Valid host should work
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            registeredHost, modelId, MIN_PRICE_NATIVE, 1 hours, 100
        );
        assertGt(sessionId, 0, "Model session created");

        // Invalid host should fail
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            unregisteredHost, modelId, MIN_PRICE_NATIVE, 1 hours, 100
        );
    }
}
