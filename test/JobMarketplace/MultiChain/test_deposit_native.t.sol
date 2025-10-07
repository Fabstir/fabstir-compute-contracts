// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

contract DepositNativeTest is Test {
    JobMarketplaceWithModels marketplace;

    address constant ALICE = address(0x1111);
    address constant BOB = address(0x2222);

    event DepositReceived(address indexed depositor, uint256 amount, address token);

    function setUp() public {
        // Deploy marketplace with required dependencies
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000 // 10% fee,
                    30);

        // Fund test accounts
        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    function test_DepositNativeAddsToBalance() public {
        vm.prank(ALICE);
        marketplace.depositNative{value: 1 ether}();

        uint256 balance = marketplace.userDepositsNative(ALICE);
        assertEq(balance, 1 ether, "Balance should be 1 ether");
    }

    function test_DepositNativeEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit DepositReceived(ALICE, 1 ether, address(0));

        vm.prank(ALICE);
        marketplace.depositNative{value: 1 ether}();
    }

    function test_MultipleDepositsAccumulate() public {
        vm.startPrank(ALICE);
        marketplace.depositNative{value: 0.5 ether}();
        marketplace.depositNative{value: 0.3 ether}();
        marketplace.depositNative{value: 0.2 ether}();
        vm.stopPrank();

        uint256 balance = marketplace.userDepositsNative(ALICE);
        assertEq(balance, 1 ether, "Balance should accumulate to 1 ether");
    }

    function test_DifferentUsersHaveSeparateBalances() public {
        vm.prank(ALICE);
        marketplace.depositNative{value: 2 ether}();

        vm.prank(BOB);
        marketplace.depositNative{value: 3 ether}();

        assertEq(marketplace.userDepositsNative(ALICE), 2 ether);
        assertEq(marketplace.userDepositsNative(BOB), 3 ether);
    }

    function test_ContractBalanceIncreasesWithDeposit() public {
        uint256 initialBalance = address(marketplace).balance;

        vm.prank(ALICE);
        marketplace.depositNative{value: 1.5 ether}();

        assertEq(address(marketplace).balance, initialBalance + 1.5 ether);
    }
}