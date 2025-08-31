// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract HostClaimTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public otherHost = address(0x1004);
    address public treasury = address(0x1003);
    address public nodeRegistry = address(0x1005);
    address public hostEarningsAddr = address(0x1006);
    uint256 public constant JOB_ID = 1;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarningsAddr));
        proofSystem = new ProofSystemMock();
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        vm.deal(user, 10 ether);
        vm.deal(host, 1 ether);
        vm.deal(otherHost, 1 ether);
    }
    
    function test_HostCanClaimWithProofs() public {
        _setupActiveSessionWithProofs(75);
        
        uint256 hostBalanceBefore = host.balance;
        
        vm.prank(host);
        marketplace.claimWithProof(JOB_ID);
        
        // Verify payment received
        uint256 expectedPayment = 0.0675 ether; // 75 * 0.001 * 0.9 (after fee)
        assertEq(host.balance - hostBalanceBefore, expectedPayment, "Host should receive payment");
    }
    
    function test_OnlyAssignedHostCanClaim() public {
        _setupActiveSessionWithProofs(50);
        
        // Other host tries to claim
        vm.prank(otherHost);
        vm.expectRevert("Not assigned host");
        marketplace.claimWithProof(JOB_ID);
        
        // Random address tries
        vm.prank(address(0x99));
        vm.expectRevert("Not assigned host");
        marketplace.claimWithProof(JOB_ID);
    }
    
    function test_RequiresProvenTokensGreaterThanZero() public {
        _setupActiveSession(); // No proofs submitted
        
        vm.prank(host);
        vm.expectRevert("No proven work");
        marketplace.claimWithProof(JOB_ID);
    }
    
    function test_CannotClaimInactiveSession() public {
        // Try with non-existent job
        vm.prank(host);
        vm.expectRevert("Not assigned host");
        marketplace.claimWithProof(999);
    }
    
    function test_HostClaimedWithProofEventEmitted() public {
        _setupActiveSessionWithProofs(100);
        
        vm.expectEmit(true, true, false, true);
        emit JobMarketplaceFABWithS5.HostClaimedWithProof(
            JOB_ID,
            host,
            100, // proven tokens
            0.09 ether // payment after fee
        );
        
        vm.prank(host);
        marketplace.claimWithProof(JOB_ID);
    }
    
    function test_ClaimUpdatesSessionStatus() public {
        _setupActiveSessionWithProofs(60);
        
        // Verify active before
        (,,,,, JobMarketplaceFABWithS5.SessionStatus statusBefore,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint(statusBefore), uint(JobMarketplaceFABWithS5.SessionStatus.Active), "Should be active");
        
        vm.prank(host);
        marketplace.claimWithProof(JOB_ID);
        
        // Verify completed after
        (,,,,, JobMarketplaceFABWithS5.SessionStatus statusAfter,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint(statusAfter), uint(JobMarketplaceFABWithS5.SessionStatus.Completed), "Should be completed");
    }
    
    function test_CannotClaimAlreadyCompletedSession() public {
        _setupActiveSessionWithProofs(50);
        
        // First claim succeeds
        vm.prank(host);
        marketplace.claimWithProof(JOB_ID);
        
        // Second claim fails
        vm.prank(host);
        vm.expectRevert("Session not active");
        marketplace.claimWithProof(JOB_ID);
    }
    
    // Helper functions
    function _setupActiveSession() internal {
        marketplace.createSessionForTesting{value: 10 ether}(JOB_ID, user, host, 1 ether, 0.001 ether);
    }
    
    function _setupActiveSessionWithProofs(uint256 tokenCount) internal {
        _setupActiveSession();
        
        bytes memory proof = hex"1234";
        proofSystem.setVerificationResult(true);
        
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, proof, tokenCount);
    }
}