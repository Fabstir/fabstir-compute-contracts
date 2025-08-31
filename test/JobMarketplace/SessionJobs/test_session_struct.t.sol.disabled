// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";

contract SessionStructTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5();
    }
    
    function test_SessionStatusEnumExists() public {
        // Test SessionStatus enum values
        assertEq(uint(JobMarketplaceFABWithS5.SessionStatus.Active), 0);
        assertEq(uint(JobMarketplaceFABWithS5.SessionStatus.Completed), 1);
        assertEq(uint(JobMarketplaceFABWithS5.SessionStatus.TimedOut), 2);
        assertEq(uint(JobMarketplaceFABWithS5.SessionStatus.Disputed), 3);
        assertEq(uint(JobMarketplaceFABWithS5.SessionStatus.Abandoned), 4);
    }
    
    function test_SessionDetailsStructCompiles() public {
        // Create a SessionDetails struct
        JobMarketplaceFABWithS5.SessionDetails memory session;
        
        // Set all fields
        session.depositAmount = 1000 ether;
        session.pricePerToken = 1e15; // 0.001 ether per token
        session.maxDuration = 3600; // 1 hour
        session.sessionStartTime = block.timestamp;
        session.assignedHost = address(0x123);
        session.status = JobMarketplaceFABWithS5.SessionStatus.Active;
        session.provenTokens = 0;
        session.lastProofSubmission = 0;
        session.aggregateProofHash = bytes32(0);
        session.checkpointInterval = 100; // Every 100 tokens
        
        // Verify fields
        assertEq(session.depositAmount, 1000 ether);
        assertEq(session.pricePerToken, 1e15);
        assertEq(session.maxDuration, 3600);
        assertEq(session.sessionStartTime, block.timestamp);
        assertEq(session.assignedHost, address(0x123));
        assertEq(uint(session.status), uint(JobMarketplaceFABWithS5.SessionStatus.Active));
        assertEq(session.provenTokens, 0);
        assertEq(session.lastProofSubmission, 0);
        assertEq(session.aggregateProofHash, bytes32(0));
        assertEq(session.checkpointInterval, 100);
    }
    
    function test_CanAccessSessionsMapping() public {
        uint256 jobId = 1;
        
        // Access the sessions mapping
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        
        // Check default values
        assertEq(session.depositAmount, 0);
        assertEq(session.pricePerToken, 0);
        assertEq(session.maxDuration, 0);
        assertEq(session.sessionStartTime, 0);
        assertEq(session.assignedHost, address(0));
        assertEq(uint(session.status), 0); // Active by default
        assertEq(session.provenTokens, 0);
        assertEq(session.lastProofSubmission, 0);
        assertEq(session.aggregateProofHash, bytes32(0));
        assertEq(session.checkpointInterval, 0);
    }
    
    function test_SessionStatusAllValues() public {
        // Test all status transitions are valid
        JobMarketplaceFABWithS5.SessionStatus status;
        
        status = JobMarketplaceFABWithS5.SessionStatus.Active;
        assertEq(uint(status), 0);
        
        status = JobMarketplaceFABWithS5.SessionStatus.Completed;
        assertEq(uint(status), 1);
        
        status = JobMarketplaceFABWithS5.SessionStatus.TimedOut;
        assertEq(uint(status), 2);
        
        status = JobMarketplaceFABWithS5.SessionStatus.Disputed;
        assertEq(uint(status), 3);
        
        status = JobMarketplaceFABWithS5.SessionStatus.Abandoned;
        assertEq(uint(status), 4);
    }
    
    function test_SessionDetailsFieldTypes() public {
        // This test verifies the struct has the correct field types
        JobMarketplaceFABWithS5.SessionDetails memory session;
        
        // Test uint256 fields
        session.depositAmount = type(uint256).max;
        session.pricePerToken = type(uint256).max;
        session.maxDuration = type(uint256).max;
        session.sessionStartTime = type(uint256).max;
        session.provenTokens = type(uint256).max;
        session.lastProofSubmission = type(uint256).max;
        session.checkpointInterval = type(uint256).max;
        
        // Test address field
        session.assignedHost = address(type(uint160).max);
        
        // Test bytes32 field
        session.aggregateProofHash = bytes32(type(uint256).max);
        
        // Test enum field
        session.status = JobMarketplaceFABWithS5.SessionStatus.Abandoned;
        
        // Verify all assignments worked
        assertTrue(session.depositAmount > 0);
        assertTrue(session.assignedHost != address(0));
        assertTrue(session.aggregateProofHash != bytes32(0));
    }
}