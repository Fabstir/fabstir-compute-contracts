// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFAB {
    function mint(address to, uint256 amount) external;
}

interface IFaucet {
    function drip() external;
}

contract SetupTestTokens is Script {
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant FAB = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    
    address constant TEST_HOST_1 = 0xf1cC3B45e0b41BeEF6f65b30EC6CCbe47a039299;
    address constant TEST_USER_1 = 0x59A4474Fb66Ed2E896D9AB7D87E719d0F8Df0779;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("SETTING UP TEST TOKENS");
        console.log("========================================\n");
        
        // Get USDC from faucet
        console.log("Getting USDC from Base Sepolia faucet...");
        console.log("Visit: https://faucet.circle.com/");
        console.log("Request USDC for:");
        console.log("  TEST_USER_1:", TEST_USER_1);
        console.log("  (Need at least 0.01 USDC)\n");
        
        // For FAB, we need to use a different approach
        console.log("For FAB tokens:");
        console.log("1. The FAB owner (0xBeAbB2a5AeD358aa0bd442Dffd793411519BDc11) needs to transfer tokens");
        console.log("2. Or deploy a new FAB token with mint function");
        
        // Let me check if we can call any functions on existing FAB
        vm.startBroadcast(deployerPrivateKey);
        
        // Try to get some test ETH first
        console.log("\nYou also need Base Sepolia ETH from:");
        console.log("https://docs.base.org/docs/tools/network-faucets/");
        
        vm.stopBroadcast();
    }
}