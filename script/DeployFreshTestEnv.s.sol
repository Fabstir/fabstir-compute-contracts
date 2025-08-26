// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/HostEarnings.sol";
import "../src/PaymentEscrowWithEarnings.sol";
import "../src/JobMarketplaceFABWithEarnings.sol";

contract DeployFreshTestEnv is Script {
    // Existing contracts we'll reuse
    address constant EXISTING_NODE_REGISTRY = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant EXISTING_FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Existing treasury to use
    address constant EXISTING_TREASURY = 0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=========================================");
        console.log("DEPLOYING FRESH TEST ENVIRONMENT");
        console.log("=========================================");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("=========================================\n");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy HostEarnings
        console.log("1. Deploying HostEarnings...");
        HostEarnings hostEarnings = new HostEarnings();
        console.log("   HostEarnings deployed at:", address(hostEarnings));
        
        // 2. Use existing treasury address
        address treasuryAddress = EXISTING_TREASURY;
        console.log("2. Using existing TreasuryManager:", treasuryAddress);
        
        // 3. Deploy PaymentEscrowWithEarnings
        console.log("3. Deploying PaymentEscrowWithEarnings...");
        PaymentEscrowWithEarnings paymentEscrow = new PaymentEscrowWithEarnings(
            treasuryAddress,
            1000 // 10% fee (1000 basis points)
        );
        console.log("   PaymentEscrow deployed at:", address(paymentEscrow));
        
        // 4. Deploy JobMarketplaceFABWithEarnings
        console.log("4. Deploying JobMarketplaceFABWithEarnings...");
        JobMarketplaceFABWithEarnings marketplace = new JobMarketplaceFABWithEarnings(
            EXISTING_NODE_REGISTRY,
            payable(address(hostEarnings))
        );
        console.log("   JobMarketplace deployed at:", address(marketplace));
        
        // 5. Configure contracts
        console.log("\n5. Configuring contracts...");
        
        // Configure HostEarnings
        console.log("   - Authorizing PaymentEscrow in HostEarnings...");
        hostEarnings.setAuthorizedCaller(address(paymentEscrow), true);
        
        // Configure PaymentEscrow
        console.log("   - Setting JobMarketplace in PaymentEscrow...");
        paymentEscrow.setJobMarketplace(address(marketplace));
        
        // Configure JobMarketplace
        console.log("   - Setting PaymentEscrow in JobMarketplace...");
        marketplace.setPaymentEscrow(address(paymentEscrow));
        
        console.log("   - Setting USDC address in JobMarketplace...");
        marketplace.setUsdcAddress(USDC_ADDRESS);
        
        vm.stopBroadcast();
        
        // Print summary
        console.log("\n=========================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("=========================================");
        console.log("\nNew Contract Addresses:");
        console.log("-----------------------");
        console.log("JobMarketplace:", address(marketplace));
        console.log("PaymentEscrow:", address(paymentEscrow));
        console.log("HostEarnings:", address(hostEarnings));
        
        console.log("\nExisting Contracts Used:");
        console.log("------------------------");
        console.log("NodeRegistry:", EXISTING_NODE_REGISTRY);
        console.log("FAB Token:", EXISTING_FAB_TOKEN);
        console.log("USDC:", USDC_ADDRESS);
        console.log("TreasuryManager:", EXISTING_TREASURY);
        
        console.log("\n=========================================");
        console.log("UPDATE YOUR CLIENT WITH THESE ADDRESSES!");
        console.log("=========================================");
        
        // Export addresses for easy copying
        console.log("\nExport commands for .env file:");
        console.log("--------------------------------");
        console.log(string.concat("export JOB_MARKETPLACE_FAB=", vm.toString(address(marketplace))));
        console.log(string.concat("export PAYMENT_ESCROW=", vm.toString(address(paymentEscrow))));
        console.log(string.concat("export HOST_EARNINGS=", vm.toString(address(hostEarnings))));
        
        // Note: File writing removed due to forge restrictions
        // Copy the addresses from the console output above
    }
}