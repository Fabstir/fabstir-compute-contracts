// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PaymentEscrow.sol";

contract DeployNewPaymentEscrow is Script {
    address constant JOB_MARKETPLACE_FAB = 0x1e97FCf16FFDf70610eC01fa800ccdE3896bF1E0;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("DEPLOYING NEW PAYMENT ESCROW");
        console.log("========================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new PaymentEscrow with no arbiter and 1% fee
        PaymentEscrow escrow = new PaymentEscrow(address(0), 100);
        console.log("[DEPLOYED] PaymentEscrow:", address(escrow));
        console.log("[OK] Fee set to 1% (100 basis points)");
        
        // Set JobMarketplace
        escrow.setJobMarketplace(JOB_MARKETPLACE_FAB);
        console.log("[OK] JobMarketplace set to:", JOB_MARKETPLACE_FAB);
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("NEW PAYMENT ESCROW READY!");
        console.log("========================================");
        console.log("PaymentEscrow:", address(escrow));
        console.log("\nNext step: Update JobMarketplaceFAB to use this escrow");
    }
}