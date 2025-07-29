// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakersPool} from "../../src/StakersPool.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract StakerRewardsTest is Test {
    StakersPool public stakersPool;
    MockERC20 public fab;
    MockERC20 public usdc;
    
    address constant STAKER1 = address(0x1);
    address constant STAKER2 = address(0x2);
    address constant STAKER3 = address(0x3);
    address constant PAYMENT_SPLITTER = address(0x4);
    
    event RewardDistributed(
        address indexed token,
        uint256 totalAmount,
        uint256 rewardPerShare
    );
    
    event RewardClaimed(
        address indexed staker,
        address indexed token,
        uint256 amount
    );
    
    event StakeUpdated(
        address indexed staker,
        uint256 newStake,
        uint256 totalStaked
    );
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        stakersPool = new StakersPool(address(fab), PAYMENT_SPLITTER);
        
        // Mint FAB to stakers
        fab.mint(STAKER1, 100000 ether);
        fab.mint(STAKER2, 200000 ether);
        fab.mint(STAKER3, 50000 ether);
        
        // Setup initial stakes
        vm.prank(STAKER1);
        fab.approve(address(stakersPool), type(uint256).max);
        
        vm.prank(STAKER2);
        fab.approve(address(stakersPool), type(uint256).max);
        
        vm.prank(STAKER3);
        fab.approve(address(stakersPool), type(uint256).max);
    }
    
    function test_DistributeUSDCRewards() public {
        // Stakers stake different amounts
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether); // 10k FAB
        
        vm.prank(STAKER2);
        stakersPool.updateStake(20000 ether); // 20k FAB
        
        vm.prank(STAKER3);
        stakersPool.updateStake(10000 ether); // 10k FAB
        
        // Total staked: 40k FAB
        
        // Distribute 1000 USDC rewards
        uint256 rewardAmount = 1000 * 10**6;
        usdc.mint(address(stakersPool), rewardAmount);
        
        vm.prank(PAYMENT_SPLITTER);
        vm.expectEmit(true, true, true, true);
        emit RewardDistributed(address(usdc), rewardAmount, rewardAmount * 1e18 / 40000 ether);
        
        stakersPool.distributeRewards(address(usdc), rewardAmount);
        
        // Check pending rewards
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 250 * 10**6); // 25%
        assertEq(stakersPool.pendingRewards(STAKER2, address(usdc)), 500 * 10**6); // 50%
        assertEq(stakersPool.pendingRewards(STAKER3, address(usdc)), 250 * 10**6); // 25%
    }
    
    function test_ClaimRewards() public {
        // Setup stakes
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether);
        
        // Distribute rewards
        uint256 rewardAmount = 1000 * 10**6;
        usdc.mint(address(stakersPool), rewardAmount);
        
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(usdc), rewardAmount);
        
        // Claim rewards
        uint256 balanceBefore = usdc.balanceOf(STAKER1);
        
        vm.prank(STAKER1);
        vm.expectEmit(true, true, true, true);
        emit RewardClaimed(STAKER1, address(usdc), rewardAmount);
        
        stakersPool.claimReward(address(usdc));
        
        assertEq(usdc.balanceOf(STAKER1) - balanceBefore, rewardAmount);
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 0);
    }
    
    function test_MultipleRewardTokens() public {
        // Stake
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether);
        
        // Distribute USDC rewards
        usdc.mint(address(stakersPool), 1000 * 10**6);
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(usdc), 1000 * 10**6);
        
        // Also distribute FAB rewards (from buyback)
        fab.mint(address(stakersPool), 500 ether);
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(fab), 500 ether);
        
        // Check both rewards
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 1000 * 10**6);
        assertEq(stakersPool.pendingRewards(STAKER1, address(fab)), 500 ether);
        
        // Claim all rewards
        vm.prank(STAKER1);
        stakersPool.claimAllRewards();
        
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 0);
        assertEq(stakersPool.pendingRewards(STAKER1, address(fab)), 0);
    }
    
    function test_StakeChangesAffectFutureRewards() public {
        // Initial stakes
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether);
        
        vm.prank(STAKER2);
        stakersPool.updateStake(10000 ether);
        
        // First distribution - equal shares
        usdc.mint(address(stakersPool), 1000 * 10**6);
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(usdc), 1000 * 10**6);
        
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 500 * 10**6);
        assertEq(stakersPool.pendingRewards(STAKER2, address(usdc)), 500 * 10**6);
        
        // STAKER2 increases stake
        vm.prank(STAKER2);
        stakersPool.updateStake(30000 ether); // Now has 3x stake
        
        // Second distribution - different shares
        usdc.mint(address(stakersPool), 1000 * 10**6);
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(usdc), 1000 * 10**6);
        
        // STAKER1: 500 + 250 = 750
        // STAKER2: 500 + 750 = 1250
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 750 * 10**6);
        assertEq(stakersPool.pendingRewards(STAKER2, address(usdc)), 1250 * 10**6);
    }
    
    function test_CompoundingRewards() public {
        // Stake FAB
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether);
        
        // Distribute FAB rewards
        fab.mint(address(stakersPool), 1000 ether);
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(fab), 1000 ether);
        
        // Compound rewards (claim and restake)
        vm.prank(STAKER1);
        stakersPool.compoundRewards();
        
        // Stake should increase by reward amount
        assertEq(stakersPool.getStakedAmount(STAKER1), 11000 ether);
        assertEq(stakersPool.pendingRewards(STAKER1, address(fab)), 0);
    }
    
    function test_RewardAccounting() public {
        // Multiple stakers and distributions
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether);
        
        vm.prank(STAKER2);
        stakersPool.updateStake(20000 ether);
        
        // Multiple distributions
        for (uint i = 0; i < 5; i++) {
            usdc.mint(address(stakersPool), 100 * 10**6);
            vm.prank(PAYMENT_SPLITTER);
            stakersPool.distributeRewards(address(usdc), 100 * 10**6);
            vm.warp(block.timestamp + 1 days);
        }
        
        // Check total distributed
        assertEq(stakersPool.totalDistributed(address(usdc)), 500 * 10**6);
        
        // Check individual rewards
        // Due to integer division, exact values might be slightly off
        uint256 staker1Rewards = stakersPool.pendingRewards(STAKER1, address(usdc));
        uint256 staker2Rewards = stakersPool.pendingRewards(STAKER2, address(usdc));
        
        // STAKER1 has 1/3 of total stake, STAKER2 has 2/3
        assertApproxEqAbs(staker1Rewards, 166666666, 40000); // Allow small deviation
        assertApproxEqAbs(staker2Rewards, 333333333, 40000); // Allow small deviation
        
        // Total should be close to distributed amount (allowing for rounding errors)
        assertApproxEqAbs(staker1Rewards + staker2Rewards, 500 * 10**6, 100000); // 0.1 USDC tolerance
    }
    
    function test_EmergencyWithdraw() public {
        // Stake
        vm.prank(STAKER1);
        stakersPool.updateStake(10000 ether);
        
        // Distribute rewards
        usdc.mint(address(stakersPool), 1000 * 10**6);
        vm.prank(PAYMENT_SPLITTER);
        stakersPool.distributeRewards(address(usdc), 1000 * 10**6);
        
        // Emergency withdraw (forfeit rewards)
        uint256 fabBalanceBefore = fab.balanceOf(STAKER1);
        
        vm.prank(STAKER1);
        stakersPool.emergencyWithdraw();
        
        // Should get stake back but no rewards
        assertEq(fab.balanceOf(STAKER1) - fabBalanceBefore, 10000 ether);
        assertEq(stakersPool.getStakedAmount(STAKER1), 0);
        assertEq(stakersPool.pendingRewards(STAKER1, address(usdc)), 0);
    }
    
    function test_MinimumStakeRequirement() public {
        // Try to stake below minimum
        vm.prank(STAKER1);
        vm.expectRevert("Below minimum stake");
        stakersPool.updateStake(10 ether); // Too small
    }
    
    function test_RewardDistributionWithNoStakers() public {
        // Distribute rewards with no stakers
        usdc.mint(address(stakersPool), 1000 * 10**6);
        
        vm.prank(PAYMENT_SPLITTER);
        vm.expectRevert("No stakers");
        stakersPool.distributeRewards(address(usdc), 1000 * 10**6);
    }
}