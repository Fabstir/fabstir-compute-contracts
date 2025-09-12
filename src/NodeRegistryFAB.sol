// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract NodeRegistryFAB is Ownable, ReentrancyGuard {
    IERC20 public immutable fabToken;
    uint256 public constant MIN_STAKE = 1000 * 10**18; // 1000 FAB tokens
    
    struct Node {
        address operator;
        uint256 stakedAmount;
        bool active;
        string metadata;
        string apiUrl;  // API endpoint URL for host discovery
    }
    
    mapping(address => Node) public nodes;
    address[] public activeNodesList;
    mapping(address => uint256) public activeNodesIndex;
    
    event NodeRegistered(address indexed operator, uint256 stakedAmount, string metadata);
    event NodeRegisteredWithUrl(address indexed operator, uint256 stakedAmount, string metadata, string apiUrl);
    event NodeUnregistered(address indexed operator, uint256 returnedAmount);
    event StakeAdded(address indexed operator, uint256 additionalAmount);
    event MetadataUpdated(address indexed operator, string newMetadata);
    event ApiUrlUpdated(address indexed operator, string newApiUrl);
    
    constructor(address _fabToken) Ownable(msg.sender) {
        require(_fabToken != address(0), "Invalid token address");
        fabToken = IERC20(_fabToken);
    }
    
    function registerNode(string memory metadata) external nonReentrant {
        require(nodes[msg.sender].operator == address(0), "Already registered");
        require(bytes(metadata).length > 0, "Empty metadata");
        
        // Transfer MIN_STAKE FAB tokens from sender to contract
        require(fabToken.transferFrom(msg.sender, address(this), MIN_STAKE), "Transfer failed");
        
        nodes[msg.sender] = Node({
            operator: msg.sender,
            stakedAmount: MIN_STAKE,
            active: true,
            metadata: metadata,
            apiUrl: ""  // Empty by default for backward compatibility
        });
        
        activeNodesList.push(msg.sender);
        activeNodesIndex[msg.sender] = activeNodesList.length - 1;
        
        emit NodeRegistered(msg.sender, MIN_STAKE, metadata);
    }
    
    function unregisterNode() external nonReentrant {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Already inactive");
        
        uint256 stakedAmount = nodes[msg.sender].stakedAmount;
        
        // Clear all node data to allow re-registration
        delete nodes[msg.sender];
        
        // Remove from active nodes list
        uint256 index = activeNodesIndex[msg.sender];
        uint256 lastIndex = activeNodesList.length - 1;
        
        if (index != lastIndex) {
            address lastNode = activeNodesList[lastIndex];
            activeNodesList[index] = lastNode;
            activeNodesIndex[lastNode] = index;
        }
        
        activeNodesList.pop();
        delete activeNodesIndex[msg.sender];
        
        // Return staked tokens
        require(fabToken.transfer(msg.sender, stakedAmount), "Transfer failed");
        
        emit NodeUnregistered(msg.sender, stakedAmount);
    }
    
    function stake(uint256 amount) external nonReentrant {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(amount > 0, "Zero amount");
        
        require(fabToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        nodes[msg.sender].stakedAmount += amount;
        
        emit StakeAdded(msg.sender, amount);
    }
    
    function registerNodeWithUrl(string memory metadata, string memory apiUrl) external nonReentrant {
        require(nodes[msg.sender].operator == address(0), "Already registered");
        require(bytes(metadata).length > 0, "Empty metadata");
        require(bytes(apiUrl).length > 0, "Empty API URL");
        
        // Transfer MIN_STAKE FAB tokens from sender to contract
        require(fabToken.transferFrom(msg.sender, address(this), MIN_STAKE), "Transfer failed");
        
        nodes[msg.sender] = Node({
            operator: msg.sender,
            stakedAmount: MIN_STAKE,
            active: true,
            metadata: metadata,
            apiUrl: apiUrl
        });
        
        activeNodesList.push(msg.sender);
        activeNodesIndex[msg.sender] = activeNodesList.length - 1;
        
        emit NodeRegisteredWithUrl(msg.sender, MIN_STAKE, metadata, apiUrl);
    }
    
    function updateMetadata(string memory newMetadata) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(bytes(newMetadata).length > 0, "Empty metadata");
        
        nodes[msg.sender].metadata = newMetadata;
        emit MetadataUpdated(msg.sender, newMetadata);
    }
    
    function updateApiUrl(string memory newApiUrl) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(bytes(newApiUrl).length > 0, "Empty API URL");
        
        nodes[msg.sender].apiUrl = newApiUrl;
        emit ApiUrlUpdated(msg.sender, newApiUrl);
    }
    
    function getNodeStake(address operator) external view returns (uint256) {
        return nodes[operator].stakedAmount;
    }
    
    function isNodeActive(address operator) external view returns (bool) {
        return nodes[operator].active;
    }
    
    function getNodeMetadata(address operator) external view returns (string memory) {
        return nodes[operator].metadata;
    }
    
    function getNodeApiUrl(address operator) external view returns (string memory) {
        return nodes[operator].apiUrl;
    }
    
    function getNodeFullInfo(address operator) external view returns (
        address nodeOperator,
        uint256 stakedAmount,
        bool active,
        string memory metadata,
        string memory apiUrl
    ) {
        Node memory node = nodes[operator];
        return (
            node.operator,
            node.stakedAmount,
            node.active,
            node.metadata,
            node.apiUrl
        );
    }
    
    function minimumStake() external pure returns (uint256) {
        return MIN_STAKE;
    }
    
    function getAllActiveNodes() external view returns (address[] memory) {
        return activeNodesList;
    }
    
    function getActiveNodeCount() external view returns (uint256) {
        return activeNodesList.length;
    }
    
    // Compatibility function for UI
    function requiredStake() external pure returns (uint256) {
        return MIN_STAKE;
    }
    
    // Emergency function - only owner
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = fabToken.balanceOf(address(this));
        require(balance > 0, "No balance");
        require(fabToken.transfer(owner(), balance), "Transfer failed");
    }
}