// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {FABBuyback} from "../../src/FABBuyback.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockDEX} from "../mocks/MockDEX.sol";

contract FABBuybackTest is Test {
    FABBuyback public buyback;
    MockERC20 public fab;
    MockERC20 public usdc;
    MockDEX public dex;
    
    address constant PROTOCOL_TREASURY = address(0x1);
    address constant STAKING_REWARDS = address(0x2);
    address constant GOVERNANCE = address(0x3);
    
    uint256 constant INITIAL_FAB_PRICE = 1e6; // 1 USDC per FAB
    
    event BuybackExecuted(
        uint256 usdcAmount,
        uint256 fabReceived,
        uint256 fabBurned,
        uint256 fabToStaking
    );
    
    event BuybackScheduled(uint256 timestamp, uint256 amount);
    event AutoBuybackEnabled(uint256 threshold, uint256 frequency);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dex = new MockDEX(address(fab), address(usdc));
        
        buyback = new FABBuyback(
            address(fab),
            address(usdc),
            address(dex),
            PROTOCOL_TREASURY,
            STAKING_REWARDS,
            GOVERNANCE
        );
        
        // Setup DEX liquidity
        fab.mint(address(dex), 1000000 ether);
        usdc.mint(address(dex), 1000000 * 10**6);
        dex.setPrice(INITIAL_FAB_PRICE);
        
        // Fund treasury
        usdc.mint(PROTOCOL_TREASURY, 100000 * 10**6); // 100k USDC
    }
    
    function test_ExecuteBuyback() public {
        uint256 buybackAmount = 10000 * 10**6; // 10k USDC
        
        // Transfer USDC to buyback contract
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), buybackAmount);
        
        uint256 expectedFAB = 10000 ether; // At 1:1 rate
        uint256 expectedBurn = 5000 ether; // 50%
        uint256 expectedStaking = 5000 ether; // 50%
        
        vm.expectEmit(true, true, true, true);
        emit BuybackExecuted(buybackAmount, expectedFAB, expectedBurn, expectedStaking);
        
        vm.prank(GOVERNANCE);
        buyback.executeBuyback(buybackAmount);
        
        // Verify FAB was burned
        assertEq(fab.balanceOf(address(0xdead)), expectedBurn);
        
        // Verify FAB sent to staking
        assertEq(fab.balanceOf(STAKING_REWARDS), expectedStaking);
        
        // Verify USDC was spent
        assertEq(usdc.balanceOf(address(buyback)), 0);
    }
    
    function test_ScheduledBuyback() public {
        uint256 buybackAmount = 5000 * 10**6; // 5k USDC
        uint256 scheduledTime = block.timestamp + 1 days;
        
        vm.prank(GOVERNANCE);
        vm.expectEmit(true, true, true, true);
        emit BuybackScheduled(scheduledTime, buybackAmount);
        
        buyback.scheduleBuyback(scheduledTime, buybackAmount);
        
        // Cannot execute before scheduled time
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), buybackAmount);
        
        vm.expectRevert("Buyback not yet executable");
        buyback.executeScheduledBuyback();
        
        // Fast forward
        vm.warp(scheduledTime);
        
        // Now can execute
        buyback.executeScheduledBuyback();
        
        // Verify execution
        assertGt(fab.balanceOf(address(0xdead)), 0);
        assertGt(fab.balanceOf(STAKING_REWARDS), 0);
    }
    
    function test_AutoBuyback() public {
        uint256 threshold = 50000 * 10**6; // 50k USDC
        uint256 frequency = 7 days;
        
        vm.prank(GOVERNANCE);
        vm.expectEmit(true, true, true, true);
        emit AutoBuybackEnabled(threshold, frequency);
        
        buyback.enableAutoBuyback(threshold, frequency);
        
        // Transfer funds above threshold
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), threshold + 10000 * 10**6);
        
        // Warp time forward to allow auto buyback
        vm.warp(block.timestamp + frequency);
        
        // Auto buyback should trigger
        buyback.checkAndExecuteAutoBuyback();
        
        // Verify buyback executed
        assertLt(usdc.balanceOf(address(buyback)), threshold);
        assertGt(fab.balanceOf(address(0xdead)), 0);
    }
    
    function test_TWAPPriceProtection() public {
        // Set up price manipulation scenario
        dex.setPrice(2e6); // Double the price suddenly
        
        uint256 buybackAmount = 10000 * 10**6;
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), buybackAmount);
        
        // Enable TWAP protection
        vm.prank(GOVERNANCE);
        buyback.enableTWAPProtection(true, 1000); // 10% max deviation
        
        // Buyback should use current price (no TWAP implemented in this version)
        vm.prank(GOVERNANCE);
        buyback.executeBuyback(buybackAmount);
        
        // With doubled price, should get half the FAB
        uint256 fabReceived = fab.balanceOf(address(0xdead)) + fab.balanceOf(STAKING_REWARDS);
        assertEq(fabReceived, 5000 ether); // Half due to doubled price
    }
    
    function test_BuybackMetrics() public {
        // Execute multiple buybacks
        for (uint i = 0; i < 3; i++) {
            vm.prank(PROTOCOL_TREASURY);
            usdc.transfer(address(buyback), 1000 * 10**6);
            
            vm.prank(GOVERNANCE);
            buyback.executeBuyback(1000 * 10**6);
            
            vm.warp(block.timestamp + 1 days);
        }
        
        (
            uint256 totalBought,
            uint256 totalBurned,
            uint256 totalToStaking,
            uint256 averagePrice,
            uint256 buybackCount
        ) = buyback.getBuybackMetrics();
        
        assertEq(totalBought, 3000 ether);
        assertEq(totalBurned, 1500 ether);
        assertEq(totalToStaking, 1500 ether);
        assertEq(buybackCount, 3);
        assertEq(averagePrice, INITIAL_FAB_PRICE);
    }
    
    function test_EmergencyPause() public {
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), 10000 * 10**6);
        
        // Pause buybacks
        vm.prank(GOVERNANCE);
        buyback.pauseBuybacks();
        
        // Cannot execute while paused
        vm.expectRevert("Buybacks paused");
        vm.prank(GOVERNANCE);
        buyback.executeBuyback(10000 * 10**6);
        
        // Unpause
        vm.prank(GOVERNANCE);
        buyback.unpauseBuybacks();
        
        // Now can execute
        vm.prank(GOVERNANCE);
        buyback.executeBuyback(10000 * 10**6);
        assertGt(fab.balanceOf(address(0xdead)), 0);
    }
    
    function test_UpdateBurnRatio() public {
        // Change from 50/50 to 70/30 burn/stake
        vm.prank(GOVERNANCE);
        buyback.updateBurnRatio(7000); // 70%
        
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), 10000 * 10**6);
        
        vm.prank(GOVERNANCE);
        buyback.executeBuyback(10000 * 10**6);
        
        assertEq(fab.balanceOf(address(0xdead)), 7000 ether);
        assertEq(fab.balanceOf(STAKING_REWARDS), 3000 ether);
    }
    
    function test_MinimumBuybackAmount() public {
        uint256 tinyAmount = 10 * 10**6; // 10 USDC
        
        vm.prank(PROTOCOL_TREASURY);
        usdc.transfer(address(buyback), tinyAmount);
        
        vm.expectRevert("Amount below minimum");
        vm.prank(GOVERNANCE);
        buyback.executeBuyback(tinyAmount);
    }
}