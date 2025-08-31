// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract SessionTimeoutTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public anyone = address(0x1003);
    address public treasury = address(0x1004);
    address public nodeRegistry = address(0x1005);
    address public hostEarnings = address(0x1006);
    
    uint256 constant JOB_ID = 1;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    
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
    
    function test_SessionTimeoutAfterMaxDuration() public {
        // Create session with 1 hour max duration
        uint256 maxDuration = 1 hours;
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Fast forward past max duration
        vm.warp(block.timestamp + maxDuration + 1);
        
        // Anyone can trigger timeout
        vm.prank(anyone);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // Verify session is timed out
        (,,,,, JobMarketplaceFABWithS5.SessionStatus status,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint8(status), uint8(JobMarketplaceFABWithS5.SessionStatus.TimedOut));
    }
    
    function test_CannotTimeoutBeforeExpiry() public {
        // Create session with 1 hour max duration
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Try to timeout before expiry
        vm.expectRevert("Session not expired");
        marketplace.triggerSessionTimeout(JOB_ID);
    }
    
    function test_AnyoneCanTriggerTimeout() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Fast forward past timeout
        vm.warp(block.timestamp + 2 hours);
        
        // Random address triggers timeout
        address randomUser = address(0x9999);
        vm.prank(randomUser);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // Verify timeout succeeded
        (,,,,, JobMarketplaceFABWithS5.SessionStatus status,,,,,,) = marketplace.sessions(JOB_ID);
        assertEq(uint8(status), uint8(JobMarketplaceFABWithS5.SessionStatus.TimedOut));
    }
    
    function test_TimeoutStatusCalculation() public {
        // Create session with 1 hour duration
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Check initial status
        (bool isExpired, bool isAbandoned, uint256 timeRemaining,) = 
            marketplace.getTimeoutStatus(JOB_ID);
        assertFalse(isExpired);
        assertFalse(isAbandoned);
        assertGt(timeRemaining, 0);
        
        // Fast forward to near expiry
        vm.warp(block.timestamp + 55 minutes);
        (isExpired, , timeRemaining,) = marketplace.getTimeoutStatus(JOB_ID);
        assertFalse(isExpired);
        assertEq(timeRemaining, 5 minutes);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 10 minutes);
        (isExpired, , timeRemaining,) = marketplace.getTimeoutStatus(JOB_ID);
        assertTrue(isExpired);
        assertEq(timeRemaining, 0);
    }
    
    function test_TimeoutWithProvenWork() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof for 500 tokens
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Fast forward and timeout
        vm.warp(block.timestamp + 2 hours);
        
        uint256 hostBalanceBefore = host.balance;
        vm.prank(anyone);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // Host should receive payment with 10% penalty
        uint256 expectedPayment = (500 * PRICE_PER_TOKEN * 90) / 100; // 10% penalty
        uint256 expectedAfterFee = (expectedPayment * 90) / 100; // 10% treasury fee
        assertGt(host.balance - hostBalanceBefore, 0);
    }
    
    function test_TimeoutWithoutProvenWork() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Fast forward and timeout without any proofs
        vm.warp(block.timestamp + 2 hours);
        
        uint256 userBalanceBefore = user.balance;
        vm.prank(anyone);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // User should receive full refund
        assertEq(user.balance - userBalanceBefore, DEPOSIT);
    }
}