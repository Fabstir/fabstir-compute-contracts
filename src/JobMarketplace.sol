// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./NodeRegistry.sol";
import "./ReputationSystem.sol";

contract JobMarketplace {
    enum JobStatus {
        Posted,
        Claimed,
        Completed
    }
    
    struct Job {
        address renter;
        string modelId;
        string inputHash;
        uint256 maxPrice;
        uint256 deadline;
        JobStatus status;
        address assignedHost;
        string resultHash;
    }
    
    NodeRegistry public nodeRegistry;
    ReputationSystem public reputationSystem;
    mapping(uint256 => Job) private jobs;
    uint256 private nextJobId;
    
    event JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice);
    event JobClaimed(uint256 indexed jobId, address indexed host);
    event JobCompleted(uint256 indexed jobId, address indexed host, string resultHash);
    
    constructor(address _nodeRegistry) {
        nodeRegistry = NodeRegistry(_nodeRegistry);
    }
    
    function setReputationSystem(address _reputationSystem) external {
        require(address(reputationSystem) == address(0), "ReputationSystem already set");
        reputationSystem = ReputationSystem(_reputationSystem);
    }
    
    function createJob(
        string memory _modelId,
        string memory _inputHash,
        uint256 _maxPrice,
        uint256 _deadline
    ) external payable returns (uint256) {
        require(msg.value >= _maxPrice, "Insufficient payment");
        require(_deadline > block.timestamp, "Invalid deadline");
        
        uint256 jobId = nextJobId++;
        
        jobs[jobId] = Job({
            renter: msg.sender,
            modelId: _modelId,
            inputHash: _inputHash,
            maxPrice: _maxPrice,
            deadline: _deadline,
            status: JobStatus.Posted,
            assignedHost: address(0),
            resultHash: ""
        });
        
        emit JobCreated(jobId, msg.sender, _modelId, _maxPrice);
        
        return jobId;
    }
    
    function claimJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        require(job.renter != address(0), "Job does not exist");
        require(job.status == JobStatus.Posted, "Job already claimed");
        
        // Verify host is registered
        NodeRegistry.Node memory node = nodeRegistry.getNode(msg.sender);
        require(node.operator != address(0), "Not a registered host");
        require(node.active, "Host not active");
        
        job.assignedHost = msg.sender;
        job.status = JobStatus.Claimed;
        
        emit JobClaimed(_jobId, msg.sender);
    }
    
    function completeJob(
        uint256 _jobId,
        string memory _resultHash,
        bytes memory _proof
    ) external {
        Job storage job = jobs[_jobId];
        require(job.assignedHost == msg.sender, "Not assigned host");
        require(job.status == JobStatus.Claimed, "Job not in claimed state");
        require(block.timestamp <= job.deadline, "Job deadline passed");
        
        job.resultHash = _resultHash;
        job.status = JobStatus.Completed;
        
        // Transfer payment to host
        (bool success, ) = payable(msg.sender).call{value: job.maxPrice}("");
        require(success, "ETH transfer failed");
        
        // Update reputation if system is set
        if (address(reputationSystem) != address(0)) {
            reputationSystem.recordJobCompletion(msg.sender, _jobId, true);
        }
        
        emit JobCompleted(_jobId, msg.sender, _resultHash);
    }
    
    function getJob(uint256 _jobId) external view returns (Job memory) {
        return jobs[_jobId];
    }
    
    // For testing purposes - allows marking a job as failed
    function failJob(uint256 _jobId) external {
        Job storage job = jobs[_jobId];
        require(job.assignedHost == msg.sender || job.renter == msg.sender, "Not authorized");
        require(job.status == JobStatus.Claimed, "Job not in claimed state");
        
        address failedHost = job.assignedHost;
        job.status = JobStatus.Posted; // Reset to allow re-claiming
        job.assignedHost = address(0);
        
        // Update reputation if system is set
        if (address(reputationSystem) != address(0) && failedHost != address(0)) {
            reputationSystem.recordJobCompletion(failedHost, _jobId, false);
        }
    }
}