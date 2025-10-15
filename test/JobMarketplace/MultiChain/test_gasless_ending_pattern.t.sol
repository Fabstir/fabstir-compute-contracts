// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract GaslessEndingPatternTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

    event SessionCompleted(
        uint256 indexed jobId,
        address indexed completedBy,
        uint256 tokensUsed,
        uint256 paymentAmount,
        uint256 refundAmount
    );

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
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

    function test_HostIncentivizedToCompleteForPayment() public {
        // Setup: Create session
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

        // Host completes to get their payment (even though no work was done, testing the pattern)
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify completion worked
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Host completed session");
    }

    function test_UserGetsRefundWithoutPayingGas() public {
        // Setup: User creates session
        vm.deal(user, 1 ether);
        uint256 userInitialBalance = user.balance;

        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.2 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );
        uint256 userBalanceAfterCreate = user.balance;
        vm.stopPrank();

        // Fast forward past dispute window
        vm.warp(block.timestamp + 3601);

        // Host completes session (pays gas)
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // User should receive full refund (no tokens were used) without paying any additional gas
        uint256 userFinalBalance = user.balance;
        uint256 expectedRefund = 0.2 ether;

        assertEq(userFinalBalance, userBalanceAfterCreate + expectedRefund, "User received refund without paying gas");
        assertLt(userBalanceAfterCreate, userInitialBalance, "User only paid gas for creation");
    }

    function test_EmergencyFallbackUserCanComplete() public {
        // Setup: Create session
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );
        vm.stopPrank();

        // Simulate host being offline/unresponsive
        // User can still complete as emergency fallback (pays gas themselves)
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify completion
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "User completed as fallback");
    }

    function test_CompletionEventShowsWhoPaidGas() public {
        // Setup: Create session
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

        // Random third party completes (simulating automated service)
        address automatedService = address(999);

        // We expect event to show who completed it (no tokens used, full refund)
        vm.expectEmit(true, true, false, false);
        emit SessionCompleted(sessionId, automatedService, 0, 0, 0.1 ether);

        vm.prank(automatedService);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");
    }

    function test_NoIncentiveForUsersToAvoidPayment() public {
        // Setup: Create session
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.3 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );
        vm.stopPrank();

        // User disconnects/closes browser thinking they can avoid payment
        // But host can still complete!
        vm.warp(block.timestamp + 3601);

        // Host completes and session settles (even without proof, testing the pattern)
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "ipfs://conversation");

        // Verify session was completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), 1, "Host completed despite user disconnect");
    }
}