// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingTiers is ReentrancyGuard, Ownable {
    address public immutable stakingToken;
    address public governance;
    
    enum Tier {
        Flexible,   // 0.5x multiplier, no lock
        Bronze,     // 0.75x multiplier, 30 days lock
        Silver,     // 1.0x multiplier, 90 days lock
        Gold,       // 1.25x multiplier, 180 days lock
        Platinum    // 1.5x multiplier, 365 days lock
    }
    
    struct StakerInfo {
        Tier tier;
        uint256 stakedAmount;
        uint256 lockEndTime;
        uint256 rewardMultiplier; // In basis points (500 = 0.5x)
        uint256 votingPower;
    }
    
    struct TierConfig {
        uint256 minimumStake;
        uint256 lockDuration;
        uint256 rewardMultiplier; // Basis points
        uint256 votingMultiplier; // Basis points
    }
    
    mapping(address => StakerInfo) public stakerInfo;
    mapping(Tier => TierConfig) public tierConfigs;
    
    uint256 public totalStaked;
    uint256 public totalVotingPower;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant EMERGENCY_UNSTAKE_PENALTY = 1000; // 10%
    
    uint256[5] public tierCounts; // Count of stakers in each tier
    
    event TierAchieved(
        address indexed staker,
        Tier tier,
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
    
    event StakeAdded(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event EmergencyUnstake(address indexed staker, uint256 amount, uint256 penalty);
    
    constructor(address _stakingToken, address _governance) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_governance != address(0), "Invalid governance");
        stakingToken = _stakingToken;
        governance = _governance;
        
        // Initialize tier configurations
        tierConfigs[Tier.Flexible] = TierConfig({
            minimumStake: 0,
            lockDuration: 0,
            rewardMultiplier: 500,  // 0.5x
            votingMultiplier: 500   // 0.5x
        });
        
        tierConfigs[Tier.Bronze] = TierConfig({
            minimumStake: 5000 ether,
            lockDuration: 30 days,
            rewardMultiplier: 750,  // 0.75x
            votingMultiplier: 750   // 0.75x
        });
        
        tierConfigs[Tier.Silver] = TierConfig({
            minimumStake: 10000 ether,
            lockDuration: 90 days,
            rewardMultiplier: 1000,  // 1.0x
            votingMultiplier: 1000   // 1.0x
        });
        
        tierConfigs[Tier.Gold] = TierConfig({
            minimumStake: 50000 ether,
            lockDuration: 180 days,
            rewardMultiplier: 1250,  // 1.25x
            votingMultiplier: 1500   // 1.5x voting power
        });
        
        tierConfigs[Tier.Platinum] = TierConfig({
            minimumStake: 100000 ether,
            lockDuration: 365 days,
            rewardMultiplier: 1500,  // 1.5x
            votingMultiplier: 2000   // 2.0x voting power
        });
    }
    
    function stakeFlexible(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        
        StakerInfo storage staker = stakerInfo[msg.sender];
        
        // If already staking, must be flexible tier
        if (staker.stakedAmount > 0) {
            require(staker.tier == Tier.Flexible, "Already locked");
        } else {
            tierCounts[uint256(Tier.Flexible)]++;
        }
        
        // Transfer tokens
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        
        // Update staker info
        uint256 oldMultiplier = staker.rewardMultiplier;
        staker.tier = Tier.Flexible;
        staker.stakedAmount += amount;
        staker.lockEndTime = 0;
        staker.rewardMultiplier = tierConfigs[Tier.Flexible].rewardMultiplier;
        
        // Update voting power
        _updateVotingPower(msg.sender);
        
        totalStaked += amount;
        
        emit TierAchieved(msg.sender, Tier.Flexible, staker.rewardMultiplier);
        if (oldMultiplier != staker.rewardMultiplier) {
            emit RewardMultiplierUpdated(msg.sender, oldMultiplier, staker.rewardMultiplier);
        }
    }
    
    function stakeLocked(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Zero amount");
        
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount == 0, "Already staking");
        
        // Determine tier based on lock duration and amount
        Tier tier = _getTierFromLockDuration(lockDuration, amount);
        TierConfig memory config = tierConfigs[tier];
        
        require(amount >= config.minimumStake, "Insufficient amount for tier");
        
        // Transfer tokens
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        
        // Update staker info
        staker.tier = tier;
        staker.stakedAmount = amount;
        staker.lockEndTime = block.timestamp + lockDuration;
        staker.rewardMultiplier = config.rewardMultiplier;
        
        // Update voting power
        _updateVotingPower(msg.sender);
        
        totalStaked += amount;
        tierCounts[uint256(tier)]++;
        
        emit StakeLocked(msg.sender, amount, lockDuration, staker.lockEndTime);
        emit TierAchieved(msg.sender, tier, staker.rewardMultiplier);
    }
    
    function addStake(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount > 0, "No existing stake");
        
        // Can only add to flexible stakes
        require(staker.tier == Tier.Flexible || block.timestamp >= staker.lockEndTime, "Still locked");
        
        // Transfer tokens
        IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
        
        staker.stakedAmount += amount;
        totalStaked += amount;
        
        // Check if tier upgrade is possible
        _checkTierUpgrade(msg.sender);
        _updateVotingPower(msg.sender);
        
        emit StakeAdded(msg.sender, amount);
    }
    
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        
        StakerInfo storage staker = stakerInfo[msg.sender];
        require(staker.stakedAmount >= amount, "Insufficient stake");
        require(block.timestamp >= staker.lockEndTime, "Still locked");
        
        staker.stakedAmount -= amount;
        totalStaked -= amount;
        
        // Check tier downgrade
        _checkTierDowngrade(msg.sender);
        _updateVotingPower(msg.sender);
        
        // Transfer tokens back
        IERC20(stakingToken).transfer(msg.sender, amount);
        
        emit Unstaked(msg.sender, amount);
    }
    
    function emergencyUnstake() external nonReentrant {
        StakerInfo storage staker = stakerInfo[msg.sender];
        uint256 amount = staker.stakedAmount;
        require(amount > 0, "No stake");
        
        // Calculate penalty
        uint256 penalty = (amount * EMERGENCY_UNSTAKE_PENALTY) / BASIS_POINTS;
        uint256 withdrawAmount = amount - penalty;
        
        // Update state
        totalStaked -= amount;
        totalVotingPower -= staker.votingPower;
        tierCounts[uint256(staker.tier)]--;
        
        // Reset staker info
        delete stakerInfo[msg.sender];
        
        // Transfer tokens (minus penalty)
        IERC20(stakingToken).transfer(msg.sender, withdrawAmount);
        
        // Send penalty to governance
        if (penalty > 0) {
            IERC20(stakingToken).transfer(governance, penalty);
        }
        
        emit EmergencyUnstake(msg.sender, withdrawAmount, penalty);
    }
    
    function getStakerInfo(address staker) external view returns (
        Tier tier,
        uint256 stakedAmount,
        uint256 lockEndTime,
        uint256 rewardMultiplier,
        uint256 votingPower
    ) {
        StakerInfo memory info = stakerInfo[staker];
        return (info.tier, info.stakedAmount, info.lockEndTime, info.rewardMultiplier, info.votingPower);
    }
    
    function calculateRewardShare(address staker, uint256 totalReward) external view returns (uint256) {
        StakerInfo memory info = stakerInfo[staker];
        if (info.stakedAmount == 0 || totalStaked == 0) {
            return 0;
        }
        
        // For simplicity, just return proportional share based on stake
        // In production, this would integrate with the actual reward distribution mechanism
        return (totalReward * info.stakedAmount) / totalStaked;
    }
    
    function getGlobalMetrics() external view returns (
        uint256 _totalStaked,
        uint256 _totalVotingPower,
        uint256 averageMultiplier,
        uint256[5] memory _tierCounts
    ) {
        _totalStaked = totalStaked;
        _totalVotingPower = totalVotingPower;
        _tierCounts = tierCounts;
        
        // Average multiplier calculation would require tracking weighted stakes
        // For now, return 0
        averageMultiplier = 0;
    }
    
    function _getTierFromLockDuration(uint256 lockDuration, uint256 amount) private view returns (Tier) {
        if (lockDuration >= 365 days && amount >= tierConfigs[Tier.Platinum].minimumStake) {
            return Tier.Platinum;
        } else if (lockDuration >= 180 days && amount >= tierConfigs[Tier.Gold].minimumStake) {
            return Tier.Gold;
        } else if (lockDuration >= 90 days && amount >= tierConfigs[Tier.Silver].minimumStake) {
            return Tier.Silver;
        } else if (lockDuration >= 30 days && amount >= tierConfigs[Tier.Bronze].minimumStake) {
            return Tier.Bronze;
        }
        revert("Insufficient amount for tier");
    }
    
    function _checkTierUpgrade(address staker) private {
        StakerInfo storage info = stakerInfo[staker];
        if (info.stakedAmount == 0) return; // No upgrade if no stake
        
        uint256 currentTier = uint256(info.tier);
        
        // Check if eligible for higher tier based on amount
        for (uint256 i = 4; i > currentTier; i--) {
            if (info.stakedAmount >= tierConfigs[Tier(i)].minimumStake && info.lockEndTime == 0) {
                // Upgrade to flexible version of higher tier (no additional lock)
                tierCounts[currentTier]--;
                tierCounts[i]++;
                info.tier = Tier(i);
                
                uint256 oldMultiplier = info.rewardMultiplier;
                info.rewardMultiplier = tierConfigs[Tier(i)].rewardMultiplier;
                
                emit TierAchieved(staker, Tier(i), info.rewardMultiplier);
                emit RewardMultiplierUpdated(staker, oldMultiplier, info.rewardMultiplier);
                break;
            }
        }
    }
    
    function _checkTierDowngrade(address staker) private {
        StakerInfo storage info = stakerInfo[staker];
        uint256 currentTier = uint256(info.tier);
        uint256 newTier = currentTier;
        
        // Find the appropriate tier based on amount
        for (uint256 i = currentTier; i > 0; i--) {
            if (info.stakedAmount < tierConfigs[Tier(i)].minimumStake) {
                newTier = i - 1;
            } else {
                break;
            }
        }
        
        // Update if tier changed
        if (newTier != currentTier) {
            tierCounts[currentTier]--;
            tierCounts[newTier]++;
            info.tier = Tier(newTier);
            
            uint256 oldMultiplier = info.rewardMultiplier;
            info.rewardMultiplier = tierConfigs[Tier(newTier)].rewardMultiplier;
            
            emit TierAchieved(staker, Tier(newTier), info.rewardMultiplier);
            emit RewardMultiplierUpdated(staker, oldMultiplier, info.rewardMultiplier);
        }
    }
    
    function _updateVotingPower(address staker) private {
        StakerInfo storage info = stakerInfo[staker];
        uint256 oldVotingPower = info.votingPower;
        
        TierConfig memory config = tierConfigs[info.tier];
        info.votingPower = (info.stakedAmount * config.votingMultiplier) / BASIS_POINTS;
        
        totalVotingPower = totalVotingPower - oldVotingPower + info.votingPower;
    }
    
    function updateGovernance(address newGovernance) external onlyOwner {
        require(newGovernance != address(0), "Invalid governance");
        governance = newGovernance;
    }
}