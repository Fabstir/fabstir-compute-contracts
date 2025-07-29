// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ModelMarketplace} from "../../src/ModelMarketplace.sol";
import {NodeRegistry} from "../../src/NodeRegistry.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract ModelListingTest is Test {
    ModelMarketplace public marketplace;
    NodeRegistry public nodeRegistry;
    MockERC20 public fab;
    
    address constant HOST1 = address(0x1);
    address constant HOST2 = address(0x2);
    address constant HOST3 = address(0x3);
    address constant USER = address(0x4);
    
    uint256 constant HOST_STAKE = 100 ether;
    
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
    
    function setUp() public {
        nodeRegistry = new NodeRegistry();
        marketplace = new ModelMarketplace(address(nodeRegistry));
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        
        // Fund and register hosts
        vm.deal(HOST1, 1000 ether);
        vm.deal(HOST2, 1000 ether);
        vm.deal(HOST3, 1000 ether);
        
        vm.prank(HOST1);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost1",
            _createModels(),
            "us-east-1"
        );
        
        vm.prank(HOST2);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost2",
            _createModels(),
            "us-west-2"
        );
        
        vm.prank(HOST3);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost3",
            _createModels(),
            "eu-west-1"
        );
    }
    
    function test_ListModel() public {
        ModelMarketplace.ModelInfo memory modelInfo = ModelMarketplace.ModelInfo({
            name: "Llama-3-70B",
            version: "1.0.0",
            modelType: ModelMarketplace.ModelType.Text,
            baseModel: "meta-llama/Llama-3-70b",
            contextLength: 8192,
            parameters: 70 * 10**9,
            quantization: "Q4_K_M",
            metadataUri: "ipfs://QmExample123"
        });
        
        uint256 pricePerToken = 0.001 ether; // Price in FAB
        
        vm.prank(HOST1);
        bytes32 modelId = marketplace.listModel(
            modelInfo,
            pricePerToken,
            true // isActive
        );
        
        // Verify listing
        (
            address host,
            ModelMarketplace.ModelInfo memory storedInfo,
            uint256 price,
            bool isActive,
            uint256 totalRequests,
            uint256 averageResponseTime
        ) = marketplace.getModelListing(modelId, HOST1);
        
        assertEq(host, HOST1);
        assertEq(storedInfo.name, "Llama-3-70B");
        assertEq(storedInfo.parameters, 70 * 10**9);
        assertEq(price, pricePerToken);
        assertTrue(isActive);
    }
    
    function test_ListMultipleModelVersions() public {
        // Host can list multiple versions of same model
        ModelMarketplace.ModelInfo memory v1 = _createModelInfo("Llama-3-70B", "1.0.0");
        ModelMarketplace.ModelInfo memory v2 = _createModelInfo("Llama-3-70B", "2.0.0");
        v2.contextLength = 16384; // Upgraded context
        
        vm.startPrank(HOST1);
        bytes32 modelId1 = marketplace.listModel(v1, 0.001 ether, true);
        bytes32 modelId2 = marketplace.listModel(v2, 0.0015 ether, true); // Higher price for v2
        vm.stopPrank();
        
        // Should have different IDs
        assertTrue(modelId1 != modelId2);
        
        // Both should be listed
        assertTrue(marketplace.isModelActive(modelId1, HOST1));
        assertTrue(marketplace.isModelActive(modelId2, HOST1));
    }
    
    function test_UpdateModelPrice() public {
        bytes32 modelId = _listTestModel(HOST1, 0.001 ether);
        
        uint256 newPrice = 0.002 ether;
        
        vm.prank(HOST1);
        vm.expectEmit(true, true, true, true);
        emit ModelUpdated(modelId, HOST1, newPrice);
        
        marketplace.updateModelPrice(modelId, newPrice);
        
        (,, uint256 price,,,) = marketplace.getModelListing(modelId, HOST1);
        assertEq(price, newPrice);
    }
    
    function test_DelistModel() public {
        bytes32 modelId = _listTestModel(HOST1, 0.001 ether);
        
        vm.prank(HOST1);
        vm.expectEmit(true, true, true, true);
        emit ModelDelisted(modelId, HOST1);
        
        marketplace.delistModel(modelId);
        
        assertFalse(marketplace.isModelActive(modelId, HOST1));
    }
    
    function test_SearchModelsByType() public {
        // List different model types
        ModelMarketplace.ModelInfo memory textModel = _createModelInfo("GPT-4", "1.0.0");
        ModelMarketplace.ModelInfo memory imageModel = _createModelInfo("DALL-E-3", "1.0.0");
        imageModel.modelType = ModelMarketplace.ModelType.Image;
        ModelMarketplace.ModelInfo memory audioModel = _createModelInfo("Whisper", "1.0.0");
        audioModel.modelType = ModelMarketplace.ModelType.Audio;
        
        vm.startPrank(HOST1);
        marketplace.listModel(textModel, 0.001 ether, true);
        marketplace.listModel(imageModel, 0.002 ether, true);
        marketplace.listModel(audioModel, 0.0005 ether, true);
        vm.stopPrank();
        
        // Search by type
        bytes32[] memory textModels = marketplace.searchModelsByType(
            ModelMarketplace.ModelType.Text
        );
        bytes32[] memory imageModels = marketplace.searchModelsByType(
            ModelMarketplace.ModelType.Image
        );
        
        assertEq(textModels.length, 1);
        assertEq(imageModels.length, 1);
    }
    
    function test_GetModelsByHost() public {
        // Host1 lists 3 models
        vm.startPrank(HOST1);
        marketplace.listModel(_createModelInfo("Model1", "1.0.0"), 0.001 ether, true);
        marketplace.listModel(_createModelInfo("Model2", "1.0.0"), 0.002 ether, true);
        marketplace.listModel(_createModelInfo("Model3", "1.0.0"), 0.003 ether, true);
        vm.stopPrank();
        
        bytes32[] memory hostModels = marketplace.getModelsByHost(HOST1);
        assertEq(hostModels.length, 3);
    }
    
    function test_GetCheapestHost() public {
        bytes32 modelId = keccak256(abi.encodePacked("Llama-3-70B", "1.0.0"));
        
        // Multiple hosts list same model at different prices
        vm.prank(HOST1);
        marketplace.listModelWithId(
            modelId,
            _createModelInfo("Llama-3-70B", "1.0.0"),
            0.003 ether,
            true
        );
        
        vm.prank(HOST2);
        marketplace.listModelWithId(
            modelId,
            _createModelInfo("Llama-3-70B", "1.0.0"),
            0.001 ether, // Cheapest
            true
        );
        
        vm.prank(HOST3);
        marketplace.listModelWithId(
            modelId,
            _createModelInfo("Llama-3-70B", "1.0.0"),
            0.002 ether,
            true
        );
        
        address cheapestHost = marketplace.getCheapestHost(modelId);
        assertEq(cheapestHost, HOST2);
    }
    
    function test_GetHostsForModel() public {
        bytes32 modelId = keccak256(abi.encodePacked("Llama-3-70B", "1.0.0"));
        
        // Multiple hosts list same model
        vm.prank(HOST1);
        marketplace.listModelWithId(modelId, _createModelInfo("Llama-3-70B", "1.0.0"), 0.001 ether, true);
        
        vm.prank(HOST2);
        marketplace.listModelWithId(modelId, _createModelInfo("Llama-3-70B", "1.0.0"), 0.001 ether, true);
        
        address[] memory hosts = marketplace.getHostsForModel(modelId);
        assertEq(hosts.length, 2);
        assertTrue(hosts[0] == HOST1 || hosts[1] == HOST1);
        assertTrue(hosts[0] == HOST2 || hosts[1] == HOST2);
    }
    
    function test_ModelStats() public {
        bytes32 modelId = _listTestModel(HOST1, 0.001 ether);
        
        // Update stats after usage
        vm.prank(address(marketplace)); // Would normally be called by job completion
        marketplace.updateModelStats(modelId, HOST1, 150); // 150ms response time
        marketplace.updateModelStats(modelId, HOST1, 200);
        marketplace.updateModelStats(modelId, HOST1, 180);
        
        (,,,, uint256 totalRequests, uint256 avgResponseTime) = 
            marketplace.getModelListing(modelId, HOST1);
            
        assertEq(totalRequests, 3);
        assertEq(avgResponseTime, 176); // (150 + 200 + 180) / 3
    }
    
    function test_OnlyRegisteredHostCanList() public {
        address unregisteredHost = address(0x999);
        
        vm.prank(unregisteredHost);
        vm.expectRevert("Not a registered host");
        marketplace.listModel(
            _createModelInfo("Model", "1.0.0"),
            0.001 ether,
            true
        );
    }
    
    function test_FeaturedModels() public {
        vm.prank(HOST1);
        bytes32 modelId1 = marketplace.listModel(
            _createModelInfo("Model1", "1.0.0"),
            0.001 ether,
            true
        );
        
        vm.prank(HOST2);
        bytes32 modelId2 = marketplace.listModel(
            _createModelInfo("Model2", "1.0.0"),
            0.002 ether,
            true
        );
        
        vm.prank(HOST3);
        bytes32 modelId3 = marketplace.listModel(
            _createModelInfo("Model3", "1.0.0"),
            0.003 ether,
            true
        );
        
        // Admin can feature models
        marketplace.setFeaturedModel(modelId1, true);
        marketplace.setFeaturedModel(modelId3, true);
        
        bytes32[] memory featured = marketplace.getFeaturedModels();
        assertEq(featured.length, 2);
        assertTrue(featured[0] == modelId1 || featured[1] == modelId1);
        assertTrue(featured[0] == modelId3 || featured[1] == modelId3);
    }
    
    function test_ModelCategories() public {
        // List models in different categories
        ModelMarketplace.ModelInfo memory chatModel = _createModelInfo("ChatGPT", "1.0.0");
        ModelMarketplace.ModelInfo memory codeModel = _createModelInfo("Codex", "1.0.0");
        
        vm.startPrank(HOST1);
        bytes32 chatId = marketplace.listModel(chatModel, 0.001 ether, true);
        bytes32 codeId = marketplace.listModel(codeModel, 0.002 ether, true);
        
        marketplace.addModelToCategory(chatId, "chat");
        marketplace.addModelToCategory(chatId, "general");
        marketplace.addModelToCategory(codeId, "code");
        marketplace.addModelToCategory(codeId, "developer");
        vm.stopPrank();
        
        bytes32[] memory chatModels = marketplace.getModelsByCategory("chat");
        bytes32[] memory codeModels = marketplace.getModelsByCategory("code");
        
        assertEq(chatModels.length, 1);
        assertEq(codeModels.length, 1);
        assertEq(chatModels[0], chatId);
        assertEq(codeModels[0], codeId);
    }
    
    // Helper functions
    function _createModels() private pure returns (string[] memory) {
        string[] memory models = new string[](2);
        models[0] = "llama3-70b";
        models[1] = "mistral-7b";
        return models;
    }
    
    function _createModelInfo(
        string memory name,
        string memory version
    ) private pure returns (ModelMarketplace.ModelInfo memory) {
        return ModelMarketplace.ModelInfo({
            name: name,
            version: version,
            modelType: ModelMarketplace.ModelType.Text,
            baseModel: name,
            contextLength: 8192,
            parameters: 70 * 10**9,
            quantization: "Q4_K_M",
            metadataUri: "ipfs://QmExample123"
        });
    }
    
    function _listTestModel(
        address host,
        uint256 price
    ) private returns (bytes32) {
        vm.prank(host);
        return marketplace.listModel(
            _createModelInfo("TestModel", "1.0.0"),
            price,
            true
        );
    }
}