// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract UserCompletionTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public treasury = address(0x1003);
    address public nodeRegistry = address(0x1004);
    address public hostEarnings = address(0x1005);
    uint256 public constant JOB_ID = 1;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        // Setup job and session for testing
        vm.deal(user, 10 ether);
        vm.deal(host, 1 ether);
    }
    
    function test_UserCanCompleteActiveSession() public {
        // Setup active session
        _setupActiveSession();
        
        // User completes session
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Verify session status
        (,,,,, JobMarketplaceFABWithS5.SessionStatus status,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint(status), uint(JobMarketplaceFABWithS5.SessionStatus.Completed), "Session should be completed");
    }
    
    function test_OnlyUserCanCompleteSession() public {
        _setupActiveSession();
        
        // Non-user tries to complete
        vm.prank(address(0x99));
        vm.expectRevert("Only user can complete");
        marketplace.completeSessionJob(JOB_ID);
        
        // Host tries to complete via this method
        vm.prank(host);
        vm.expectRevert("Only user can complete");
        marketplace.completeSessionJob(JOB_ID);
    }
    
    function test_PaymentCalculatedFromProvenTokens() public {
        _setupActiveSessionWithProofs(100); // 100 proven tokens
        
        uint256 hostBalanceBefore = host.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Expected payment: 100 tokens * 0.001 ether/token = 0.1 ether
        // After 10% treasury fee: 0.09 ether to host
        uint256 expectedPayment = 0.09 ether;
        assertEq(host.balance - hostBalanceBefore, expectedPayment, "Host should receive correct payment");
    }
    
    function test_SessionCompletedEventEmitted() public {
        _setupActiveSessionWithProofs(50);
        
        vm.expectEmit(true, true, false, true);
        emit JobMarketplaceFABWithS5.SessionCompleted(
            JOB_ID,
            user,
            50, // proven tokens
            0.045 ether, // payment after fee
            0.95 ether // refund (1 ether deposit - 0.05 ether cost)
        );
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
    }
    
    function test_CannotCompleteInactiveSession() public {
        // Try to complete non-existent session
        vm.prank(user);
        vm.expectRevert("Only user can complete");
        marketplace.completeSessionJob(999);
    }
    
    function test_SessionStatusUpdatedToCompleted() public {
        _setupActiveSessionWithProofs(25);
        
        // Verify initial status
        (,,,,, JobMarketplaceFABWithS5.SessionStatus statusBefore,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint(statusBefore), uint(JobMarketplaceFABWithS5.SessionStatus.Active), "Should start active");
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Verify final status
        (,,,,, JobMarketplaceFABWithS5.SessionStatus statusAfter,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint(statusAfter), uint(JobMarketplaceFABWithS5.SessionStatus.Completed), "Should be completed");
    }
    
    // Helper functions
    function _setupActiveSession() internal {
        // Create a simple session directly for testing
        marketplace.createSessionForTesting{value: 10 ether}(JOB_ID, user, host, 1 ether, 0.001 ether);
    }
    
    function _setupActiveSessionWithProofs(uint256 tokenCount) internal {
        _setupActiveSession();
        
        // Submit proof for tokens
        bytes memory proof = hex"1234";
        proofSystem.setVerificationResult(true);
        
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, proof, tokenCount);
    }
}