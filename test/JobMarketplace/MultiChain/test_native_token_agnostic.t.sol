// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract TestNativeTokenAgnostic is Test {
    JobMarketplaceWithModels public marketplace;
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    event DepositReceived(address indexed depositor, uint256 amount, address indexed token);
    event WithdrawalProcessed(address indexed depositor, uint256 amount, address indexed token);

    function setUp() public {
        // Deploy marketplace
        ERC20Mock fabToken = new ERC20Mock("FAB", "FAB");
        ERC20Mock govToken = new ERC20Mock("GOV", "GOV");
        ModelRegistry modelReg = new ModelRegistry(address(govToken));
        NodeRegistryWithModels nodeReg = new NodeRegistryWithModels(address(fabToken), address(modelReg));
        ProofSystem proofSys = new ProofSystem();
        HostEarnings hostEarn = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeReg),
            payable(address(hostEarn)),
            1000, // 10% fee
            30
        );

        hostEarn.setAuthorizedCaller(address(marketplace), true);

        // Fund users
        vm.deal(alice, 50 ether);
        vm.deal(bob, 50 ether);
    }

    function test_DepositNativeFunctionNameAgnostic() public {
        // Same function name regardless of chain
        vm.prank(alice);
        marketplace.depositNative{value: 2 ether}();

        assertEq(marketplace.userDepositsNative(alice), 2 ether);
    }

    function test_WithdrawNativeFunctionNameAgnostic() public {
        // Deposit first
        vm.prank(bob);
        marketplace.depositNative{value: 5 ether}();

        // Same withdraw function name regardless of chain
        vm.prank(bob);
        marketplace.withdrawNative(2 ether);

        assertEq(marketplace.userDepositsNative(bob), 3 ether);
    }

    function test_BalanceTrackingChainAgnostic() public {
        // Multiple users can deposit/withdraw using same mapping
        vm.prank(alice);
        marketplace.depositNative{value: 1 ether}();

        vm.prank(bob);
        marketplace.depositNative{value: 3 ether}();

        // Balances tracked independently
        assertEq(marketplace.userDepositsNative(alice), 1 ether);
        assertEq(marketplace.userDepositsNative(bob), 3 ether);

        // Withdrawals don't affect other users
        vm.prank(alice);
        marketplace.withdrawNative(0.5 ether);

        assertEq(marketplace.userDepositsNative(alice), 0.5 ether);
        assertEq(marketplace.userDepositsNative(bob), 3 ether);
    }

    function test_EventsUseAddressZeroForNative() public {
        // Test deposit event uses address(0) for native token
        vm.expectEmit(true, false, false, true);
        emit DepositReceived(alice, 1 ether, address(0));

        vm.prank(alice);
        marketplace.depositNative{value: 1 ether}();

        // Test withdrawal event uses address(0) for native token
        vm.expectEmit(true, false, false, true);
        emit WithdrawalProcessed(alice, 0.5 ether, address(0));

        vm.prank(alice);
        marketplace.withdrawNative(0.5 ether);
    }

    function test_NativeTokenWorksWithoutChainConfig() public {
        // Deploy fresh marketplace without chain config
        ERC20Mock fabToken = new ERC20Mock("FAB", "FAB");
        ERC20Mock govToken = new ERC20Mock("GOV", "GOV");
        ModelRegistry modelReg = new ModelRegistry(address(govToken));
        NodeRegistryWithModels nodeReg = new NodeRegistryWithModels(address(fabToken), address(modelReg));
        HostEarnings hostEarn = new HostEarnings();

        JobMarketplaceWithModels freshMarketplace = new JobMarketplaceWithModels(
            address(nodeReg),
            payable(address(hostEarn)),
            1000,
            30
        );

        // Native functions work even without chain config
        vm.prank(alice);
        freshMarketplace.depositNative{value: 1 ether}();

        assertEq(freshMarketplace.userDepositsNative(alice), 1 ether);
    }
}