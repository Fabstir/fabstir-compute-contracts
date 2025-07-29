// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface IFABBuyback {
    function executeBuybackFromTreasury(uint256 usdcAmount) external;
}

contract TreasuryManager is ReentrancyGuard, AccessControl, Pausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");
    
    // Fund allocation percentages (out of 1000 basis points = 10% total treasury)
    uint256 public constant DEVELOPMENT_FUND_BASIS_POINTS = 300; // 3% of total (30% of treasury)
    uint256 public constant ECOSYSTEM_GROWTH_BASIS_POINTS = 200; // 2% of total (20% of treasury)
    uint256 public constant INSURANCE_SECURITY_BASIS_POINTS = 200; // 2% of total (20% of treasury)
    uint256 public constant BUYBACK_BURN_BASIS_POINTS = 200; // 2% of total (20% of treasury)
    uint256 public constant FUTURE_RESERVE_BASIS_POINTS = 100; // 1% of total (10% of treasury)
    
    uint256 public constant TREASURY_TOTAL_BASIS_POINTS = 1000; // 10% total
    uint256 public constant BASIS_POINTS = 10000;
    
    // Fund addresses
    address public developmentFund;
    address public ecosystemGrowthFund;
    address public insuranceSecurityFund;
    address public fabBuyback;
    address public futureReserveFund;
    
    // Token addresses
    address public fabToken;
    address public usdcToken;
    
    // Tracking
    mapping(address => uint256) public totalReceived; // token => amount
    mapping(address => mapping(address => uint256)) public fundBalances; // fund => token => amount
    
    // Cumulative tracking
    mapping(address => uint256) public cumulativeDevelopment;
    mapping(address => uint256) public cumulativeEcosystem;
    mapping(address => uint256) public cumulativeInsurance;
    mapping(address => uint256) public cumulativeBuyback;
    mapping(address => uint256) public cumulativeReserve;
    
    event FundsReceived(
        address indexed token,
        uint256 amount,
        address indexed from
    );
    
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
    
    event FundAddressUpdated(
        string fundName,
        address oldAddress,
        address newAddress
    );
    
    event BuybackExecuted(
        address indexed token,
        uint256 amount
    );
    
    constructor(
        address _developmentFund,
        address _ecosystemGrowthFund,
        address _insuranceSecurityFund,
        address _fabBuyback,
        address _futureReserveFund,
        address _admin
    ) AccessControl() Pausable() {
        require(_developmentFund != address(0), "Invalid development fund");
        require(_ecosystemGrowthFund != address(0), "Invalid ecosystem fund");
        require(_insuranceSecurityFund != address(0), "Invalid insurance fund");
        require(_fabBuyback != address(0), "Invalid buyback contract");
        require(_futureReserveFund != address(0), "Invalid reserve fund");
        require(_admin != address(0), "Invalid admin");
        
        developmentFund = _developmentFund;
        ecosystemGrowthFund = _ecosystemGrowthFund;
        insuranceSecurityFund = _insuranceSecurityFund;
        fabBuyback = _fabBuyback;
        futureReserveFund = _futureReserveFund;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(WITHDRAWER_ROLE, _admin);
    }
    
    // Process funds that have been sent to this contract
    function processFunds(address token) external nonReentrant whenNotPaused {
        uint256 amount;
        
        if (token == address(0)) {
            amount = address(this).balance;
        } else {
            amount = IERC20(token).balanceOf(address(this));
        }
        
        // Calculate already processed amount
        uint256 alreadyProcessed = 
            fundBalances[developmentFund][token] +
            fundBalances[ecosystemGrowthFund][token] +
            fundBalances[insuranceSecurityFund][token] +
            fundBalances[fabBuyback][token] +
            fundBalances[futureReserveFund][token];
            
        uint256 unprocessedAmount = amount - alreadyProcessed;
        require(unprocessedAmount > 0, "No new funds to process");
        
        totalReceived[token] += unprocessedAmount;
        emit FundsReceived(token, unprocessedAmount, msg.sender);
        
        // Distribute to sub-funds
        _distributeFunds(token, unprocessedAmount);
    }
    
    function _distributeFunds(address token, uint256 amount) private {
        // Calculate allocations
        uint256 developmentAmount = (amount * DEVELOPMENT_FUND_BASIS_POINTS) / TREASURY_TOTAL_BASIS_POINTS;
        uint256 ecosystemAmount = (amount * ECOSYSTEM_GROWTH_BASIS_POINTS) / TREASURY_TOTAL_BASIS_POINTS;
        uint256 insuranceAmount = (amount * INSURANCE_SECURITY_BASIS_POINTS) / TREASURY_TOTAL_BASIS_POINTS;
        uint256 buybackAmount = (amount * BUYBACK_BURN_BASIS_POINTS) / TREASURY_TOTAL_BASIS_POINTS;
        uint256 reserveAmount = (amount * FUTURE_RESERVE_BASIS_POINTS) / TREASURY_TOTAL_BASIS_POINTS;
        
        // Handle rounding
        uint256 distributed = developmentAmount + ecosystemAmount + insuranceAmount + buybackAmount + reserveAmount;
        if (distributed < amount) {
            developmentAmount += amount - distributed; // Add remainder to development
        }
        
        // Update balances
        fundBalances[developmentFund][token] += developmentAmount;
        fundBalances[ecosystemGrowthFund][token] += ecosystemAmount;
        fundBalances[insuranceSecurityFund][token] += insuranceAmount;
        fundBalances[fabBuyback][token] += buybackAmount;
        fundBalances[futureReserveFund][token] += reserveAmount;
        
        // Update cumulative tracking
        cumulativeDevelopment[token] += developmentAmount;
        cumulativeEcosystem[token] += ecosystemAmount;
        cumulativeInsurance[token] += insuranceAmount;
        cumulativeBuyback[token] += buybackAmount;
        cumulativeReserve[token] += reserveAmount;
        
        emit FundsDistributed(
            token,
            amount,
            developmentAmount,
            ecosystemAmount,
            insuranceAmount,
            buybackAmount,
            reserveAmount
        );
    }
    
    // Withdraw funds to designated addresses
    function withdrawFund(
        address fund,
        address token,
        uint256 amount,
        address recipient
    ) external nonReentrant onlyRole(WITHDRAWER_ROLE) whenNotPaused {
        require(
            fund == developmentFund ||
            fund == ecosystemGrowthFund ||
            fund == insuranceSecurityFund ||
            fund == futureReserveFund,
            "Invalid fund"
        );
        require(fund != fabBuyback, "Use executeBuyback for buyback funds");
        require(amount > 0, "Amount must be greater than zero");
        require(fundBalances[fund][token] >= amount, "Insufficient balance");
        require(recipient != address(0), "Invalid recipient");
        
        fundBalances[fund][token] -= amount;
        
        if (token == address(0)) {
            (bool success,) = payable(recipient).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).transfer(recipient, amount);
        }
        
        emit FundWithdrawn(fund, token, amount, recipient);
    }
    
    // Execute buyback with accumulated funds
    function executeBuyback(address token) external nonReentrant whenNotPaused {
        require(token != address(0), "ETH buyback not supported");
        uint256 amount = fundBalances[fabBuyback][token];
        require(amount > 0, "No funds available for buyback");
        
        fundBalances[fabBuyback][token] = 0;
        
        // Approve FABBuyback contract
        IERC20(token).approve(fabBuyback, amount);
        
        // Transfer to FABBuyback
        IERC20(token).transfer(fabBuyback, amount);
        
        // Execute buyback
        IFABBuyback(fabBuyback).executeBuybackFromTreasury(amount);
        
        emit BuybackExecuted(token, amount);
    }
    
    // Direct FAB burn (when receiving FAB tokens)
    function burnFAB() external nonReentrant whenNotPaused {
        require(fabToken != address(0), "FAB token not set");
        uint256 amount = fundBalances[fabBuyback][fabToken];
        require(amount > 0, "No FAB to burn");
        
        fundBalances[fabBuyback][fabToken] = 0;
        
        // Burn FAB directly
        IERC20(fabToken).transfer(address(0x000000000000000000000000000000000000dEaD), amount);
        
        emit BuybackExecuted(fabToken, amount);
    }
    
    // Set token addresses
    function setTokenAddresses(address _fabToken, address _usdcToken) external onlyRole(ADMIN_ROLE) {
        require(_fabToken != address(0), "Invalid FAB token");
        require(_usdcToken != address(0), "Invalid USDC token");
        fabToken = _fabToken;
        usdcToken = _usdcToken;
    }
    
    // Admin functions
    function updateDevelopmentFund(address newFund) external onlyRole(ADMIN_ROLE) {
        require(newFund != address(0), "Invalid address");
        
        // Transfer existing balance to new fund
        address oldFund = developmentFund;
        developmentFund = newFund;
        
        // Transfer all token balances
        _transferFundBalances(oldFund, newFund);
        
        emit FundAddressUpdated("Development", oldFund, newFund);
    }
    
    function updateEcosystemFund(address newFund) external onlyRole(ADMIN_ROLE) {
        require(newFund != address(0), "Invalid address");
        
        address oldFund = ecosystemGrowthFund;
        ecosystemGrowthFund = newFund;
        
        _transferFundBalances(oldFund, newFund);
        
        emit FundAddressUpdated("Ecosystem", oldFund, newFund);
    }
    
    function updateInsuranceFund(address newFund) external onlyRole(ADMIN_ROLE) {
        require(newFund != address(0), "Invalid address");
        
        address oldFund = insuranceSecurityFund;
        insuranceSecurityFund = newFund;
        
        _transferFundBalances(oldFund, newFund);
        
        emit FundAddressUpdated("Insurance", oldFund, newFund);
    }
    
    function updateReserveFund(address newFund) external onlyRole(ADMIN_ROLE) {
        require(newFund != address(0), "Invalid address");
        
        address oldFund = futureReserveFund;
        futureReserveFund = newFund;
        
        _transferFundBalances(oldFund, newFund);
        
        emit FundAddressUpdated("Reserve", oldFund, newFund);
    }
    
    function updateFABBuyback(address newBuyback) external onlyRole(ADMIN_ROLE) {
        require(newBuyback != address(0), "Invalid address");
        
        address oldBuyback = fabBuyback;
        fabBuyback = newBuyback;
        
        _transferFundBalances(oldBuyback, newBuyback);
        
        emit FundAddressUpdated("Buyback", oldBuyback, newBuyback);
    }
    
    function _transferFundBalances(address oldFund, address newFund) private {
        // This is a placeholder - in production, you'd enumerate all tokens
        // For now, we'll handle this case-by-case when updating funds
    }
    
    // Emergency functions
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    // View functions
    function getFundBalance(address fund, address token) external view returns (uint256) {
        return fundBalances[fund][token];
    }
    
    function getAllocations() external pure returns (
        uint256 development,
        uint256 ecosystem,
        uint256 insurance,
        uint256 buyback,
        uint256 reserve
    ) {
        return (
            DEVELOPMENT_FUND_BASIS_POINTS,
            ECOSYSTEM_GROWTH_BASIS_POINTS,
            INSURANCE_SECURITY_BASIS_POINTS,
            BUYBACK_BURN_BASIS_POINTS,
            FUTURE_RESERVE_BASIS_POINTS
        );
    }
    
    function getCumulativeAmounts(address token) external view returns (
        uint256 development,
        uint256 ecosystem,
        uint256 insurance,
        uint256 buyback,
        uint256 reserve
    ) {
        return (
            cumulativeDevelopment[token],
            cumulativeEcosystem[token],
            cumulativeInsurance[token],
            cumulativeBuyback[token],
            cumulativeReserve[token]
        );
    }
    
    // Receive ETH
    receive() external payable {
        // ETH received will be processed when processFunds is called
    }
}