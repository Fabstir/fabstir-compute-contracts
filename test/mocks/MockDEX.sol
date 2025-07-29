// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MockDEX {
    address public fabToken;
    address public usdcToken;
    uint256 public currentPrice; // Price of 1 FAB in USDC (6 decimals)
    uint256[] public priceHistory;
    uint256 public constant FAB_DECIMALS = 18;
    uint256 public constant USDC_DECIMALS = 6;
    
    constructor(address _fab, address _usdc) {
        fabToken = _fab;
        usdcToken = _usdc;
    }
    
    function setPrice(uint256 _price) external {
        currentPrice = _price;
        priceHistory.push(_price);
    }
    
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        require(tokenIn == usdcToken && tokenOut == fabToken, "Only USDC->FAB swaps supported");
        
        // Calculate FAB amount based on price
        // amountIn is in USDC (6 decimals), currentPrice is USDC per FAB (6 decimals)
        // amountOut = (amountIn * 10^18) / currentPrice
        amountOut = (amountIn * 10**FAB_DECIMALS) / currentPrice;
        
        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
        return amountOut;
    }
    
    function getTWAPPrice(uint256 /* periods */) external view returns (uint256) {
        // Mock TWAP - return current price for simplicity
        // In real implementation would average over historical prices
        return currentPrice;
    }
}