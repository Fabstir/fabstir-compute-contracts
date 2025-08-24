// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceFAB.sol";

interface IPaymentEscrowMin {
    function setJobMarketplace(address) external;
}

contract DeployJobMarketplaceFAB is Script {
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("Deploying JobMarketplaceFAB - THE FIX!");
        console.log("========================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy JobMarketplaceFAB
        JobMarketplaceFAB marketplace = new JobMarketplaceFAB(NODE_REGISTRY_FAB);
        console.log("[DEPLOYED] JobMarketplaceFAB:", address(marketplace));
        
        // Configure USDC
        marketplace.setUsdcAddress(USDC);
        console.log("[OK] USDC configured");
        
        // Connect PaymentEscrow
        marketplace.setPaymentEscrow(PAYMENT_ESCROW);
        console.log("[OK] PaymentEscrow connected");
        
        // Update PaymentEscrow to accept this marketplace
        IPaymentEscrowMin escrow = IPaymentEscrowMin(PAYMENT_ESCROW);
        escrow.setJobMarketplace(address(marketplace));
        console.log("[OK] PaymentEscrow updated to accept JobMarketplaceFAB\n");
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("DEPLOYMENT SUCCESSFUL!");
        console.log("========================================");
        console.log("JobMarketplaceFAB:", address(marketplace));
        console.log("NodeRegistryFAB:", NODE_REGISTRY_FAB);
        console.log("PaymentEscrow:", PAYMENT_ESCROW);
        console.log("USDC:", USDC);
        console.log("\n[READY] System is now ready for complete flow test!");
    }
}