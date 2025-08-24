// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CheckBalances is Script {
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant FAB = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    
    address constant TEST_HOST_1 = 0xf1cC3B45e0b41BeEF6f65b30EC6CCbe47a039299;
    address constant TEST_USER_1 = 0x59A4474Fb66Ed2E896D9AB7D87E719d0F8Df0779;
    address constant DEPLOYER = 0xC8A3DD60fEF85f93e93cA4f1eab7D6a60CFD7643;
    
    function run() external view {
        IERC20 fab = IERC20(FAB);
        IERC20 usdc = IERC20(USDC);
        
        console.log("========================================");
        console.log("CHECKING TOKEN BALANCES");
        console.log("========================================\n");
        
        console.log("TEST_HOST_1:", TEST_HOST_1);
        console.log("  FAB:", fab.balanceOf(TEST_HOST_1) / 1e18, "tokens");
        console.log("  USDC:", usdc.balanceOf(TEST_HOST_1), "tokens");
        console.log("  ETH:", TEST_HOST_1.balance / 1e18, "ETH");
        
        console.log("\nTEST_USER_1:", TEST_USER_1);
        console.log("  FAB:", fab.balanceOf(TEST_USER_1) / 1e18, "tokens");
        console.log("  USDC:", usdc.balanceOf(TEST_USER_1), "tokens");
        console.log("  ETH:", TEST_USER_1.balance / 1e18, "ETH");
        
        console.log("\nDEPLOYER:", DEPLOYER);
        console.log("  FAB:", fab.balanceOf(DEPLOYER) / 1e18, "tokens");
        console.log("  USDC:", usdc.balanceOf(DEPLOYER), "tokens");
        console.log("  ETH:", DEPLOYER.balance / 1e18, "ETH");
    }
}