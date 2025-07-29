// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ModelMarketplace} from "./ModelMarketplace.sol";
import {PricingEngine} from "./PricingEngine.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DynamicPricing is AccessControl, ReentrancyGuard {
    ModelMarketplace public immutable marketplace;
    PricingEngine public immutable pricingEngine;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DEMAND_WINDOW = 1 hours;
    uint256 public constant PRICE_UPDATE_COOLDOWN = 15 minutes;
    
    // Surge pricing thresholds and multipliers
    uint256 public lowSurgeThreshold = 50;
    uint256 public mediumSurgeThreshold = 100;
    uint256 public highSurgeThreshold = 200;
    
    uint256 public lowSurgeMultiplier = 1200; // 1.2x
    uint256 public mediumSurgeMultiplier = 1500; // 1.5x
    uint256 public highSurgeMultiplier = 2000; // 2.0x
    
    // Peak hours
    uint256 public peakStartHour = 9; // 9 AM
    uint256 public peakEndHour = 17; // 5 PM
    uint256 public peakPriceMultiplier = 1250; // 1.25x
    
    bool public automaticAdjustmentsEnabled;
    
    struct DemandData {
        uint256 requestCount;
        uint256 lastRequestTime;
        uint256 averageDemand;
        bool surgeActive;
        uint256 surgeMultiplier;
    }
    
    struct HostUtilization {
        uint256 utilizationPercentage;
        uint256 lastUpdated;
    }
    
    struct MarketData {
        bool marketPricingEnabled;
        uint256 hostUsageShare;
        uint256 totalMarketRequests;
    }
    
    // modelId => DemandData
    mapping(bytes32 => DemandData) public modelDemand;
    
    // host => HostUtilization
    mapping(address => HostUtilization) public hostUtilization;
    
    // modelId => MarketData
    mapping(bytes32 => MarketData) public marketData;
    
    // modelId => host => lastPriceUpdate
    mapping(bytes32 => mapping(address => uint256)) public lastPriceUpdate;
    
    // modelId => price cap
    mapping(bytes32 => uint256) public priceCaps;
    
    // region => multiplier
    mapping(string => uint256) public regionalMultipliers;
    
    // modelId => timestamp => demand count
    mapping(bytes32 => mapping(uint256 => uint256)) public demandHistory;
    
    // modelId => host => usage share
    mapping(bytes32 => mapping(address => uint256)) public hostUsageShares;
    
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
    
    constructor(
        address _marketplace,
        address _pricingEngine,
        address _governance
    ) AccessControl() {
        require(_marketplace != address(0), "Invalid marketplace");
        require(_pricingEngine != address(0), "Invalid pricing engine");
        require(_governance != address(0), "Invalid governance");
        
        marketplace = ModelMarketplace(_marketplace);
        pricingEngine = PricingEngine(_pricingEngine);
        
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
    }
    
    // Demand tracking
    
    function recordRequest(bytes32 modelId) external {
        DemandData storage demand = modelDemand[modelId];
        demand.requestCount++;
        demand.lastRequestTime = block.timestamp;
        
        // Update hourly history
        uint256 currentHour = block.timestamp / 1 hours;
        demandHistory[modelId][currentHour]++;
        
        // Calculate rolling average
        uint256 totalDemand = 0;
        uint256 hourCount = 0;
        for (uint256 i = 0; i < 24 && i <= currentHour; i++) {
            uint256 hourSlot = currentHour - i;
            if (demandHistory[modelId][hourSlot] > 0) {
                totalDemand += demandHistory[modelId][hourSlot];
                hourCount++;
            }
        }
        
        if (hourCount > 0) {
            demand.averageDemand = totalDemand / hourCount;
        }
        
        emit DemandUpdated(modelId, demand.requestCount, demand.averageDemand);
    }
    
    function updateSurgePricing(bytes32 modelId) external {
        DemandData storage demand = modelDemand[modelId];
        uint256 currentHourDemand = demandHistory[modelId][block.timestamp / 1 hours];
        
        uint256 oldMultiplier = demand.surgeMultiplier;
        
        if (currentHourDemand >= highSurgeThreshold) {
            demand.surgeActive = true;
            demand.surgeMultiplier = highSurgeMultiplier;
        } else if (currentHourDemand >= mediumSurgeThreshold) {
            demand.surgeActive = true;
            demand.surgeMultiplier = mediumSurgeMultiplier;
        } else if (currentHourDemand >= lowSurgeThreshold) {
            demand.surgeActive = true;
            demand.surgeMultiplier = lowSurgeMultiplier;
        } else {
            demand.surgeActive = false;
            demand.surgeMultiplier = BASIS_POINTS;
        }
        
        if (demand.surgeActive && oldMultiplier != demand.surgeMultiplier) {
            emit SurgePricingActivated(modelId, currentHourDemand, demand.surgeMultiplier);
        } else if (!demand.surgeActive && oldMultiplier != BASIS_POINTS) {
            emit SurgePricingDeactivated(modelId);
        }
    }
    
    function getSurgePrice(
        address host,
        bytes32 modelId,
        uint256 basePrice
    ) public view returns (uint256) {
        DemandData memory demand = modelDemand[modelId];
        
        if (!demand.surgeActive) {
            return basePrice;
        }
        
        uint256 surgedPrice = (basePrice * demand.surgeMultiplier) / BASIS_POINTS;
        
        // Apply price cap if set
        if (priceCaps[modelId] > 0 && surgedPrice > priceCaps[modelId]) {
            return priceCaps[modelId];
        }
        
        return surgedPrice;
    }
    
    // Time-based pricing
    
    function getTimeAdjustedPrice(
        bytes32 modelId,
        uint256 basePrice
    ) public view returns (uint256) {
        uint256 hour = (block.timestamp / 1 hours) % 24;
        
        if (hour >= peakStartHour && hour < peakEndHour) {
            return (basePrice * peakPriceMultiplier) / BASIS_POINTS;
        }
        
        return basePrice;
    }
    
    // Utilization-based pricing
    
    function updateHostUtilization(address host, uint256 utilizationPercentage) external {
        require(utilizationPercentage <= 100, "Invalid utilization");
        
        hostUtilization[host] = HostUtilization({
            utilizationPercentage: utilizationPercentage,
            lastUpdated: block.timestamp
        });
    }
    
    function getUtilizationAdjustedPrice(
        address host,
        uint256 basePrice
    ) public view returns (uint256) {
        HostUtilization memory util = hostUtilization[host];
        
        if (util.utilizationPercentage > 80) {
            // High utilization - increase price
            uint256 multiplier = BASIS_POINTS + ((util.utilizationPercentage - 80) * 50); // +5% per 10% over 80%
            return (basePrice * multiplier) / BASIS_POINTS;
        } else if (util.utilizationPercentage < 30) {
            // Low utilization - decrease price
            uint256 discount = (30 - util.utilizationPercentage) * 20; // -2% per 10% under 30%
            uint256 multiplier = BASIS_POINTS - discount;
            return (basePrice * multiplier) / BASIS_POINTS;
        }
        
        return basePrice;
    }
    
    // Market-driven pricing
    
    function enableMarketPricing(bytes32 modelId, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        marketData[modelId].marketPricingEnabled = enabled;
    }
    
    function recordHostUsage(bytes32 modelId, address host, uint256 requestShare) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || msg.sender == address(marketplace), "Unauthorized");
        
        MarketData storage market = marketData[modelId];
        hostUsageShares[modelId][host] = requestShare;
        market.totalMarketRequests++;
    }
    
    function getSuggestedMarketPrice(
        address host,
        bytes32 modelId
    ) public view returns (uint256) {
        MarketData memory market = marketData[modelId];
        if (!market.marketPricingEnabled) {
            return 0;
        }
        
        // Get current price
        (uint256 currentPrice,,) = pricingEngine.getPrice(host, modelId);
        
        // Get host's usage share
        uint256 hostShare = hostUsageShares[modelId][host];
        
        // If host has low market share, suggest lower price
        if (hostShare <= 20 && market.totalMarketRequests >= 100) {
            return (currentPrice * 900) / 1000; // 10% reduction
        }
        
        return currentPrice;
    }
    
    function getCompetitivePrice(
        address host,
        bytes32 modelId,
        uint256 maxDeviationPercent
    ) public view returns (uint256) {
        address[] memory hosts = marketplace.getHostsForModel(modelId);
        uint256 totalPrice = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < hosts.length; i++) {
            if (hosts[i] != host && marketplace.isModelActive(modelId, hosts[i])) {
                (uint256 price,,) = pricingEngine.getPrice(hosts[i], modelId);
                if (price > 0) {
                    totalPrice += price;
                    count++;
                }
            }
        }
        
        if (count == 0) {
            (uint256 currentPrice,,) = pricingEngine.getPrice(host, modelId);
            return currentPrice;
        }
        
        uint256 averagePrice = totalPrice / count;
        uint256 competitivePrice = (averagePrice * (10000 - maxDeviationPercent * 100)) / 10000;
        
        return competitivePrice;
    }
    
    // Automatic adjustments
    
    function enableAutomaticAdjustments(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        automaticAdjustmentsEnabled = enabled;
    }
    
    function performAutomaticAdjustment(address host, bytes32 modelId) external nonReentrant {
        require(automaticAdjustmentsEnabled, "Automatic adjustments disabled");
        require(
            block.timestamp > lastPriceUpdate[modelId][host] + PRICE_UPDATE_COOLDOWN,
            "Too soon to update"
        );
        
        (uint256 currentPrice,, address token) = pricingEngine.getPrice(host, modelId);
        require(currentPrice > 0, "No current price");
        
        uint256 newPrice = currentPrice;
        string memory reason;
        
        // Check for sustained high demand
        DemandData memory demand = modelDemand[modelId];
        if (demand.requestCount >= 200 && demand.averageDemand >= 150) {
            newPrice = (currentPrice * 11) / 10; // 10% increase
            reason = "High sustained demand";
        }
        
        // Apply adjustment
        if (newPrice != currentPrice) {
            pricingEngine.updatePrice(host, modelId, newPrice, token);
            lastPriceUpdate[modelId][host] = block.timestamp;
            
            emit PriceAdjusted(host, modelId, currentPrice, newPrice, reason);
        }
    }
    
    // Demand forecasting
    
    function forecastDemand(
        bytes32 modelId,
        uint256 targetTime,
        uint256 duration
    ) external view returns (uint256) {
        // Simple forecast based on historical patterns
        uint256 targetHour = (targetTime / 1 hours) % 24;
        uint256 targetDayOfWeek = (targetTime / 1 days) % 7;
        
        uint256 totalDemand = 0;
        uint256 samples = 0;
        
        // Look at same hour/day in previous weeks
        for (uint256 week = 1; week <= 4; week++) {
            uint256 weekSeconds = week * 7 days;
            if (targetTime > weekSeconds) {
                uint256 pastTime = targetTime - weekSeconds;
                uint256 pastHour = pastTime / 1 hours;
                
                for (uint256 h = 0; h < (duration / 1 hours); h++) {
                    uint256 demand = demandHistory[modelId][pastHour + h];
                    if (demand > 0) {
                        totalDemand += demand;
                        samples++;
                    }
                }
            }
        }
        
        if (samples == 0) {
            return modelDemand[modelId].averageDemand * (duration / 1 hours);
        }
        
        return totalDemand / samples;
    }
    
    // Regional pricing
    
    function setRegionalMultiplier(string memory region, uint256 multiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(multiplier > 0 && multiplier <= 20000, "Invalid multiplier"); // Max 2x
        regionalMultipliers[region] = multiplier;
    }
    
    function getRegionalPrice(string memory region, uint256 basePrice) public view returns (uint256) {
        uint256 multiplier = regionalMultipliers[region];
        if (multiplier == 0) {
            return basePrice; // Default 1.0x
        }
        return (basePrice * multiplier) / BASIS_POINTS;
    }
    
    // Admin functions
    
    function setSurgeThresholds(
        uint256 _low,
        uint256 _medium,
        uint256 _high
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_low < _medium && _medium < _high, "Invalid thresholds");
        lowSurgeThreshold = _low;
        mediumSurgeThreshold = _medium;
        highSurgeThreshold = _high;
    }
    
    function setSurgeMultipliers(
        uint256 _low,
        uint256 _medium,
        uint256 _high
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _low > 0 && _medium >= _low && _high >= _medium,
            "Invalid multipliers"
        );
        lowSurgeMultiplier = _low;
        mediumSurgeMultiplier = _medium;
        highSurgeMultiplier = _high;
    }
    
    function setPeakHours(uint256 start, uint256 end) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(start < 24 && end < 24, "Invalid hours");
        peakStartHour = start;
        peakEndHour = end;
    }
    
    function setPeakPriceMultiplier(uint256 multiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(multiplier > 0 && multiplier <= 20000, "Invalid multiplier");
        peakPriceMultiplier = multiplier;
    }
    
    function setPriceCap(bytes32 modelId, uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        priceCaps[modelId] = cap;
    }
}