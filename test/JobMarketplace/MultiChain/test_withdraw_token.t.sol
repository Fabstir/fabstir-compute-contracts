// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokenWithdraw is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract WithdrawTokenTest is Test {
    JobMarketplaceWithModels marketplace;
    MockTokenWithdraw token;

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
            1000 // 10% fee
        );

        // Deploy mock token and distribute
        token = new MockTokenWithdraw();
        token.transfer(ALICE, 100 * 10**18);
        token.transfer(BOB, 50 * 10**18);

        // Make token deposits
        vm.startPrank(ALICE);
        token.approve(address(marketplace), 60 * 10**18);
        marketplace.depositToken(address(token), 60 * 10**18);
        vm.stopPrank();

        vm.startPrank(BOB);
        token.approve(address(marketplace), 30 * 10**18);
        marketplace.depositToken(address(token), 30 * 10**18);
        vm.stopPrank();
    }

    function test_WithdrawTokenReducesBalance() public {
        uint256 initialBalance = marketplace.userDepositsToken(ALICE, address(token));

        vm.prank(ALICE);
        marketplace.withdrawToken(address(token), 20 * 10**18);

        uint256 finalBalance = marketplace.userDepositsToken(ALICE, address(token));
        assertEq(finalBalance, initialBalance - 20 * 10**18);
    }

    function test_WithdrawTokenEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit WithdrawalProcessed(ALICE, 15 * 10**18, address(token));

        vm.prank(ALICE);
        marketplace.withdrawToken(address(token), 15 * 10**18);
    }

    function test_WithdrawTokenTransfersTokens() public {
        uint256 initialTokens = token.balanceOf(ALICE);

        vm.prank(ALICE);
        marketplace.withdrawToken(address(token), 25 * 10**18);

        assertEq(token.balanceOf(ALICE), initialTokens + 25 * 10**18);
    }

    function test_WithdrawFullTokenBalance() public {
        vm.prank(ALICE);
        marketplace.withdrawToken(address(token), 60 * 10**18);

        assertEq(marketplace.userDepositsToken(ALICE, address(token)), 0);
        assertEq(token.balanceOf(ALICE), 100 * 10**18); // Original balance restored
    }

    function test_RevertOnInsufficientTokenBalance() public {
        vm.expectRevert("Insufficient balance");

        vm.prank(ALICE);
        marketplace.withdrawToken(address(token), 70 * 10**18); // Has only 60
    }
}