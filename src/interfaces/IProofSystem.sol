// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

interface IProofSystem {
    function verifyHostSignature(
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