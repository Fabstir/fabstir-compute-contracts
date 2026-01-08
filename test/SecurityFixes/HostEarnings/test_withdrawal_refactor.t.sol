// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title HostEarningsUpgradeable Withdrawal Refactor Tests
 * @dev Tests for Phase 1: Code Deduplication - verifies withdrawal behavior unchanged
 *      after extracting common logic into _executeTransfer()
 */
contract HostEarningsWithdrawalRefactorTest is Test {
    HostEarningsUpgradeable public implementation;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public usdc;
    ERC20Mock public fab;

    address public owner = address(0x1);
    address public host1 = address(0x2);
    address public host2 = address(0x3);
    address public authorizedCaller = address(0x4);

    event EarningsWithdrawn(
        address indexed host,
        address indexed token,
        uint256 amount,
        uint256 remainingBalance
    );

    function setUp() public {
        // Deploy mock tokens
        usdc = new ERC20Mock("USD Coin", "USDC");
        fab = new ERC20Mock("FAB Token", "FAB");

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
        fab.mint(address(hostEarnings), 10000 * 10**18);
    }

    // ============================================================
    // Test: withdraw() behavior unchanged after refactor
    // ============================================================

    function test_Withdraw_BehaviorUnchanged_ETH() public {
        // Setup: Credit ETH earnings
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 10 ether, address(0));

        uint256 hostBalanceBefore = host1.balance;
        uint256 contractBalanceBefore = address(hostEarnings).balance;

        // Action: Partial withdrawal
        vm.prank(host1);
        hostEarnings.withdraw(3 ether, address(0));

        // Assert: Balances updated correctly
        assertEq(host1.balance, hostBalanceBefore + 3 ether, "Host should receive 3 ETH");
        assertEq(address(hostEarnings).balance, contractBalanceBefore - 3 ether, "Contract should send 3 ETH");
        assertEq(hostEarnings.getBalance(host1, address(0)), 7 ether, "Remaining balance should be 7 ETH");
        assertEq(hostEarnings.totalWithdrawn(address(0)), 3 ether, "Total withdrawn should be 3 ETH");
    }

    function test_Withdraw_BehaviorUnchanged_ERC20() public {
        // Setup: Credit USDC earnings
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));

        uint256 hostBalanceBefore = usdc.balanceOf(host1);
        uint256 contractBalanceBefore = usdc.balanceOf(address(hostEarnings));

        // Action: Partial withdrawal
        vm.prank(host1);
        hostEarnings.withdraw(400 * 10**18, address(usdc));

        // Assert: Balances updated correctly
        assertEq(usdc.balanceOf(host1), hostBalanceBefore + 400 * 10**18, "Host should receive 400 USDC");
        assertEq(usdc.balanceOf(address(hostEarnings)), contractBalanceBefore - 400 * 10**18, "Contract should send 400 USDC");
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 600 * 10**18, "Remaining balance should be 600 USDC");
        assertEq(hostEarnings.totalWithdrawn(address(usdc)), 400 * 10**18, "Total withdrawn should be 400 USDC");
    }

    function test_Withdraw_EmitsCorrectEvent_ETH() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 10 ether, address(0));

        // Expect event with correct parameters
        vm.expectEmit(true, true, false, true, address(hostEarnings));
        emit EarningsWithdrawn(host1, address(0), 4 ether, 6 ether);

        vm.prank(host1);
        hostEarnings.withdraw(4 ether, address(0));
    }

    function test_Withdraw_EmitsCorrectEvent_ERC20() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));

        // Expect event with correct parameters
        vm.expectEmit(true, true, false, true, address(hostEarnings));
        emit EarningsWithdrawn(host1, address(usdc), 300 * 10**18, 700 * 10**18);

        vm.prank(host1);
        hostEarnings.withdraw(300 * 10**18, address(usdc));
    }

    // ============================================================
    // Test: withdrawAll() behavior unchanged after refactor
    // ============================================================

    function test_WithdrawAll_BehaviorUnchanged_ETH() public {
        // Setup: Credit ETH earnings
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 7 ether, address(0));

        uint256 hostBalanceBefore = host1.balance;

        // Action: Withdraw all
        vm.prank(host1);
        hostEarnings.withdrawAll(address(0));

        // Assert: All earnings withdrawn
        assertEq(host1.balance, hostBalanceBefore + 7 ether, "Host should receive all 7 ETH");
        assertEq(hostEarnings.getBalance(host1, address(0)), 0, "Remaining balance should be 0");
        assertEq(hostEarnings.totalWithdrawn(address(0)), 7 ether, "Total withdrawn should be 7 ETH");
    }

    function test_WithdrawAll_BehaviorUnchanged_ERC20() public {
        // Setup: Credit USDC earnings
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 500 * 10**18, address(usdc));

        uint256 hostBalanceBefore = usdc.balanceOf(host1);

        // Action: Withdraw all
        vm.prank(host1);
        hostEarnings.withdrawAll(address(usdc));

        // Assert: All earnings withdrawn
        assertEq(usdc.balanceOf(host1), hostBalanceBefore + 500 * 10**18, "Host should receive all 500 USDC");
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 0, "Remaining balance should be 0");
        assertEq(hostEarnings.totalWithdrawn(address(usdc)), 500 * 10**18, "Total withdrawn should be 500 USDC");
    }

    function test_WithdrawAll_EmitsCorrectEvent_ETH() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 8 ether, address(0));

        // Expect event with remainingBalance = 0
        vm.expectEmit(true, true, false, true, address(hostEarnings));
        emit EarningsWithdrawn(host1, address(0), 8 ether, 0);

        vm.prank(host1);
        hostEarnings.withdrawAll(address(0));
    }

    function test_WithdrawAll_EmitsCorrectEvent_ERC20() public {
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 200 * 10**18, address(usdc));

        // Expect event with remainingBalance = 0
        vm.expectEmit(true, true, false, true, address(hostEarnings));
        emit EarningsWithdrawn(host1, address(usdc), 200 * 10**18, 0);

        vm.prank(host1);
        hostEarnings.withdrawAll(address(usdc));
    }

    // ============================================================
    // Test: withdrawMultiple() behavior unchanged after refactor
    // ============================================================

    function test_WithdrawMultiple_BehaviorUnchanged() public {
        // Setup: Credit multiple tokens
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));
        hostEarnings.creditEarnings(host1, 500 * 10**18, address(fab));
        vm.stopPrank();

        uint256 ethBalanceBefore = host1.balance;
        uint256 usdcBalanceBefore = usdc.balanceOf(host1);
        uint256 fabBalanceBefore = fab.balanceOf(host1);

        // Action: Withdraw all three tokens
        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = address(usdc);
        tokens[2] = address(fab);

        vm.prank(host1);
        hostEarnings.withdrawMultiple(tokens);

        // Assert: All tokens withdrawn
        assertEq(host1.balance, ethBalanceBefore + 5 ether, "Host should receive 5 ETH");
        assertEq(usdc.balanceOf(host1), usdcBalanceBefore + 1000 * 10**18, "Host should receive 1000 USDC");
        assertEq(fab.balanceOf(host1), fabBalanceBefore + 500 * 10**18, "Host should receive 500 FAB");

        // Assert: All balances zeroed
        assertEq(hostEarnings.getBalance(host1, address(0)), 0, "ETH balance should be 0");
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 0, "USDC balance should be 0");
        assertEq(hostEarnings.getBalance(host1, address(fab)), 0, "FAB balance should be 0");
    }

    function test_WithdrawMultiple_MixedTokens_SomeWithZeroBalance() public {
        // Setup: Only credit ETH and USDC, not FAB
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 3 ether, address(0));
        hostEarnings.creditEarnings(host1, 200 * 10**18, address(usdc));
        // Note: No FAB credited
        vm.stopPrank();

        uint256 ethBalanceBefore = host1.balance;
        uint256 usdcBalanceBefore = usdc.balanceOf(host1);
        uint256 fabBalanceBefore = fab.balanceOf(host1);

        // Action: Try to withdraw all three including zero-balance FAB
        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = address(usdc);
        tokens[2] = address(fab);

        vm.prank(host1);
        hostEarnings.withdrawMultiple(tokens);

        // Assert: ETH and USDC withdrawn, FAB unchanged
        assertEq(host1.balance, ethBalanceBefore + 3 ether, "Host should receive 3 ETH");
        assertEq(usdc.balanceOf(host1), usdcBalanceBefore + 200 * 10**18, "Host should receive 200 USDC");
        assertEq(fab.balanceOf(host1), fabBalanceBefore, "FAB balance should be unchanged");
    }

    function test_WithdrawMultiple_EmitsCorrectEvents() public {
        // Setup: Credit ETH and USDC
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 2 ether, address(0));
        hostEarnings.creditEarnings(host1, 100 * 10**18, address(usdc));
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = address(0);
        tokens[1] = address(usdc);

        // Note: Events are emitted in order
        vm.expectEmit(true, true, false, true, address(hostEarnings));
        emit EarningsWithdrawn(host1, address(0), 2 ether, 0);

        vm.expectEmit(true, true, false, true, address(hostEarnings));
        emit EarningsWithdrawn(host1, address(usdc), 100 * 10**18, 0);

        vm.prank(host1);
        hostEarnings.withdrawMultiple(tokens);
    }

    // ============================================================
    // Test: ETH-specific path
    // ============================================================

    function test_WithdrawETH_Success() public {
        // Setup
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 15 ether, address(0));

        uint256 balanceBefore = host1.balance;

        // Action
        vm.prank(host1);
        hostEarnings.withdraw(15 ether, address(0));

        // Assert
        assertEq(host1.balance, balanceBefore + 15 ether, "Full ETH amount received");
        assertEq(hostEarnings.getBalance(host1, address(0)), 0, "Balance should be 0");
    }

    function test_WithdrawETH_TransferFailed_Reverts() public {
        // This test verifies the revert when ETH transfer fails
        // We'll use a contract that rejects ETH as the host

        // Deploy a contract that rejects ETH
        RejectETH rejecter = new RejectETH();

        // Credit earnings to the rejecter
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(address(rejecter), 1 ether, address(0));

        // Try to withdraw - should fail because rejecter won't accept ETH
        vm.prank(address(rejecter));
        vm.expectRevert("ETH transfer failed");
        hostEarnings.withdraw(1 ether, address(0));
    }

    // ============================================================
    // Test: ERC20-specific path
    // ============================================================

    function test_WithdrawERC20_Success() public {
        // Setup
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 777 * 10**18, address(usdc));

        uint256 balanceBefore = usdc.balanceOf(host1);

        // Action
        vm.prank(host1);
        hostEarnings.withdraw(777 * 10**18, address(usdc));

        // Assert
        assertEq(usdc.balanceOf(host1), balanceBefore + 777 * 10**18, "Full USDC amount received");
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 0, "Balance should be 0");
    }

    function test_WithdrawERC20_DifferentTokens() public {
        // Setup: Credit both USDC and FAB
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 100 * 10**18, address(usdc));
        hostEarnings.creditEarnings(host1, 200 * 10**18, address(fab));
        vm.stopPrank();

        // Withdraw USDC only
        vm.prank(host1);
        hostEarnings.withdraw(50 * 10**18, address(usdc));

        // Assert: USDC withdrawn, FAB unchanged
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 50 * 10**18, "USDC balance should be 50");
        assertEq(hostEarnings.getBalance(host1, address(fab)), 200 * 10**18, "FAB balance should be 200");
    }

    // ============================================================
    // Test: Multiple sequential withdrawals
    // ============================================================

    function test_MultipleSequentialWithdrawals() public {
        // Setup
        vm.prank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 10 ether, address(0));

        uint256 balanceBefore = host1.balance;

        // Action: Multiple small withdrawals
        vm.startPrank(host1);
        hostEarnings.withdraw(2 ether, address(0));
        hostEarnings.withdraw(3 ether, address(0));
        hostEarnings.withdraw(1 ether, address(0));
        vm.stopPrank();

        // Assert
        assertEq(host1.balance, balanceBefore + 6 ether, "Should have received 6 ETH total");
        assertEq(hostEarnings.getBalance(host1, address(0)), 4 ether, "Should have 4 ETH remaining");
        assertEq(hostEarnings.totalWithdrawn(address(0)), 6 ether, "Total withdrawn should be 6 ETH");
    }

    // ============================================================
    // Test: Multiple hosts withdrawing
    // ============================================================

    function test_MultipleHostsWithdrawing() public {
        // Setup: Credit both hosts
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 5 ether, address(0));
        hostEarnings.creditEarnings(host2, 8 ether, address(0));
        vm.stopPrank();

        uint256 host1BalanceBefore = host1.balance;
        uint256 host2BalanceBefore = host2.balance;

        // Both hosts withdraw
        vm.prank(host1);
        hostEarnings.withdraw(3 ether, address(0));

        vm.prank(host2);
        hostEarnings.withdraw(4 ether, address(0));

        // Assert: Each host's balance is independent
        assertEq(host1.balance, host1BalanceBefore + 3 ether, "Host1 should receive 3 ETH");
        assertEq(host2.balance, host2BalanceBefore + 4 ether, "Host2 should receive 4 ETH");
        assertEq(hostEarnings.getBalance(host1, address(0)), 2 ether, "Host1 should have 2 ETH remaining");
        assertEq(hostEarnings.getBalance(host2, address(0)), 4 ether, "Host2 should have 4 ETH remaining");
        assertEq(hostEarnings.totalWithdrawn(address(0)), 7 ether, "Total withdrawn should be 7 ETH");
    }
}

/**
 * @dev Helper contract that rejects ETH transfers
 */
contract RejectETH {
    receive() external payable {
        revert("I reject ETH");
    }
}
