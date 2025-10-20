// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../../src/interfaces/IJobMarketplace.sol";

contract JobMarketplaceMock is IJobMarketplace {
    bytes32 public constant PROOF_SYSTEM_ROLE = keccak256("PROOF_SYSTEM_ROLE");
    
    // Simple role management
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    struct Job {
        address renter;
        string modelId;
        string inputHash;
        uint256 maxPrice;
        uint256 deadline;
        JobStatus status;
        address assignedHost;
        string resultHash;
        address paymentToken;
        bytes32 modelCommitment;
        bytes32 inputHashBytes;
    }
    
    mapping(uint256 => Job) public jobs;
    uint256 public nextJobId = 1;
    
    event JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice);
    event JobClaimed(uint256 indexed jobId, address indexed host);
    event JobCompleted(uint256 indexed jobId, address indexed host, bytes32 outputHash);
    
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    uint256 public maxJobDuration = 7 days;
    bool public paused;
    
    constructor() {
        _roles[bytes32(0)][msg.sender] = true; // Grant admin role
    }
    
    function grantRole(bytes32 role, address account) external {
        require(_roles[bytes32(0)][msg.sender], "Not admin");
        _roles[role][account] = true;
    }
    
    function setMaxJobDuration(uint256 _maxJobDuration) external {
        require(_roles[GOVERNANCE_ROLE][msg.sender], "Not governance");
        maxJobDuration = _maxJobDuration;
    }
    
    function pause() external {
        require(_roles[GOVERNANCE_ROLE][msg.sender], "Not governance");
        paused = true;
    }
    
    function unpause() external {
        require(_roles[GOVERNANCE_ROLE][msg.sender], "Not governance");
        paused = false;
    }
    
    function postJob(
        string memory modelId,
        uint256 maxPrice,
        address paymentToken,
        uint256 deadline,
        bytes32 modelCommitment,
        bytes32 inputHash
    ) external returns (uint256) {
        uint256 jobId = nextJobId++;
        
        jobs[jobId] = Job({
            renter: msg.sender,
            modelId: modelId,
            inputHash: string(abi.encodePacked(inputHash)),
            maxPrice: maxPrice,
            deadline: deadline,
            status: JobStatus.Posted,
            assignedHost: address(0),
            resultHash: "",
            paymentToken: paymentToken,
            modelCommitment: modelCommitment,
            inputHashBytes: inputHash
        });
        
        emit JobCreated(jobId, msg.sender, modelId, maxPrice);
        return jobId;
    }
    
    function claimJob(uint256 jobId) external {
        Job storage job = jobs[jobId];
        require(job.renter != address(0), "Job does not exist");
        require(job.status == JobStatus.Posted, "Job not available");
        
        job.status = JobStatus.Claimed;
        job.assignedHost = msg.sender;
        
        emit JobClaimed(jobId, msg.sender);
    }
    
    function completeJob(uint256 jobId, bytes32 outputHash) external {
        Job storage job = jobs[jobId];
        require(job.assignedHost == msg.sender, "Not assigned host");
        require(job.status == JobStatus.Claimed, "Invalid job status");
        
        // Check if proof is valid (would integrate with ProofSystem)
        require(_checkProofValid(jobId), "Valid proof required");
        
        job.status = JobStatus.Completed;
        job.resultHash = string(abi.encodePacked(outputHash));
        
        emit JobCompleted(jobId, msg.sender, outputHash);
    }
    
    function getJob(uint256 jobId) external view returns (
        address renter,
        string memory modelId,
        string memory inputHash,
        address paymentToken,
        JobStatus status,
        address assignedHost,
        string memory resultHash,
        bytes32 modelCommitment,
        bytes32 inputHashBytes
    ) {
        Job memory job = jobs[jobId];
        return (
            job.renter,
            job.modelId,
            job.inputHash,
            job.paymentToken,
            job.status,
            job.assignedHost,
            job.resultHash,
            job.modelCommitment,
            job.inputHashBytes
        );
    }
    
    address public proofSystem;
    
    function setProofSystem(address _proofSystem) external {
        proofSystem = _proofSystem;
    }
    
    function _checkProofValid(uint256 jobId) private view returns (bool) {
        if (proofSystem == address(0)) return false;
        
        // Call ProofSystem to check if job can be completed
        (bool success, bytes memory result) = proofSystem.staticcall(
            abi.encodeWithSignature("canCompleteJob(uint256)", jobId)
        );
        
        if (!success) return false;
        return abi.decode(result, (bool));
    }
    
    function postJobWithToken(
        JobDetails memory details,
        JobRequirements memory requirements,
        address paymentToken,
        uint256 paymentAmount
    ) external returns (bytes32) {
        // Mock implementation - just return a dummy job ID
        bytes32 jobId = keccak256(abi.encodePacked(msg.sender, block.timestamp, details.modelId));
        return jobId;
    }
}