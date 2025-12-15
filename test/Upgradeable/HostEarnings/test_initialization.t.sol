// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title HostEarningsUpgradeable Initialization Tests
 * @dev Tests initialization, re-initialization protection, and basic proxy functionality
 */
contract HostEarningsInitializationTest is Test {
    HostEarningsUpgradeable public implementation;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public usdc;

    address public owner = address(0x1);
    address public host1 = address(0x2);
    address public host2 = address(0x3);
    address public authorizedCaller = address(0x4);

    function setUp() public {
        // Deploy mock USDC
        usdc = new ERC20Mock("USD Coin", "USDC");

        // Deploy implementation
        implementation = new HostEarningsUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(proxyAddr));

        // Authorize a caller
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(authorizedCaller, true);

        // Fund the contract with ETH and tokens
        vm.deal(address(hostEarnings), 100 ether);
        usdc.mint(address(hostEarnings), 10000 * 10**18);
    }

    // ============================================================
    // Initialization Tests
    // ============================================================

    function test_InitializeSetsOwner() public view {
        assertEq(hostEarnings.owner(), owner);
    }

    function test_InitializeCanOnlyBeCalledOnce() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        hostEarnings.initialize();
    }

    function test_ImplementationCannotBeInitialized() public {
        // Try to initialize implementation directly - should revert
        vm.expectRevert();
        implementation.initialize();
    }

    // ============================================================
    // Authorization Tests
    // ============================================================

    function test_SetAuthorizedCallerWorks() public {
        address newCaller = address(0x100);

        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(newCaller, true);

        assertTrue(hostEarnings.authorizedCallers(newCaller));
    }

    function test_SetAuthorizedCallerOnlyOwner() public {
        vm.prank(host1);
        vm.expectRevert();
        hostEarnings.setAuthorizedCaller(address(0x100), true);
    }

    function test_SetAuthorizedCallerRejectsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid caller address");
        hostEarnings.setAuthorizedCaller(address(0), true);
    }

    function test_RevokeAuthorizedCaller() public {
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(authorizedCaller, false);

        assertFalse(hostEarnings.authorizedCallers(authorizedCaller));
    }

    // ============================================================
    // Credit Earnings Tests
    // ============================================================

    function test_CreditEarningsWorks() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1 ether, address(0));

        assertEq(hostEarnings.getBalance(host1, address(0)), 1 ether);
    }

    function test_CreditEarningsOnlyAuthorized() public {
        vm.prank(host1);
        vm.expectRevert("Not authorized to credit earnings");
        hostEarnings.creditEarnings(host1, 1 ether, address(0));
    }

    function test_CreditEarningsRejectsZeroHost() public {
        vm.prank(authorizedCaller);
        vm.expectRevert("Invalid host address");
        hostEarnings.creditEarnings(address(0), 1 ether, address(0));
    }

    function test_CreditEarningsRejectsZeroAmount() public {
        vm.prank(authorizedCaller);
        vm.expectRevert("Amount must be positive");
        hostEarnings.creditEarnings(host1, 0, address(0));
    }

    function test_CreditEarningsAccumulates() public {
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1 ether, address(0));
        hostEarnings.creditEarnings(host1, 2 ether, address(0));
        vm.stopPrank();

        assertEq(hostEarnings.getBalance(host1, address(0)), 3 ether);
    }

    function test_CreditEarningsUpdatesTotal() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));

        assertEq(hostEarnings.totalAccumulated(address(0)), 5 ether);
    }

    function test_CreditEarningsWithToken() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));

        assertEq(hostEarnings.getBalance(host1, address(usdc)), 1000 * 10**18);
    }

    // ============================================================
    // Withdrawal Tests
    // ============================================================

    function test_WithdrawETHWorks() public {
        // Credit some earnings
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));

        uint256 balanceBefore = host1.balance;

        vm.prank(host1);
        hostEarnings.withdraw(2 ether, address(0));

        assertEq(host1.balance, balanceBefore + 2 ether);
        assertEq(hostEarnings.getBalance(host1, address(0)), 3 ether);
    }

    function test_WithdrawTokenWorks() public {
        // Credit some earnings
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));

        vm.prank(host1);
        hostEarnings.withdraw(500 * 10**18, address(usdc));

        assertEq(usdc.balanceOf(host1), 500 * 10**18);
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 500 * 10**18);
    }

    function test_WithdrawRejectsInsufficientBalance() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1 ether, address(0));

        vm.prank(host1);
        vm.expectRevert("Insufficient earnings");
        hostEarnings.withdraw(2 ether, address(0));
    }

    function test_WithdrawAllWorks() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));

        uint256 balanceBefore = host1.balance;

        vm.prank(host1);
        hostEarnings.withdrawAll(address(0));

        assertEq(host1.balance, balanceBefore + 5 ether);
        assertEq(hostEarnings.getBalance(host1, address(0)), 0);
    }

    function test_WithdrawAllRejectsZeroBalance() public {
        vm.prank(host1);
        vm.expectRevert("No earnings to withdraw");
        hostEarnings.withdrawAll(address(0));
    }

    function test_WithdrawMultipleWorks() public {
        // Credit ETH and token earnings
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = address(usdc);

        uint256 ethBalanceBefore = host1.balance;

        vm.prank(host1);
        hostEarnings.withdrawMultiple(tokens);

        assertEq(host1.balance, ethBalanceBefore + 5 ether);
        assertEq(usdc.balanceOf(host1), 1000 * 10**18);
        assertEq(hostEarnings.getBalance(host1, address(0)), 0);
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 0);
    }

    // ============================================================
    // Query Functions Tests
    // ============================================================

    function test_GetBalancesWorks() public {
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = address(usdc);

        uint256[] memory balances = hostEarnings.getBalances(host1, tokens);

        assertEq(balances[0], 5 ether);
        assertEq(balances[1], 1000 * 10**18);
    }

    function test_GetTokenStatsWorks() public {
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 10 ether, address(0));
        hostEarnings.creditEarnings(host2, 5 ether, address(0));
        vm.stopPrank();

        vm.prank(host1);
        hostEarnings.withdraw(3 ether, address(0));

        (uint256 accumulated, uint256 withdrawn, uint256 outstanding) =
            hostEarnings.getTokenStats(address(0));

        assertEq(accumulated, 15 ether);
        assertEq(withdrawn, 3 ether);
        assertEq(outstanding, 12 ether);
    }

    // ============================================================
    // Receive ETH Tests
    // ============================================================

    function test_ReceiveETHWorks() public {
        uint256 balanceBefore = address(hostEarnings).balance;

        (bool success, ) = address(hostEarnings).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(hostEarnings).balance, balanceBefore + 1 ether);
    }
}
