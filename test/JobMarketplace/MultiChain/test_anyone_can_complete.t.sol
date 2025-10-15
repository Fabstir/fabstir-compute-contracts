// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract AnyoneCanCompleteTest is Test {
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
    address public randomUser = address(4);
    address public automatedService = address(5);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

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

    function test_RandomUserCanCompleteSession() public {
        // Setup: Create an active session
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

        // Random user (not host or requester) completes the session
        vm.prank(randomUser);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify session was completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Session should be completed"); // 1 = Completed
    }

    function test_AutomatedServiceCanCompleteSession() public {
        // Setup: Create an active session
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

        // Automated service completes the session (simulating host node automation)
        vm.prank(automatedService);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify session was completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Session should be completed");
    }

    function test_HostCanStillCompleteOwnSession() public {
        // Setup: Create an active session
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

        // Host completes their own session (traditional path)
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify session was completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Session should be completed");
    }

    function test_UserCanStillCompleteOwnSession() public {
        // Setup: Create an active session
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );

        // User completes their own session immediately (no dispute window for requester)
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify session was completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Session should be completed");

        vm.stopPrank();
    }

    function test_PaymentsDistributeCorrectlyWhenRandomUserCompletes() public {
        // Setup: Create an active session (no proof submission needed for this test)
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.5 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );
        vm.stopPrank();

        // Fast forward past dispute window
        vm.warp(block.timestamp + 3601);

        uint256 userBalanceBefore = user.balance;

        // Random user completes - they should NOT receive any payment
        uint256 randomUserBalanceBefore = randomUser.balance;
        vm.prank(randomUser);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");
        uint256 randomUserBalanceAfter = randomUser.balance;

        // Verify random user got nothing
        assertEq(randomUserBalanceAfter, randomUserBalanceBefore, "Random user should not receive payment");

        // User should get full refund since no tokens were used
        assertEq(user.balance, userBalanceBefore + 0.5 ether, "User should receive full refund");
    }

    function test_DisputeWindowStillEnforcedForNonRequesterCallers() public {
        // Setup: Create an active session
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );
        vm.stopPrank();

        // Random user tries to complete immediately (should fail if dispute window enforced)
        vm.prank(randomUser);
        vm.expectRevert("Must wait dispute window");
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Host also needs to wait
        vm.prank(host);
        vm.expectRevert("Must wait dispute window");
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // But requester can complete immediately
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify it worked for requester
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Session should be completed");
    }
}