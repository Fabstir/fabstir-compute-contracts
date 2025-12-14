// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title JobMarketplaceWithModelsUpgradeable Initialization Tests
 * @dev Tests initialization, re-initialization protection, and basic proxy functionality
 */
contract JobMarketplaceInitializationTest is Test {
    JobMarketplaceWithModelsUpgradeable public implementation;
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host1 = address(0x2);
    address public user1 = address(0x3);
    address public treasury = address(0x4);

    bytes32 public modelId1;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30; // 30 seconds
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        vm.prank(owner);
        modelRegistry = new ModelRegistry(address(fabToken));

        // Add approved model
        vm.prank(owner);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistryWithModels
        vm.prank(owner);
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));

        // Deploy HostEarnings
        vm.prank(owner);
        hostEarnings = new HostEarnings();

        // Deploy implementation
        implementation = new JobMarketplaceWithModelsUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(proxyAddr));

        // Authorize marketplace in HostEarnings
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Setup host with stake
        fabToken.mint(host1, 10000 * 10**18);
        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        // Setup user with ETH
        vm.deal(user1, 100 ether);
    }

    // ============================================================
    // Initialization Tests
    // ============================================================

    function test_InitializeSetsOwner() public view {
        assertEq(marketplace.owner(), owner);
    }

    function test_InitializeSetsNodeRegistry() public view {
        assertEq(address(marketplace.nodeRegistry()), address(nodeRegistry));
    }

    function test_InitializeSetsHostEarnings() public view {
        assertEq(address(marketplace.hostEarnings()), address(hostEarnings));
    }

    function test_InitializeSetsFeeBasisPoints() public view {
        assertEq(marketplace.FEE_BASIS_POINTS(), FEE_BASIS_POINTS);
    }

    function test_InitializeSetsDisputeWindow() public view {
        assertEq(marketplace.DISPUTE_WINDOW(), DISPUTE_WINDOW);
    }

    function test_InitializeSetsTreasuryToOwner() public view {
        assertEq(marketplace.treasuryAddress(), owner);
    }

    function test_InitializeSetsNextJobIdTo1() public view {
        assertEq(marketplace.nextJobId(), 1);
    }

    function test_InitializeCanOnlyBeCalledOnce() public {
        vm.expectRevert();
        marketplace.initialize(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            DISPUTE_WINDOW
        );
    }

    function test_InitializeRevertsWithZeroNodeRegistry() public {
        JobMarketplaceWithModelsUpgradeable newImpl = new JobMarketplaceWithModelsUpgradeable();

        vm.expectRevert("Invalid node registry");
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(0),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        );
    }

    function test_InitializeRevertsWithZeroHostEarnings() public {
        JobMarketplaceWithModelsUpgradeable newImpl = new JobMarketplaceWithModelsUpgradeable();

        vm.expectRevert("Invalid host earnings");
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(0)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        );
    }

    function test_InitializeRevertsWithExcessiveFee() public {
        JobMarketplaceWithModelsUpgradeable newImpl = new JobMarketplaceWithModelsUpgradeable();

        vm.expectRevert("Fee cannot exceed 100%");
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                10001, // > 10000
                DISPUTE_WINDOW
            ))
        );
    }

    function test_InitializeRevertsWithZeroDisputeWindow() public {
        JobMarketplaceWithModelsUpgradeable newImpl = new JobMarketplaceWithModelsUpgradeable();

        vm.expectRevert("Invalid dispute window");
        new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                0
            ))
        );
    }

    function test_ImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            DISPUTE_WINDOW
        );
    }

    // ============================================================
    // Session Creation Tests
    // ============================================================

    function test_CreateSessionJobWorks() public {
        vm.prank(user1);
        uint256 sessionId = marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        assertEq(sessionId, 1);
        assertEq(marketplace.nextJobId(), 2);
    }

    function test_CreateSessionJobEmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit JobMarketplaceWithModelsUpgradeable.SessionJobCreated(1, user1, host1, 0.01 ether);
        marketplace.createSessionJob{value: 0.01 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    function test_CreateSessionJobRejectsInsufficientDeposit() public {
        vm.prank(user1);
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJob{value: 0.0001 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );
    }

    // ============================================================
    // Admin Function Tests
    // ============================================================

    function test_SetTreasuryWorks() public {
        vm.prank(owner);
        marketplace.setTreasury(treasury);
        assertEq(marketplace.treasuryAddress(), treasury);
    }

    function test_SetTreasuryOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        marketplace.setTreasury(treasury);
    }

    function test_SetTreasuryRejectsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid treasury address");
        marketplace.setTreasury(address(0));
    }

    // ============================================================
    // Constants Tests
    // ============================================================

    function test_ConstantsAreCorrect() public view {
        assertEq(marketplace.MIN_DEPOSIT(), 0.0002 ether);
        assertEq(marketplace.MIN_PROVEN_TOKENS(), 100);
        assertEq(marketplace.ABANDONMENT_TIMEOUT(), 24 hours);
        assertEq(marketplace.USDC_MIN_DEPOSIT(), 800000);
        assertEq(marketplace.PRICE_PRECISION(), 1000);
    }
}
