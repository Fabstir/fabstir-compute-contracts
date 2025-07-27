// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/interfaces/IReputationSystem.sol";

contract ReputationSystemMock is IReputationSystem {
    mapping(address => uint256) public reputation;
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    uint256 public decayRate = 100; // 100%
    
    constructor() {
        // Initialize with default reputation
        _roles[bytes32(0)][msg.sender] = true; // Admin role
    }
    
    function recordJobCompletion(address host, uint256, bool success) external {
        // Initialize reputation if not set
        if (reputation[host] == 0) {
            reputation[host] = 1000;
        }
        
        if (success) {
            reputation[host] += 10;
        } else {
            if (reputation[host] >= 20) {
                reputation[host] -= 20;
            } else {
                reputation[host] = 0;
            }
        }
    }
    
    function getReputation(address host) external view returns (uint256) {
        return reputation[host] == 0 ? 1000 : reputation[host]; // Default 1000
    }
    
    function setDecayRate(uint256 _decayRate) external {
        require(_roles[GOVERNANCE_ROLE][msg.sender], "Not governance");
        decayRate = _decayRate;
    }
    
    function grantRole(bytes32 role, address account) external {
        require(_roles[bytes32(0)][msg.sender], "Not admin");
        _roles[role][account] = true;
    }
}