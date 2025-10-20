// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

contract NodeRegistryMock {
    struct Host {
        address operator;
        string uri;
        uint256 stake;
        bool active;
    }
    
    mapping(address => Host) public hosts;
    mapping(bytes32 => mapping(address => bool)) private _roles;
    
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    
    uint256 public minimumStake = 100e18;
    
    event HostRegistered(address indexed operator, string uri, uint256 stake);
    
    constructor() {
        _roles[bytes32(0)][msg.sender] = true; // Admin role
    }
    
    function registerHost(string memory uri, uint256 stake) external {
        hosts[msg.sender] = Host({
            operator: msg.sender,
            uri: uri,
            stake: stake,
            active: true
        });
        
        emit HostRegistered(msg.sender, uri, stake);
    }
    
    function getHost(address operator) external view returns (Host memory) {
        return hosts[operator];
    }
    
    function setMinimumStake(uint256 _minimumStake) external {
        require(_roles[GOVERNANCE_ROLE][msg.sender], "Not governance");
        minimumStake = _minimumStake;
    }
    
    function grantRole(bytes32 role, address account) external {
        require(_roles[bytes32(0)][msg.sender], "Not admin");
        _roles[role][account] = true;
    }
}