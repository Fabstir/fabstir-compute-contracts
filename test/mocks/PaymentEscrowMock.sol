// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/interfaces/IPaymentEscrow.sol";

contract PaymentEscrowMock is IPaymentEscrow {
    bytes32 public constant PROOF_SYSTEM_ROLE = keccak256("PROOF_SYSTEM_ROLE");
    
    // Simple role management
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    constructor() {
        _roles[bytes32(0)][msg.sender] = true; // Grant admin role
    }
    
    function grantRole(bytes32 role, address account) external {
        require(_roles[bytes32(0)][msg.sender], "Not admin");
        _roles[role][account] = true;
    }
}