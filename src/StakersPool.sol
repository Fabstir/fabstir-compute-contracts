// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakersPool is ReentrancyGuard, Ownable {
    address public immutable stakingToken;
    address public paymentSplitter;
    
    uint256 public totalStaked;
    uint256 public constant MINIMUM_STAKE = 100 ether; // 100 FAB minimum
    
    struct StakerInfo {
        uint256 stakedAmount;
        mapping(address => uint256) rewardDebt; // Reward debt per token
    }
    
    struct RewardInfo {
        uint256 accumulatedPerShare; // Accumulated rewards per share
        uint256 totalDistributed;
    }
    
    mapping(address => StakerInfo) public stakers;
    mapping(address => RewardInfo) public rewardTokens;
    address[] public rewardTokenList;
    
    event StakeUpdated(
        address indexed staker,
        uint256 newStake,
        uint256 totalStaked
    );
    
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
    
    event EmergencyWithdraw(address indexed staker, uint256 amount);
    
    modifier onlyPaymentSplitter() {
        require(msg.sender == paymentSplitter, "Only payment splitter");
        _;
    }
    
    constructor(address _stakingToken, address _paymentSplitter) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid staking token");
        require(_paymentSplitter != address(0), "Invalid payment splitter");
        stakingToken = _stakingToken;
        paymentSplitter = _paymentSplitter;
    }
    
    function updateStake(uint256 newAmount) external nonReentrant {
        require(newAmount == 0 || newAmount >= MINIMUM_STAKE, "Below minimum stake");
        
        StakerInfo storage staker = stakers[msg.sender];
        uint256 oldAmount = staker.stakedAmount;
        
        if (newAmount > oldAmount) {
            // Increasing stake
            uint256 difference = newAmount - oldAmount;
            IERC20(stakingToken).transferFrom(msg.sender, address(this), difference);
        } else if (newAmount < oldAmount) {
            // Decreasing stake
            uint256 difference = oldAmount - newAmount;
            IERC20(stakingToken).transfer(msg.sender, difference);
        }
        
        // Update state
        staker.stakedAmount = newAmount;
        totalStaked = totalStaked - oldAmount + newAmount;
        
        // Update reward debt for all tokens to lock in current pending rewards
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address token = rewardTokenList[i];
            RewardInfo storage rewardInfo = rewardTokens[token];
            
            if (oldAmount > 0) {
                // Calculate pending rewards before updating
                uint256 accumulatedReward = (oldAmount * rewardInfo.accumulatedPerShare) / 1e18;
                uint256 pending = accumulatedReward - staker.rewardDebt[token];
                
                // Update debt to include old pending + new accumulation on new stake
                staker.rewardDebt[token] = (newAmount * rewardInfo.accumulatedPerShare) / 1e18 - pending;
            } else {
                // No previous stake, just set debt based on current accumulation
                staker.rewardDebt[token] = (newAmount * rewardInfo.accumulatedPerShare) / 1e18;
            }
        }
        
        emit StakeUpdated(msg.sender, newAmount, totalStaked);
    }
    
    function distributeRewards(address token, uint256 amount) external onlyPaymentSplitter nonReentrant {
        require(totalStaked > 0, "No stakers");
        require(amount > 0, "Zero amount");
        
        // Add token to list if new
        RewardInfo storage rewardInfo = rewardTokens[token];
        if (rewardInfo.totalDistributed == 0) {
            rewardTokenList.push(token);
        }
        
        // Calculate reward per share (scaled by 1e18 for precision)
        uint256 rewardPerShare = (amount * 1e18) / totalStaked;
        rewardInfo.accumulatedPerShare += rewardPerShare;
        rewardInfo.totalDistributed += amount;
        
        emit RewardDistributed(token, amount, rewardPerShare);
    }
    
    function pendingRewards(address staker, address token) public view returns (uint256) {
        StakerInfo storage stakerInfo = stakers[staker];
        RewardInfo storage rewardInfo = rewardTokens[token];
        
        if (stakerInfo.stakedAmount == 0) {
            return 0;
        }
        
        uint256 accumulatedReward = (stakerInfo.stakedAmount * rewardInfo.accumulatedPerShare) / 1e18;
        return accumulatedReward - stakerInfo.rewardDebt[token];
    }
    
    function claimReward(address token) external nonReentrant {
        uint256 pending = pendingRewards(msg.sender, token);
        require(pending > 0, "No pending rewards");
        
        StakerInfo storage staker = stakers[msg.sender];
        RewardInfo storage rewardInfo = rewardTokens[token];
        
        // Update reward debt
        staker.rewardDebt[token] = (staker.stakedAmount * rewardInfo.accumulatedPerShare) / 1e18;
        
        // Transfer reward
        IERC20(token).transfer(msg.sender, pending);
        
        emit RewardClaimed(msg.sender, token, pending);
    }
    
    function claimAllRewards() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        require(staker.stakedAmount > 0, "No stake");
        
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            address token = rewardTokenList[i];
            uint256 pending = pendingRewards(msg.sender, token);
            
            if (pending > 0) {
                RewardInfo storage rewardInfo = rewardTokens[token];
                staker.rewardDebt[token] = (staker.stakedAmount * rewardInfo.accumulatedPerShare) / 1e18;
                IERC20(token).transfer(msg.sender, pending);
                emit RewardClaimed(msg.sender, token, pending);
            }
        }
    }
    
    function compoundRewards() external nonReentrant {
        uint256 pending = pendingRewards(msg.sender, stakingToken);
        require(pending > 0, "No FAB rewards to compound");
        
        StakerInfo storage staker = stakers[msg.sender];
        RewardInfo storage rewardInfo = rewardTokens[stakingToken];
        
        // Add rewards to stake
        staker.stakedAmount += pending;
        totalStaked += pending;
        
        // Update reward debt AFTER updating stake to account for the new stake amount
        staker.rewardDebt[stakingToken] = (staker.stakedAmount * rewardInfo.accumulatedPerShare) / 1e18;
        
        emit StakeUpdated(msg.sender, staker.stakedAmount, totalStaked);
        emit RewardClaimed(msg.sender, stakingToken, pending);
    }
    
    function emergencyWithdraw() external nonReentrant {
        StakerInfo storage staker = stakers[msg.sender];
        uint256 amount = staker.stakedAmount;
        require(amount > 0, "No stake");
        
        // Reset staker info (forfeit all pending rewards)
        staker.stakedAmount = 0;
        for (uint256 i = 0; i < rewardTokenList.length; i++) {
            staker.rewardDebt[rewardTokenList[i]] = 0;
        }
        
        totalStaked -= amount;
        
        // Transfer stake back
        IERC20(stakingToken).transfer(msg.sender, amount);
        
        emit EmergencyWithdraw(msg.sender, amount);
    }
    
    
    function getStakedAmount(address staker) external view returns (uint256) {
        return stakers[staker].stakedAmount;
    }
    
    function totalDistributed(address token) external view returns (uint256) {
        return rewardTokens[token].totalDistributed;
    }
    
    function getRewardTokenCount() external view returns (uint256) {
        return rewardTokenList.length;
    }
    
    function getRewardToken(uint256 index) external view returns (address) {
        return rewardTokenList[index];
    }
    
    function updatePaymentSplitter(address newSplitter) external onlyOwner {
        require(newSplitter != address(0), "Invalid splitter");
        paymentSplitter = newSplitter;
    }
}