// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";

contract StorageLayoutTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5();
    }
    
    function test_SessionsMappingStorage() public {
        uint256 jobId = 1;
        
        // Read from sessions mapping
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        
        // Verify default values
        assertEq(session.depositAmount, 0);
        assertEq(session.pricePerToken, 0);
        assertEq(session.maxDuration, 0);
        assertEq(session.sessionStartTime, 0);
        assertEq(session.assignedHost, address(0));
        assertEq(uint(session.status), 0);
        assertEq(session.provenTokens, 0);
        assertEq(session.lastProofSubmission, 0);
        assertEq(session.aggregateProofHash, bytes32(0));
        assertEq(session.checkpointInterval, 0);
    }
    
    function test_SessionProofsMappingStorage() public {
        uint256 jobId = 1;
        
        // Read from sessionProofs mapping (should return empty array)
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = marketplace.sessionProofs(jobId);
        
        // Verify empty array
        assertEq(proofs.length, 0);
    }
    
    function test_JobTypesMappingStorage() public {
        uint256 jobId = 1;
        
        // Read from jobTypes mapping
        JobMarketplaceFABWithS5.JobType jobType = marketplace.jobTypes(jobId);
        
        // Default should be SinglePrompt (0)
        assertEq(uint(jobType), 0);
    }
    
    function test_MultipleJobsStorage() public {
        // Test storage for multiple job IDs
        uint256[] memory jobIds = new uint256[](5);
        jobIds[0] = 1;
        jobIds[1] = 100;
        jobIds[2] = 999;
        jobIds[3] = 10000;
        jobIds[4] = type(uint256).max;
        
        for (uint256 i = 0; i < jobIds.length; i++) {
            uint256 jobId = jobIds[i];
            
            // Test sessions mapping
            JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
            assertEq(session.depositAmount, 0);
            
            // Test sessionProofs mapping
            JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = marketplace.sessionProofs(jobId);
            assertEq(proofs.length, 0);
            
            // Test jobTypes mapping
            JobMarketplaceFABWithS5.JobType jobType = marketplace.jobTypes(jobId);
            assertEq(uint(jobType), 0);
        }
    }
    
    function test_StorageIsolation() public {
        // Verify that different job IDs have isolated storage
        uint256 jobId1 = 1;
        uint256 jobId2 = 2;
        
        // Read sessions for both
        JobMarketplaceFABWithS5.SessionDetails memory session1 = marketplace.sessions(jobId1);
        JobMarketplaceFABWithS5.SessionDetails memory session2 = marketplace.sessions(jobId2);
        
        // Both should have default values but be independent
        assertEq(session1.depositAmount, 0);
        assertEq(session2.depositAmount, 0);
        
        // Read proofs for both
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs1 = marketplace.sessionProofs(jobId1);
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs2 = marketplace.sessionProofs(jobId2);
        
        assertEq(proofs1.length, 0);
        assertEq(proofs2.length, 0);
    }
    
    function test_GasForStorageAccess() public {
        uint256 jobId = 12345;
        
        // Measure gas for accessing sessions mapping
        uint256 gasStart = gasleft();
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        uint256 gasUsed = gasStart - gasleft();
        
        // Gas should be reasonable (< 10000 for cold read)
        assertLt(gasUsed, 10000);
        
        // Measure gas for accessing sessionProofs mapping
        gasStart = gasleft();
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = marketplace.sessionProofs(jobId);
        gasUsed = gasStart - gasleft();
        
        // Gas should be reasonable
        assertLt(gasUsed, 10000);
        
        // Measure gas for accessing jobTypes mapping
        gasStart = gasleft();
        JobMarketplaceFABWithS5.JobType jobType = marketplace.jobTypes(jobId);
        gasUsed = gasStart - gasleft();
        
        // Gas should be reasonable
        assertLt(gasUsed, 10000);
    }
    
    function test_LargeJobIdStorage() public {
        // Test with very large job IDs
        uint256 largeJobId = type(uint256).max - 1;
        
        // Should handle large IDs without issues
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(largeJobId);
        assertEq(session.depositAmount, 0);
        
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = marketplace.sessionProofs(largeJobId);
        assertEq(proofs.length, 0);
        
        JobMarketplaceFABWithS5.JobType jobType = marketplace.jobTypes(largeJobId);
        assertEq(uint(jobType), 0);
    }
}