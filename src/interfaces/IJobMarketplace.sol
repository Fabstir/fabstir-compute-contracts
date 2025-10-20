// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IJobMarketplace {
    enum JobStatus {
        Posted,
        Claimed,
        Completed
    }
    
    struct JobDetails {
        string modelId;
        string prompt;
        uint256 maxTokens;
        uint256 temperature;
        uint32 seed;
        string resultFormat;
    }
    
    struct JobRequirements {
        uint256 minGPUMemory;
        uint256 minReputationScore;
        uint256 maxTimeToComplete;
        bool requiresProof;
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
    );
    
    function postJob(
        string memory modelId,
        uint256 maxPrice,
        address paymentToken,
        uint256 deadline,
        bytes32 modelCommitment,
        bytes32 inputHash
    ) external returns (uint256);
    
    function claimJob(uint256 jobId) external;
    
    function completeJob(uint256 jobId, bytes32 outputHash) external;
    
    function grantRole(bytes32 role, address account) external;
    
    function PROOF_SYSTEM_ROLE() external view returns (bytes32);
    
    function postJobWithToken(
        JobDetails memory details,
        JobRequirements memory requirements,
        address paymentToken,
        uint256 paymentAmount
    ) external returns (bytes32);
}