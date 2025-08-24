// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VerifyCompleteFlow is Script {
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant FAB = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    address constant TEST_HOST_1 = 0xf1cC3B45e0b41BeEF6f65b30EC6CCbe47a039299;
    
    function run() external view {
        IERC20 usdc = IERC20(USDC);
        IERC20 fab = IERC20(FAB);
        
        console.log("=== ACTUAL BALANCE VERIFICATION ===\n");
        
        // Original host address that was funded
        address originalHost = 0x4594F755F593B517Bb3194F4DeC20C48a3f04504;
        
        console.log("HOST ADDRESSES:");
        console.log("TEST_HOST_1:", TEST_HOST_1);
        console.log("Original Host:", originalHost);
        
        console.log("\nCURRENT BALANCES:");
        console.log("TEST_HOST_1 FAB:", fab.balanceOf(TEST_HOST_1));
        console.log("TEST_HOST_1 USDC:", usdc.balanceOf(TEST_HOST_1));
        
        console.log("\nOriginal Host FAB:", fab.balanceOf(originalHost));
        console.log("Original Host USDC:", usdc.balanceOf(originalHost));
        
        console.log("\n=== COMMANDS TO VERIFY ===");
        console.log("Check FAB balance:");
        console.log("cast call 0xC78949004B4EB6dEf2D66e49Cd81231472612D62 \"balanceOf(address)\" \"0x4594F755F593B517Bb3194F4DeC20C48a3f04504\" --rpc-url https://sepolia.base.org | cast to-dec");
        
        console.log("\nCheck USDC balance:");
        console.log("cast call 0x036CbD53842c5426634e7929541eC2318f3dCF7e \"balanceOf(address)\" \"0x4594F755F593B517Bb3194F4DeC20C48a3f04504\" --rpc-url https://sepolia.base.org | cast to-dec");
    }
}