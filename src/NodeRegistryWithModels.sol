// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ModelRegistry.sol";

/**
 * @title NodeRegistryWithModels
 * @notice Extended NodeRegistry that integrates with ModelRegistry for approved models
 * @dev Hosts must register with approved models and use structured JSON metadata
 */
contract NodeRegistryWithModels is Ownable, ReentrancyGuard {
    IERC20 public immutable fabToken;
    ModelRegistry public modelRegistry;
    uint256 public constant MIN_STAKE = 1000 * 10**18; // 1000 FAB tokens

    struct Node {
        address operator;
        uint256 stakedAmount;
        bool active;
        string metadata;        // JSON formatted metadata
        string apiUrl;          // API endpoint URL
        bytes32[] supportedModels; // Array of model IDs this node supports
    }

    // Mappings
    mapping(address => Node) public nodes;
    mapping(address => uint256) public activeNodesIndex;
    mapping(bytes32 => address[]) public modelToNodes; // modelId => array of nodes supporting it

    address[] public activeNodesList;

    // Events
    event NodeRegistered(address indexed operator, uint256 stakedAmount, string metadata, bytes32[] models);
    event NodeUnregistered(address indexed operator, uint256 returnedAmount);
    event MetadataUpdated(address indexed operator, string newMetadata);
    event ApiUrlUpdated(address indexed operator, string newApiUrl);
    event ModelsUpdated(address indexed operator, bytes32[] newModels);
    event ModelRegistryUpdated(address indexed newRegistry);

    constructor(address _fabToken, address _modelRegistry) Ownable(msg.sender) {
        require(_fabToken != address(0), "Invalid FAB token address");
        require(_modelRegistry != address(0), "Invalid model registry address");
        fabToken = IERC20(_fabToken);
        modelRegistry = ModelRegistry(_modelRegistry);
    }

    /**
     * @notice Register a node with supported models
     * @param metadata JSON formatted metadata with hardware specs, capabilities, etc.
     * @param apiUrl The API endpoint URL for the node
     * @param modelIds Array of model IDs this node supports
     */
    function registerNode(
        string memory metadata,
        string memory apiUrl,
        bytes32[] memory modelIds
    ) external nonReentrant {
        require(nodes[msg.sender].operator == address(0), "Already registered");
        require(bytes(metadata).length > 0, "Empty metadata");
        require(bytes(apiUrl).length > 0, "Empty API URL");
        require(modelIds.length > 0, "Must support at least one model");

        // Verify all models are approved
        for (uint i = 0; i < modelIds.length; i++) {
            require(modelRegistry.isModelApproved(modelIds[i]), "Model not approved");
        }

        // Transfer stake
        require(fabToken.transferFrom(msg.sender, address(this), MIN_STAKE), "Stake transfer failed");

        // Create node
        nodes[msg.sender] = Node({
            operator: msg.sender,
            stakedAmount: MIN_STAKE,
            active: true,
            metadata: metadata,
            apiUrl: apiUrl,
            supportedModels: modelIds
        });

        // Add to active nodes list
        activeNodesIndex[msg.sender] = activeNodesList.length;
        activeNodesList.push(msg.sender);

        // Update model-to-nodes mapping
        for (uint i = 0; i < modelIds.length; i++) {
            modelToNodes[modelIds[i]].push(msg.sender);
        }

        emit NodeRegistered(msg.sender, MIN_STAKE, metadata, modelIds);
    }

    /**
     * @notice Update supported models for a node
     */
    function updateSupportedModels(bytes32[] memory newModelIds) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(newModelIds.length > 0, "Must support at least one model");

        // Verify all models are approved
        for (uint i = 0; i < newModelIds.length; i++) {
            require(modelRegistry.isModelApproved(newModelIds[i]), "Model not approved");
        }

        // Remove node from old model mappings
        bytes32[] memory oldModels = nodes[msg.sender].supportedModels;
        for (uint i = 0; i < oldModels.length; i++) {
            _removeNodeFromModel(oldModels[i], msg.sender);
        }

        // Update supported models
        nodes[msg.sender].supportedModels = newModelIds;

        // Add node to new model mappings
        for (uint i = 0; i < newModelIds.length; i++) {
            modelToNodes[newModelIds[i]].push(msg.sender);
        }

        emit ModelsUpdated(msg.sender, newModelIds);
    }

    /**
     * @notice Get nodes that support a specific model
     */
    function getNodesForModel(bytes32 modelId) external view returns (address[] memory) {
        return modelToNodes[modelId];
    }

    /**
     * @notice Get all models supported by a node
     */
    function getNodeModels(address nodeAddress) external view returns (bytes32[] memory) {
        return nodes[nodeAddress].supportedModels;
    }

    /**
     * @notice Check if a node supports a specific model
     */
    function nodeSupportsModel(address nodeAddress, bytes32 modelId) external view returns (bool) {
        bytes32[] memory models = nodes[nodeAddress].supportedModels;
        for (uint i = 0; i < models.length; i++) {
            if (models[i] == modelId) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Update metadata (must maintain valid JSON format)
     */
    function updateMetadata(string memory newMetadata) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(bytes(newMetadata).length > 0, "Empty metadata");

        nodes[msg.sender].metadata = newMetadata;
        emit MetadataUpdated(msg.sender, newMetadata);
    }

    /**
     * @notice Update API URL
     */
    function updateApiUrl(string memory newApiUrl) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(bytes(newApiUrl).length > 0, "Empty API URL");

        nodes[msg.sender].apiUrl = newApiUrl;
        emit ApiUrlUpdated(msg.sender, newApiUrl);
    }

    /**
     * @notice Unregister node and return stake
     */
    function unregisterNode() external nonReentrant {
        require(nodes[msg.sender].operator != address(0), "Not registered");

        uint256 stakeToReturn = nodes[msg.sender].stakedAmount;
        bytes32[] memory models = nodes[msg.sender].supportedModels;

        // Remove from model mappings
        for (uint i = 0; i < models.length; i++) {
            _removeNodeFromModel(models[i], msg.sender);
        }

        // Remove from active nodes list
        uint256 index = activeNodesIndex[msg.sender];
        uint256 lastIndex = activeNodesList.length - 1;
        if (index != lastIndex) {
            address lastNode = activeNodesList[lastIndex];
            activeNodesList[index] = lastNode;
            activeNodesIndex[lastNode] = index;
        }
        activeNodesList.pop();

        // Delete node data
        delete activeNodesIndex[msg.sender];
        delete nodes[msg.sender];

        // Return stake
        require(fabToken.transfer(msg.sender, stakeToReturn), "Stake return failed");

        emit NodeUnregistered(msg.sender, stakeToReturn);
    }

    /**
     * @notice Add additional stake
     */
    function stake(uint256 amount) external nonReentrant {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(amount > 0, "Zero amount");

        require(fabToken.transferFrom(msg.sender, address(this), amount), "Stake transfer failed");
        nodes[msg.sender].stakedAmount += amount;
    }

    /**
     * @notice Check if address is an active node
     */
    function isActiveNode(address operator) external view returns (bool) {
        return nodes[operator].active;
    }

    /**
     * @notice Get node API URL
     */
    function getNodeApiUrl(address operator) external view returns (string memory) {
        return nodes[operator].apiUrl;
    }

    /**
     * @notice Get full node information
     */
    function getNodeFullInfo(address operator) external view returns (
        address,
        uint256,
        bool,
        string memory,
        string memory,
        bytes32[] memory
    ) {
        Node storage node = nodes[operator];
        return (
            node.operator,
            node.stakedAmount,
            node.active,
            node.metadata,
            node.apiUrl,
            node.supportedModels
        );
    }

    /**
     * @notice Get all active nodes
     */
    function getAllActiveNodes() external view returns (address[] memory) {
        return activeNodesList;
    }

    /**
     * @notice Update model registry address (owner only)
     */
    function updateModelRegistry(address newRegistry) external onlyOwner {
        require(newRegistry != address(0), "Invalid registry address");
        modelRegistry = ModelRegistry(newRegistry);
        emit ModelRegistryUpdated(newRegistry);
    }

    /**
     * @notice Remove node from model mapping
     */
    function _removeNodeFromModel(bytes32 modelId, address nodeAddress) private {
        address[] storage nodesForModel = modelToNodes[modelId];
        for (uint i = 0; i < nodesForModel.length; i++) {
            if (nodesForModel[i] == nodeAddress) {
                nodesForModel[i] = nodesForModel[nodesForModel.length - 1];
                nodesForModel.pop();
                break;
            }
        }
    }

    /**
     * @notice Legacy function for compatibility
     */
    function getNodeController(address) external pure returns (address) {
        return address(0);
    }
}