// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceFABWithS5Deploy.sol";
import "../src/HostEarnings.sol";

contract DeployWithHostEarnings is Script {
    // Existing contracts to reuse (Base Sepolia)
    address constant NODE_REGISTRY = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant EXISTING_PROOF_SYSTEM = 0x2ACcc60893872A499700908889B38C5420CBcFD1;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant TREASURY = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11; // Actual treasury address
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy new HostEarnings contract
        console.log("\n1. Deploying HostEarnings...");
        HostEarnings hostEarnings = new HostEarnings();
        console.log("HostEarnings deployed at:", address(hostEarnings));
        
        // 2. Deploy new JobMarketplace with HostEarnings
        console.log("\n2. Deploying JobMarketplaceFABWithS5...");
        JobMarketplaceFABWithS5 marketplace = new JobMarketplaceFABWithS5(
            NODE_REGISTRY,
            payable(address(hostEarnings))
        );
        console.log("JobMarketplace deployed at:", address(marketplace));
        
        // 3. Configure marketplace
        console.log("\n3. Configuring marketplace...");
        
        // Set ProofSystem
        marketplace.setProofSystem(EXISTING_PROOF_SYSTEM);
        console.log("ProofSystem set to:", EXISTING_PROOF_SYSTEM);
        
        // Set USDC
        marketplace.setUsdcAddress(USDC);
        marketplace.setAcceptedToken(USDC, true, 800000); // Accept USDC with 0.80 USDC minimum
        console.log("USDC configured");
        
        // Set treasury
        marketplace.setTreasuryAddress(TREASURY);
        console.log("Treasury set to:", TREASURY);
        
        // 4. Authorize marketplace in HostEarnings
        console.log("\n4. Authorizing marketplace in HostEarnings...");
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        console.log("Marketplace authorized to credit earnings");
        
        // 5. Update ProofSystem to use new marketplace
        console.log("\n5. Updating ProofSystem...");
        console.log("NOTE: ProofSystem owner must call:");
        console.log("  proofSystem.setJobMarketplace(", address(marketplace), ")");
        
        vm.stopBroadcast();
        
        // Print summary
        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETE - GAS-EFFICIENT HOST EARNINGS ENABLED!");
        console.log("========================================");
        console.log("\nNew Contract Addresses:");
        console.log("  HostEarnings:   ", address(hostEarnings));
        console.log("  JobMarketplace: ", address(marketplace));
        console.log("\nReused Contracts:");
        console.log("  NodeRegistry:   ", NODE_REGISTRY);
        console.log("  ProofSystem:    ", EXISTING_PROOF_SYSTEM);
        console.log("  USDC:          ", USDC);
        console.log("\nFeatures Enabled:");
        console.log("  - Host earnings accumulation (gas-efficient)");
        console.log("  - Batch withdrawals for hosts");
        console.log("  - Multi-token support (ETH + USDC)");
        console.log("  - ~40,000 gas saved per job");
        console.log("\nHosts can withdraw earnings using:");
        console.log("  hostEarnings.withdrawAll(address(0))     // ETH");
        console.log("  hostEarnings.withdrawAll(USDC)           // USDC");
        console.log("  hostEarnings.withdrawMultiple([...])     // Multiple tokens");
    }
}