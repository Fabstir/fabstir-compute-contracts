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
 * @title Host Validation All Paths Security Tests
 * @dev Tests for Sub-phase 2.2: Ensure all session creation paths validate host
 *
 * Verifies that _validateHostRegistration is called in:
 * 1. createSessionJobForModel
 * 2. createSessionJobForModelWithToken
 * 3. createSessionFromDepositForModel
 *
 * Also verifies validation happens BEFORE any state changes.
 */
contract HostValidationAllPathsTest is Test {
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

        // Add mock USDC to accepted tokens
        marketplace.addAcceptedToken(address(usdcToken), 500000, 1_000_000 * 10**6);
        vm.stopPrank();

        // Register the host in NodeRegistry
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
        vm.prank(registeredHost);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        vm.prank(registeredHost);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);

        // Setup user with ETH
        vm.deal(user, 100 ether);

        // Setup user with USDC
        usdcToken.mint(user, 1000 * 10**6);
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    // ============================================================
    // Path 1: createSessionJobForModel
    // ============================================================

    function test_CreateSessionJobForModel_ValidatesHost() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            unregisteredHost,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );
    }

    function test_CreateSessionJobForModel_SucceedsWithRegisteredHost() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 0.01 ether}(
            registeredHost,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );
        assertEq(sessionId, 1);
    }

    function test_CreateSessionJobForModel_NoStateChangeOnRevert() public {
        uint256 nextJobIdBefore = marketplace.nextJobId();

        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModel{value: 0.01 ether}(
            unregisteredHost,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Verify no state change
        assertEq(marketplace.nextJobId(), nextJobIdBefore);
    }

    // ============================================================
    // Path 2: createSessionJobForModelWithToken
    // ============================================================

    function test_CreateSessionJobForModelWithToken_ValidatesHost() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModelWithToken(
            unregisteredHost,
            modelId,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );
    }

    function test_CreateSessionJobForModelWithToken_SucceedsWithRegisteredHost() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            registeredHost,
            modelId,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );
        assertEq(sessionId, 1);
    }

    function test_CreateSessionJobForModelWithToken_NoTokenTransferOnRevert() public {
        uint256 userBalanceBefore = usdcToken.balanceOf(user);

        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModelWithToken(
            unregisteredHost,
            modelId,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );

        // Verify no token transfer occurred
        assertEq(usdcToken.balanceOf(user), userBalanceBefore);
    }

    // ============================================================
    // Path 3: createSessionFromDepositForModel
    // ============================================================

    function test_CreateSessionFromDepositForModel_ValidatesHostNative() public {
        // First deposit some ETH
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();

        // Try to create session with unregistered host
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionFromDepositForModel(
            modelId,
            unregisteredHost,
            address(0), // native token
            0.01 ether,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );
    }

    function test_CreateSessionFromDepositForModel_ValidatesHostToken() public {
        // First deposit some USDC
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        vm.prank(user);
        marketplace.depositToken(address(usdcToken), 10 * 10**6);

        // Try to create session with unregistered host
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionFromDepositForModel(
            modelId,
            unregisteredHost,
            address(usdcToken),
            1 * 10**6,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );
    }

    function test_CreateSessionFromDepositForModel_SucceedsWithRegisteredHost() public {
        // First deposit some ETH
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();

        // Create session with registered host
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId,
            registeredHost,
            address(0),
            0.01 ether,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );
        assertEq(sessionId, 1);
    }

    function test_CreateSessionFromDepositForModel_NoBalanceChangeOnRevert() public {
        // First deposit some ETH
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();

        uint256 depositBefore = marketplace.userDepositsNative(user);

        // Try to create session with unregistered host
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionFromDepositForModel(
            modelId,
            unregisteredHost,
            address(0),
            0.01 ether,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Verify no balance change
        assertEq(marketplace.userDepositsNative(user), depositBefore);
    }

    // ============================================================
    // Comprehensive All-Paths Test
    // ============================================================

    function test_AllPaths_UnregisteredHostRevertsWithCorrectError() public {
        // Path 1: createSessionJobForModel
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModel{value: 0.01 ether}(unregisteredHost, modelId, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Path 2: createSessionJobForModelWithToken
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModelWithToken(unregisteredHost, modelId, address(usdcToken), 1 * 10**6, MIN_PRICE_STABLE, 1 days, 1000, 300);

        // Path 3: createSessionFromDepositForModel (need to deposit first)
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionFromDepositForModel(modelId, unregisteredHost, address(0), 0.01 ether, MIN_PRICE_NATIVE, 1 days, 1000, 300);
    }

    function test_AllPaths_RegisteredHostSucceeds() public {
        // Path 1
        vm.prank(user);
        assertEq(marketplace.createSessionJobForModel{value: 0.01 ether}(registeredHost, modelId, MIN_PRICE_NATIVE, 1 days, 1000, 300), 1);

        // Path 2
        vm.prank(user);
        assertEq(marketplace.createSessionJobForModelWithToken(registeredHost, modelId, address(usdcToken), 1 * 10**6, MIN_PRICE_STABLE, 1 days, 1000, 300), 2);

        // Path 3
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();
        vm.prank(user);
        assertEq(marketplace.createSessionFromDepositForModel(modelId, registeredHost, address(0), 0.01 ether, MIN_PRICE_NATIVE, 1 days, 1000, 300), 3);
    }

    // ============================================================
    // Inactive Host Tests (using mock)
    // ============================================================

    function test_AllPaths_InactiveHostRevertsWithCorrectError() public {
        // Mock getNodeFullInfo to return inactive host
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(NodeRegistryWithModelsUpgradeable.getNodeFullInfo.selector, registeredHost),
            abi.encode(
                registeredHost, MIN_STAKE, false, '{}', "", new bytes32[](0), MIN_PRICE_NATIVE, MIN_PRICE_STABLE
            )
        );

        // Path 1
        vm.prank(user);
        vm.expectRevert("Host not active");
        marketplace.createSessionJobForModel{value: 0.01 ether}(registeredHost, modelId, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Path 2
        vm.prank(user);
        vm.expectRevert("Host not active");
        marketplace.createSessionJobForModelWithToken(registeredHost, modelId, address(usdcToken), 1 * 10**6, MIN_PRICE_STABLE, 1 days, 1000, 300);

        // Clear mock for deposit
        vm.clearMockedCalls();

        // Deposit first (without mock)
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();

        // Re-apply mock
        vm.mockCall(
            address(nodeRegistry),
            abi.encodeWithSelector(NodeRegistryWithModelsUpgradeable.getNodeFullInfo.selector, registeredHost),
            abi.encode(
                registeredHost, MIN_STAKE, false, '{}', "", new bytes32[](0), MIN_PRICE_NATIVE, MIN_PRICE_STABLE
            )
        );

        // Path 3
        vm.prank(user);
        vm.expectRevert("Host not active");
        marketplace.createSessionFromDepositForModel(modelId, registeredHost, address(0), 0.01 ether, MIN_PRICE_NATIVE, 1 days, 1000, 300);
    }
}
