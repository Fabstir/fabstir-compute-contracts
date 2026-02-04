// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

contract ProofSystemMock {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => bool) public verifiedProofs;

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bool private _verificationResult = true;

    constructor() {
        _roles[bytes32(0)][msg.sender] = true; // Admin role
    }

    function grantRole(bytes32 role, address account) external {
        require(_roles[bytes32(0)][msg.sender], "Not admin");
        _roles[role][account] = true;
    }

    function setVerificationResult(bool result) external {
        _verificationResult = result;
    }

    function markProofUsed(
        bytes32 proofHash,
        address,
        uint256,
        bytes32
    ) external returns (bool) {
        if (!_verificationResult) return false;
        if (verifiedProofs[proofHash]) return false;
        verifiedProofs[proofHash] = true;
        return true;
    }
}
