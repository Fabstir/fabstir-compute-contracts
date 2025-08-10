// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/GovernanceToken.sol";
import "../src/NodeRegistry.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/ProofSystem.sol";
import "../src/Governance.sol";
import "../src/BaseAccountIntegration.sol";

contract DeployBaseSepolia is Script {
    // Deployed contract addresses
    GovernanceToken public governanceToken;
    NodeRegistry public nodeRegistry;
    JobMarketplace public jobMarketplace;
    PaymentEscrow public paymentEscrow;
    ReputationSystem public reputationSystem;
    ProofSystem public proofSystem;
    Governance public governance;
    BaseAccountIntegration public baseAccountIntegration;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Configuration
        uint256 minStake = vm.envUint("MIN_STAKE");
        uint256 feeBasisPoints = vm.envUint("FEE_BASIS_POINTS");
        address arbiter = vm.envAddress("ARBITER_ADDRESS");
        
        console.log("Deploying contracts to Base Sepolia...");
        console.log("Deployer:", deployer);
        console.log("Min Stake:", minStake);
        console.log("Fee Basis Points:", feeBasisPoints);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy GovernanceToken
        console.log("\n1. Deploying GovernanceToken...");
        governanceToken = new GovernanceToken(
            "Fabstir Governance",
            "FAB",
            1_000_000 ether  // 1M tokens initial supply
        );
        console.log("   GovernanceToken deployed at:", address(governanceToken));
        
        // 2. Deploy NodeRegistry
        console.log("\n2. Deploying NodeRegistry...");
        nodeRegistry = new NodeRegistry(minStake);
        console.log("   NodeRegistry deployed at:", address(nodeRegistry));
        
        // 3. Deploy JobMarketplace
        console.log("\n3. Deploying JobMarketplace...");
        jobMarketplace = new JobMarketplace(address(nodeRegistry));
        console.log("   JobMarketplace deployed at:", address(jobMarketplace));
        
        // 4. Deploy PaymentEscrow
        console.log("\n4. Deploying PaymentEscrow...");
        paymentEscrow = new PaymentEscrow(
            arbiter,  // arbiter address
            feeBasisPoints  // fee basis points
        );
        console.log("   PaymentEscrow deployed at:", address(paymentEscrow));
        
        // 5. Deploy ReputationSystem
        console.log("\n5. Deploying ReputationSystem...");
        reputationSystem = new ReputationSystem(
            address(nodeRegistry),
            address(jobMarketplace),
            address(0)  // governance will be set later
        );
        console.log("   ReputationSystem deployed at:", address(reputationSystem));
        
        // 6. Deploy ProofSystem
        console.log("\n6. Deploying ProofSystem...");
        proofSystem = new ProofSystem(
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem)
        );
        console.log("   ProofSystem deployed at:", address(proofSystem));
        
        // 7. Deploy Governance
        console.log("\n7. Deploying Governance...");
        governance = new Governance(
            address(governanceToken),
            address(nodeRegistry),
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem),
            address(proofSystem)
        );
        console.log("   Governance deployed at:", address(governance));
        
        // 8. Deploy BaseAccountIntegration (ERC-4337)
        console.log("\n8. Deploying BaseAccountIntegration...");
        address entryPoint = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789; // Base Sepolia EntryPoint
        address paymaster = address(0); // No paymaster for now
        baseAccountIntegration = new BaseAccountIntegration(
            entryPoint,
            paymaster,
            address(jobMarketplace),
            address(nodeRegistry)
        );
        console.log("   BaseAccountIntegration deployed at:", address(baseAccountIntegration));
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        
        // Save deployment addresses - commented out due to forge restrictions
        // saveDeploymentAddresses();
    }
    
    function saveDeploymentAddresses() internal {
        string memory output = string(abi.encodePacked(
            "# Deployed Contract Addresses - Base Sepolia\n",
            "# Deployed at: ", vm.toString(block.timestamp), "\n",
            "# Block: ", vm.toString(block.number), "\n\n",
            "GOVERNANCE_TOKEN_ADDRESS=", vm.toString(address(governanceToken)), "\n",
            "NODE_REGISTRY_ADDRESS=", vm.toString(address(nodeRegistry)), "\n",
            "JOB_MARKETPLACE_ADDRESS=", vm.toString(address(jobMarketplace)), "\n",
            "PAYMENT_ESCROW_ADDRESS=", vm.toString(address(paymentEscrow)), "\n",
            "REPUTATION_SYSTEM_ADDRESS=", vm.toString(address(reputationSystem)), "\n",
            "PROOF_SYSTEM_ADDRESS=", vm.toString(address(proofSystem)), "\n",
            "GOVERNANCE_ADDRESS=", vm.toString(address(governance)), "\n",
            "BASE_ACCOUNT_INTEGRATION_ADDRESS=", vm.toString(address(baseAccountIntegration)), "\n"
        ));
        
        vm.writeFile("deployed-addresses.txt", output);
        console.log("\nAddresses saved to deployed-addresses.txt");
    }
}