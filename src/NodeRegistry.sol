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
    address[] private nodeList; // Track all registered nodes
    
    // Circuit breaker for registration spam
    uint256 private registrationCount;
    uint256 private registrationWindowStart;
    uint256 private constant REGISTRATION_WINDOW = 1 hours;
    uint256 private constant MAX_REGISTRATIONS_PER_WINDOW = 10;
    bool private registrationPaused;
    
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
        require(!registrationPaused, "Registration is paused");
        require(bytes(metadata).length > 0, "Empty metadata");
        require(bytes(metadata).length <= 10000, "Metadata too long");
        require(_validateString(metadata), "Invalid characters");
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(nodes[msg.sender].operator == address(0), "Already registered");
        
        // Check registration rate
        if (block.timestamp > registrationWindowStart + REGISTRATION_WINDOW) {
            registrationWindowStart = block.timestamp;
            registrationCount = 0;
        }
        
        registrationCount++;
        if (registrationCount >= MAX_REGISTRATIONS_PER_WINDOW) {
            registrationPaused = true;
        }
        
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
        
        // Track node in list
        nodeList.push(msg.sender);
        
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
        
        // Track node in list
        nodeList.push(msg.sender);
        
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
        require(newAmount > 0, "Stake must be positive");
        require(newAmount < 10000 ether, "Stake too high");
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
        
        // Track node in list
        nodeList.push(operator);
        
        emit NodeRegistered(operator, _peerId);
    }
    
    function isActiveNode(address operator) external view returns (bool) {
        return nodes[operator].active && nodes[operator].stake >= MIN_STAKE;
    }
    
    function setGovernance(address _governance) external onlyOwner {
        require(_governance != address(0), "Invalid address");
        require(governance == address(0), "Governance already set");
        governance = _governance;
    }
    
    function getGovernance() external view returns (address) {
        return governance;
    }
    
    function isRegistrationPaused() external view returns (bool) {
        return registrationPaused;
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
        
        // Track node in list
        nodeList.push(nodeOperator);
        
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
    
    function _validateString(string memory str) private pure returns (bool) {
        bytes memory b = bytes(str);
        for (uint i = 0; i < b.length; i++) {
            uint8 char = uint8(b[i]);
            // Reject null bytes, newlines, carriage returns, and other control characters
            if (char < 0x20 || char == 0x7F) {
                return false;
            }
        }
        return true;
    }

    // ========== Migration Functions ==========
    
    address public migrationHelper;
    
    modifier onlyMigrationHelper() {
        require(msg.sender == migrationHelper, "Only migration helper");
        _;
    }
    
    function setMigrationHelper(address _migrationHelper) external onlyOwner {
        require(_migrationHelper != address(0), "Invalid address");
        migrationHelper = _migrationHelper;
    }
    
    function addMigratedNode(
        address operator,
        string memory peerId,
        string[] memory models,
        string memory region
    ) external payable onlyMigrationHelper {
        require(nodes[operator].operator == address(0), "Node exists");
        require(msg.value > 0, "No stake provided");
        
        nodes[operator] = Node({
            operator: operator,
            peerId: peerId,
            stake: msg.value,
            active: true,
            models: models,
            region: region
        });
        
        // Track node in list
        nodeList.push(operator);
        
        emit NodeRegistered(operator, peerId);
    }
    
    function getActiveNodes() external view returns (address[] memory) {
        // Count active nodes
        uint256 activeCount = 0;
        for (uint256 i = 0; i < nodeList.length; i++) {
            if (nodes[nodeList[i]].active) {
                activeCount++;
            }
        }
        
        // Create array of active nodes
        address[] memory activeNodes = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < nodeList.length; i++) {
            if (nodes[nodeList[i]].active) {
                activeNodes[index++] = nodeList[i];
            }
        }
        
        return activeNodes;
    }
    
    function minimumStake() external view returns (uint256) {
        return MIN_STAKE;
    }
}
