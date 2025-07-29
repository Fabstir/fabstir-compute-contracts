// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IDEX {
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);
    function getTWAPPrice(uint256 periods) external view returns (uint256);
}

contract FABBuyback is ReentrancyGuard, Ownable {
    address public immutable fabToken;
    address public immutable usdcToken;
    address public dexRouter;
    address public protocolTreasury;
    address public stakingRewards;
    address public governance;
    
    uint256 public burnRatioBasisPoints = 5000; // 50%
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MINIMUM_BUYBACK = 100 * 10**6; // 100 USDC
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    bool public buybacksPaused;
    bool public twapProtectionEnabled;
    uint256 public maxTwapDeviationBasisPoints = 500; // 5%
    
    // Auto buyback parameters
    bool public autoBuybackEnabled;
    uint256 public autoBuybackThreshold;
    uint256 public autoBuybackFrequency;
    uint256 public lastAutoBuyback;
    
    // Scheduled buyback
    uint256 public scheduledBuybackTime;
    uint256 public scheduledBuybackAmount;
    
    // Metrics
    uint256 public totalBought;
    uint256 public totalBurned;
    uint256 public totalToStaking;
    uint256 public buybackCount;
    uint256 public totalUSDCSpent;
    
    event BuybackExecuted(
        uint256 usdcAmount,
        uint256 fabReceived,
        uint256 fabBurned,
        uint256 fabToStaking
    );
    
    event DirectBurnExecuted(
        uint256 fabAmount
    );
    
    event BuybackScheduled(uint256 timestamp, uint256 amount);
    event AutoBuybackEnabled(uint256 threshold, uint256 frequency);
    event PriceOracleUpdated(address oldOracle, address newOracle);
    event BurnRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event BuybacksPaused();
    event BuybacksUnpaused();
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }
    
    constructor(
        address _fabToken,
        address _usdcToken,
        address _dexRouter,
        address _protocolTreasury,
        address _stakingRewards,
        address _governance
    ) Ownable(msg.sender) {
        fabToken = _fabToken;
        usdcToken = _usdcToken;
        dexRouter = _dexRouter;
        protocolTreasury = _protocolTreasury;
        stakingRewards = _stakingRewards;
        governance = _governance;
    }
    
    function executeBuyback(uint256 usdcAmount) external onlyGovernance nonReentrant {
        require(!buybacksPaused, "Buybacks paused");
        require(usdcAmount >= MINIMUM_BUYBACK, "Amount below minimum");
        require(IERC20(usdcToken).balanceOf(address(this)) >= usdcAmount, "Insufficient USDC balance");
        
        // Approve DEX to spend USDC
        IERC20(usdcToken).approve(dexRouter, usdcAmount);
        
        // Swap USDC for FAB
        uint256 fabReceived = IDEX(dexRouter).swap(usdcToken, fabToken, usdcAmount);
        
        // Calculate split
        uint256 fabToBurn = (fabReceived * burnRatioBasisPoints) / BASIS_POINTS;
        uint256 fabToStaking = fabReceived - fabToBurn;
        
        // Burn FAB
        IERC20(fabToken).transfer(BURN_ADDRESS, fabToBurn);
        
        // Send to staking rewards
        IERC20(fabToken).transfer(stakingRewards, fabToStaking);
        
        // Update metrics
        totalBought += fabReceived;
        totalBurned += fabToBurn;
        totalToStaking += fabToStaking;
        totalUSDCSpent += usdcAmount;
        buybackCount++;
        
        emit BuybackExecuted(usdcAmount, fabReceived, fabToBurn, fabToStaking);
    }
    
    function scheduleBuyback(uint256 timestamp, uint256 amount) external onlyGovernance {
        require(timestamp > block.timestamp, "Timestamp must be in future");
        require(amount >= MINIMUM_BUYBACK, "Amount below minimum");
        
        scheduledBuybackTime = timestamp;
        scheduledBuybackAmount = amount;
        
        emit BuybackScheduled(timestamp, amount);
    }
    
    function executeScheduledBuyback() external nonReentrant {
        require(scheduledBuybackTime > 0 && block.timestamp >= scheduledBuybackTime, "Buyback not yet executable");
        require(scheduledBuybackAmount > 0, "No buyback scheduled");
        
        uint256 amount = scheduledBuybackAmount;
        scheduledBuybackTime = 0;
        scheduledBuybackAmount = 0;
        
        // Execute through internal function to avoid governance check
        _executeBuybackInternal(amount);
    }
    
    function enableAutoBuyback(uint256 threshold, uint256 frequency) external onlyGovernance {
        require(threshold >= MINIMUM_BUYBACK, "Threshold below minimum");
        require(frequency > 0, "Invalid frequency");
        
        autoBuybackEnabled = true;
        autoBuybackThreshold = threshold;
        autoBuybackFrequency = frequency;
        lastAutoBuyback = block.timestamp;
        
        emit AutoBuybackEnabled(threshold, frequency);
    }
    
    function disableAutoBuyback() external onlyGovernance {
        autoBuybackEnabled = false;
    }
    
    function checkAndExecuteAutoBuyback() external nonReentrant {
        require(autoBuybackEnabled, "Auto buyback not enabled");
        require(block.timestamp >= lastAutoBuyback + autoBuybackFrequency, "Too soon");
        
        uint256 balance = IERC20(usdcToken).balanceOf(address(this));
        if (balance >= autoBuybackThreshold) {
            lastAutoBuyback = block.timestamp;
            _executeBuybackInternal(balance - autoBuybackThreshold + MINIMUM_BUYBACK);
        }
    }
    
    function _executeBuybackInternal(uint256 usdcAmount) private {
        require(!buybacksPaused, "Buybacks paused");
        require(usdcAmount >= MINIMUM_BUYBACK, "Amount below minimum");
        require(IERC20(usdcToken).balanceOf(address(this)) >= usdcAmount, "Insufficient USDC balance");
        
        // Approve DEX to spend USDC
        IERC20(usdcToken).approve(dexRouter, usdcAmount);
        
        // Swap USDC for FAB
        uint256 fabReceived = IDEX(dexRouter).swap(usdcToken, fabToken, usdcAmount);
        
        // Calculate split
        uint256 fabToBurn = (fabReceived * burnRatioBasisPoints) / BASIS_POINTS;
        uint256 fabToStaking = fabReceived - fabToBurn;
        
        // Burn FAB
        IERC20(fabToken).transfer(BURN_ADDRESS, fabToBurn);
        
        // Send to staking rewards
        IERC20(fabToken).transfer(stakingRewards, fabToStaking);
        
        // Update metrics
        totalBought += fabReceived;
        totalBurned += fabToBurn;
        totalToStaking += fabToStaking;
        totalUSDCSpent += usdcAmount;
        buybackCount++;
        
        emit BuybackExecuted(usdcAmount, fabReceived, fabToBurn, fabToStaking);
    }
    
    function enableTWAPProtection(bool enabled, uint256 maxDeviation) external onlyGovernance {
        twapProtectionEnabled = enabled;
        maxTwapDeviationBasisPoints = maxDeviation;
    }
    
    function updateBurnRatio(uint256 newRatioBasisPoints) external onlyGovernance {
        require(newRatioBasisPoints <= BASIS_POINTS, "Invalid ratio");
        uint256 oldRatio = burnRatioBasisPoints;
        burnRatioBasisPoints = newRatioBasisPoints;
        emit BurnRatioUpdated(oldRatio, newRatioBasisPoints);
    }
    
    function pauseBuybacks() external onlyGovernance {
        buybacksPaused = true;
        emit BuybacksPaused();
    }
    
    function unpauseBuybacks() external onlyGovernance {
        buybacksPaused = false;
        emit BuybacksUnpaused();
    }
    
    function updateDexRouter(address newRouter) external onlyGovernance {
        require(newRouter != address(0), "Invalid router");
        address oldRouter = dexRouter;
        dexRouter = newRouter;
        emit PriceOracleUpdated(oldRouter, newRouter);
    }
    
    function updateStakingRewards(address newRewards) external onlyGovernance {
        require(newRewards != address(0), "Invalid address");
        stakingRewards = newRewards;
    }
    
    function updateProtocolTreasury(address newTreasury) external onlyGovernance {
        require(newTreasury != address(0), "Invalid treasury");
        protocolTreasury = newTreasury;
    }
    
    function getBuybackMetrics() external view returns (
        uint256 _totalBought,
        uint256 _totalBurned,
        uint256 _totalToStaking,
        uint256 averagePrice,
        uint256 _buybackCount
    ) {
        _totalBought = totalBought;
        _totalBurned = totalBurned;
        _totalToStaking = totalToStaking;
        _buybackCount = buybackCount;
        
        if (_buybackCount > 0 && _totalBought > 0) {
            // Calculate average price in USDC per FAB (6 decimals)
            // totalUSDCSpent is in 6 decimals, totalBought is in 18 decimals
            // We want price in 6 decimals, so: (USDC * 10^18) / FAB = price in 6 decimals
            averagePrice = (totalUSDCSpent * 10**18) / _totalBought;
        }
    }
    
    // Direct burn function for FAB tokens (no DEX swap needed)
    function directBurnFAB(uint256 amount) external nonReentrant {
        require(!buybacksPaused, "Buybacks paused");
        require(amount > 0, "Amount must be greater than zero");
        require(IERC20(fabToken).balanceOf(address(this)) >= amount, "Insufficient FAB balance");
        
        // Burn all FAB directly (100% burn for direct FAB)
        IERC20(fabToken).transfer(BURN_ADDRESS, amount);
        
        // Update metrics
        totalBurned += amount;
        
        emit DirectBurnExecuted(amount);
    }
    
    // Allow TreasuryManager to execute buybacks
    function executeBuybackFromTreasury(uint256 usdcAmount) external nonReentrant {
        require(msg.sender == protocolTreasury, "Only treasury manager");
        _executeBuybackInternal(usdcAmount);
    }
    
    // Emergency function to recover stuck tokens
    function recoverToken(address token, uint256 amount) external onlyGovernance {
        require(token != fabToken && token != usdcToken, "Cannot recover buyback tokens");
        IERC20(token).transfer(governance, amount);
    }
}