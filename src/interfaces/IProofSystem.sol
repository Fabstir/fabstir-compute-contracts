// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IProofSystem {
    /**
     * @notice Verify host signature including modelId in the signed message
     * @param proof Proof bytes: [32 bytes proofHash][32 bytes r][32 bytes s][1 byte v]
     * @param prover Address that should have signed the proof (host)
     * @param claimedTokens Number of tokens being claimed
     * @param modelId Model ID for the session (bytes32(0) for non-model sessions)
     * @return True if signature is valid
     */
    function verifyHostSignature(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens,
        bytes32 modelId
    ) external view returns (bool);

    /**
     * @notice Verify and mark proof as complete (prevents replay)
     * @param proof Proof bytes: [32 bytes proofHash][32 bytes r][32 bytes s][1 byte v]
     * @param prover Address that should have signed the proof (host)
     * @param claimedTokens Number of tokens being claimed
     * @param modelId Model ID for the session (bytes32(0) for non-model sessions)
     * @return True if verification succeeded
     */
    function verifyAndMarkComplete(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens,
        bytes32 modelId
    ) external returns (bool);
}