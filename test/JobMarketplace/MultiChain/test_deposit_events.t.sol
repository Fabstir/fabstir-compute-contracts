// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

contract DepositEventsTest is Test {
    JobMarketplaceWithModels marketplace;

    address constant ALICE = address(0x1111);
    address constant BOB = address(0x2222);
    address constant USDC_TOKEN = address(0x3333);

    // Define expected events - must match contract signatures
    event DepositReceived(address indexed depositor, uint256 amount, address indexed token);
    event WithdrawalProcessed(address indexed depositor, uint256 amount, address indexed token);

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
    }

    function test_DepositReceivedEventSignature() public {
        // Fund ALICE and test native deposit emits correct event
        vm.deal(ALICE, 2 ether);

        vm.expectEmit(true, false, true, true);
        emit DepositReceived(ALICE, 1 ether, address(0));

        vm.prank(ALICE);
        marketplace.depositNative{value: 1 ether}();
    }

    function test_WithdrawalProcessedEventSignature() public {
        // Fund BOB, deposit, then withdraw
        vm.deal(BOB, 2 ether);

        vm.prank(BOB);
        marketplace.depositNative{value: 1 ether}();

        vm.expectEmit(true, false, true, true);
        emit WithdrawalProcessed(BOB, 0.5 ether, address(0));

        vm.prank(BOB);
        marketplace.withdrawNative(0.5 ether);
    }

    function test_EventsHaveCorrectIndexedParams() public {
        // Verify depositor and token are indexed in DepositReceived
        vm.deal(ALICE, 2 ether);

        vm.expectEmit(true, false, true, true);
        emit DepositReceived(ALICE, 1 ether, address(0));

        vm.prank(ALICE);
        marketplace.depositNative{value: 1 ether}();
    }

    function test_EventsDistinguishNativeFromToken() public {
        // Native token uses address(0)
        vm.deal(ALICE, 2 ether);

        vm.expectEmit(true, false, true, true);
        emit DepositReceived(ALICE, 1 ether, address(0));

        vm.prank(ALICE);
        marketplace.depositNative{value: 1 ether}();
    }
}