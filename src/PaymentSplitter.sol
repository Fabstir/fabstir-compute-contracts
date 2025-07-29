// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentSplitter is ReentrancyGuard, Ownable {
    address public protocolTreasury; // Now points to TreasuryManager
    address public stakersPool;
    
    uint256 public protocolFeeBasisPoints = 1000; // 10% - goes to TreasuryManager for splitting
    uint256 public stakersFeeBasisPoints = 500; // 5%
    uint256 public constant MAX_TOTAL_FEE = 3000; // 30%
    uint256 public constant BASIS_POINTS = 10000;
    
    event PaymentSplit(
        uint256 indexed jobId,
        address indexed token,
        uint256 totalAmount,
        uint256 hostAmount,
        uint256 protocolAmount,
        uint256 stakersAmount
    );
    
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event StakersFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event StakersPoolUpdated(address oldPool, address newPool);
    
    constructor(address _protocolTreasury, address _stakersPool) Ownable(msg.sender) {
        require(_protocolTreasury != address(0), "Invalid treasury");
        require(_stakersPool != address(0), "Invalid stakers pool");
        protocolTreasury = _protocolTreasury;
        stakersPool = _stakersPool;
    }
    
    function splitPayment(
        uint256 jobId,
        uint256 amount,
        address host,
        address token
    ) external payable nonReentrant {
        _splitPaymentInternal(jobId, amount, host, token);
    }
    
    function _splitPaymentInternal(
        uint256 jobId,
        uint256 amount,
        address host,
        address token
    ) private {
        require(amount > 0, "Amount must be greater than zero");
        require(host != address(0), "Invalid host address");
        
        (uint256 hostAmount, uint256 protocolAmount, uint256 stakersAmount) = getPaymentBreakdown(amount);
        
        if (token == address(0)) {
            // ETH payment
            require(address(this).balance >= amount, "Insufficient ETH balance");
            
            (bool successHost,) = payable(host).call{value: hostAmount}("");
            require(successHost, "ETH transfer to host failed");
            
            (bool successProtocol,) = payable(protocolTreasury).call{value: protocolAmount}("");
            require(successProtocol, "ETH transfer to protocol failed");
            
            (bool successStakers,) = payable(stakersPool).call{value: stakersAmount}("");
            require(successStakers, "ETH transfer to stakers failed");
        } else {
            // ERC20 payment
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.balanceOf(address(this)) >= amount, "Insufficient token balance");
            
            require(tokenContract.transfer(host, hostAmount), "Token transfer to host failed");
            // Transfer to TreasuryManager and let it pull the tokens
            require(tokenContract.transfer(protocolTreasury, protocolAmount), "Token transfer to protocol failed");
            require(tokenContract.transfer(stakersPool, stakersAmount), "Token transfer to stakers failed");
        }
        
        emit PaymentSplit(jobId, token, amount, hostAmount, protocolAmount, stakersAmount);
    }
    
    function batchSplitPayments(
        uint256[] calldata jobIds,
        uint256[] calldata amounts,
        address[] calldata hosts,
        address token
    ) external payable nonReentrant {
        require(jobIds.length == amounts.length && amounts.length == hosts.length, "Array length mismatch");
        
        for (uint256 i = 0; i < jobIds.length; i++) {
            _splitPaymentInternal(jobIds[i], amounts[i], hosts[i], token);
        }
    }
    
    function getPaymentBreakdown(uint256 amount) public view returns (
        uint256 hostAmount,
        uint256 protocolAmount,
        uint256 stakersAmount
    ) {
        protocolAmount = (amount * protocolFeeBasisPoints) / BASIS_POINTS;
        stakersAmount = (amount * stakersFeeBasisPoints) / BASIS_POINTS;
        hostAmount = amount - protocolAmount - stakersAmount;
    }
    
    function updateProtocolFee(uint256 newFeeBasisPoints) external onlyOwner {
        require(newFeeBasisPoints + stakersFeeBasisPoints <= MAX_TOTAL_FEE, "Total fees exceed maximum");
        uint256 oldFee = protocolFeeBasisPoints;
        protocolFeeBasisPoints = newFeeBasisPoints;
        emit ProtocolFeeUpdated(oldFee, newFeeBasisPoints);
    }
    
    function updateStakersFee(uint256 newFeeBasisPoints) external onlyOwner {
        require(protocolFeeBasisPoints + newFeeBasisPoints <= MAX_TOTAL_FEE, "Total fees exceed maximum");
        uint256 oldFee = stakersFeeBasisPoints;
        stakersFeeBasisPoints = newFeeBasisPoints;
        emit StakersFeeUpdated(oldFee, newFeeBasisPoints);
    }
    
    function updateProtocolTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury");
        address oldTreasury = protocolTreasury;
        protocolTreasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    function updateStakersPool(address newPool) external onlyOwner {
        require(newPool != address(0), "Invalid pool");
        address oldPool = stakersPool;
        stakersPool = newPool;
        emit StakersPoolUpdated(oldPool, newPool);
    }
}