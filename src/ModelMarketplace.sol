// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {INodeRegistry} from "./interfaces/INodeRegistry.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ModelMarketplace is ReentrancyGuard, Ownable {
    INodeRegistry public immutable nodeRegistry;
    
    enum ModelType {
        Text,
        Image,
        Audio,
        Video,
        Custom
    }
    
    struct ModelInfo {
        string name;
        string version;
        ModelType modelType;
        string baseModel;
        uint256 contextLength;
        uint256 parameters;
        string quantization;
        string metadataUri;
    }
    
    struct ModelListing {
        address host;
        ModelInfo info;
        uint256 pricePerToken;
        bool isActive;
        uint256 totalRequests;
        uint256 averageResponseTime;
        uint256 listedAt;
    }
    
    // modelId => host => ModelListing
    mapping(bytes32 => mapping(address => ModelListing)) public listings;
    
    // host => modelIds
    mapping(address => bytes32[]) public hostModels;
    
    // modelId => hosts
    mapping(bytes32 => address[]) public modelHosts;
    
    // modelType => modelIds
    mapping(ModelType => bytes32[]) public modelsByType;
    
    // category => modelIds
    mapping(string => bytes32[]) public modelsByCategory;
    
    // modelId => categories
    mapping(bytes32 => string[]) public modelCategories;
    
    // featured models
    bytes32[] public featuredModels;
    mapping(bytes32 => bool) public isFeatured;
    
    event ModelListed(
        bytes32 indexed modelId,
        address indexed host,
        string name,
        string version,
        uint256 basePrice
    );
    
    event ModelDelisted(
        bytes32 indexed modelId,
        address indexed host
    );
    
    event ModelUpdated(
        bytes32 indexed modelId,
        address indexed host,
        uint256 newPrice
    );
    
    event ModelMetadataUpdated(
        bytes32 indexed modelId,
        string metadataUri
    );
    
    event ModelStatsUpdated(
        bytes32 indexed modelId,
        address indexed host,
        uint256 totalRequests,
        uint256 averageResponseTime
    );
    
    modifier onlyRegisteredHost() {
        require(nodeRegistry.isActiveNode(msg.sender), "Not a registered host");
        _;
    }
    
    constructor(address _nodeRegistry) Ownable(msg.sender) {
        require(_nodeRegistry != address(0), "Invalid node registry");
        nodeRegistry = INodeRegistry(_nodeRegistry);
    }
    
    function listModel(
        ModelInfo memory info,
        uint256 pricePerToken,
        bool isActive
    ) external onlyRegisteredHost returns (bytes32) {
        bytes32 modelId = keccak256(abi.encodePacked(info.name, info.version));
        return _listModelWithId(modelId, info, pricePerToken, isActive);
    }
    
    function listModelWithId(
        bytes32 modelId,
        ModelInfo memory info,
        uint256 pricePerToken,
        bool isActive
    ) external onlyRegisteredHost returns (bytes32) {
        return _listModelWithId(modelId, info, pricePerToken, isActive);
    }
    
    function _listModelWithId(
        bytes32 modelId,
        ModelInfo memory info,
        uint256 pricePerToken,
        bool isActive
    ) private returns (bytes32) {
        require(bytes(info.name).length > 0, "Invalid model name");
        require(bytes(info.version).length > 0, "Invalid model version");
        require(pricePerToken > 0, "Invalid price");
        
        // If this is a new listing for this host
        if (listings[modelId][msg.sender].host == address(0)) {
            hostModels[msg.sender].push(modelId);
            
            // Track model hosts
            bool hostExists = false;
            for (uint i = 0; i < modelHosts[modelId].length; i++) {
                if (modelHosts[modelId][i] == msg.sender) {
                    hostExists = true;
                    break;
                }
            }
            if (!hostExists) {
                modelHosts[modelId].push(msg.sender);
            }
            
            // Track by type
            bool typeExists = false;
            for (uint i = 0; i < modelsByType[info.modelType].length; i++) {
                if (modelsByType[info.modelType][i] == modelId) {
                    typeExists = true;
                    break;
                }
            }
            if (!typeExists) {
                modelsByType[info.modelType].push(modelId);
            }
        }
        
        listings[modelId][msg.sender] = ModelListing({
            host: msg.sender,
            info: info,
            pricePerToken: pricePerToken,
            isActive: isActive,
            totalRequests: 0,
            averageResponseTime: 0,
            listedAt: block.timestamp
        });
        
        emit ModelListed(modelId, msg.sender, info.name, info.version, pricePerToken);
        
        return modelId;
    }
    
    function updateModelPrice(bytes32 modelId, uint256 newPrice) external onlyRegisteredHost {
        require(listings[modelId][msg.sender].host == msg.sender, "Model not listed");
        require(newPrice > 0, "Invalid price");
        
        listings[modelId][msg.sender].pricePerToken = newPrice;
        
        emit ModelUpdated(modelId, msg.sender, newPrice);
    }
    
    function delistModel(bytes32 modelId) external onlyRegisteredHost {
        require(listings[modelId][msg.sender].host == msg.sender, "Model not listed");
        
        listings[modelId][msg.sender].isActive = false;
        
        emit ModelDelisted(modelId, msg.sender);
    }
    
    function updateModelStats(
        bytes32 modelId,
        address host,
        uint256 responseTime
    ) external {
        // In production, this would be restricted to authorized callers
        ModelListing storage listing = listings[modelId][host];
        require(listing.host != address(0), "Model not listed");
        
        uint256 currentTotal = listing.totalRequests;
        uint256 currentAvg = listing.averageResponseTime;
        
        // Calculate new average
        listing.totalRequests = currentTotal + 1;
        listing.averageResponseTime = ((currentAvg * currentTotal) + responseTime) / (currentTotal + 1);
        
        emit ModelStatsUpdated(modelId, host, listing.totalRequests, listing.averageResponseTime);
    }
    
    function addModelToCategory(bytes32 modelId, string memory category) external onlyRegisteredHost {
        require(listings[modelId][msg.sender].host == msg.sender, "Model not listed");
        require(bytes(category).length > 0, "Invalid category");
        
        // Check if already in category
        bool exists = false;
        for (uint i = 0; i < modelCategories[modelId].length; i++) {
            if (keccak256(bytes(modelCategories[modelId][i])) == keccak256(bytes(category))) {
                exists = true;
                break;
            }
        }
        
        if (!exists) {
            modelCategories[modelId].push(category);
            modelsByCategory[category].push(modelId);
        }
    }
    
    function setFeaturedModel(bytes32 modelId, bool featured) external onlyOwner {
        if (featured && !isFeatured[modelId]) {
            featuredModels.push(modelId);
            isFeatured[modelId] = true;
        } else if (!featured && isFeatured[modelId]) {
            // Remove from featured
            for (uint i = 0; i < featuredModels.length; i++) {
                if (featuredModels[i] == modelId) {
                    featuredModels[i] = featuredModels[featuredModels.length - 1];
                    featuredModels.pop();
                    break;
                }
            }
            isFeatured[modelId] = false;
        }
    }
    
    // View functions
    
    function getModelListing(bytes32 modelId, address host) external view returns (
        address hostAddress,
        ModelInfo memory info,
        uint256 pricePerToken,
        bool isActive,
        uint256 totalRequests,
        uint256 averageResponseTime
    ) {
        ModelListing memory listing = listings[modelId][host];
        return (
            listing.host,
            listing.info,
            listing.pricePerToken,
            listing.isActive,
            listing.totalRequests,
            listing.averageResponseTime
        );
    }
    
    function isModelActive(bytes32 modelId, address host) external view returns (bool) {
        return listings[modelId][host].isActive;
    }
    
    function searchModelsByType(ModelType modelType) external view returns (bytes32[] memory) {
        return modelsByType[modelType];
    }
    
    function getModelsByHost(address host) external view returns (bytes32[] memory) {
        return hostModels[host];
    }
    
    function getHostsForModel(bytes32 modelId) external view returns (address[] memory) {
        return modelHosts[modelId];
    }
    
    function getCheapestHost(bytes32 modelId) external view returns (address) {
        address[] memory hosts = modelHosts[modelId];
        require(hosts.length > 0, "No hosts for model");
        
        address cheapestHost = address(0);
        uint256 cheapestPrice = type(uint256).max;
        
        for (uint i = 0; i < hosts.length; i++) {
            ModelListing memory listing = listings[modelId][hosts[i]];
            if (listing.isActive && listing.pricePerToken < cheapestPrice) {
                cheapestPrice = listing.pricePerToken;
                cheapestHost = hosts[i];
            }
        }
        
        require(cheapestHost != address(0), "No active hosts");
        return cheapestHost;
    }
    
    function getFeaturedModels() external view returns (bytes32[] memory) {
        return featuredModels;
    }
    
    function getModelsByCategory(string memory category) external view returns (bytes32[] memory) {
        return modelsByCategory[category];
    }
}