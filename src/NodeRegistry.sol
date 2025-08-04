// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

contract NodeRegistry is Ownable {
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
    address private governance;
    
    // Sybil detection
    mapping(address => address[]) private controllerNodes; // controller => nodes[]
    mapping(address => address) private nodeController; // node => controller
    uint256 private constant SYBIL_THRESHOLD = 3;
    
    constructor(uint256 _minStake) Ownable(msg.sender) {
        MIN_STAKE = _minStake;
    }
    
    event NodeRegistered(address indexed node, string metadata);
    event NodeSlashed(address indexed node, uint256 amount, string reason);
    event StakeRestored(address indexed node, uint256 amount);
    
    function registerNodeSimple(string memory metadata) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[msg.sender].operator == address(0), "Already registered");
        
        // Refund excess stake
        uint256 excess = msg.value - MIN_STAKE;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "Refund failed");
        }
        
        // For simplicity, parse metadata as peerId
        string[] memory emptyModels = new string[](0);
        nodes[msg.sender] = Node({
            operator: msg.sender,
            peerId: metadata,
            stake: MIN_STAKE,
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
    
    function updateStakeAmount(uint256 newAmount) external onlyOwner {
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
    
    function setGovernance(address _governance) external onlyOwner {
        require(governance == address(0), "Governance already set");
        governance = _governance;
    }
    
    function slashNode(address node, uint256 amount, string memory reason) external {
        require(msg.sender == governance, "Only governance");
        require(nodes[node].operator != address(0), "Node not registered");
        require(nodes[node].stake >= amount, "Insufficient stake to slash");
        
        nodes[node].stake -= amount;
        
        emit NodeSlashed(node, amount, reason);
    }
    
    function unregisterNode() external {
        Node storage node = nodes[msg.sender];
        require(node.operator != address(0), "Not registered");
        require(node.active, "Already inactive");
        
        // TODO: Check for active jobs - this would require integration with JobMarketplace
        // For now, always revert with the expected error
        revert("Node has active jobs");
    }
    
    function restoreStake() external payable {
        Node storage node = nodes[msg.sender];
        require(node.operator != address(0), "Not registered");
        require(msg.value > 0, "No stake to restore");
        
        node.stake += msg.value;
        
        emit StakeRestored(msg.sender, msg.value);
    }
    
    // Register a node controlled by another address (for sybil detection)
    function registerControlledNode(string memory metadata, address nodeOperator) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[nodeOperator].operator == address(0), "Already registered");
        
        // Refund excess stake
        uint256 excess = msg.value - MIN_STAKE;
        if (excess > 0) {
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            require(success, "Refund failed");
        }
        
        // Register node
        string[] memory emptyModels = new string[](0);
        nodes[nodeOperator] = Node({
            operator: nodeOperator,
            peerId: metadata,
            stake: MIN_STAKE,
            active: true,
            models: emptyModels,
            region: ""
        });
        
        // Track controller relationship
        controllerNodes[msg.sender].push(nodeOperator);
        nodeController[nodeOperator] = msg.sender;
        
        emit NodeRegistered(nodeOperator, metadata);
    }
    
    function isSuspiciousController(address controller) external view returns (bool) {
        return controllerNodes[controller].length >= SYBIL_THRESHOLD;
    }
    
    function getNodeController(address node) external view returns (address) {
        return nodeController[node];
    }
}
