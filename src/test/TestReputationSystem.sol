// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../ReputationSystem.sol";

// Test wrapper for ReputationSystem that allows deployment without parameters
contract TestReputationSystem is ReputationSystem {
    constructor() ReputationSystem(address(1), address(1), address(1)) {
        // Deploy with dummy addresses, will be initialized later
    }
    
    function initializeForTest(address _nodeRegistry, address _jobMarketplace, address _governance) external {
        nodeRegistry = NodeRegistry(_nodeRegistry);
        jobMarketplace = JobMarketplace(_jobMarketplace);  
        governance = _governance;
    }
}