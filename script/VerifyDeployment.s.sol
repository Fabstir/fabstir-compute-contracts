// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/NodeRegistry.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/ProofSystem.sol";
import "../src/GovernanceToken.sol";
import "../src/Governance.sol";
import "../src/BaseAccountIntegration.sol";

contract VerifyDeployment is Script {
    struct DeployedAddresses {
        address nodeRegistry;
        address jobMarketplace;
        address paymentEscrow;
        address reputationSystem;
        address proofSystem;
        address governanceToken;
        address governance;
        address baseAccountIntegration;
    }
    
    function run() external view {
        DeployedAddresses memory addrs = DeployedAddresses({
            nodeRegistry: vm.envAddress("NODE_REGISTRY_ADDRESS"),
            jobMarketplace: vm.envAddress("JOB_MARKETPLACE_ADDRESS"),
            paymentEscrow: vm.envAddress("PAYMENT_ESCROW_ADDRESS"),
            reputationSystem: vm.envAddress("REPUTATION_SYSTEM_ADDRESS"),
            proofSystem: vm.envAddress("PROOF_SYSTEM_ADDRESS"),
            governanceToken: vm.envAddress("GOVERNANCE_TOKEN_ADDRESS"),
            governance: vm.envAddress("GOVERNANCE_ADDRESS"),
            baseAccountIntegration: vm.envAddress("BASE_ACCOUNT_INTEGRATION_ADDRESS")
        });
        
        console.log("========================================");
        console.log("Verifying deployment...");
        console.log("========================================\n");
        
        // 1. Check NodeRegistry
        console.log("1. Checking NodeRegistry...");
        NodeRegistry registry = NodeRegistry(addrs.nodeRegistry);
        uint256 minStake = registry.requiredStake();
        console.log("   Required stake:", minStake);
        require(minStake == 0.1 ether, "Invalid min stake");
        console.log("   [OK] NodeRegistry verified");
        
        // 2. Check JobMarketplace connections
        console.log("\n2. Checking JobMarketplace...");
        JobMarketplace marketplace = JobMarketplace(addrs.jobMarketplace);
        
        address connectedRegistry = address(marketplace.nodeRegistry());
        console.log("   Connected NodeRegistry:", connectedRegistry);
        require(connectedRegistry == addrs.nodeRegistry, "NodeRegistry not connected");
        
        address connectedReputation = address(marketplace.reputationSystem());
        console.log("   Connected ReputationSystem:", connectedReputation);
        require(connectedReputation == addrs.reputationSystem, "ReputationSystem not connected");
        console.log("   [OK] JobMarketplace verified");
        
        // 3. Check PaymentEscrow
        console.log("\n3. Checking PaymentEscrow...");
        PaymentEscrow escrow = PaymentEscrow(payable(addrs.paymentEscrow));
        uint256 feeBasisPoints = escrow.feeBasisPoints();
        console.log("   Fee basis points:", feeBasisPoints);
        require(feeBasisPoints == 250, "Invalid fee basis points");
        
        address escrowArbiter = escrow.arbiter();
        console.log("   Arbiter:", escrowArbiter);
        console.log("   [OK] PaymentEscrow verified");
        
        // 4. Check ReputationSystem
        console.log("\n4. Checking ReputationSystem...");
        ReputationSystem reputation = ReputationSystem(addrs.reputationSystem);
        bool isAuthorized = reputation.authorizedContracts(addrs.jobMarketplace);
        console.log("   JobMarketplace authorized:", isAuthorized);
        require(isAuthorized, "JobMarketplace not authorized in ReputationSystem");
        console.log("   [OK] ReputationSystem verified");
        
        // 5. Check ProofSystem
        console.log("\n5. Checking ProofSystem...");
        ProofSystem proof = ProofSystem(addrs.proofSystem);
        bytes32 VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
        bool hasVerifierRole = proof.hasRole(VERIFIER_ROLE, addrs.jobMarketplace);
        console.log("   JobMarketplace has verifier role:", hasVerifierRole);
        require(hasVerifierRole, "JobMarketplace doesn't have verifier role in ProofSystem");
        console.log("   [OK] ProofSystem verified");
        
        // 6. Check GovernanceToken
        console.log("\n6. Checking GovernanceToken...");
        GovernanceToken token = GovernanceToken(addrs.governanceToken);
        string memory name = token.name();
        string memory symbol = token.symbol();
        uint256 totalSupply = token.totalSupply();
        console.log("   Name:", name);
        console.log("   Symbol:", symbol);
        console.log("   Total Supply:", totalSupply);
        require(keccak256(bytes(name)) == keccak256(bytes("Fabstir Governance")), "Invalid token name");
        require(keccak256(bytes(symbol)) == keccak256(bytes("FAB")), "Invalid token symbol");
        console.log("   [OK] GovernanceToken verified");
        
        // 7. Check Governance
        console.log("\n7. Checking Governance...");
        Governance gov = Governance(addrs.governance);
        address govToken = address(gov.governanceToken());
        console.log("   Governance token:", govToken);
        require(govToken == addrs.governanceToken, "Invalid governance token");
        console.log("   [OK] Governance verified");
        
        // 8. Check BaseAccountIntegration
        console.log("\n8. Checking BaseAccountIntegration...");
        BaseAccountIntegration account = BaseAccountIntegration(payable(addrs.baseAccountIntegration));
        address entryPointAddr = address(account.entryPoint());
        console.log("   EntryPoint:", entryPointAddr);
        require(entryPointAddr == 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, "Invalid EntryPoint");
        console.log("   [OK] BaseAccountIntegration verified");
        
        console.log("\n========================================");
        console.log("[SUCCESS] All verifications passed!");
        console.log("========================================");
    }
}