// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ModelMarketplace} from "./ModelMarketplace.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract PricingEngine is ReentrancyGuard, AccessControl {
    bytes32 public constant DYNAMIC_PRICING_ROLE = keccak256("DYNAMIC_PRICING_ROLE");
    
    ModelMarketplace public immutable marketplace;
    address public immutable fabToken;
    address public immutable usdcToken;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant FAB_DISCOUNT = 2000; // 20% discount
    uint256 public constant MINIMUM_PRICE_PER_TOKEN = 1e12; // 0.000001 token
    uint256 public constant MINIMUM_PRICE_PER_MINUTE = 1e14; // 0.0001 token
    uint256 public constant QUOTE_VALIDITY = 300; // 5 minutes
    
    struct Price {
        uint256 pricePerToken;
        uint256 pricePerMinute;
        address paymentToken;
        uint256 lastUpdated;
    }
    
    struct VolumeDiscount {
        uint256 threshold;
        uint256 discountBasisPoints;
    }
    
    struct PriceQuote {
        address user;
        address host;
        bytes32 modelId;
        uint256 estimatedTokens;
        uint256 estimatedDuration;
        uint256 totalPrice;
        address paymentToken;
        uint256 validUntil;
        bool used;
    }
    
    struct PriceHistory {
        uint256 price;
        uint256 timestamp;
    }
    
    struct HostPrice {
        address host;
        uint256 totalPrice;
        uint256 pricePerToken;
        uint256 pricePerMinute;
    }
    
    // host => modelId => token => Price
    mapping(address => mapping(bytes32 => mapping(address => Price))) public prices;
    
    // host => modelId => VolumeDiscount[]
    mapping(address => mapping(bytes32 => VolumeDiscount[])) public volumeDiscounts;
    
    // quoteId => PriceQuote
    mapping(bytes32 => PriceQuote) public quotes;
    
    // host => modelId => token => PriceHistory[]
    mapping(address => mapping(bytes32 => mapping(address => PriceHistory[]))) public priceHistories;
    
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
    
    modifier onlyHost() {
        require(marketplace.getModelsByHost(msg.sender).length > 0, "Not a host");
        _;
    }
    
    constructor(
        address _marketplace,
        address _fabToken,
        address _usdcToken,
        address _governance
    ) AccessControl() {
        require(_marketplace != address(0), "Invalid marketplace");
        require(_fabToken != address(0), "Invalid FAB token");
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_governance != address(0), "Invalid governance");
        
        marketplace = ModelMarketplace(_marketplace);
        fabToken = _fabToken;
        usdcToken = _usdcToken;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _governance);
    }
    
    function setPricePerToken(
        bytes32 modelId,
        uint256 pricePerToken,
        address paymentToken
    ) external onlyHost {
        // Adjust minimum price based on token decimals
        uint256 minPrice = paymentToken == usdcToken ? 1 : MINIMUM_PRICE_PER_TOKEN; // 1 unit for USDC (0.000001 USDC)
        require(pricePerToken >= minPrice, "Price below minimum");
        require(paymentToken == fabToken || paymentToken == usdcToken, "Invalid payment token");
        
        Price storage price = prices[msg.sender][modelId][paymentToken];
        
        // Record price history
        if (price.pricePerToken > 0) {
            priceHistories[msg.sender][modelId][paymentToken].push(
                PriceHistory(price.pricePerToken, block.timestamp)
            );
        }
        
        price.pricePerToken = pricePerToken;
        price.paymentToken = paymentToken;
        price.lastUpdated = block.timestamp;
        
        emit PriceSet(msg.sender, modelId, pricePerToken, price.pricePerMinute, paymentToken);
    }
    
    function setPricePerMinute(
        bytes32 modelId,
        uint256 pricePerMinute,
        address paymentToken
    ) external onlyHost {
        // Adjust minimum price based on token decimals
        uint256 minPrice = paymentToken == usdcToken ? 60 : MINIMUM_PRICE_PER_MINUTE; // 60 units for USDC (0.00006 USDC/min)
        require(pricePerMinute >= minPrice, "Price below minimum");
        require(paymentToken == fabToken || paymentToken == usdcToken, "Invalid payment token");
        
        Price storage price = prices[msg.sender][modelId][paymentToken];
        
        // Record price history
        if (price.pricePerMinute > 0) {
            priceHistories[msg.sender][modelId][paymentToken].push(
                PriceHistory(price.pricePerMinute, block.timestamp)
            );
        }
        
        price.pricePerMinute = pricePerMinute;
        price.paymentToken = paymentToken;
        price.lastUpdated = block.timestamp;
        
        emit PriceSet(msg.sender, modelId, price.pricePerToken, pricePerMinute, paymentToken);
    }
    
    function setVolumeDiscount(
        bytes32 modelId,
        uint256 volumeThreshold,
        uint256 discountBasisPoints
    ) external onlyHost {
        require(volumeThreshold > 0, "Invalid threshold");
        require(discountBasisPoints > 0 && discountBasisPoints < BASIS_POINTS, "Invalid discount");
        
        VolumeDiscount[] storage discounts = volumeDiscounts[msg.sender][modelId];
        
        // Find position to insert (keep sorted by threshold)
        uint256 insertIndex = discounts.length;
        for (uint256 i = 0; i < discounts.length; i++) {
            if (discounts[i].threshold == volumeThreshold) {
                // Update existing
                discounts[i].discountBasisPoints = discountBasisPoints;
                emit PriceDiscountSet(msg.sender, modelId, volumeThreshold, discountBasisPoints);
                return;
            }
            if (discounts[i].threshold > volumeThreshold) {
                insertIndex = i;
                break;
            }
        }
        
        // Add new discount
        discounts.push(VolumeDiscount(volumeThreshold, discountBasisPoints));
        
        // Sort if needed
        if (insertIndex < discounts.length - 1) {
            VolumeDiscount memory temp = discounts[discounts.length - 1];
            for (uint256 i = discounts.length - 1; i > insertIndex; i--) {
                discounts[i] = discounts[i - 1];
            }
            discounts[insertIndex] = temp;
        }
        
        emit PriceDiscountSet(msg.sender, modelId, volumeThreshold, discountBasisPoints);
    }
    
    function setBulkPrices(
        bytes32[] memory modelIds,
        uint256[] memory pricesArray,
        address paymentToken,
        bool isPerToken
    ) external onlyHost {
        require(modelIds.length == pricesArray.length, "Length mismatch");
        require(paymentToken == fabToken || paymentToken == usdcToken, "Invalid payment token");
        
        for (uint256 i = 0; i < modelIds.length; i++) {
            if (isPerToken) {
                require(pricesArray[i] >= MINIMUM_PRICE_PER_TOKEN, "Price below minimum");
                prices[msg.sender][modelIds[i]][paymentToken].pricePerToken = pricesArray[i];
            } else {
                require(pricesArray[i] >= MINIMUM_PRICE_PER_MINUTE, "Price below minimum");
                prices[msg.sender][modelIds[i]][paymentToken].pricePerMinute = pricesArray[i];
            }
            prices[msg.sender][modelIds[i]][paymentToken].paymentToken = paymentToken;
            prices[msg.sender][modelIds[i]][paymentToken].lastUpdated = block.timestamp;
            
            emit PriceSet(
                msg.sender,
                modelIds[i],
                isPerToken ? pricesArray[i] : prices[msg.sender][modelIds[i]][paymentToken].pricePerToken,
                isPerToken ? prices[msg.sender][modelIds[i]][paymentToken].pricePerMinute : pricesArray[i],
                paymentToken
            );
        }
    }
    
    function calculateQuote(
        address host,
        bytes32 modelId,
        uint256 estimatedTokens,
        uint256 estimatedDuration,
        address paymentToken
    ) public view returns (uint256) {
        Price memory price = prices[host][modelId][paymentToken];
        require(price.paymentToken != address(0), "Price not set");
        
        uint256 totalPrice = 0;
        
        // Calculate token-based price
        if (price.pricePerToken > 0 && estimatedTokens > 0) {
            totalPrice = price.pricePerToken * estimatedTokens;
        }
        
        // Calculate time-based price
        if (price.pricePerMinute > 0 && estimatedDuration > 0) {
            uint256 timePrice = (price.pricePerMinute * estimatedDuration) / 60; // duration in seconds
            totalPrice = totalPrice > timePrice ? totalPrice : timePrice; // Use higher price
        }
        
        // Apply volume discount
        VolumeDiscount[] memory discounts = volumeDiscounts[host][modelId];
        for (uint256 i = discounts.length; i > 0; i--) {
            if (estimatedTokens >= discounts[i - 1].threshold) {
                totalPrice = (totalPrice * (BASIS_POINTS - discounts[i - 1].discountBasisPoints)) / BASIS_POINTS;
                break;
            }
        }
        
        return totalPrice;
    }
    
    function generateQuote(
        address user,
        address host,
        bytes32 modelId,
        uint256 estimatedTokens,
        uint256 estimatedDuration,
        address paymentToken
    ) external returns (PriceQuote memory) {
        uint256 totalPrice = calculateQuote(host, modelId, estimatedTokens, estimatedDuration, paymentToken);
        
        bytes32 quoteId = keccak256(
            abi.encodePacked(user, host, modelId, block.timestamp, totalPrice)
        );
        
        PriceQuote memory quote = PriceQuote({
            user: user,
            host: host,
            modelId: modelId,
            estimatedTokens: estimatedTokens,
            estimatedDuration: estimatedDuration,
            totalPrice: totalPrice,
            paymentToken: paymentToken,
            validUntil: block.timestamp + QUOTE_VALIDITY,
            used: false
        });
        
        quotes[quoteId] = quote;
        
        emit PriceQuoteGenerated(user, modelId, host, estimatedTokens, totalPrice);
        
        return quote;
    }
    
    function comparePrices(
        bytes32 modelId,
        uint256 estimatedTokens,
        address paymentToken
    ) external view returns (HostPrice[] memory) {
        address[] memory hosts = marketplace.getHostsForModel(modelId);
        uint256 activeCount = 0;
        
        // Count active hosts with prices
        for (uint256 i = 0; i < hosts.length; i++) {
            if (prices[hosts[i]][modelId][paymentToken].paymentToken != address(0) &&
                marketplace.isModelActive(modelId, hosts[i])) {
                activeCount++;
            }
        }
        
        HostPrice[] memory hostPrices = new HostPrice[](activeCount);
        uint256 index = 0;
        
        // Collect prices
        for (uint256 i = 0; i < hosts.length; i++) {
            Price memory price = prices[hosts[i]][modelId][paymentToken];
            if (price.paymentToken != address(0) && marketplace.isModelActive(modelId, hosts[i])) {
                uint256 totalPrice = calculateQuote(hosts[i], modelId, estimatedTokens, 0, paymentToken);
                hostPrices[index] = HostPrice({
                    host: hosts[i],
                    totalPrice: totalPrice,
                    pricePerToken: price.pricePerToken,
                    pricePerMinute: price.pricePerMinute
                });
                index++;
            }
        }
        
        // Sort by total price (bubble sort for simplicity)
        for (uint256 i = 0; i < hostPrices.length; i++) {
            for (uint256 j = i + 1; j < hostPrices.length; j++) {
                if (hostPrices[i].totalPrice > hostPrices[j].totalPrice) {
                    HostPrice memory temp = hostPrices[i];
                    hostPrices[i] = hostPrices[j];
                    hostPrices[j] = temp;
                }
            }
        }
        
        return hostPrices;
    }
    
    // View functions
    
    function getPrice(address host, bytes32 modelId) external view returns (
        uint256 pricePerToken,
        uint256 pricePerMinute,
        address paymentToken
    ) {
        // Default to FAB token
        Price memory price = prices[host][modelId][fabToken];
        if (price.paymentToken == address(0)) {
            price = prices[host][modelId][usdcToken];
        }
        return (price.pricePerToken, price.pricePerMinute, price.paymentToken);
    }
    
    function getPriceInToken(
        address host,
        bytes32 modelId,
        address paymentToken
    ) external view returns (
        uint256 pricePerToken,
        uint256 pricePerMinute,
        address token
    ) {
        Price memory price = prices[host][modelId][paymentToken];
        return (price.pricePerToken, price.pricePerMinute, price.paymentToken);
    }
    
    function getPriceHistory(
        address host,
        bytes32 modelId,
        address paymentToken
    ) external view returns (PriceHistory[] memory) {
        return priceHistories[host][modelId][paymentToken];
    }
    
    function minimumPricePerToken() external pure returns (uint256) {
        return MINIMUM_PRICE_PER_TOKEN;
    }
    
    function minimumPricePerMinute() external pure returns (uint256) {
        return MINIMUM_PRICE_PER_MINUTE;
    }
    
    // Admin functions
    
    function grantDynamicPricingRole(address dynamicPricing) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DYNAMIC_PRICING_ROLE, dynamicPricing);
    }
    
    function updatePrice(
        address host,
        bytes32 modelId,
        uint256 newPricePerToken,
        address paymentToken
    ) external onlyRole(DYNAMIC_PRICING_ROLE) {
        // Adjust minimum price based on token decimals
        uint256 minPrice = paymentToken == usdcToken ? 1 : MINIMUM_PRICE_PER_TOKEN;
        require(newPricePerToken >= minPrice, "Price below minimum");
        
        Price storage price = prices[host][modelId][paymentToken];
        price.pricePerToken = newPricePerToken;
        price.lastUpdated = block.timestamp;
        
        emit PriceSet(host, modelId, newPricePerToken, price.pricePerMinute, paymentToken);
    }
}