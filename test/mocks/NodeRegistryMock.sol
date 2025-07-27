// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract NodeRegistryMock {
    struct Host {
        address operator;
        string uri;
        uint256 stake;
        bool active;
    }
    
    mapping(address => Host) public hosts;
    
    event HostRegistered(address indexed operator, string uri, uint256 stake);
    
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
}