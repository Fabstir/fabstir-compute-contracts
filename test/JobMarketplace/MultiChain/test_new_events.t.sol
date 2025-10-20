// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract NewEventsTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public randomCaller = address(4);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

    // Event definitions for testing
    event SessionCreatedByDepositor(
        uint256 indexed sessionId,
        address indexed depositor,
        address indexed host,
        uint256 deposit
    );

    event SessionCompleted(
        uint256 indexed jobId,
        address indexed completedBy,
        uint256 tokensUsed,
        uint256 paymentAmount,
        uint256 refundAmount
    );

    event DepositReceived(
        address indexed depositor,
        uint256 amount,
        address indexed token
    );

    event WithdrawalProcessed(
        address indexed depositor,
        uint256 amount,
        address indexed token
    );

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC Token", "USDC");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));
        proofSystem = new ProofSystem();
        hostEarnings = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            30);

        vm.stopPrank();

        // Set proof system from treasury
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
    }

    function test_SessionCreatedByDepositorEvent() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Expect the SessionCreatedByDepositor event
        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDepositor(1, user, host, 0.1 ether);

        marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );

        vm.stopPrank();
    }

    function test_SessionCompletedWithCompletedByEvent() public {
        // Create session
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );
        vm.stopPrank();

        // Fast forward past dispute window
        vm.warp(block.timestamp + 3601);

        // Expect new SessionCompleted event with completedBy
        vm.expectEmit(true, true, false, false);
        emit SessionCompleted(sessionId, randomCaller, 0, 0, 0.1 ether);

        // Random caller completes
        vm.prank(randomCaller);
        marketplace.completeSessionJob(sessionId, "ipfs://cid");
    }

    function test_DepositReceivedEventForNative() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Expect DepositReceived event for native token
        vm.expectEmit(true, false, true, true);
        emit DepositReceived(user, 0.5 ether, address(0));

        marketplace.depositNative{value: 0.5 ether}();

        vm.stopPrank();
    }

    function test_DepositReceivedEventForToken() public {
        address actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        vm.etch(actualUsdcAddress, address(usdcToken).code);
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        vm.startPrank(user);
        actualUsdc.mint(user, 1000e6);
        actualUsdc.approve(address(marketplace), 1000e6);

        // Expect DepositReceived event for token
        vm.expectEmit(true, false, true, true);
        emit DepositReceived(user, 100e6, actualUsdcAddress);

        marketplace.depositToken(actualUsdcAddress, 100e6);

        vm.stopPrank();
    }

    function test_WithdrawalProcessedEventForNative() public {
        // First deposit
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        marketplace.depositNative{value: 0.5 ether}();

        // Expect WithdrawalProcessed event for native
        vm.expectEmit(true, false, true, true);
        emit WithdrawalProcessed(user, 0.3 ether, address(0));

        marketplace.withdrawNative(0.3 ether);

        vm.stopPrank();
    }

    function test_WithdrawalProcessedEventForToken() public {
        address actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        vm.etch(actualUsdcAddress, address(usdcToken).code);
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        vm.startPrank(user);
        actualUsdc.mint(user, 1000e6);
        actualUsdc.approve(address(marketplace), 1000e6);
        marketplace.depositToken(actualUsdcAddress, 100e6);

        // Expect WithdrawalProcessed event for token
        vm.expectEmit(true, false, true, true);
        emit WithdrawalProcessed(user, 50e6, actualUsdcAddress);

        marketplace.withdrawToken(actualUsdcAddress, 50e6);

        vm.stopPrank();
    }
}