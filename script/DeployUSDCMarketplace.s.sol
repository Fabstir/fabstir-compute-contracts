// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/NodeRegistry.sol";
import "../src/PaymentEscrow.sol";

contract DeployUSDCMarketplace is Script {
    // Base Sepolia addresses
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant EXISTING_NODE_REGISTRY = 0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3; // Using existing ETH-based registry
    address constant EXISTING_PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("USDC-Enabled JobMarketplace Deployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Use existing NodeRegistry
        address nodeRegistryAddress = EXISTING_NODE_REGISTRY;
        console.log("\nUsing existing NodeRegistry at:", nodeRegistryAddress);
        
        // Deploy new JobMarketplace with USDC support
        console.log("\nDeploying new JobMarketplace...");
        JobMarketplace jobMarketplace = new JobMarketplace(nodeRegistryAddress);
        console.log("[OK] JobMarketplace deployed at:", address(jobMarketplace));
        
        // Set USDC address on marketplace
        console.log("\nConfiguring USDC address...");
        jobMarketplace.setUsdcAddress(USDC_ADDRESS);
        console.log("[OK] USDC address set to:", USDC_ADDRESS);
        
        // Connect to existing PaymentEscrow
        console.log("\nConnecting to PaymentEscrow...");
        jobMarketplace.setPaymentEscrow(EXISTING_PAYMENT_ESCROW);
        console.log("[OK] Connected to PaymentEscrow at:", EXISTING_PAYMENT_ESCROW);
        
        // IMPORTANT: Update PaymentEscrow to allow new JobMarketplace
        console.log("\nUpdating PaymentEscrow permissions...");
        PaymentEscrow existingEscrow = PaymentEscrow(payable(EXISTING_PAYMENT_ESCROW));
        existingEscrow.setJobMarketplace(address(jobMarketplace));
        console.log("[OK] PaymentEscrow updated to allow new JobMarketplace");
        
        vm.stopBroadcast();
        
        // Verify integration
        console.log("\n========================================");
        console.log("Verification");
        console.log("========================================");
        console.log("NodeRegistry connected:", address(jobMarketplace.nodeRegistry()));
        console.log("PaymentEscrow connected:", address(jobMarketplace.paymentEscrow()));
        console.log("USDC address configured:", jobMarketplace.usdcAddress());
        
        // Note: File write disabled for broadcast mode
        // Deployment info will be saved to broadcast/ directory
        
        // Output deployment summary
        console.log("\n========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        console.log("\nContract Addresses:");
        console.log("  JobMarketplace:", address(jobMarketplace));
        console.log("  PaymentEscrow:", EXISTING_PAYMENT_ESCROW);
        console.log("  NodeRegistry:", nodeRegistryAddress);
        console.log("  USDC:", USDC_ADDRESS);
        
        console.log("\nFrontend Integration:");
        console.log("  1. Update JobMarketplace address to:", address(jobMarketplace));
        console.log("  2. For USDC payments:");
        console.log("     - Approve USDC: USDC.approve(marketplace, amount)");
        console.log("     - Call: postJobWithToken(details, requirements, USDC, amount)");
        console.log("  3. For ETH payments: Use existing postJob() with msg.value");
        
        console.log("\nVerify on Basescan:");
        console.log("  https://sepolia.basescan.io/address/", vm.toString(address(jobMarketplace)));
    }
    
    // Verification script to test the deployment
    function verify() external view {
        address marketplaceAddress = vm.envAddress("MARKETPLACE_ADDRESS");
        JobMarketplace marketplace = JobMarketplace(marketplaceAddress);
        
        console.log("Verifying JobMarketplace at:", marketplaceAddress);
        console.log("- USDC address configured:", marketplace.usdcAddress());
        console.log("- NodeRegistry connected:", address(marketplace.nodeRegistry()));
        
        // Check if USDC is set correctly
        require(marketplace.usdcAddress() == USDC_ADDRESS, "USDC address mismatch");
        console.log("[OK] USDC address correctly configured");
        
        console.log("\nVerification complete!");
    }
}