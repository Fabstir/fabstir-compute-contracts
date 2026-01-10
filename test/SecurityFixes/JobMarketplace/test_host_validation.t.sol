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
 * @title Host Validation Security Tests
 * @dev Tests for Sub-phase 2.1: Proper _validateHostRegistration
 *
 * Issue: _validateHostRegistration() only checks for non-zero address,
 * allowing any address as host. This enables:
 * - Fake hosts to receive payments
 * - Bypassing staking requirements
 * - Potential fund redirection
 */
contract HostValidationTest is Test {
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

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry as proxy
        vm.startPrank(owner);
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

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

        // Deploy JobMarketplace as proxy
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                feeBasisPoints,
                disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        vm.stopPrank();

        // Register the "registeredHost" in NodeRegistry
        fabToken.mint(registeredHost, 10000 * 10**18);
        vm.prank(registeredHost);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.prank(registeredHost);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.registered-host.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        // Setup user with ETH
        vm.deal(user, 100 ether);

        // Setup user with USDC
        usdcToken.mint(user, 1000 * 10**6);
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // Add mock USDC to accepted tokens
        vm.prank(owner);
        marketplace.addAcceptedToken(address(usdcToken), 500000, 1_000_000 * 10**6); // $0.50 min, $1M max
    }

    // ============================================================
    // Zero Address Validation Tests
    // ============================================================

    function test_ZeroAddressFailsValidation() public {
        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionJob{value: 0.01 ether}(
            address(0),
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_ZeroAddressFailsValidationWithToken() public {
        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionJobWithToken(
            address(0),
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );
    }

    // ============================================================
    // Unregistered Host Validation Tests
    // ============================================================

    function test_UnregisteredHostFailsValidation() public {
        // unregisteredHost is not registered in NodeRegistry
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 0.01 ether}(
            unregisteredHost,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_UnregisteredHostFailsValidationWithToken() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobWithToken(
            unregisteredHost,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );
    }

    function test_UnregisteredHostFailsValidationForModel() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            unregisteredHost,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_UnregisteredHostFailsValidationForModelWithToken() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModelWithToken(
            unregisteredHost,
            modelId,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );
    }

    // ============================================================
    // Inactive Host Validation Tests
    // ============================================================

    function test_InactiveHostFailsValidation() public {
        // First verify the host is currently active
        assertTrue(nodeRegistry.isActiveNode(registeredHost));

        // Mock getNodeFullInfo to return inactive host (operator set, active = false)
        // This simulates a future "deactivate" feature for defense-in-depth testing
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(NodeRegistryWithModelsUpgradeable.getNodeFullInfo.selector, registeredHost),
            abi.encode(
                registeredHost,  // operator (non-zero = registered)
                MIN_STAKE,       // stakedAmount
                false,           // active = FALSE
                '{"hardware": "GPU"}',
                "https://api.registered-host.com",
                new bytes32[](0),
                MIN_PRICE_NATIVE,
                MIN_PRICE_STABLE
            )
        );

        // Now try to create session - should fail
        vm.prank(user);
        vm.expectRevert("Host not active");
        marketplace.createSessionJob{value: 0.01 ether}(
            registeredHost,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_InactiveHostFailsValidationWithToken() public {
        // Mock getNodeFullInfo to return inactive host
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(NodeRegistryWithModelsUpgradeable.getNodeFullInfo.selector, registeredHost),
            abi.encode(
                registeredHost, MIN_STAKE, false, '{}', "", new bytes32[](0), MIN_PRICE_NATIVE, MIN_PRICE_STABLE
            )
        );

        vm.prank(user);
        vm.expectRevert("Host not active");
        marketplace.createSessionJobWithToken(
            registeredHost,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );
    }

    // ============================================================
    // Registered Active Host Passes Validation Tests
    // ============================================================

    function test_RegisteredActiveHostPassesValidation() public {
        // Verify host is registered and active
        assertTrue(nodeRegistry.isActiveNode(registeredHost));

        // Should succeed
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            registeredHost,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        assertEq(sessionId, 1);
    }

    function test_RegisteredActiveHostPassesValidationWithToken() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            registeredHost,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        assertEq(sessionId, 1);
    }

    function test_RegisteredActiveHostPassesValidationForModel() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            registeredHost,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        assertEq(sessionId, 1);
    }

    function test_RegisteredActiveHostPassesValidationForModelWithToken() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            registeredHost,
            modelId,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        assertEq(sessionId, 1);
    }

    // ============================================================
    // Previously Registered Then Unregistered Host Tests
    // ============================================================

    function test_UnregisteredAfterRegistrationFailsValidation() public {
        // Create a new host, register, then unregister
        address tempHost = address(0x999);
        fabToken.mint(tempHost, 10000 * 10**18);

        vm.prank(tempHost);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.prank(tempHost);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.temp-host.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        // Verify registered
        assertTrue(nodeRegistry.isActiveNode(tempHost));

        // Unregister
        vm.prank(tempHost);
        nodeRegistry.unregisterNode();

        // Verify unregistered
        assertFalse(nodeRegistry.isActiveNode(tempHost));

        // Now try to create session - should fail
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: 0.01 ether}(
            tempHost,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

}
