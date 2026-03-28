// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IProofSystem {
    /**
     * @notice Mark a proof hash as used (replay protection only)
     * @dev Called by JobMarketplace after msg.sender authentication
     * @param proofHash The hash of the proof
     * @param prover The address of the prover (host) - for event logging
     * @param claimedTokens Number of tokens claimed - for event logging
     * @param modelId The model ID for the session (bytes32(0) for non-model sessions)
     * @return True if proof was successfully marked (not already used)
     */
    function markProofUsed(
        bytes32 proofHash,
        address prover,
        uint256 claimedTokens,
        bytes32 modelId
    ) external returns (bool);
}
