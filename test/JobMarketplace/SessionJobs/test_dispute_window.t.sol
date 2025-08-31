// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract SessionDisputeWindowTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public treasury = address(0x1003);
    address public nodeRegistry = address(0x1004);
    address public hostEarnings = address(0x1005);
    
    uint256 constant JOB_ID = 1;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    uint256 constant DISPUTE_WINDOW = 1 hours;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        // Fund user and host
        vm.deal(user, 10 ether);
        vm.deal(host, 10 ether);
        vm.deal(address(marketplace), 10 ether);
    }
    
    function test_DisputeWindowAfterCompletion() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Complete session
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Check dispute deadline is set
        (,,,,,,,,,,, uint256 disputeDeadline) = marketplace.sessions(JOB_ID);
        assertEq(disputeDeadline, block.timestamp + DISPUTE_WINDOW);
    }
    
    function test_ActionsBlockedDuringDispute() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof and complete
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Try to perform actions during dispute window
        vm.prank(host);
        vm.expectRevert("Dispute window active");
        marketplace.withdrawFromSession(JOB_ID);
    }
    
    function test_DisputeWindowExpiry() public {
        // Create and complete session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Fast forward past dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        
        // Now actions should be allowed
        vm.prank(host);
        marketplace.withdrawFromSession(JOB_ID);
    }
    
    function test_EmergencyResolutionDuringDispute() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Complete with dispute
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Owner can perform emergency resolution
        vm.prank(marketplace.owner());
        marketplace.emergencyResolveSession(JOB_ID);
    }
    
    function test_NoDisputeWindowForTimeout() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Fast forward and timeout
        vm.warp(block.timestamp + 2 hours);
        vm.prank(user);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // No dispute deadline should be set for timeout
        (,,,,,,,,,,, uint256 disputeDeadline) = marketplace.sessions(JOB_ID);
        assertEq(disputeDeadline, 0);
    }
}