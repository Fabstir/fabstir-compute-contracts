// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title HostEarnings
 * @dev Accumulates host earnings from completed jobs to reduce gas costs
 * Hosts can withdraw accumulated earnings in batches instead of receiving payment per job
 */
contract HostEarnings is ReentrancyGuard, Ownable {
    // Earnings tracking: host => token => amount
    // token address(0) represents ETH
    mapping(address => mapping(address => uint256)) private earnings;
    
    // Total accumulated per token (for accounting)
    mapping(address => uint256) public totalAccumulated;
    
    // Total withdrawn per token (for accounting)
    mapping(address => uint256) public totalWithdrawn;
    
    // Authorized contracts that can credit earnings
    mapping(address => bool) public authorizedCallers;
    
    // Events
    event EarningsCredited(
        address indexed host,
        address indexed token,
        uint256 amount,
        uint256 newBalance
    );
    
    event EarningsWithdrawn(
        address indexed host,
        address indexed token,
        uint256 amount,
        uint256 remainingBalance
    );
    
    event CallerAuthorized(address indexed caller, bool authorized);
    
    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender], "Not authorized to credit earnings");
        _;
    }
    
    constructor() Ownable(msg.sender) {}
    
    // Allow contract to receive ETH for accumulation
    // (receive and fallback are already defined below)
    
    /**
     * @dev Authorize a contract (JobMarketplace) to credit earnings
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "Invalid caller address");
        authorizedCallers[caller] = authorized;
        emit CallerAuthorized(caller, authorized);
    }
    
    /**
     * @dev Credit earnings to a host (called by JobMarketplace)
     * @param host The host address to credit
     * @param amount The amount to credit
     * @param token The token address (address(0) for ETH)
     */
    function creditEarnings(
        address host,
        uint256 amount,
        address token
    ) external onlyAuthorized nonReentrant {
        require(host != address(0), "Invalid host address");
        require(amount > 0, "Amount must be positive");
        
        earnings[host][token] += amount;
        totalAccumulated[token] += amount;
        
        emit EarningsCredited(host, token, amount, earnings[host][token]);
    }
    
    /**
     * @dev Get the balance of a host for a specific token
     * @param host The host address
     * @param token The token address (address(0) for ETH)
     * @return The accumulated balance
     */
    function getBalance(address host, address token) external view returns (uint256) {
        return earnings[host][token];
    }
    
    /**
     * @dev Withdraw a specific amount of earnings
     * @param amount The amount to withdraw
     * @param token The token to withdraw (address(0) for ETH)
     */
    function withdraw(uint256 amount, address token) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(earnings[msg.sender][token] >= amount, "Insufficient earnings");
        
        earnings[msg.sender][token] -= amount;
        totalWithdrawn[token] += amount;
        
        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).transfer(msg.sender, amount);
        }
        
        emit EarningsWithdrawn(
            msg.sender,
            token,
            amount,
            earnings[msg.sender][token]
        );
    }
    
    /**
     * @dev Withdraw all accumulated earnings for a specific token
     * @param token The token to withdraw (address(0) for ETH)
     */
    function withdrawAll(address token) external nonReentrant {
        uint256 amount = earnings[msg.sender][token];
        require(amount > 0, "No earnings to withdraw");
        
        earnings[msg.sender][token] = 0;
        totalWithdrawn[token] += amount;
        
        if (token == address(0)) {
            // ETH withdrawal
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 withdrawal
            IERC20(token).transfer(msg.sender, amount);
        }
        
        emit EarningsWithdrawn(msg.sender, token, amount, 0);
    }
    
    /**
     * @dev Withdraw multiple tokens at once
     * @param tokens Array of token addresses to withdraw
     */
    function withdrawMultiple(address[] calldata tokens) external nonReentrant {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amount = earnings[msg.sender][tokens[i]];
            if (amount > 0) {
                earnings[msg.sender][tokens[i]] = 0;
                totalWithdrawn[tokens[i]] += amount;
                
                if (tokens[i] == address(0)) {
                    // ETH withdrawal
                    (bool success, ) = payable(msg.sender).call{value: amount}("");
                    require(success, "ETH transfer failed");
                } else {
                    // ERC20 withdrawal
                    IERC20(tokens[i]).transfer(msg.sender, amount);
                }
                
                emit EarningsWithdrawn(msg.sender, tokens[i], amount, 0);
            }
        }
    }
    
    
    /**
     * @dev Get multiple token balances for a host
     * @param host The host address
     * @param tokens Array of token addresses
     * @return balances Array of corresponding balances
     */
    function getBalances(
        address host,
        address[] calldata tokens
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = earnings[host][tokens[i]];
        }
    }
    
    /**
     * @dev Emergency function to rescue stuck tokens (owner only)
     * Should only be used if tokens are accidentally sent directly to contract
     */
    function rescueTokens(
        address token,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "Amount must be positive");
        
        if (token == address(0)) {
            // Rescue ETH
            uint256 contractBalance = address(this).balance;
            uint256 totalOwed = totalAccumulated[token] - totalWithdrawn[token];
            require(contractBalance > totalOwed, "No excess ETH to rescue");
            uint256 rescueable = contractBalance - totalOwed;
            require(amount <= rescueable, "Amount exceeds rescueable balance");
            
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH rescue failed");
        } else {
            // Rescue ERC20
            uint256 contractBalance = IERC20(token).balanceOf(address(this));
            uint256 totalOwed = totalAccumulated[token] - totalWithdrawn[token];
            require(contractBalance > totalOwed, "No excess tokens to rescue");
            uint256 rescueable = contractBalance - totalOwed;
            require(amount <= rescueable, "Amount exceeds rescueable balance");
            
            IERC20(token).transfer(owner(), amount);
        }
    }
    
    /**
     * @dev Receive ETH when JobMarketplace or PaymentEscrow sends it
     */
    receive() external payable {
        // Accept ETH transfers
    }
    
    /**
     * @dev Get statistics for a token
     */
    function getTokenStats(address token) external view returns (
        uint256 accumulated,
        uint256 withdrawn,
        uint256 outstanding
    ) {
        accumulated = totalAccumulated[token];
        withdrawn = totalWithdrawn[token];
        outstanding = accumulated - withdrawn;
    }
}