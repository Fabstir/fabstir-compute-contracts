// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../ReputationSystem.sol";
import "../ProofSystem.sol";
import "../PaymentEscrow.sol";
import "../Governance.sol";
import "../GovernanceToken.sol";

// Factory contract to handle deployment with different constructor signatures
contract DeploymentHelpers {
    
    // Deploy ReputationSystem with no parameters and then initialize
    function deployReputationSystem(address nodeRegistry, address jobMarketplace, address governance) external returns (ReputationSystem) {
        ReputationSystem system = new ReputationSystem(nodeRegistry, jobMarketplace, governance);
        return system;
    }
    
    // Deploy ProofSystem with no parameters and then initialize  
    function deployProofSystem(address jobMarketplace, address paymentEscrow, address reputationSystem) external returns (ProofSystem) {
        ProofSystem system = new ProofSystem(jobMarketplace, paymentEscrow, reputationSystem);
        return system;
    }
    
    // Deploy PaymentEscrow with no parameters and then initialize
    function deployPaymentEscrow(address arbiter, uint256 feeBasisPoints) external returns (PaymentEscrow) {
        PaymentEscrow escrow = new PaymentEscrow(arbiter, feeBasisPoints);
        return escrow;
    }
    
    // Deploy Governance with simplified parameters
    function deployGovernance(address nodeRegistry, address jobMarketplace, address reputationSystem) external returns (Governance) {
        // First deploy token
        GovernanceToken token = new GovernanceToken("Fabstir Governance", "FAB", 1000000 * 10**18);
        
        // Deploy governance with all required params
        Governance gov = new Governance(
            address(token),
            nodeRegistry,
            jobMarketplace,
            address(0), // paymentEscrow - will be set later
            reputationSystem,
            address(0)  // proofSystem - will be set later
        );
        
        return gov;
    }
}