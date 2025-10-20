// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

contract MockNodeRegistry {
    struct Node {
        address operator;
        uint256 stakedAmount;
        bool active;
        uint256 reputation;
    }
    
    mapping(address => Node) public nodes;
    uint256 public constant MIN_STAKE = 1000 ether;
    
    function registerMockHost(address host) external {
        nodes[host] = Node({
            operator: host,
            stakedAmount: MIN_STAKE,
            active: true,
            reputation: 100
        });
    }
}
