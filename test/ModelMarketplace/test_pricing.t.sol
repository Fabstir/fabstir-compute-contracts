// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PricingEngine} from "../../src/PricingEngine.sol";
import {ModelMarketplace} from "../../src/ModelMarketplace.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockNodeRegistry} from "../mocks/MockNodeRegistry.sol";

contract PricingTest is Test {
    PricingEngine public pricingEngine;
    ModelMarketplace public marketplace;
    MockERC20 public fab;
    MockERC20 public usdc;
    
    address constant HOST1 = address(0x1);
    address constant HOST2 = address(0x2);
    address constant USER = address(0x3);
    address constant GOVERNANCE = address(0x4);
    
    bytes32 constant MODEL_ID = keccak256(abi.encodePacked("llama3-70b", "v1"));
    
    event PriceSet(
        address indexed host,
        bytes32 indexed modelId,
        uint256 pricePerToken,
        uint256 pricePerMinute,
        address paymentToken
    );
    
    event PriceDiscountSet(
        address indexed host,
        bytes32 indexed modelId,
        uint256 volumeThreshold,
        uint256 discountPercentage
    );
    
    event PriceQuoteGenerated(
        address indexed user,
        bytes32 indexed modelId,
        address indexed host,
        uint256 estimatedTokens,
        uint256 totalPrice
    );
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        MockNodeRegistry nodeRegistry = new MockNodeRegistry();
        nodeRegistry.setActiveNode(HOST1, true);
        nodeRegistry.setActiveNode(HOST2, true);
        
        marketplace = new ModelMarketplace(address(nodeRegistry));
        pricingEngine = new PricingEngine(
            address(marketplace),
            address(fab),
            address(usdc),
            GOVERNANCE
        );
        
        // List a model for each host so they become valid hosts
        vm.prank(HOST1);
        marketplace.listModel(
            ModelMarketplace.ModelInfo({
                name: "llama3-70b",
                version: "v1",
                modelType: ModelMarketplace.ModelType.Text,
                baseModel: "llama3-70b",
                contextLength: 8192,
                parameters: 70 * 10**9,
                quantization: "Q4_K_M",
                metadataUri: "ipfs://test"
            }),
            0.001 ether,
            true
        );
        
        vm.prank(HOST2);
        marketplace.listModel(
            ModelMarketplace.ModelInfo({
                name: "llama3-70b",
                version: "v1",
                modelType: ModelMarketplace.ModelType.Text,
                baseModel: "llama3-70b",
                contextLength: 8192,
                parameters: 70 * 10**9,
                quantization: "Q4_K_M",
                metadataUri: "ipfs://test"
            }),
            0.001 ether,
            true
        );
    }
    
    function test_SetPricePerToken() public {
        uint256 pricePerToken = 0.001 ether; // 0.001 FAB per token
        
        vm.prank(HOST1);
        vm.expectEmit(true, true, true, true);
        emit PriceSet(HOST1, MODEL_ID, pricePerToken, 0, address(fab));
        
        pricingEngine.setPricePerToken(MODEL_ID, pricePerToken, address(fab));
        
        (uint256 tokenPrice, uint256 minutePrice, address token) = 
            pricingEngine.getPrice(HOST1, MODEL_ID);
            
        assertEq(tokenPrice, pricePerToken);
        assertEq(minutePrice, 0);
        assertEq(token, address(fab));
    }
    
    function test_SetPricePerMinute() public {
        uint256 pricePerMinute = 0.1 ether; // 0.1 FAB per minute
        
        vm.prank(HOST1);
        pricingEngine.setPricePerMinute(MODEL_ID, pricePerMinute, address(fab));
        
        (uint256 tokenPrice, uint256 minutePrice, address token) = 
            pricingEngine.getPrice(HOST1, MODEL_ID);
            
        assertEq(tokenPrice, 0);
        assertEq(minutePrice, pricePerMinute);
        assertEq(token, address(fab));
    }
    
    function test_SetBothPricingModels() public {
        // Host can set both token and minute pricing
        uint256 pricePerToken = 0.001 ether;
        uint256 pricePerMinute = 0.1 ether;
        
        vm.startPrank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, pricePerToken, address(fab));
        pricingEngine.setPricePerMinute(MODEL_ID, pricePerMinute, address(fab));
        vm.stopPrank();
        
        (uint256 tokenPrice, uint256 minutePrice,) = 
            pricingEngine.getPrice(HOST1, MODEL_ID);
            
        assertEq(tokenPrice, pricePerToken);
        assertEq(minutePrice, pricePerMinute);
    }
    
    function test_DifferentTokenPricing() public {
        // Host can price in different tokens
        uint256 fabPrice = 0.001 ether;
        uint256 usdcPrice = 1 * 10**6; // 1 USDC (6 decimals)
        
        vm.startPrank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, fabPrice, address(fab));
        pricingEngine.setPricePerToken(MODEL_ID, usdcPrice, address(usdc));
        vm.stopPrank();
        
        // Get FAB price
        (uint256 price,, address token) = pricingEngine.getPriceInToken(HOST1, MODEL_ID, address(fab));
        assertEq(price, fabPrice);
        assertEq(token, address(fab));
        
        // Get USDC price
        (price,, token) = pricingEngine.getPriceInToken(HOST1, MODEL_ID, address(usdc));
        assertEq(price, usdcPrice);
        assertEq(token, address(usdc));
    }
    
    function test_FABPaymentDiscount() public {
        // Set prices in both FAB and USDC
        uint256 usdcPrice = 1 * 10**6; // 1 USDC per token
        uint256 fabPrice = 0.001 ether; // 0.001 FAB per token
        
        vm.startPrank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, usdcPrice, address(usdc));
        pricingEngine.setPricePerToken(MODEL_ID, fabPrice, address(fab));
        vm.stopPrank();
        
        // Calculate quote for 1000 tokens
        uint256 estimatedTokens = 1000;
        
        uint256 usdcQuote = pricingEngine.calculateQuote(
            HOST1,
            MODEL_ID,
            estimatedTokens,
            0, // duration not used for token pricing
            address(usdc)
        );
        
        uint256 fabQuote = pricingEngine.calculateQuote(
            HOST1,
            MODEL_ID,
            estimatedTokens,
            0,
            address(fab)
        );
        
        // FAB and USDC quotes should match their prices
        assertEq(usdcQuote, 1000 * usdcPrice); // 1000 USDC total
        assertEq(fabQuote, 1000 * fabPrice); // 1 FAB total
    }
    
    function test_VolumeDiscount() public {
        uint256 basePrice = 0.001 ether;
        
        vm.prank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, basePrice, address(fab));
        
        // Set volume discounts: 10% off at 10k tokens, 20% off at 100k tokens
        vm.startPrank(HOST1);
        vm.expectEmit(true, true, true, true);
        emit PriceDiscountSet(HOST1, MODEL_ID, 10000, 1000); // 10%
        pricingEngine.setVolumeDiscount(MODEL_ID, 10000, 1000); // 10% = 1000 basis points
        
        pricingEngine.setVolumeDiscount(MODEL_ID, 100000, 2000); // 20%
        vm.stopPrank();
        
        // Test different volumes
        uint256 smallQuote = pricingEngine.calculateQuote(HOST1, MODEL_ID, 1000, 0, address(fab));
        uint256 mediumQuote = pricingEngine.calculateQuote(HOST1, MODEL_ID, 15000, 0, address(fab));
        uint256 largeQuote = pricingEngine.calculateQuote(HOST1, MODEL_ID, 150000, 0, address(fab));
        
        assertEq(smallQuote, 1000 * basePrice); // No discount
        assertEq(mediumQuote, 15000 * basePrice * 90 / 100); // 10% discount
        assertEq(largeQuote, 150000 * basePrice * 80 / 100); // 20% discount
    }
    
    function test_GeneratePriceQuote() public {
        vm.prank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        uint256 estimatedTokens = 5000;
        
        vm.expectEmit(true, true, true, true);
        emit PriceQuoteGenerated(USER, MODEL_ID, HOST1, estimatedTokens, 5 ether);
        
        PricingEngine.PriceQuote memory quote = pricingEngine.generateQuote(
            USER,
            HOST1,
            MODEL_ID,
            estimatedTokens,
            0,
            address(fab)
        );
        
        assertEq(quote.user, USER);
        assertEq(quote.host, HOST1);
        assertEq(quote.modelId, MODEL_ID);
        assertEq(quote.estimatedTokens, estimatedTokens);
        assertEq(quote.totalPrice, 5 ether);
        assertEq(quote.paymentToken, address(fab));
        assertEq(quote.validUntil, block.timestamp + 300); // 5 min validity
    }
    
    function test_ComparePricesAcrossHosts() public {
        // Different hosts set different prices for same model
        vm.prank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        vm.prank(HOST2);
        pricingEngine.setPricePerToken(MODEL_ID, 0.0008 ether, address(fab));
        
        PricingEngine.HostPrice[] memory prices = pricingEngine.comparePrices(
            MODEL_ID,
            1000, // tokens
            address(fab)
        );
        
        assertEq(prices.length, 2);
        
        // Should be sorted by price (cheapest first)
        assertEq(prices[0].host, HOST2);
        assertEq(prices[0].totalPrice, 0.8 ether);
        assertEq(prices[1].host, HOST1);
        assertEq(prices[1].totalPrice, 1 ether);
    }
    
    function test_MinimumPrice() public {
        // Cannot set price below minimum
        uint256 minimumPrice = pricingEngine.minimumPricePerToken();
        
        vm.prank(HOST1);
        vm.expectRevert("Price below minimum");
        pricingEngine.setPricePerToken(MODEL_ID, minimumPrice - 1, address(fab));
    }
    
    function test_PriceHistory() public {
        // Track price changes over time
        vm.startPrank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        vm.warp(block.timestamp + 1 days);
        pricingEngine.setPricePerToken(MODEL_ID, 0.0012 ether, address(fab));
        
        vm.warp(block.timestamp + 1 days);
        pricingEngine.setPricePerToken(MODEL_ID, 0.0008 ether, address(fab));
        vm.stopPrank();
        
        PricingEngine.PriceHistory[] memory history = pricingEngine.getPriceHistory(
            HOST1,
            MODEL_ID,
            address(fab)
        );
        
        assertEq(history.length, 2);
        assertEq(history[0].price, 0.001 ether);
        assertEq(history[1].price, 0.0012 ether);
    }
    
    function test_BulkPricing() public {
        bytes32[] memory modelIds = new bytes32[](3);
        uint256[] memory prices = new uint256[](3);
        
        modelIds[0] = keccak256("model1");
        modelIds[1] = keccak256("model2");
        modelIds[2] = keccak256("model3");
        
        prices[0] = 0.001 ether;
        prices[1] = 0.002 ether;
        prices[2] = 0.003 ether;
        
        vm.prank(HOST1);
        pricingEngine.setBulkPrices(modelIds, prices, address(fab), true); // true = per token
        
        // Verify all prices set
        for (uint i = 0; i < modelIds.length; i++) {
            (uint256 price,,) = pricingEngine.getPrice(HOST1, modelIds[i]);
            assertEq(price, prices[i]);
        }
    }
}