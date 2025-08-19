// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";

contract ConfigureContracts is Script {
    // Deployed contract addresses on Base Sepolia
    address constant JOB_MARKETPLACE = 0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6;
    address constant PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("CRITICAL: Configuring USDC Contracts");
        console.log("========================================");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get contract instances
        JobMarketplace marketplace = JobMarketplace(JOB_MARKETPLACE);
        PaymentEscrow escrow = PaymentEscrow(payable(PAYMENT_ESCROW));
        
        console.log("\nCurrent Configuration:");
        console.log("JobMarketplace.paymentEscrow:", address(marketplace.paymentEscrow()));
        console.log("JobMarketplace.usdcAddress:", marketplace.usdcAddress());
        console.log("PaymentEscrow.jobMarketplace:", escrow.jobMarketplace());
        
        // 1. Set PaymentEscrow in JobMarketplace
        if (address(marketplace.paymentEscrow()) != PAYMENT_ESCROW) {
            console.log("\n[1/3] Setting PaymentEscrow in JobMarketplace...");
            marketplace.setPaymentEscrow(PAYMENT_ESCROW);
            console.log("[OK] PaymentEscrow set!");
        }
        
        // 2. Set USDC address in JobMarketplace
        if (marketplace.usdcAddress() != USDC_ADDRESS) {
            console.log("\n[2/3] Setting USDC address in JobMarketplace...");
            marketplace.setUsdcAddress(USDC_ADDRESS);
            console.log("[OK] USDC address set!");
        }
        
        // 3. Set JobMarketplace in PaymentEscrow
        if (escrow.jobMarketplace() != JOB_MARKETPLACE) {
            console.log("\n[3/3] Setting JobMarketplace in PaymentEscrow...");
            escrow.setJobMarketplace(JOB_MARKETPLACE);
            console.log("[OK] JobMarketplace set!");
        }
        
        vm.stopBroadcast();
        
        // Verify configuration
        console.log("\n========================================");
        console.log("Verification");
        console.log("========================================");
        
        require(address(marketplace.paymentEscrow()) == PAYMENT_ESCROW, "PaymentEscrow not set!");
        require(marketplace.usdcAddress() == USDC_ADDRESS, "USDC not set!");
        require(escrow.jobMarketplace() == JOB_MARKETPLACE, "JobMarketplace not set!");
        
        console.log("[OK] JobMarketplace.paymentEscrow:", PAYMENT_ESCROW);
        console.log("[OK] JobMarketplace.usdcAddress:", USDC_ADDRESS);
        console.log("[OK] PaymentEscrow.jobMarketplace:", JOB_MARKETPLACE);
        console.log("\nSUCCESS: USDC payments now enabled!");
    }
}