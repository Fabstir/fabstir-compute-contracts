// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/ReentrancyGuardUpgradeable.sol";
import "./ModelRegistryUpgradeable.sol";

/**
 * @title NodeRegistryWithModelsUpgradeable
 * @notice Extended NodeRegistry that integrates with ModelRegistry for approved models (UUPS Upgradeable)
 * @dev Hosts must register with approved models and use structured JSON metadata
 */
contract NodeRegistryWithModelsUpgradeable is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    // Storage (was immutable, now regular storage)
    IERC20 public fabToken;
    ModelRegistryUpgradeable public modelRegistry;

    uint256 public constant MIN_STAKE = 1000 * 10**18; // 1000 FAB tokens

    // Price precision: prices are stored with 1000x precision for sub-cent granularity
    uint256 public constant PRICE_PRECISION = 1000;

    // Stable pricing (with 1000x precision)
    uint256 public constant MIN_PRICE_PER_TOKEN_STABLE = 1;
    uint256 public constant MAX_PRICE_PER_TOKEN_STABLE = 100_000_000;

    // Native pricing (with 1000x precision, calibrated for ~$4400 ETH)
    uint256 public constant MIN_PRICE_PER_TOKEN_NATIVE = 227_273;
    uint256 public constant MAX_PRICE_PER_TOKEN_NATIVE = 22_727_272_727_273_000;

    struct Node {
        address operator;
        uint256 stakedAmount;
        bool active;
        string metadata;
        string apiUrl;
        bytes32[] supportedModels;
        uint256 minPricePerTokenNative;
        uint256 minPricePerTokenStable;
    }

    // Mappings
    mapping(address => Node) public nodes;
    mapping(address => uint256) public activeNodesIndex;
    mapping(bytes32 => address[]) public modelToNodes;

    // Per-model pricing overrides
    mapping(address => mapping(bytes32 => uint256)) public modelPricingNative;
    mapping(address => mapping(bytes32 => uint256)) public modelPricingStable;

    // Per-token pricing overrides
    mapping(address => mapping(address => uint256)) public customTokenPricing;

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
    event TokenPricingUpdated(address indexed operator, address indexed token, uint256 price);

    // Storage gap for future upgrades
    uint256[40] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor)
     * @param _fabToken The FAB token address for staking
     * @param _modelRegistry The ModelRegistry contract address
     */
    function initialize(address _fabToken, address _modelRegistry) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        // Note: UUPSUpgradeable in OZ 5.x doesn't require initialization

        require(_fabToken != address(0), "Invalid FAB token address");
        require(_modelRegistry != address(0), "Invalid model registry address");
        fabToken = IERC20(_fabToken);
        modelRegistry = ModelRegistryUpgradeable(_modelRegistry);
    }

    /**
     * @notice Authorize upgrade (only owner can upgrade)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Register a node with supported models and dual pricing
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
     * @notice Update metadata
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
     * @notice Update minimum price per token for native tokens
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
     * @notice Update minimum price per token for stablecoins
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
     */
    function setModelPricing(bytes32 modelId, uint256 nativePrice, uint256 stablePrice) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(_nodeSupportsModel(msg.sender, modelId), "Model not supported");

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
     * @notice Clear per-model pricing overrides
     */
    function clearModelPricing(bytes32 modelId) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");

        modelPricingNative[msg.sender][modelId] = 0;
        modelPricingStable[msg.sender][modelId] = 0;

        emit ModelPricingUpdated(msg.sender, modelId, 0, 0);
    }

    /**
     * @notice Set token-specific pricing for a stablecoin
     */
    function setTokenPricing(address token, uint256 price) external {
        require(nodes[msg.sender].operator != address(0), "Not registered");
        require(nodes[msg.sender].active, "Node not active");
        require(token != address(0), "Use updatePricingNative for native token");

        if (price > 0) {
            require(price >= MIN_PRICE_PER_TOKEN_STABLE, "Price below minimum");
            require(price <= MAX_PRICE_PER_TOKEN_STABLE, "Price above maximum");
        }

        customTokenPricing[msg.sender][token] = price;

        emit TokenPricingUpdated(msg.sender, token, price);
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
     */
    function getNodePricing(address operator, address token) external view returns (uint256) {
        if (token == address(0)) {
            return nodes[operator].minPricePerTokenNative;
        } else {
            uint256 customPrice = customTokenPricing[operator][token];
            if (customPrice > 0) {
                return customPrice;
            }
            return nodes[operator].minPricePerTokenStable;
        }
    }

    /**
     * @notice Get model-specific pricing with fallback to default
     */
    function getModelPricing(address operator, bytes32 modelId, address token) external view returns (uint256) {
        if (nodes[operator].operator == address(0)) return 0;

        if (token == address(0)) {
            uint256 modelPrice = modelPricingNative[operator][modelId];
            return modelPrice > 0 ? modelPrice : nodes[operator].minPricePerTokenNative;
        } else {
            uint256 modelPrice = modelPricingStable[operator][modelId];
            return modelPrice > 0 ? modelPrice : nodes[operator].minPricePerTokenStable;
        }
    }

    /**
     * @notice Get all model prices for a host in a single batch query
     */
    function getHostModelPrices(address operator) external view returns (
        bytes32[] memory modelIds,
        uint256[] memory nativePrices,
        uint256[] memory stablePrices
    ) {
        if (nodes[operator].operator == address(0)) {
            return (new bytes32[](0), new uint256[](0), new uint256[](0));
        }

        Node storage node = nodes[operator];
        uint256 modelCount = node.supportedModels.length;

        modelIds = new bytes32[](modelCount);
        nativePrices = new uint256[](modelCount);
        stablePrices = new uint256[](modelCount);

        for (uint256 i = 0; i < modelCount; i++) {
            bytes32 modelId = node.supportedModels[i];
            modelIds[i] = modelId;

            uint256 nativeOverride = modelPricingNative[operator][modelId];
            nativePrices[i] = nativeOverride > 0 ? nativeOverride : node.minPricePerTokenNative;

            uint256 stableOverride = modelPricingStable[operator][modelId];
            stablePrices[i] = stableOverride > 0 ? stableOverride : node.minPricePerTokenStable;
        }

        return (modelIds, nativePrices, stablePrices);
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
        modelRegistry = ModelRegistryUpgradeable(newRegistry);
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
