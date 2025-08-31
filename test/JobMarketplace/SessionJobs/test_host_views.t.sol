// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract HostViewsTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user1 = address(0x1001);
    address public user2 = address(0x1002);
    address public host1 = address(0x2001);
    address public host2 = address(0x2002);
    address public treasury = address(0x3001);
    address public nodeRegistry = address(0x4001);
    address public hostEarnings = address(0x5001);
    
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        // Fund users and hosts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(host1, 10 ether);
        vm.deal(host2, 10 ether);
        vm.deal(address(marketplace), 10 ether);
    }
    
    function test_GetActiveSessionsForHost() public {
        // Create multiple sessions for host1
        vm.prank(user1);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            1, user1, host1, DEPOSIT, PRICE_PER_TOKEN
        );
        
        vm.prank(user2);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            2, user2, host1, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Create session for host2
        vm.prank(user1);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            3, user1, host2, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Get active sessions for host1
        uint256[] memory sessions = marketplace.getActiveSessionsForHost(host1);
        assertEq(sessions.length, 2);
        assertEq(sessions[0], 1);
        assertEq(sessions[1], 2);
        
        // Get active sessions for host2
        sessions = marketplace.getActiveSessionsForHost(host2);
        assertEq(sessions.length, 1);
        assertEq(sessions[0], 3);
    }
    
    function test_GetSessionDetails() public {
        // Create a session
        vm.prank(user1);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            1, user1, host1, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit some proofs
        proofSystem.setVerificationResult(true);
        vm.prank(host1);
        marketplace.submitProofOfWork(1, "proof1", 100);
        
        // Get session details
        (
            address user,
            address host,
            uint256 deposit,
            uint256 pricePerToken,
            uint256 provenTokens,
            uint256 startTime,
            JobMarketplaceFABWithS5.SessionStatus status,
            uint256 lastActivity
        ) = marketplace.getSessionDetails(1);
        
        assertEq(user, user1);
        assertEq(host, host1);
        assertEq(deposit, DEPOSIT);
        assertEq(pricePerToken, PRICE_PER_TOKEN);
        assertEq(provenTokens, 100);
        assertGt(startTime, 0);
        assertEq(uint(status), uint(JobMarketplaceFABWithS5.SessionStatus.Active));
        assertGt(lastActivity, 0);
    }
    
    function test_GetHostStats() public {
        // Create sessions for host1
        vm.prank(user1);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            1, user1, host1, DEPOSIT, PRICE_PER_TOKEN
        );
        
        vm.prank(user2);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            2, user2, host1, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proofs and complete one session
        proofSystem.setVerificationResult(true);
        vm.prank(host1);
        marketplace.submitProofOfWork(1, "proof1", 500);
        
        vm.prank(user1);
        marketplace.completeSessionJob(1);
        
        // Submit proof for second session (keep active)
        vm.prank(host1);
        marketplace.submitProofOfWork(2, "proof2", 300);
        
        // Get host stats
        (
            uint256 totalSessions,
            uint256 activeSessions,
            uint256 completedSessions,
            uint256 totalTokensProven,
            uint256 totalEarnings
        ) = marketplace.getHostStats(host1);
        
        assertEq(totalSessions, 2);
        assertEq(activeSessions, 1);
        assertEq(completedSessions, 1);
        assertEq(totalTokensProven, 800);
        
        // Calculate expected earnings (800 tokens * 0.001 ETH * 0.9)
        uint256 expectedEarnings = (800 * PRICE_PER_TOKEN * 90) / 100;
        assertEq(totalEarnings, expectedEarnings);
    }
    
    function test_ViewsForHostWithNoSessions() public {
        // Get sessions for host with no activity
        uint256[] memory sessions = marketplace.getActiveSessionsForHost(host2);
        assertEq(sessions.length, 0);
        
        // Get stats for host with no sessions
        (
            uint256 totalSessions,
            uint256 activeSessions,
            uint256 completedSessions,
            uint256 totalTokensProven,
            uint256 totalEarnings
        ) = marketplace.getHostStats(host2);
        
        assertEq(totalSessions, 0);
        assertEq(activeSessions, 0);
        assertEq(completedSessions, 0);
        assertEq(totalTokensProven, 0);
        assertEq(totalEarnings, 0);
    }
    
    function test_ViewsForMultipleSessions() public {
        // Create 5 sessions for host1
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(user1);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user1, host1, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        // Complete some sessions
        proofSystem.setVerificationResult(true);
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(host1);
            marketplace.submitProofOfWork(i, "proof", 100 * i);
            
            vm.prank(user1);
            marketplace.completeSessionJob(i);
        }
        
        // Get active sessions (should be 2)
        uint256[] memory activeSessions = marketplace.getActiveSessionsForHost(host1);
        assertEq(activeSessions.length, 2);
        assertEq(activeSessions[0], 4);
        assertEq(activeSessions[1], 5);
        
        // Get stats
        (
            uint256 totalSessions,
            uint256 active,
            uint256 completed,
            uint256 totalTokens,
        ) = marketplace.getHostStats(host1);
        
        assertEq(totalSessions, 5);
        assertEq(active, 2);
        assertEq(completed, 3);
        assertEq(totalTokens, 600); // 100 + 200 + 300
    }
}