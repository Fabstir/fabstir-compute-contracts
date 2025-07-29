// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {INodeRegistry} from "../../src/interfaces/INodeRegistry.sol";

contract MockNodeRegistry is INodeRegistry {
    mapping(address => bool) public activeNodes;
    
    function setActiveNode(address node, bool active) external {
        activeNodes[node] = active;
    }
    
    function isActiveNode(address operator) external view returns (bool) {
        return activeNodes[operator];
    }
}