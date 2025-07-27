// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/interfaces/IReputationSystem.sol";

contract ReputationSystemMock is IReputationSystem {
    mapping(address => uint256) public reputation;
    
    constructor() {
        // Initialize with default reputation
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
}