// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

contract ProofSystemMock {
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
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
    
    function verifyHostSignature(
        bytes calldata,
        address,
        uint256
    ) external view returns (bool) {
        return _verificationResult;
    }
    
    function verifyAndMarkComplete(
        bytes calldata proof,
        address prover,
        uint256 tokens
    ) external returns (bool) {
        return _verificationResult;
    }
}