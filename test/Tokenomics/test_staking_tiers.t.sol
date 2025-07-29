// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakingTiers} from "../../src/StakingTiers.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract StakingTiersTest is Test {
    StakingTiers public staking;
    MockERC20 public fab;
    
    address constant STAKER1 = address(0x1);
    address constant STAKER2 = address(0x2);
    address constant STAKER3 = address(0x3);
    address constant GOVERNANCE = address(0x4);
    
    // Tier thresholds
    uint256 constant BRONZE_THRESHOLD = 5000 ether;
    uint256 constant SILVER_THRESHOLD = 10000 ether;
    uint256 constant GOLD_THRESHOLD = 50000 ether;
    uint256 constant PLATINUM_THRESHOLD = 100000 ether;
    
    event TierAchieved(
        address indexed staker,
        StakingTiers.Tier tier,
        uint256 multiplier
    );
    
    event StakeLocked(
        address indexed staker,
        uint256 amount,
        uint256 lockDuration,
        uint256 unlockTime
    );
    
    event RewardMultiplierUpdated(
        address indexed staker,
        uint256 oldMultiplier,
        uint256 newMultiplier
    );
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        staking = new StakingTiers(address(fab), GOVERNANCE);
        
        // Mint FAB to stakers
        fab.mint(STAKER1, 200000 ether);
        fab.mint(STAKER2, 200000 ether);
        fab.mint(STAKER3, 200000 ether);
        
        // Approve staking contract
        vm.prank(STAKER1);
        fab.approve(address(staking), type(uint256).max);
        
        vm.prank(STAKER2);
        fab.approve(address(staking), type(uint256).max);
        
        vm.prank(STAKER3);
        fab.approve(address(staking), type(uint256).max);
    }
    
    function test_FlexibleStaking() public {
        uint256 stakeAmount = 1000 ether;
        
        vm.prank(STAKER1);
        vm.expectEmit(true, true, true, true);
        emit TierAchieved(STAKER1, StakingTiers.Tier.Flexible, 500); // 0.5x multiplier
        
        staking.stakeFlexible(stakeAmount);
        
        (
            StakingTiers.Tier tier,
            uint256 stakedAmount,
            uint256 lockEnd,
            uint256 multiplier,
            uint256 votingPower
        ) = staking.getStakerInfo(STAKER1);
        
        assertEq(uint8(tier), uint8(StakingTiers.Tier.Flexible));
        assertEq(stakedAmount, stakeAmount);
        assertEq(lockEnd, 0); // No lock
        assertEq(multiplier, 500); // 0.5x
        assertEq(votingPower, 50 ether); // 1000 * 0.05 (500 basis points)
    }
    
    function test_BronzeTier() public {
        vm.prank(STAKER1);
        vm.expectEmit(true, true, true, true);
        emit StakeLocked(STAKER1, BRONZE_THRESHOLD, 30 days, block.timestamp + 30 days);
        vm.expectEmit(true, true, true, true);
        emit TierAchieved(STAKER1, StakingTiers.Tier.Bronze, 750); // 0.75x
        
        staking.stakeLocked(BRONZE_THRESHOLD, 30 days);
        
        (StakingTiers.Tier tier,,,uint256 multiplier, uint256 votingPower) = 
            staking.getStakerInfo(STAKER1);
            
        assertEq(uint8(tier), uint8(StakingTiers.Tier.Bronze));
        assertEq(multiplier, 750);
        assertEq(votingPower, 375 ether); // 5000 * 0.075 (750 basis points)
    }
    
    function test_SilverTier() public {
        vm.prank(STAKER1);
        staking.stakeLocked(SILVER_THRESHOLD, 90 days);
        
        (StakingTiers.Tier tier,,,uint256 multiplier, uint256 votingPower) = 
            staking.getStakerInfo(STAKER1);
            
        assertEq(uint8(tier), uint8(StakingTiers.Tier.Silver));
        assertEq(multiplier, 1000); // 1.0x
        assertEq(votingPower, 1000 ether); // 10000 * 0.1 (1000 basis points)
    }
    
    function test_GoldTier() public {
        vm.prank(STAKER1);
        staking.stakeLocked(GOLD_THRESHOLD, 180 days);
        
        (StakingTiers.Tier tier,,,uint256 multiplier, uint256 votingPower) = 
            staking.getStakerInfo(STAKER1);
            
        assertEq(uint8(tier), uint8(StakingTiers.Tier.Gold));
        assertEq(multiplier, 1250); // 1.25x
        assertEq(votingPower, 7500 ether); // 50000 * 0.15 (1500 basis points)
    }
    
    function test_PlatinumTier() public {
        vm.prank(STAKER1);
        staking.stakeLocked(PLATINUM_THRESHOLD, 365 days);
        
        (StakingTiers.Tier tier,,,uint256 multiplier, uint256 votingPower) = 
            staking.getStakerInfo(STAKER1);
            
        assertEq(uint8(tier), uint8(StakingTiers.Tier.Platinum));
        assertEq(multiplier, 1500); // 1.5x
        assertEq(votingPower, 20000 ether); // 100000 * 0.2 (2000 basis points)
    }
    
    function test_InsufficientAmountForTier() public {
        // Try to stake less than Bronze minimum with any lock
        vm.prank(STAKER1);
        vm.expectRevert("Insufficient amount for tier");
        staking.stakeLocked(1000 ether, 30 days); // Less than Bronze minimum
    }
    
    function test_CannotUnstakeBeforeLock() public {
        vm.prank(STAKER1);
        staking.stakeLocked(SILVER_THRESHOLD, 90 days);
        
        // Try to unstake immediately
        vm.prank(STAKER1);
        vm.expectRevert("Still locked");
        staking.unstake(SILVER_THRESHOLD);
        
        // Fast forward past lock
        vm.warp(block.timestamp + 91 days);
        
        // Now can unstake
        vm.prank(STAKER1);
        staking.unstake(SILVER_THRESHOLD);
        
        (,uint256 stakedAmount,,,) = staking.getStakerInfo(STAKER1);
        assertEq(stakedAmount, 0);
    }
    
    function test_PartialUnstake() public {
        // Flexible stake allows partial unstake
        vm.prank(STAKER1);
        staking.stakeFlexible(10000 ether);
        
        vm.prank(STAKER1);
        staking.unstake(5000 ether);
        
        (,uint256 stakedAmount,,,) = staking.getStakerInfo(STAKER1);
        assertEq(stakedAmount, 5000 ether);
    }
    
    function test_TierDowngrade() public {
        // Start at Gold
        vm.prank(STAKER1);
        staking.stakeLocked(GOLD_THRESHOLD, 180 days);
        
        // Fast forward and unstake some
        vm.warp(block.timestamp + 181 days);
        vm.prank(STAKER1);
        staking.unstake(45000 ether); // Leave 5000 (Bronze level)
        
        (StakingTiers.Tier tier,,,,) = staking.getStakerInfo(STAKER1);
        assertEq(uint8(tier), uint8(StakingTiers.Tier.Bronze));
    }
    
    function test_CompoundStaking() public {
        // Initial stake
        vm.prank(STAKER1);
        staking.stakeFlexible(10000 ether);
        
        // Add more stake
        vm.prank(STAKER1);
        staking.addStake(5000 ether);
        
        (,uint256 stakedAmount,,,) = staking.getStakerInfo(STAKER1);
        assertEq(stakedAmount, 15000 ether);
    }
    
    function test_EmergencyUnstake() public {
        // Lock stake
        vm.prank(STAKER1);
        staking.stakeLocked(GOLD_THRESHOLD, 180 days);
        
        // Emergency unstake with penalty
        uint256 balanceBefore = fab.balanceOf(STAKER1);
        
        vm.prank(STAKER1);
        staking.emergencyUnstake();
        
        // Should receive 90% (10% penalty)
        assertEq(fab.balanceOf(STAKER1) - balanceBefore, 45000 ether);
        
        (,uint256 stakedAmount,,,) = staking.getStakerInfo(STAKER1);
        assertEq(stakedAmount, 0);
    }
    
    function test_StakingMetrics() public {
        // Multiple stakers at different tiers
        vm.prank(STAKER1);
        staking.stakeFlexible(1000 ether);
        
        vm.prank(STAKER2);
        staking.stakeLocked(SILVER_THRESHOLD, 90 days);
        
        vm.prank(STAKER3);
        staking.stakeLocked(GOLD_THRESHOLD, 180 days);
        
        (
            uint256 totalStaked,
            uint256 totalVotingPower,
            uint256 averageMultiplier,
            uint256[5] memory tierCounts
        ) = staking.getGlobalMetrics();
        
        assertEq(totalStaked, 61000 ether);
        assertEq(tierCounts[0], 1); // 1 flexible
        assertEq(tierCounts[2], 1); // 1 silver
        assertEq(tierCounts[3], 1); // 1 gold
    }
    
    function test_RewardBoost() public {
        // Stake at different tiers
        vm.prank(STAKER1);
        staking.stakeFlexible(10000 ether);
        
        vm.prank(STAKER2);
        staking.stakeLocked(PLATINUM_THRESHOLD, 365 days);
        
        // Calculate reward shares
        uint256 rewardPool = 1000 ether;
        
        uint256 staker1Share = staking.calculateRewardShare(STAKER1, rewardPool);
        uint256 staker2Share = staking.calculateRewardShare(STAKER2, rewardPool);
        
        // STAKER2 has 10x more stake, so should get approximately 10x more rewards
        assertApproxEqAbs(staker2Share, staker1Share * 10, 10);
    }
}