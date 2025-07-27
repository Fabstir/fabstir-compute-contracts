// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IReputationSystem {
    function recordJobCompletion(address host, uint256 jobId, bool success) external;
    function getReputation(address host) external view returns (uint256);
}