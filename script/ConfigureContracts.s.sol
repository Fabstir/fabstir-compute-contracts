// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/NodeRegistry.sol";
import "../src/ProofSystem.sol";
import "../src/Governance.sol";

contract ConfigureContracts is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Load deployed addresses from environment
        // These should be set after deployment
        address nodeRegistry = vm.envAddress("NODE_REGISTRY_ADDRESS");
        address jobMarketplace = vm.envAddress("JOB_MARKETPLACE_ADDRESS");
        address paymentEscrow = vm.envAddress("PAYMENT_ESCROW_ADDRESS");
        address reputationSystem = vm.envAddress("REPUTATION_SYSTEM_ADDRESS");
        address proofSystem = vm.envAddress("PROOF_SYSTEM_ADDRESS");
        address governance = vm.envAddress("GOVERNANCE_ADDRESS");
        
        console.log("Configuring contract connections...");
        console.log("NodeRegistry:", nodeRegistry);
        console.log("JobMarketplace:", jobMarketplace);
        console.log("PaymentEscrow:", paymentEscrow);
        console.log("ReputationSystem:", reputationSystem);
        console.log("ProofSystem:", proofSystem);
        console.log("Governance:", governance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Connect JobMarketplace to ReputationSystem
        console.log("\n1. Connecting JobMarketplace to ReputationSystem...");
        JobMarketplace(jobMarketplace).setReputationSystem(reputationSystem);
        console.log("   Connected!");
        
        // 2. Set Governance for JobMarketplace
        console.log("\n2. Setting Governance for JobMarketplace...");
        JobMarketplace(jobMarketplace).setGovernance(governance);
        console.log("   Connected!");
        
        // 3. Set Governance for NodeRegistry
        console.log("\n3. Setting Governance for NodeRegistry...");
        NodeRegistry(nodeRegistry).setGovernance(governance);
        console.log("   Connected!");
        
        // 4. Authorize JobMarketplace in ReputationSystem
        console.log("\n4. Authorizing JobMarketplace in ReputationSystem...");
        ReputationSystem(reputationSystem).addAuthorizedContract(jobMarketplace);
        console.log("   Authorized!");
        
        // 5. Grant verifier role to JobMarketplace in ProofSystem
        console.log("\n5. Granting verifier role to JobMarketplace in ProofSystem...");
        bytes32 VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
        ProofSystem(proofSystem).grantRole(VERIFIER_ROLE, jobMarketplace);
        console.log("   Role granted!");
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("Configuration Complete!");
        console.log("========================================");
    }
}