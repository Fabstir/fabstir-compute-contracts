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
    uint256 public MIN_STAKE;
    
    constructor(uint256 _minStake) {
        MIN_STAKE = _minStake;
    }
    
    event NodeRegistered(address indexed node, string metadata);
    
    function registerNodeSimple(string memory metadata) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[msg.sender].operator == address(0), "Already registered");
        
        // For simplicity, parse metadata as peerId
        string[] memory emptyModels = new string[](0);
        nodes[msg.sender] = Node({
            operator: msg.sender,
            peerId: metadata,
            stake: msg.value,
            active: true,
            models: emptyModels,
            region: ""
        });
        
        emit NodeRegistered(msg.sender, metadata);
    }
    
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
        
        emit NodeRegistered(msg.sender, _peerId);
    }
    
    function getNode(address _operator) external view returns (Node memory) {
        return nodes[_operator];
    }
    
    function isNodeActive(address _operator) external view returns (bool) {
        return nodes[_operator].active && nodes[_operator].operator != address(0);
    }
    
    function getNodeStake(address _operator) external view returns (uint256) {
        return nodes[_operator].stake;
    }
    
    function requiredStake() external view returns (uint256) {
        return MIN_STAKE;
    }
    
    function updateStakeAmount(uint256 newAmount) external {
        // In production, this would have access control
        MIN_STAKE = newAmount;
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
        
        emit NodeRegistered(operator, _peerId);
    }
    
    function isActiveNode(address operator) external view returns (bool) {
        return nodes[operator].active && nodes[operator].stake >= MIN_STAKE;
    }
}
