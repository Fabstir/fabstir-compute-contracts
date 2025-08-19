// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/NodeRegistry.sol";
import "../src/PaymentEscrow.sol";

contract DeployUSDCMarketplace is Script {
    // Base Sepolia addresses
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant EXISTING_NODE_REGISTRY = address(0); // Set this if you have existing registry
    address constant EXISTING_PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying USDC-enabled JobMarketplace with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy or get existing NodeRegistry
        address nodeRegistryAddress;
        if (EXISTING_NODE_REGISTRY != address(0)) {
            nodeRegistryAddress = EXISTING_NODE_REGISTRY;
            console.log("Using existing NodeRegistry at:", nodeRegistryAddress);
        } else {
            NodeRegistry nodeRegistry = new NodeRegistry(10 ether); // 10 ETH min stake
            nodeRegistryAddress = address(nodeRegistry);
            console.log("Deployed new NodeRegistry at:", nodeRegistryAddress);
        }
        
        // Deploy new JobMarketplace with USDC support
        JobMarketplace jobMarketplace = new JobMarketplace(nodeRegistryAddress);
        console.log("Deployed JobMarketplace with USDC support at:", address(jobMarketplace));
        
        // Connect to existing PaymentEscrow or deploy new one
        if (EXISTING_PAYMENT_ESCROW != address(0)) {
            jobMarketplace.setPaymentEscrow(EXISTING_PAYMENT_ESCROW);
            console.log("Connected to existing PaymentEscrow at:", EXISTING_PAYMENT_ESCROW);
            
            // Update PaymentEscrow to allow JobMarketplace
            PaymentEscrow existingEscrow = PaymentEscrow(payable(EXISTING_PAYMENT_ESCROW));
            existingEscrow.setJobMarketplace(address(jobMarketplace));
        } else {
            // Deploy new PaymentEscrow
            PaymentEscrow paymentEscrow = new PaymentEscrow(deployer, 100); // 1% fee
            jobMarketplace.setPaymentEscrow(address(paymentEscrow));
            paymentEscrow.setJobMarketplace(address(jobMarketplace));
            console.log("Deployed new PaymentEscrow at:", address(paymentEscrow));
        }
        
        // Set USDC address (already set in constructor, but can be updated if needed)
        // Note: In production, you might want to remove the setter and use only the constant
        console.log("USDC address configured:", jobMarketplace.usdcAddress());
        
        // Verify integration
        console.log("Verifying integration...");
        console.log("- NodeRegistry connected:", address(jobMarketplace.nodeRegistry()));
        console.log("- USDC address set:", jobMarketplace.usdcAddress());
        console.log("- Existing PaymentEscrow (not integrated):", EXISTING_PAYMENT_ESCROW);
        
        vm.stopBroadcast();
        
        // Output deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("JobMarketplace with USDC:", address(jobMarketplace));
        console.log("NodeRegistry:", nodeRegistryAddress);
        console.log("USDC Token:", USDC_ADDRESS);
        console.log("\n=== Integration Instructions ===");
        console.log("1. For ETH payments: Use postJob() function with msg.value");
        console.log("2. For USDC payments: Use postJobWithToken() function");
        console.log("   - First approve USDC: USDC.approve(marketplace, amount)");
        console.log("   - Then call: postJobWithToken(details, requirements, USDC_ADDRESS, amount)");
        console.log("\n=== SDK Update Required ===");
        console.log("Update your SDK/frontend to:");
        console.log("- Use new JobMarketplace address:", address(jobMarketplace));
        console.log("- Call postJobWithToken for USDC payments");
        console.log("- Approve USDC before calling postJobWithToken");
        
        // Write deployment info to file
        string memory deploymentInfo = string(abi.encodePacked(
            "USDC-Enabled JobMarketplace Deployment\n",
            "=====================================\n",
            "Network: Base Sepolia\n",
            "JobMarketplace: ", vm.toString(address(jobMarketplace)), "\n",
            "NodeRegistry: ", vm.toString(nodeRegistryAddress), "\n",
            "USDC Token: ", vm.toString(USDC_ADDRESS), "\n",
            "Deployed by: ", vm.toString(deployer), "\n",
            "Timestamp: ", vm.toString(block.timestamp), "\n"
        ));
        
        vm.writeFile("./usdc-marketplace-deployment.txt", deploymentInfo);
        console.log("\nDeployment info saved to: usdc-marketplace-deployment.txt");
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