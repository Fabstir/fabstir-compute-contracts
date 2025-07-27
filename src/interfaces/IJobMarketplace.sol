// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IJobMarketplace {
    enum JobStatus {
        Posted,
        Claimed,
        Completed
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
}