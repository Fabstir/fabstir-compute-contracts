// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {DynamicPricing} from "../../src/DynamicPricing.sol";
import {ModelMarketplace} from "../../src/ModelMarketplace.sol";
import {PricingEngine} from "../../src/PricingEngine.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockNodeRegistry} from "../mocks/MockNodeRegistry.sol";

contract DynamicPricingTest is Test {
    DynamicPricing public dynamicPricing;
    ModelMarketplace public marketplace;
    PricingEngine public pricingEngine;
    MockERC20 public fab;
    
    address constant HOST1 = address(0x1);
    address constant HOST2 = address(0x2);
    address constant USER = address(0x3);
    address constant GOVERNANCE = address(0x4);
    
    bytes32 constant MODEL_ID = keccak256("llama3-70b-v1");
    
    event SurgePricingActivated(
        bytes32 indexed modelId,
        uint256 demandLevel,
        uint256 surgeMultiplier
    );
    
    event SurgePricingDeactivated(
        bytes32 indexed modelId
    );
    
    event DemandUpdated(
        bytes32 indexed modelId,
        uint256 currentDemand,
        uint256 averageDemand
    );
    
    event PriceAdjusted(
        address indexed host,
        bytes32 indexed modelId,
        uint256 oldPrice,
        uint256 newPrice,
        string reason
    );
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        
        MockNodeRegistry nodeRegistry = new MockNodeRegistry();
        nodeRegistry.setActiveNode(HOST1, true);
        nodeRegistry.setActiveNode(HOST2, true);
        
        marketplace = new ModelMarketplace(address(nodeRegistry));
        pricingEngine = new PricingEngine(address(marketplace), address(fab), address(usdc), GOVERNANCE);
        
        // List models for hosts
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
        
        dynamicPricing = new DynamicPricing(
            address(marketplace),
            address(pricingEngine),
            GOVERNANCE
        );
        
        // Grant dynamic pricing permission to update prices
        vm.prank(GOVERNANCE);
        pricingEngine.grantDynamicPricingRole(address(dynamicPricing));
    }
    
    function test_SurgePricing() public {
        // Set base price
        vm.prank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        // Simulate high demand (mock many requests)
        vm.prank(address(marketplace)); // Normally called by job completion
        for (uint i = 0; i < 100; i++) {
            dynamicPricing.recordRequest(MODEL_ID);
        }
        
        // Check surge pricing
        vm.expectEmit(true, true, true, true);
        emit SurgePricingActivated(MODEL_ID, 100, 1500); // 1.5x surge
        
        dynamicPricing.updateSurgePricing(MODEL_ID);
        
        uint256 surgedPrice = dynamicPricing.getSurgePrice(
            HOST1,
            MODEL_ID,
            0.001 ether
        );
        
        assertEq(surgedPrice, 0.0015 ether); // 50% surge
    }
    
    function test_SurgePricingThresholds() public {
        // Configure surge thresholds
        vm.prank(GOVERNANCE);
        dynamicPricing.setSurgeThresholds(
            50,  // Low threshold
            100, // Medium threshold  
            200  // High threshold
        );
        
        vm.prank(GOVERNANCE);
        dynamicPricing.setSurgeMultipliers(
            1200, // 1.2x for low
            1500, // 1.5x for medium
            2000  // 2.0x for high
        );
        
        // Test different demand levels
        uint256 basePrice = 0.001 ether;
        
        // Low demand - no surge
        vm.prank(address(marketplace));
        for (uint i = 0; i < 30; i++) {
            dynamicPricing.recordRequest(MODEL_ID);
        }
        uint256 price = dynamicPricing.getSurgePrice(HOST1, MODEL_ID, basePrice);
        assertEq(price, basePrice);
        
        // Medium demand - 1.2x surge
        for (uint i = 0; i < 30; i++) {
            dynamicPricing.recordRequest(MODEL_ID);
        }
        dynamicPricing.updateSurgePricing(MODEL_ID);
        price = dynamicPricing.getSurgePrice(HOST1, MODEL_ID, basePrice);
        assertEq(price, basePrice * 120 / 100);
    }
    
    function test_TimedPricing() public {
        // Set peak and off-peak hours
        vm.prank(GOVERNANCE);
        dynamicPricing.setPeakHours(9, 17); // 9 AM to 5 PM
        
        vm.prank(GOVERNANCE);
        dynamicPricing.setPeakPriceMultiplier(1250); // 1.25x during peak
        
        uint256 basePrice = 0.001 ether;
        
        // Test off-peak (2 AM)
        vm.warp(1640995200 + 2 hours); // Jan 1, 2022 2:00 AM
        uint256 offPeakPrice = dynamicPricing.getTimeAdjustedPrice(MODEL_ID, basePrice);
        assertEq(offPeakPrice, basePrice);
        
        // Test peak hours (2 PM)
        vm.warp(1640995200 + 14 hours); // Jan 1, 2022 2:00 PM
        uint256 peakPrice = dynamicPricing.getTimeAdjustedPrice(MODEL_ID, basePrice);
        assertEq(peakPrice, basePrice * 125 / 100);
    }
    
    function test_MarketDrivenPricing() public {
        // Enable market-driven pricing
        vm.prank(GOVERNANCE);
        dynamicPricing.enableMarketPricing(MODEL_ID, true);
        
        // Multiple hosts with different prices
        vm.prank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        vm.prank(HOST2);
        pricingEngine.setPricePerToken(MODEL_ID, 0.0008 ether, address(fab));
        
        // Record usage patterns (HOST2 gets more traffic due to lower price)
        vm.prank(address(marketplace));
        dynamicPricing.recordHostUsage(MODEL_ID, HOST1, 20);
        dynamicPricing.recordHostUsage(MODEL_ID, HOST2, 80);
        
        // Market adjustment should suggest HOST1 lower price
        uint256 suggestedPrice = dynamicPricing.getSuggestedMarketPrice(
            HOST1,
            MODEL_ID
        );
        
        assertLt(suggestedPrice, 0.001 ether); // Should suggest lower price
    }
    
    function test_UtilizationBasedPricing() public {
        // Track host utilization
        vm.prank(address(dynamicPricing)); // System tracking
        dynamicPricing.updateHostUtilization(HOST1, 90); // 90% utilized
        
        // High utilization should increase price
        uint256 basePrice = 0.001 ether;
        uint256 adjustedPrice = dynamicPricing.getUtilizationAdjustedPrice(
            HOST1,
            basePrice
        );
        
        assertGt(adjustedPrice, basePrice); // Price should increase
        
        // Low utilization should decrease price
        dynamicPricing.updateHostUtilization(HOST2, 20); // 20% utilized
        adjustedPrice = dynamicPricing.getUtilizationAdjustedPrice(
            HOST2,
            basePrice
        );
        
        assertLt(adjustedPrice, basePrice); // Price should decrease
    }
    
    function test_AutomaticPriceAdjustment() public {
        // Enable automatic adjustments
        vm.prank(GOVERNANCE);
        dynamicPricing.enableAutomaticAdjustments(true);
        
        // Set base price
        vm.prank(HOST1);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        // Simulate sustained high demand
        vm.prank(address(marketplace));
        for (uint i = 0; i < 200; i++) {
            dynamicPricing.recordRequest(MODEL_ID);
        }
        
        // Trigger automatic adjustment
        vm.expectEmit(true, true, true, true);
        emit PriceAdjusted(
            HOST1,
            MODEL_ID,
            0.001 ether,
            0.0011 ether, // 10% increase
            "High sustained demand"
        );
        
        dynamicPricing.performAutomaticAdjustment(HOST1, MODEL_ID);
        
        (uint256 newPrice,,) = pricingEngine.getPrice(HOST1, MODEL_ID);
        assertGt(newPrice, 0.001 ether);
    }
    
    function test_CompetitivePricing() public {
        // Multiple hosts compete on price
        address[] memory hosts = new address[](3);
        hosts[0] = HOST1;
        hosts[1] = HOST2;
        hosts[2] = address(0x5);
        
        // Set different prices
        vm.prank(hosts[0]);
        pricingEngine.setPricePerToken(MODEL_ID, 0.001 ether, address(fab));
        
        vm.prank(hosts[1]);
        pricingEngine.setPricePerToken(MODEL_ID, 0.0009 ether, address(fab));
        
        vm.prank(hosts[2]);
        pricingEngine.setPricePerToken(MODEL_ID, 0.0011 ether, address(fab));
        
        // Get competitive pricing suggestions
        uint256 competitivePrice = dynamicPricing.getCompetitivePrice(
            hosts[0],
            MODEL_ID,
            10 // Stay within 10% of competition
        );
        
        // Should suggest price close to average but slightly below
        assertLt(competitivePrice, 0.001 ether);
        assertGt(competitivePrice, 0.0008 ether);
    }
    
    function test_DemandForecasting() public {
        // Record historical demand
        uint256 startTime = block.timestamp;
        
        // Simulate weekly pattern
        for (uint day = 0; day < 7; day++) {
            vm.warp(startTime + day * 1 days);
            
            uint requests = day < 5 ? 100 : 50; // Lower on weekends
            vm.prank(address(marketplace));
            for (uint i = 0; i < requests; i++) {
                dynamicPricing.recordRequest(MODEL_ID);
            }
        }
        
        // Forecast demand for next Monday
        vm.warp(startTime + 7 days); // Next Monday
        uint256 forecastedDemand = dynamicPricing.forecastDemand(
            MODEL_ID,
            block.timestamp,
            1 days
        );
        
        // Should predict ~100 requests (weekday pattern)
        assertGt(forecastedDemand, 80);
        assertLt(forecastedDemand, 120);
    }
    
    function test_PriceCaps() public {
        // Set price caps to prevent excessive surge
        vm.prank(GOVERNANCE);
        dynamicPricing.setPriceCap(MODEL_ID, 0.003 ether); // 3x max
        
        // Even with extreme demand, price shouldn't exceed cap
        vm.prank(address(marketplace));
        for (uint i = 0; i < 1000; i++) {
            dynamicPricing.recordRequest(MODEL_ID);
        }
        
        dynamicPricing.updateSurgePricing(MODEL_ID);
        
        uint256 basePrice = 0.001 ether;
        uint256 surgedPrice = dynamicPricing.getSurgePrice(HOST1, MODEL_ID, basePrice);
        
        assertLe(surgedPrice, 0.003 ether); // Should not exceed cap
    }
    
    function test_RegionalPricing() public {
        // Different prices for different regions
        vm.startPrank(GOVERNANCE);
        dynamicPricing.setRegionalMultiplier("us-east-1", 1000); // 1.0x
        dynamicPricing.setRegionalMultiplier("eu-west-1", 1100); // 1.1x
        dynamicPricing.setRegionalMultiplier("ap-south-1", 900);  // 0.9x
        vm.stopPrank();
        
        uint256 basePrice = 0.001 ether;
        
        // US East price (base)
        uint256 usPrice = dynamicPricing.getRegionalPrice("us-east-1", basePrice);
        assertEq(usPrice, basePrice);
        
        // EU price (10% higher)
        uint256 euPrice = dynamicPricing.getRegionalPrice("eu-west-1", basePrice);
        assertEq(euPrice, basePrice * 110 / 100);
        
        // Asia price (10% lower)
        uint256 apPrice = dynamicPricing.getRegionalPrice("ap-south-1", basePrice);
        assertEq(apPrice, basePrice * 90 / 100);
    }
}