// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceFAB.sol";

contract DeployFinalJobMarketplaceFAB is Script {
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant NEW_PAYMENT_ESCROW = 0x240258A70E1DBAC442202a74739F0e6dC16ef558;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("DEPLOYING FINAL JOBMARKETPLACEFAB");
        console.log("========================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy JobMarketplaceFAB
        JobMarketplaceFAB marketplace = new JobMarketplaceFAB(NODE_REGISTRY_FAB);
        console.log("[DEPLOYED] JobMarketplaceFAB:", address(marketplace));
        
        // Configure USDC
        marketplace.setUsdcAddress(USDC);
        console.log("[OK] USDC configured");
        
        // Connect NEW PaymentEscrow
        marketplace.setPaymentEscrow(NEW_PAYMENT_ESCROW);
        console.log("[OK] NEW PaymentEscrow connected");
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("FINAL DEPLOYMENT COMPLETE!");
        console.log("========================================");
        console.log("JobMarketplaceFAB:", address(marketplace));
        console.log("NodeRegistryFAB:", NODE_REGISTRY_FAB);
        console.log("PaymentEscrow:", NEW_PAYMENT_ESCROW);
        console.log("USDC:", USDC);
        console.log("\n[READY] System is now ready for complete payment flow!");
    }
}