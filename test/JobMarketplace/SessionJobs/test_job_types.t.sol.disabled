// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";

contract JobTypesTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    
    function setUp() public {
        // Deploy contract
        marketplace = new JobMarketplaceFABWithS5();
    }
    
    function test_JobTypeEnumExists() public {
        // Test that JobType.SinglePrompt exists and equals 0
        assertEq(uint(JobMarketplaceFABWithS5.JobType.SinglePrompt), 0);
    }
    
    function test_JobTypeSessionExists() public {
        // Test that JobType.Session exists and equals 1
        assertEq(uint(JobMarketplaceFABWithS5.JobType.Session), 1);
    }
    
    function test_CanSetJobType() public {
        // Test that we can set and retrieve job types
        uint256 jobId = 1;
        
        // Access the jobTypes mapping (will fail until we add it)
        JobMarketplaceFABWithS5.JobType jobType = marketplace.jobTypes(jobId);
        
        // Default should be SinglePrompt (0)
        assertEq(uint(jobType), 0);
    }
    
    function test_JobTypeValuesAreDistinct() public {
        // Ensure enum values are different
        assertTrue(uint(JobMarketplaceFABWithS5.JobType.SinglePrompt) != uint(JobMarketplaceFABWithS5.JobType.Session));
    }
    
    function test_JobTypeEnumComplete() public {
        // Test that we have exactly 2 job types
        // SinglePrompt = 0, Session = 1
        assertEq(uint(JobMarketplaceFABWithS5.JobType.SinglePrompt), 0);
        assertEq(uint(JobMarketplaceFABWithS5.JobType.Session), 1);
        
        // Cast and verify range
        JobMarketplaceFABWithS5.JobType singleType = JobMarketplaceFABWithS5.JobType(0);
        JobMarketplaceFABWithS5.JobType sessionType = JobMarketplaceFABWithS5.JobType(1);
        
        assertEq(uint(singleType), 0);
        assertEq(uint(sessionType), 1);
    }
}