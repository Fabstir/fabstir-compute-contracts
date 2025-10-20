// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract DepositTokenTest is Test {
    JobMarketplaceWithModels marketplace;
    MockToken token;

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

        // Deploy mock token and distribute to test accounts
        token = new MockToken();
        token.transfer(ALICE, 100 * 10**18);
        token.transfer(BOB, 100 * 10**18);
    }

    function test_DepositTokenUpdatesBalance() public {
        vm.startPrank(ALICE);
        token.approve(address(marketplace), 10 * 10**18);
        marketplace.depositToken(address(token), 10 * 10**18);
        vm.stopPrank();

        uint256 balance = marketplace.userDepositsToken(ALICE, address(token));
        assertEq(balance, 10 * 10**18, "Token balance should be 10 tokens");
    }

    function test_DepositTokenEmitsEvent() public {
        vm.startPrank(ALICE);
        token.approve(address(marketplace), 5 * 10**18);

        vm.expectEmit(true, false, false, true);
        emit DepositReceived(ALICE, 5 * 10**18, address(token));

        marketplace.depositToken(address(token), 5 * 10**18);
        vm.stopPrank();
    }

    function test_DepositTokenTransfersFromUser() public {
        uint256 initialUserBalance = token.balanceOf(ALICE);
        uint256 initialContractBalance = token.balanceOf(address(marketplace));

        vm.startPrank(ALICE);
        token.approve(address(marketplace), 15 * 10**18);
        marketplace.depositToken(address(token), 15 * 10**18);
        vm.stopPrank();

        assertEq(token.balanceOf(ALICE), initialUserBalance - 15 * 10**18);
        assertEq(token.balanceOf(address(marketplace)), initialContractBalance + 15 * 10**18);
    }

    function test_MultipleTokenDeposits() public {
        MockToken token2 = new MockToken();
        token2.transfer(ALICE, 50 * 10**18);

        vm.startPrank(ALICE);
        token.approve(address(marketplace), 20 * 10**18);
        marketplace.depositToken(address(token), 20 * 10**18);

        token2.approve(address(marketplace), 30 * 10**18);
        marketplace.depositToken(address(token2), 30 * 10**18);
        vm.stopPrank();

        assertEq(marketplace.userDepositsToken(ALICE, address(token)), 20 * 10**18);
        assertEq(marketplace.userDepositsToken(ALICE, address(token2)), 30 * 10**18);
    }
}