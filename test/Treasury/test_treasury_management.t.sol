// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {TreasuryManager} from "../../src/TreasuryManager.sol";
import {PaymentSplitter} from "../../src/PaymentSplitter.sol";
import {FABBuyback} from "../../src/FABBuyback.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract MockDEX {
    uint256 public exchangeRate = 2 * 10**12; // 1 USDC = 2 FAB (accounting for decimals)
    
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256) {
        // Simple mock swap - USDC to FAB
        MockERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = (amountIn * exchangeRate) / 10**6; // Convert USDC (6 dec) to FAB (18 dec)
        MockERC20(tokenOut).mint(msg.sender, amountOut);
        return amountOut;
    }
    
    function getTWAPPrice(uint256) external view returns (uint256) {
        return exchangeRate;
    }
}

contract TreasuryManagementTest is Test {
    TreasuryManager public treasuryManager;
    PaymentSplitter public paymentSplitter;
    FABBuyback public fabBuyback;
    MockERC20 public fab;
    MockERC20 public usdc;
    MockDEX public dex;
    
    address constant ADMIN = address(0x1);
    address constant HOST = address(0x2);
    address constant STAKERS_POOL = address(0x3);
    address constant DEVELOPMENT_FUND = address(0x4);
    address constant ECOSYSTEM_FUND = address(0x5);
    address constant INSURANCE_FUND = address(0x6);
    address constant RESERVE_FUND = address(0x7);
    address constant STAKING_REWARDS = address(0x8);
    address constant GOVERNANCE = address(0x9);
    
    uint256 constant JOB_PAYMENT = 1000 * 10**6; // 1000 USDC
    uint256 constant HOST_SHARE = 850 * 10**6; // 850 USDC (85%)
    uint256 constant STAKERS_SHARE = 50 * 10**6; // 50 USDC (5%)
    uint256 constant TREASURY_SHARE = 100 * 10**6; // 100 USDC (10%)
    
    // Sub-allocations from treasury (10%)
    uint256 constant DEVELOPMENT_AMOUNT = 30 * 10**6; // 30 USDC (3%)
    uint256 constant ECOSYSTEM_AMOUNT = 20 * 10**6; // 20 USDC (2%)
    uint256 constant INSURANCE_AMOUNT = 20 * 10**6; // 20 USDC (2%)
    uint256 constant BUYBACK_AMOUNT = 20 * 10**6; // 20 USDC (2%)
    uint256 constant BUYBACK_BURN_BASIS_POINTS = 200; // From TreasuryManager
    uint256 constant TREASURY_TOTAL_BASIS_POINTS = 1000; // From TreasuryManager
    uint256 constant RESERVE_AMOUNT = 10 * 10**6; // 10 USDC (1%)
    
    event FundsReceived(address indexed token, uint256 amount, address indexed from);
    event FundsDistributed(
        address indexed token,
        uint256 totalAmount,
        uint256 developmentAmount,
        uint256 ecosystemAmount,
        uint256 insuranceAmount,
        uint256 buybackAmount,
        uint256 reserveAmount
    );
    event FundWithdrawn(
        address indexed fund,
        address indexed token,
        uint256 amount,
        address indexed recipient
    );
    event BuybackExecuted(address indexed token, uint256 amount);
    event DirectBurnExecuted(uint256 fabAmount);
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dex = new MockDEX();
        
        // Deploy FABBuyback (treasury will be set later)
        fabBuyback = new FABBuyback(
            address(fab),
            address(usdc),
            address(dex),
            address(0), // Will be updated to TreasuryManager
            STAKING_REWARDS,
            GOVERNANCE
        );
        
        // Deploy TreasuryManager
        treasuryManager = new TreasuryManager(
            DEVELOPMENT_FUND,
            ECOSYSTEM_FUND,
            INSURANCE_FUND,
            address(fabBuyback),
            RESERVE_FUND,
            ADMIN
        );
        
        // Deploy PaymentSplitter with TreasuryManager as treasury
        paymentSplitter = new PaymentSplitter(
            address(treasuryManager),
            STAKERS_POOL
        );
        
        // Update FABBuyback to use treasury manager
        vm.startPrank(GOVERNANCE);
        fabBuyback.updateDexRouter(address(dex)); // Use our mock DEX
        fabBuyback.updateStakingRewards(STAKING_REWARDS); // Set staking rewards
        fabBuyback.updateProtocolTreasury(address(treasuryManager)); // Set treasury manager
        vm.stopPrank();
        
        // Set token addresses in TreasuryManager
        vm.prank(ADMIN);
        treasuryManager.setTokenAddresses(address(fab), address(usdc));
        
        // Fund test accounts
        usdc.mint(address(this), 10000 * 10**6); // 10,000 USDC
        fab.mint(address(this), 10000 ether); // 10,000 FAB
        
        // Approve spending
        usdc.approve(address(paymentSplitter), type(uint256).max);
        usdc.approve(address(treasuryManager), type(uint256).max);
        fab.approve(address(paymentSplitter), type(uint256).max);
        fab.approve(address(treasuryManager), type(uint256).max);
    }
    
    function test_PaymentSplitPercentages() public {
        // Transfer USDC to PaymentSplitter
        usdc.transfer(address(paymentSplitter), JOB_PAYMENT);
        
        // Execute payment split
        paymentSplitter.splitPayment(1, JOB_PAYMENT, HOST, address(usdc));
        
        // Check balances
        assertEq(usdc.balanceOf(HOST), HOST_SHARE, "Host should receive 85%");
        assertEq(usdc.balanceOf(STAKERS_POOL), STAKERS_SHARE, "Stakers should receive 5%");
        assertEq(usdc.balanceOf(address(treasuryManager)), TREASURY_SHARE, "Treasury should receive 10%");
    }
    
    function test_TreasuryDistribution() public {
        // Send funds to TreasuryManager
        usdc.transfer(address(treasuryManager), TREASURY_SHARE);
        
        // Record expected event
        vm.expectEmit(true, true, false, true);
        emit FundsReceived(address(usdc), TREASURY_SHARE, address(this));
        
        vm.expectEmit(true, true, true, true);
        emit FundsDistributed(
            address(usdc),
            TREASURY_SHARE,
            DEVELOPMENT_AMOUNT,
            ECOSYSTEM_AMOUNT,
            INSURANCE_AMOUNT,
            BUYBACK_AMOUNT,
            RESERVE_AMOUNT
        );
        
        // Process the funds
        treasuryManager.processFunds(address(usdc));
        
        // Check fund balances
        assertEq(treasuryManager.getFundBalance(DEVELOPMENT_FUND, address(usdc)), DEVELOPMENT_AMOUNT);
        assertEq(treasuryManager.getFundBalance(ECOSYSTEM_FUND, address(usdc)), ECOSYSTEM_AMOUNT);
        assertEq(treasuryManager.getFundBalance(INSURANCE_FUND, address(usdc)), INSURANCE_AMOUNT);
        assertEq(treasuryManager.getFundBalance(address(fabBuyback), address(usdc)), BUYBACK_AMOUNT);
        assertEq(treasuryManager.getFundBalance(RESERVE_FUND, address(usdc)), RESERVE_AMOUNT);
    }
    
    function test_CumulativeTracking() public {
        // Send funds multiple times
        for (uint i = 0; i < 3; i++) {
            usdc.transfer(address(treasuryManager), TREASURY_SHARE);
            treasuryManager.processFunds(address(usdc));
        }
        
        // Check cumulative amounts
        (
            uint256 development,
            uint256 ecosystem,
            uint256 insurance,
            uint256 buyback,
            uint256 reserve
        ) = treasuryManager.getCumulativeAmounts(address(usdc));
        
        assertEq(development, DEVELOPMENT_AMOUNT * 3);
        assertEq(ecosystem, ECOSYSTEM_AMOUNT * 3);
        assertEq(insurance, INSURANCE_AMOUNT * 3);
        assertEq(buyback, BUYBACK_AMOUNT * 3);
        assertEq(reserve, RESERVE_AMOUNT * 3);
    }
    
    function test_FundWithdrawal() public {
        // Setup funds
        usdc.transfer(address(treasuryManager), TREASURY_SHARE);
        treasuryManager.processFunds(address(usdc));
        
        // Withdraw development funds
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit FundWithdrawn(DEVELOPMENT_FUND, address(usdc), DEVELOPMENT_AMOUNT, DEVELOPMENT_FUND);
        
        treasuryManager.withdrawFund(
            DEVELOPMENT_FUND,
            address(usdc),
            DEVELOPMENT_AMOUNT,
            DEVELOPMENT_FUND
        );
        
        assertEq(usdc.balanceOf(DEVELOPMENT_FUND), DEVELOPMENT_AMOUNT);
        assertEq(treasuryManager.getFundBalance(DEVELOPMENT_FUND, address(usdc)), 0);
    }
    
    function test_BuybackExecution() public {
        // Setup funds - need at least 100 USDC for buyback minimum
        // Buyback gets 20% of treasury funds, so need 500 USDC in treasury
        uint256 treasuryAmount = 500 * 10**6; // 500 USDC
        usdc.transfer(address(treasuryManager), treasuryAmount);
        treasuryManager.processFunds(address(usdc));
        
        // Calculate expected buyback amount (20% of treasury = 100 USDC)
        uint256 expectedBuybackAmount = (treasuryAmount * BUYBACK_BURN_BASIS_POINTS) / TREASURY_TOTAL_BASIS_POINTS;
        assertEq(expectedBuybackAmount, 100 * 10**6); // Verify it's 100 USDC
        
        // Execute buyback
        vm.expectEmit(true, true, true, true);
        emit BuybackExecuted(address(usdc), expectedBuybackAmount);
        
        treasuryManager.executeBuyback(address(usdc));
        
        // Check that funds were processed
        assertEq(treasuryManager.getFundBalance(address(fabBuyback), address(usdc)), 0);
        
        // Verify buyback metrics
        (uint256 totalBought, uint256 totalBurned,,, uint256 buybackCount) = fabBuyback.getBuybackMetrics();
        assertGt(totalBought, 0, "Should have bought FAB");
        assertGt(totalBurned, 0, "Should have burned FAB");
        assertEq(buybackCount, 1, "Should have executed 1 buyback");
    }
    
    function test_DirectFABBurn() public {
        // Send FAB to TreasuryManager
        fab.transfer(address(treasuryManager), 100 ether);
        treasuryManager.processFunds(address(fab));
        
        // Check FAB allocation to buyback (2%)
        uint256 fabForBurn = (100 ether * 200) / 1000; // 20 FAB
        assertEq(treasuryManager.getFundBalance(address(fabBuyback), address(fab)), fabForBurn);
        
        // Use burnFAB instead of withdrawing to buyback
        vm.expectEmit(true, true, true, true);
        emit BuybackExecuted(address(fab), fabForBurn);
        
        treasuryManager.burnFAB();
        
        // Check burn address received FAB
        assertEq(fab.balanceOf(0x000000000000000000000000000000000000dEaD), fabForBurn);
    }
    
    function test_OnlyAuthorizedWithdrawal() public {
        // Setup funds
        usdc.transfer(address(treasuryManager), TREASURY_SHARE);
        treasuryManager.processFunds(address(usdc));
        
        // Try to withdraw without permission
        vm.prank(address(0x123));
        vm.expectRevert();
        treasuryManager.withdrawFund(
            DEVELOPMENT_FUND,
            address(usdc),
            DEVELOPMENT_AMOUNT,
            DEVELOPMENT_FUND
        );
    }
    
    function test_CannotWithdrawBuybackFunds() public {
        // Setup funds
        usdc.transfer(address(treasuryManager), TREASURY_SHARE);
        treasuryManager.processFunds(address(usdc));
        
        // Try to withdraw buyback funds
        vm.prank(ADMIN);
        vm.expectRevert("Invalid fund");
        treasuryManager.withdrawFund(
            address(fabBuyback),
            address(usdc),
            BUYBACK_AMOUNT,
            address(0x123)
        );
    }
    
    function test_EmergencyPause() public {
        // Pause contract
        vm.prank(ADMIN);
        treasuryManager.pause();
        
        // Try to process funds while paused
        usdc.transfer(address(treasuryManager), TREASURY_SHARE);
        vm.expectRevert("EnforcedPause()");
        treasuryManager.processFunds(address(usdc));
        
        // Unpause
        vm.prank(ADMIN);
        treasuryManager.unpause();
        
        // Should work now
        treasuryManager.processFunds(address(usdc));
    }
    
    function test_UpdateFundAddresses() public {
        address newDevelopmentFund = address(0x100);
        
        // Update development fund
        vm.prank(ADMIN);
        treasuryManager.updateDevelopmentFund(newDevelopmentFund);
        
        assertEq(treasuryManager.developmentFund(), newDevelopmentFund);
    }
    
    function test_ETHPaymentFlow() public {
        // Send ETH to PaymentSplitter
        paymentSplitter.splitPayment{value: 1 ether}(1, 1 ether, HOST, address(0));
        
        // Check balances
        assertEq(HOST.balance, 0.85 ether, "Host should receive 85%");
        assertEq(STAKERS_POOL.balance, 0.05 ether, "Stakers should receive 5%");
        assertEq(address(treasuryManager).balance, 0.1 ether, "Treasury should receive 10%");
        
        // Process ETH in treasury
        treasuryManager.processFunds(address(0));
        
        // Check allocations
        assertEq(treasuryManager.getFundBalance(DEVELOPMENT_FUND, address(0)), 0.03 ether);
        assertEq(treasuryManager.getFundBalance(ECOSYSTEM_FUND, address(0)), 0.02 ether);
        assertEq(treasuryManager.getFundBalance(INSURANCE_FUND, address(0)), 0.02 ether);
        assertEq(treasuryManager.getFundBalance(address(fabBuyback), address(0)), 0.02 ether);
        assertEq(treasuryManager.getFundBalance(RESERVE_FUND, address(0)), 0.01 ether);
    }
    
    function test_AllocationPercentages() public {
        (
            uint256 development,
            uint256 ecosystem,
            uint256 insurance,
            uint256 buyback,
            uint256 reserve
        ) = treasuryManager.getAllocations();
        
        assertEq(development, 300); // 3%
        assertEq(ecosystem, 200); // 2%
        assertEq(insurance, 200); // 2%
        assertEq(buyback, 200); // 2%
        assertEq(reserve, 100); // 1%
        assertEq(development + ecosystem + insurance + buyback + reserve, 1000); // Total 10%
    }
    
    function test_RoundingHandling() public {
        // Test with amount that doesn't divide evenly
        uint256 oddAmount = 10000001; // 10.000001 USDC
        
        usdc.transfer(address(treasuryManager), oddAmount);
        treasuryManager.processFunds(address(usdc));
        
        // Check that total distributed equals input
        uint256 totalDistributed = 
            treasuryManager.getFundBalance(DEVELOPMENT_FUND, address(usdc)) +
            treasuryManager.getFundBalance(ECOSYSTEM_FUND, address(usdc)) +
            treasuryManager.getFundBalance(INSURANCE_FUND, address(usdc)) +
            treasuryManager.getFundBalance(address(fabBuyback), address(usdc)) +
            treasuryManager.getFundBalance(RESERVE_FUND, address(usdc));
            
        assertEq(totalDistributed, oddAmount, "Total distributed should equal input");
    }
    
    function test_MultipleFundWithdrawals() public {
        // Setup funds
        usdc.transfer(address(treasuryManager), TREASURY_SHARE * 5);
        treasuryManager.processFunds(address(usdc));
        
        // Withdraw from multiple funds
        vm.startPrank(ADMIN);
        
        treasuryManager.withdrawFund(DEVELOPMENT_FUND, address(usdc), DEVELOPMENT_AMOUNT * 2, DEVELOPMENT_FUND);
        treasuryManager.withdrawFund(ECOSYSTEM_FUND, address(usdc), ECOSYSTEM_AMOUNT, ECOSYSTEM_FUND);
        treasuryManager.withdrawFund(INSURANCE_FUND, address(usdc), INSURANCE_AMOUNT * 3, INSURANCE_FUND);
        
        vm.stopPrank();
        
        // Check remaining balances
        assertEq(treasuryManager.getFundBalance(DEVELOPMENT_FUND, address(usdc)), DEVELOPMENT_AMOUNT * 3);
        assertEq(treasuryManager.getFundBalance(ECOSYSTEM_FUND, address(usdc)), ECOSYSTEM_AMOUNT * 4);
        assertEq(treasuryManager.getFundBalance(INSURANCE_FUND, address(usdc)), INSURANCE_AMOUNT * 2);
    }
}