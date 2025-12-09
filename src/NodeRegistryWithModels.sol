// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
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
    uint256 public constant MIN_PRICE_PER_TOKEN_STABLE = 10; // Minimum for stablecoins: 0.00001 USDC per AI token
    uint256 public constant MIN_PRICE_PER_TOKEN_NATIVE = 2_272_727_273; // Minimum for native tokens: ~0.00001 USD @ $4400 ETH
    uint256 public constant MAX_PRICE_PER_TOKEN_STABLE = 100_000; // Maximum for stablecoins: 0.1 USDC per AI token
    uint256 public constant MAX_PRICE_PER_TOKEN_NATIVE = 22_727_272_727_273; // Maximum for native tokens: ~0.1 USD @ $4400 ETH

    struct Node {
        address operator;
        uint256 stakedAmount;
        bool active;
        string metadata;        // JSON formatted metadata
        string apiUrl;          // API endpoint URL
        bytes32[] supportedModels; // Array of model IDs this node supports
        uint256 minPricePerTokenNative;  // Minimum price per token for native tokens (ETH/BNB) - 18 decimals
        uint256 minPricePerTokenStable;  // Minimum price per token for stablecoins (USDC) - 6 decimals
    }

    // Mappings
    mapping(address => Node) public nodes;
    mapping(address => uint256) public activeNodesIndex;
    mapping(bytes32 => address[]) public modelToNodes; // modelId => array of nodes supporting it

    // Per-model pricing overrides (operator => modelId => price)
    // When set (> 0), these override the default minPricePerTokenNative/Stable
    mapping(address => mapping(bytes32 => uint256)) public modelPricingNative;
    mapping(address => mapping(bytes32 => uint256)) public modelPricingStable;

    address[] public activeNodesList;

    // Events
    event NodeRegistered(address indexed operator, uint256 stakedAmount, string metadata, bytes32[] models);
    event NodeUnregistered(address indexed operator, uint256 returnedAmount);
    event MetadataUpdated(address indexed operator, string newMetadata);
    event ApiUrlUpdated(address indexed operator, string newApiUrl);
    event ModelsUpdated(address indexed operator, bytes32[] newModels);
    event ModelRegistryUpdated(address indexed newRegistry);
    event PricingUpdated(address indexed operator, uint256 newMinPrice);
    event ModelPricingUpdated(address indexed operator, bytes32 indexed modelId, uint256 nativePrice, uint256 stablePrice);

    constructor(address _fabToken, address _modelRegistry) Ownable(msg.sender) {
        require(_fabToken != address(0), "Invalid FAB token address");
        require(_modelRegistry != address(0), "Invalid model registry address");
        fabToken = IERC20(_fabToken);
        modelRegistry = ModelRegistry(_modelRegistry);
    }

    /**
     * @notice Register a node with supported models and dual pricing
     * @param metadata JSON formatted metadata with hardware specs, capabilities, etc.
     * @param apiUrl The API endpoint URL for the node
     * @param modelIds Array of model IDs this node supports
     * @param minPricePerTokenNative Minimum price for native tokens (ETH/BNB) per AI token (2,272,727,273-22,727,272,727,273 wei)
     * @param minPricePerTokenStable Minimum price for stablecoins (USDC) per AI token (10-100,000)
     */
    function registerNode(
        string memory metadata,
        string memory apiUrl,
        bytes32[] memory modelIds,
        uint256 minPricePerTokenNative,
        uint256 minPricePerTokenStable
    ) external nonReentrant {
        require(nodes[msg.sender].operator == address(0), "Already registered");
        require(bytes(metadata).length > 0, "Empty metadata");
        require(bytes(apiUrl).length > 0, "Empty API URL");
        require(modelIds.length > 0, "Must support at least one model");
        require(minPricePerTokenNative >= MIN_PRICE_PER_TOKEN_NATIVE, "Native price below minimum");
        require(minPricePerTokenNative <= MAX_PRICE_PER_TOKEN_NATIVE, "Native price above maximum");
        require(minPricePerTokenStable >= MIN_PRICE_PER_TOKEN_STABLE, "Stable price below minimum");
        require(minPricePerTokenStable <= MAX_PRICE_PER_TOKEN_STABLE, "Stable price above maximum");

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
            supportedModels: modelIds,
            minPricePerTokenNative: minPricePerTokenNative,
            minPricePerTokenStable: minPricePerTokenStable
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
     * @notice Update minimum price per token for native tokens (ETH/BNB)
     * @param newMinPrice New minimum price for native tokens (2,272,727,273-22,727,272,727,273 wei)
     */
    function updatePricingNative(uint256 newMinPrice) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(newMinPrice >= MIN_PRICE_PER_TOKEN_NATIVE, "Price below minimum");
        require(newMinPrice <= MAX_PRICE_PER_TOKEN_NATIVE, "Price above maximum");

        nodes[msg.sender].minPricePerTokenNative = newMinPrice;

        emit PricingUpdated(msg.sender, newMinPrice);
    }

    /**
     * @notice Update minimum price per token for stablecoins (USDC)
     * @param newMinPrice New minimum price for stablecoins (10-100,000)
     */
    function updatePricingStable(uint256 newMinPrice) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(newMinPrice >= MIN_PRICE_PER_TOKEN_STABLE, "Price below minimum");
        require(newMinPrice <= MAX_PRICE_PER_TOKEN_STABLE, "Price above maximum");

        nodes[msg.sender].minPricePerTokenStable = newMinPrice;

        emit PricingUpdated(msg.sender, newMinPrice);
    }

    /**
     * @notice Set per-model pricing overrides
     * @dev Setting price to 0 clears the override (uses default pricing)
     * @param modelId The model ID to set pricing for (must be in host's supportedModels)
     * @param nativePrice Price for native tokens (0 = use default, otherwise MIN_PRICE_PER_TOKEN_NATIVE to MAX_PRICE_PER_TOKEN_NATIVE)
     * @param stablePrice Price for stablecoins (0 = use default, otherwise MIN_PRICE_PER_TOKEN_STABLE to MAX_PRICE_PER_TOKEN_STABLE)
     */
    function setModelPricing(bytes32 modelId, uint256 nativePrice, uint256 stablePrice) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(_nodeSupportsModel(msg.sender, modelId), "Model not supported");

        // Validate prices (0 means use default, otherwise must be in range)
        if (nativePrice > 0) {
            require(nativePrice >= MIN_PRICE_PER_TOKEN_NATIVE, "Native price below minimum");
            require(nativePrice <= MAX_PRICE_PER_TOKEN_NATIVE, "Native price above maximum");
        }
        if (stablePrice > 0) {
            require(stablePrice >= MIN_PRICE_PER_TOKEN_STABLE, "Stable price below minimum");
            require(stablePrice <= MAX_PRICE_PER_TOKEN_STABLE, "Stable price above maximum");
        }

        modelPricingNative[msg.sender][modelId] = nativePrice;
        modelPricingStable[msg.sender][modelId] = stablePrice;

        emit ModelPricingUpdated(msg.sender, modelId, nativePrice, stablePrice);
    }

    /**
     * @notice Clear per-model pricing overrides (revert to default pricing)
     * @dev Sets both native and stable model pricing to 0, causing getModelPricing to return defaults
     * @param modelId The model ID to clear pricing for
     */
    function clearModelPricing(bytes32 modelId) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");

        modelPricingNative[msg.sender][modelId] = 0;
        modelPricingStable[msg.sender][modelId] = 0;

        emit ModelPricingUpdated(msg.sender, modelId, 0, 0);
    }

    /**
     * @notice Check if a node supports a specific model (internal helper)
     */
    function _nodeSupportsModel(address operator, bytes32 modelId) internal view returns (bool) {
        bytes32[] memory models = nodes[operator].supportedModels;
        for (uint i = 0; i < models.length; i++) {
            if (models[i] == modelId) return true;
        }
        return false;
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
     * @notice Get full node information including dual pricing
     */
    function getNodeFullInfo(address operator) external view returns (
        address,
        uint256,
        bool,
        string memory,
        string memory,
        bytes32[] memory,
        uint256,
        uint256
    ) {
        Node storage node = nodes[operator];
        return (
            node.operator,
            node.stakedAmount,
            node.active,
            node.metadata,
            node.apiUrl,
            node.supportedModels,
            node.minPricePerTokenNative,
            node.minPricePerTokenStable
        );
    }

    /**
     * @notice Get node's minimum price per token for a specific payment token
     * @param operator The address of the node operator
     * @param token The payment token address (address(0) for native ETH/BNB, USDC address for stablecoin)
     * @return Minimum price per token (0 if not registered)
     */
    function getNodePricing(address operator, address token) external view returns (uint256) {
        if (token == address(0)) {
            // Native token (ETH on Base, BNB on opBNB)
            return nodes[operator].minPricePerTokenNative;
        } else {
            // Stablecoin (USDC or other)
            return nodes[operator].minPricePerTokenStable;
        }
    }

    /**
     * @notice Get model-specific pricing with fallback to default
     * @dev Returns model-specific price if set (> 0), otherwise falls back to default pricing
     * @param operator The address of the node operator
     * @param modelId The model ID to query pricing for
     * @param token The payment token address (address(0) for native, any other for stablecoin)
     * @return Effective minimum price per token (0 if operator not registered)
     */
    function getModelPricing(address operator, bytes32 modelId, address token) external view returns (uint256) {
        if (nodes[operator].operator == address(0)) return 0;

        if (token == address(0)) {
            // Native token - check model-specific, fall back to default
            uint256 modelPrice = modelPricingNative[operator][modelId];
            return modelPrice > 0 ? modelPrice : nodes[operator].minPricePerTokenNative;
        } else {
            // Stablecoin - check model-specific, fall back to default
            uint256 modelPrice = modelPricingStable[operator][modelId];
            return modelPrice > 0 ? modelPrice : nodes[operator].minPricePerTokenStable;
        }
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