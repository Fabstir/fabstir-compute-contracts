// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProofSystem {
    function verifyEKZL(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external view returns (bool);

    function verifyAndMarkComplete(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external returns (bool);
}