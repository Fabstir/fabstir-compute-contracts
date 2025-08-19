// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/interfaces/IPaymentEscrow.sol";

contract PaymentEscrowMock is IPaymentEscrow {
    bytes32 public constant PROOF_SYSTEM_ROLE = keccak256("PROOF_SYSTEM_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    // Simple role management
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    uint256 public feePercentage = 200; // 2%
    
    constructor() {
        _roles[bytes32(0)][msg.sender] = true; // Grant admin role
    }
    
    function grantRole(bytes32 role, address account) external {
        require(_roles[bytes32(0)][msg.sender], "Not admin");
        _roles[role][account] = true;
    }
    
    function setFeePercentage(uint256 _feePercentage) external {
        require(_roles[GOVERNANCE_ROLE][msg.sender], "Not governance");
        feePercentage = _feePercentage;
    }
    
    function createEscrow(
        bytes32 _jobId,
        address _host,
        uint256 _amount,
        address _token
    ) external payable {
        // Mock implementation - does nothing
    }
    
    function releaseEscrow(bytes32 _jobId) external {
        // Mock implementation - does nothing
    }
}