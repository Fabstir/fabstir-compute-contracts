// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {JobMarketplace} from "../../src/JobMarketplace.sol";
import {NodeRegistry} from "../../src/NodeRegistry.sol";

contract JobMarketplaceTest is Test {
    JobMarketplace public jobMarketplace;
    NodeRegistry public nodeRegistry;
    
    address constant RENTER = address(0x1);
    address constant HOST = address(0x2);
    address constant HOST2 = address(0x3);
    
    uint256 constant JOB_PRICE = 10 ether;
    uint256 constant HOST_STAKE = 100 ether;
    
    string constant MODEL_ID = "llama3-70b";
    string constant INPUT_HASH = "QmExample123";
    
    function setUp() public {
        nodeRegistry = new NodeRegistry(10 ether);
        jobMarketplace = new JobMarketplace(address(nodeRegistry));
        
        // Setup test accounts
        vm.deal(RENTER, 1000 ether);
        vm.deal(HOST, 1000 ether);
        vm.deal(HOST2, 1000 ether);
        
        // Register hosts
        vm.prank(HOST);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost1",
            _createModels(),
            "us-east-1"
        );
        
        vm.prank(HOST2);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost2", 
            _createModels(),
            "us-west-2"
        );
    }
    
    function test_CreateJob() public {
        vm.startPrank(RENTER);
        
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        JobMarketplace.Job memory job = jobMarketplace.getJobStruct(jobId);
        
        assertEq(job.renter, RENTER);
        assertEq(job.modelId, MODEL_ID);
        assertEq(job.inputHash, INPUT_HASH);
        assertEq(job.maxPrice, JOB_PRICE);
        assertEq(job.deadline, block.timestamp + 1 hours);
        assertEq(uint256(job.status), uint256(JobMarketplace.JobStatus.Posted));
        
        vm.stopPrank();
    }
    
    function test_CannotCreateJobWithoutPayment() public {
        vm.startPrank(RENTER);
        
        vm.expectRevert("Insufficient payment");
        jobMarketplace.createJob{value: 0}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        vm.stopPrank();
    }
    
    function test_ClaimJob() public {
        // Create job first
        vm.prank(RENTER);
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        // Host claims job
        vm.prank(HOST);
        jobMarketplace.claimJob(jobId);
        
        JobMarketplace.Job memory job = jobMarketplace.getJobStruct(jobId);
        assertEq(job.assignedHost, HOST);
        assertEq(uint256(job.status), uint256(JobMarketplace.JobStatus.Claimed));
    }
    
    function test_OnlyRegisteredHostCanClaimJob() public {
        // Create job
        vm.prank(RENTER);
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        // Unregistered address tries to claim
        address unregistered = address(0x999);
        vm.prank(unregistered);
        vm.expectRevert("Not a registered host");
        jobMarketplace.claimJob(jobId);
    }
    
    function test_CannotClaimAlreadyClaimedJob() public {
        // Create and claim job
        vm.prank(RENTER);
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        vm.prank(HOST);
        jobMarketplace.claimJob(jobId);
        
        // Another host tries to claim
        vm.prank(HOST2);
        vm.expectRevert("Job already claimed");
        jobMarketplace.claimJob(jobId);
    }
    
    function test_CompleteJob() public {
        // Create and claim job
        vm.prank(RENTER);
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        vm.prank(HOST);
        jobMarketplace.claimJob(jobId);
        
        // Host completes job
        string memory resultHash = "QmResult456";
        bytes memory proof = "0x1234"; // Simplified proof
        
        uint256 hostBalanceBefore = HOST.balance;
        
        vm.prank(HOST);
        jobMarketplace.completeJob(jobId, resultHash, proof);
        
        // Verify job status and payment
        JobMarketplace.Job memory job = jobMarketplace.getJobStruct(jobId);
        assertEq(uint256(job.status), uint256(JobMarketplace.JobStatus.Completed));
        assertEq(job.resultHash, resultHash);
        
        // Host should receive payment
        assertEq(HOST.balance, hostBalanceBefore + JOB_PRICE);
    }
    
    function test_OnlyAssignedHostCanCompleteJob() public {
        // Create and claim job
        vm.prank(RENTER);
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        vm.prank(HOST);
        jobMarketplace.claimJob(jobId);
        
        // Different host tries to complete
        vm.prank(HOST2);
        vm.expectRevert("Not assigned host");
        jobMarketplace.completeJob(jobId, "QmResult", "0x1234");
    }
    
    function test_CannotCompleteAfterDeadline() public {
        // Create job with short deadline
        vm.prank(RENTER);
        uint256 jobId = jobMarketplace.createJob{value: JOB_PRICE}(
            MODEL_ID,
            INPUT_HASH,
            JOB_PRICE,
            block.timestamp + 1 hours
        );
        
        vm.prank(HOST);
        jobMarketplace.claimJob(jobId);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 2 hours);
        
        vm.prank(HOST);
        vm.expectRevert("Job deadline passed");
        jobMarketplace.completeJob(jobId, "QmResult", "0x1234");
    }
    
    function _createModels() private pure returns (string[] memory) {
        string[] memory models = new string[](2);
        models[0] = "llama3-70b";
        models[1] = "mistral-7b";
        return models;
    }
}
