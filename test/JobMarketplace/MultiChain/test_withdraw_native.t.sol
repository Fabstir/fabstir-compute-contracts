// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

contract WithdrawNativeTest is Test {
    JobMarketplaceWithModels marketplace;

    address constant ALICE = address(0x1111);
    address constant BOB = address(0x2222);

    event WithdrawalProcessed(address indexed depositor, uint256 amount, address token);

    function setUp() public {
        // Deploy marketplace with required dependencies
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000, // 10% fee
            30
        );

        // Fund test accounts and make deposits
        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);

        vm.prank(ALICE);
        marketplace.depositNative{value: 5 ether}();

        vm.prank(BOB);
        marketplace.depositNative{value: 3 ether}();
    }

    function test_WithdrawNativeReducesBalance() public {
        uint256 initialBalance = marketplace.userDepositsNative(ALICE);

        vm.prank(ALICE);
        marketplace.withdrawNative(2 ether);

        uint256 finalBalance = marketplace.userDepositsNative(ALICE);
        assertEq(finalBalance, initialBalance - 2 ether);
    }

    function test_WithdrawNativeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit WithdrawalProcessed(ALICE, 1 ether, address(0));

        vm.prank(ALICE);
        marketplace.withdrawNative(1 ether);
    }

    function test_WithdrawNativeTransfersETH() public {
        uint256 initialETH = ALICE.balance;

        vm.prank(ALICE);
        marketplace.withdrawNative(2 ether);

        assertEq(ALICE.balance, initialETH + 2 ether);
    }

    function test_WithdrawFullBalance() public {
        vm.prank(ALICE);
        marketplace.withdrawNative(5 ether);

        assertEq(marketplace.userDepositsNative(ALICE), 0);
        assertEq(ALICE.balance, 10 ether); // Original 5 + withdrawn 5
    }

    function test_RevertOnInsufficientBalance() public {
        vm.expectRevert("Insufficient balance");

        vm.prank(ALICE);
        marketplace.withdrawNative(6 ether); // Has only 5
    }

    function test_MultipleWithdrawals() public {
        vm.startPrank(ALICE);
        marketplace.withdrawNative(1 ether);
        marketplace.withdrawNative(1.5 ether);
        marketplace.withdrawNative(0.5 ether);
        vm.stopPrank();

        assertEq(marketplace.userDepositsNative(ALICE), 2 ether); // 5 - 3
    }
}