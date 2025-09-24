// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract InlineDepositTrackingTest is Test {
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
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;
    address public actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

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
            FEE_BASIS_POINTS
        );

        vm.stopPrank();

        // Set proof system from treasury
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));

        // Setup mock USDC at the actual address
        vm.etch(actualUsdcAddress, address(usdcToken).code);
    }

    function test_CreateSessionJobTracksNativeDeposit() public {
        // Test that createSessionJob tracks deposit in userDepositsNative
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Check initial balance is 0
        uint256 initialBalance = marketplace.userDepositsNative(user);
        assertEq(initialBalance, 0, "Initial balance should be 0");

        // Create session with inline payment
        marketplace.createSessionJob{value: 0.1 ether}(
            host,
            0.0001 ether,
            3600,
            100
        );

        // Check that deposit is tracked
        uint256 trackedDeposit = marketplace.userDepositsNative(user);
        assertEq(trackedDeposit, 0.1 ether, "Native deposit should be tracked");

        vm.stopPrank();
    }

    function test_CreateSessionJobWithTokenTracksTokenDeposit() public {
        // Test that createSessionJobWithToken tracks deposit in userDepositsToken
        ERC20Mock actualUsdc = ERC20Mock(actualUsdcAddress);

        vm.startPrank(user);
        actualUsdc.mint(user, 100e6);
        actualUsdc.approve(address(marketplace), 100e6);

        // Check initial balance is 0
        uint256 initialBalance = marketplace.userDepositsToken(user, actualUsdcAddress);
        assertEq(initialBalance, 0, "Initial USDC balance should be 0");

        // Create session with token payment
        marketplace.createSessionJobWithToken(
            host,
            actualUsdcAddress,
            1e6, // 1 USDC
            1e3,
            3600,
            100
        );

        // Check that deposit is tracked
        uint256 trackedDeposit = marketplace.userDepositsToken(user, actualUsdcAddress);
        assertEq(trackedDeposit, 1e6, "Token deposit should be tracked");

        vm.stopPrank();
    }

    function test_MultipleInlineDepositsAccumulate() public {
        // Test that multiple inline deposits accumulate correctly
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Create first session
        marketplace.createSessionJob{value: 0.1 ether}(host, 0.0001 ether, 3600, 100);
        uint256 firstBalance = marketplace.userDepositsNative(user);
        assertEq(firstBalance, 0.1 ether, "First deposit should be tracked");

        // Create second session
        marketplace.createSessionJob{value: 0.2 ether}(host, 0.0001 ether, 3600, 100);
        uint256 secondBalance = marketplace.userDepositsNative(user);
        assertEq(secondBalance, 0.3 ether, "Deposits should accumulate");

        vm.stopPrank();
    }

    function test_InlineDepositCanBeUsedForSessionFromDeposit() public {
        // Test that inline deposits can be used with createSessionFromDeposit
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Create session with inline payment (tracks deposit)
        marketplace.createSessionJob{value: 0.5 ether}(host, 0.0001 ether, 3600, 100);

        // Now use the tracked deposit to create another session
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            0.0001 ether,
            3600,
            100
        );

        // Check remaining balance
        uint256 remainingBalance = marketplace.userDepositsNative(user);
        assertEq(remainingBalance, 0.4 ether, "Should have 0.4 ether left after using 0.1");

        vm.stopPrank();
    }

    function test_GetDepositBalanceIncludesInlineDeposits() public {
        // Test that getDepositBalance includes inline deposits
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Create session with inline payment
        marketplace.createSessionJob{value: 0.3 ether}(host, 0.0001 ether, 3600, 100);

        // Check balance using getDepositBalance
        uint256 balance = marketplace.getDepositBalance(user, address(0));
        assertEq(balance, 0.3 ether, "getDepositBalance should return inline deposits");

        vm.stopPrank();
    }

    function test_CanWithdrawInlineDeposits() public {
        // Test that inline deposits can be withdrawn (if session allows)
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Create session with inline payment
        marketplace.createSessionJob{value: 0.5 ether}(host, 0.0001 ether, 3600, 100);

        // Explicitly deposit more
        marketplace.depositNative{value: 0.2 ether}();

        // Total should be 0.7 ether
        uint256 totalBalance = marketplace.userDepositsNative(user);
        assertEq(totalBalance, 0.7 ether, "Total balance should be 0.7 ether");

        // Withdraw some funds
        uint256 balanceBefore = user.balance;
        marketplace.withdrawNative(0.3 ether);
        uint256 balanceAfter = user.balance;

        assertEq(balanceAfter - balanceBefore, 0.3 ether, "Should have withdrawn 0.3 ether");
        assertEq(marketplace.userDepositsNative(user), 0.4 ether, "Should have 0.4 ether left");

        vm.stopPrank();
    }
}