// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract NodeRegistry {
    struct Node {
        address operator;
        string peerId;
        uint256 stake;
        bool active;
        string[] models;
        string region;
    }
    
    mapping(address => Node) private nodes;
    uint256 public constant MIN_STAKE = 100 ether;
    
    event NodeRegistered(address indexed operator, string peerId, uint256 stake);
    
    function registerNode(
        string memory _peerId,
        string[] memory _models,
        string memory _region
    ) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[msg.sender].operator == address(0), "Already registered");
        
        nodes[msg.sender] = Node({
            operator: msg.sender,
            peerId: _peerId,
            stake: msg.value,
            active: true,
            models: _models,
            region: _region
        });
        
        emit NodeRegistered(msg.sender, _peerId, msg.value);
    }
    
    function getNode(address _operator) external view returns (Node memory) {
        return nodes[_operator];
    }
    
    // For BaseAccountIntegration - register node on behalf of a wallet
    function registerNodeFor(
        address operator,
        string memory _peerId,
        string[] memory _models,
        string memory _region
    ) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[operator].operator == address(0), "Already registered");
        
        nodes[operator] = Node({
            operator: operator,
            peerId: _peerId,
            stake: msg.value,
            active: true,
            models: _models,
            region: _region
        });
        
        emit NodeRegistered(operator, _peerId, msg.value);
    }
    
    function isActiveNode(address operator) external view returns (bool) {
        return nodes[operator].active && nodes[operator].stake >= MIN_STAKE;
    }
}
