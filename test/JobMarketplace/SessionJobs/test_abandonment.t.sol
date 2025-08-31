// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract SessionAbandonmentTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public otherHost = address(0x1003);
    address public treasury = address(0x1004);
    address public nodeRegistry = address(0x1005);
    address public hostEarnings = address(0x1006);
    
    uint256 constant JOB_ID = 1;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    uint256 constant ABANDONMENT_TIMEOUT = 24 hours;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        // Fund user and hosts
        vm.deal(user, 10 ether);
        vm.deal(host, 10 ether);
        vm.deal(otherHost, 10 ether);
        vm.deal(address(marketplace), 10 ether);
    }
    
    function test_AbandonmentAfter24HoursInactivity() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Fast forward 24 hours + 1 second
        vm.warp(block.timestamp + ABANDONMENT_TIMEOUT + 1);
        
        // Host claims abandoned session
        uint256 hostBalanceBefore = host.balance;
        vm.prank(host);
        marketplace.claimAbandonedSession(JOB_ID);
        
        // Verify host received payment
        assertGt(host.balance - hostBalanceBefore, 0);
        
        // Verify session marked as abandoned
        (,,,,, JobMarketplaceFABWithS5.SessionStatus status,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint8(status), uint8(JobMarketplaceFABWithS5.SessionStatus.Abandoned));
    }
    
    function test_OnlyHostCanClaimAbandonedSession() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Fast forward past abandonment timeout
        vm.warp(block.timestamp + ABANDONMENT_TIMEOUT + 1);
        
        // Other host cannot claim
        vm.prank(otherHost);
        vm.expectRevert("Not assigned host");
        marketplace.claimAbandonedSession(JOB_ID);
        
        // User cannot claim
        vm.prank(user);
        vm.expectRevert("Not assigned host");
        marketplace.claimAbandonedSession(JOB_ID);
    }
    
    function test_RequiresProvenTokensForClaim() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Fast forward without submitting any proofs
        vm.warp(block.timestamp + ABANDONMENT_TIMEOUT + 1);
        
        // Host cannot claim without proven work
        vm.prank(host);
        vm.expectRevert("No proven work");
        marketplace.claimAbandonedSession(JOB_ID);
    }
    
    function test_CannotClaimIfStillActive() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Fast forward less than abandonment timeout
        vm.warp(block.timestamp + ABANDONMENT_TIMEOUT - 1 hours);
        
        // Cannot claim yet
        vm.prank(host);
        vm.expectRevert("Session not abandoned");
        marketplace.claimAbandonedSession(JOB_ID);
    }
    
    function test_AbandonmentPeriodCalculation() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        uint256 startTime = block.timestamp;
        
        // Check initial status
        (,bool isAbandoned,, uint256 inactivityPeriod) = 
            marketplace.getTimeoutStatus(JOB_ID);
        assertFalse(isAbandoned);
        assertEq(inactivityPeriod, 0);
        
        // Fast forward 12 hours (absolute time)
        vm.warp(12 hours + 1);
        (,isAbandoned,, inactivityPeriod) = marketplace.getTimeoutStatus(JOB_ID);
        assertFalse(isAbandoned);
        assertEq(inactivityPeriod, 12 hours);
        
        // Fast forward to exactly 24 hours (absolute time)
        vm.warp(ABANDONMENT_TIMEOUT + 1);
        (,isAbandoned,, inactivityPeriod) = marketplace.getTimeoutStatus(JOB_ID);
        assertFalse(isAbandoned); // Not abandoned at exactly 24 hours
        assertEq(inactivityPeriod, ABANDONMENT_TIMEOUT);
        
        // Fast forward past abandonment timeout (absolute time)
        vm.warp(ABANDONMENT_TIMEOUT + 2);
        (,isAbandoned,, inactivityPeriod) = marketplace.getTimeoutStatus(JOB_ID);
        assertTrue(isAbandoned);
        assertEq(inactivityPeriod, ABANDONMENT_TIMEOUT + 1);
    }
}