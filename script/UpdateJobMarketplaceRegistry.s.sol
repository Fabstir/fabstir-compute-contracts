// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";

contract UpdateJobMarketplaceRegistry is Script {
    // Existing Base Sepolia contracts
    address constant EXISTING_JOB_MARKETPLACE = 0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6;
    address constant EXISTING_PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get NodeRegistryFAB address from environment
        address nodeRegistryFAB = vm.envAddress("NODE_REGISTRY_FAB");
        
        console.log("========================================");
        console.log("Update JobMarketplace Configuration");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("NodeRegistryFAB:", nodeRegistryFAB);
        console.log("JobMarketplace:", EXISTING_JOB_MARKETPLACE);
        
        vm.startBroadcast(deployerPrivateKey);
        
        JobMarketplace marketplace = JobMarketplace(EXISTING_JOB_MARKETPLACE);
        
        // Option 1: Try to update existing marketplace (requires owner)
        console.log("\nAttempting to update existing JobMarketplace...");
        try marketplace.setNodeRegistry(nodeRegistryFAB) {
            console.log("[OK] JobMarketplace updated with NodeRegistryFAB!");
            console.log("\n[SUCCESS] Existing marketplace can now use FAB staking!");
        } catch {
            console.log("[FAIL] Cannot update existing marketplace (not owner)");
            console.log("\nDeploying new JobMarketplace with FAB support...");
            
            // Option 2: Deploy new JobMarketplace
            JobMarketplace newMarketplace = new JobMarketplace(nodeRegistryFAB);
            console.log("[OK] New JobMarketplace deployed at:", address(newMarketplace));
            
            // Configure USDC
            newMarketplace.setUsdcAddress(USDC_ADDRESS);
            console.log("[OK] USDC configured");
            
            // Connect PaymentEscrow
            newMarketplace.setPaymentEscrow(EXISTING_PAYMENT_ESCROW);
            console.log("[OK] PaymentEscrow connected");
            
            // Update PaymentEscrow to accept new marketplace
            PaymentEscrow escrow = PaymentEscrow(payable(EXISTING_PAYMENT_ESCROW));
            try escrow.setJobMarketplace(address(newMarketplace)) {
                console.log("[OK] PaymentEscrow updated");
            } catch {
                console.log("[WARN] Could not update PaymentEscrow");
                console.log("       May need to deploy new PaymentEscrow");
            }
            
            console.log("\n========================================");
            console.log("New JobMarketplace Ready!");
            console.log("========================================");
            console.log("Address:", address(newMarketplace));
            console.log("NodeRegistryFAB:", address(newMarketplace.nodeRegistry()));
            console.log("PaymentEscrow:", address(newMarketplace.paymentEscrow()));
            console.log("USDC:", newMarketplace.usdcAddress());
            
            // Save deployment info
            string memory json = string.concat(
                '{"jobMarketplace":"',
                vm.toString(address(newMarketplace)),
                '","nodeRegistryFAB":"',
                vm.toString(nodeRegistryFAB),
                '","paymentEscrow":"',
                vm.toString(EXISTING_PAYMENT_ESCROW),
                '","usdc":"',
                vm.toString(USDC_ADDRESS),
                '"}'
            );
            
            vm.writeFile("./deployments/fab-job-marketplace.json", json);
            console.log("\n[OK] Saved to deployments/fab-job-marketplace.json");
            
            console.log("\n[IMPORTANT] Update frontend to use new address!");
        }
        
        vm.stopBroadcast();
    }
}