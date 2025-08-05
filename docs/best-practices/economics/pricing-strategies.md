# Pricing Strategies Best Practices

This guide covers effective pricing strategies for maximizing profitability while remaining competitive in the Fabstir marketplace.

## Why It Matters

Smart pricing strategies enable:
- **Profit maximization** - Optimize revenue per job
- **Market competitiveness** - Win more jobs
- **Resource utilization** - Fill idle capacity
- **Risk management** - Cover operational costs
- **Growth sustainability** - Fund expansion

## Understanding Market Dynamics

### Price Discovery Mechanism
```javascript
class MarketPriceDiscovery {
    constructor() {
        this.priceHistory = new Map();
        this.competitorPrices = new Map();
        this.demandIndicators = new Map();
    }
    
    async analyzeMarketPrice(modelId) {
        const analysis = {
            timestamp: Date.now(),
            modelId,
            currentPrices: await this.getCurrentPrices(modelId),
            historicalTrend: await this.getHistoricalTrend(modelId),
            demandSupply: await this.analyzeDemandSupply(modelId),
            competitorAnalysis: await this.analyzeCompetitors(modelId),
            recommendation: {}
        };
        
        // Calculate price statistics
        const prices = analysis.currentPrices.map(p => p.price);
        analysis.statistics = {
            min: Math.min(...prices),
            max: Math.max(...prices),
            mean: prices.reduce((a, b) => a + b) / prices.length,
            median: this.calculateMedian(prices),
            stdDev: this.calculateStdDev(prices)
        };
        
        // Generate pricing recommendation
        analysis.recommendation = this.generateRecommendation(analysis);
        
        return analysis;
    }
    
    async getCurrentPrices(modelId) {
        // Query active jobs for the model
        const activeJobs = await this.queryActiveJobs(modelId);
        
        return activeJobs.map(job => ({
            jobId: job.id,
            price: parseFloat(ethers.formatEther(job.payment)),
            pricePerToken: job.payment / job.maxTokens,
            host: job.assignedHost,
            posted: job.postedAt,
            requirements: job.requirements
        })).sort((a, b) => a.price - b.price);
    }
    
    async analyzeDemandSupply(modelId) {
        const window = 24 * 60 * 60 * 1000; // 24 hours
        const now = Date.now();
        
        // Demand indicators
        const demand = {
            jobsPosted: await this.countJobs(modelId, now - window, now),
            avgWaitTime: await this.getAvgWaitTime(modelId),
            unfulfilled: await this.getUnfulfilledJobs(modelId),
            growthRate: await this.calculateDemandGrowth(modelId)
        };
        
        // Supply indicators
        const supply = {
            activeNodes: await this.countActiveNodes(modelId),
            totalCapacity: await this.getTotalCapacity(modelId),
            utilization: await this.getUtilization(modelId),
            avgResponseTime: await this.getAvgResponseTime(modelId)
        };
        
        // Calculate market pressure
        const pressure = {
            demandSupplyRatio: demand.jobsPosted / supply.activeNodes,
            capacityUtilization: supply.utilization,
            marketTightness: this.calculateMarketTightness(demand, supply),
            priceDirection: this.predictPriceDirection(demand, supply)
        };
        
        return { demand, supply, pressure };
    }
    
    generateRecommendation(analysis) {
        const { statistics, demandSupply, competitorAnalysis } = analysis;
        
        // Base price on market median
        let recommendedPrice = statistics.median;
        
        // Adjust for demand/supply
        if (demandSupply.pressure.marketTightness > 0.8) {
            // High demand, low supply - increase price
            recommendedPrice *= 1.1;
        } else if (demandSupply.pressure.marketTightness < 0.3) {
            // Low demand, high supply - decrease price
            recommendedPrice *= 0.9;
        }
        
        // Consider competitor positioning
        if (competitorAnalysis.position === 'premium') {
            recommendedPrice *= 1.15;
        } else if (competitorAnalysis.position === 'budget') {
            recommendedPrice *= 0.85;
        }
        
        return {
            basePrice: recommendedPrice,
            minPrice: recommendedPrice * 0.8,
            maxPrice: recommendedPrice * 1.5,
            confidence: this.calculateConfidence(analysis),
            factors: this.explainFactors(analysis)
        };
    }
}
```

### Dynamic Pricing Implementation
```javascript
class DynamicPricingEngine {
    constructor(config) {
        this.config = config;
        this.priceAdjustmentInterval = config.adjustmentInterval || 3600000; // 1 hour
        this.maxPriceChange = config.maxPriceChange || 0.2; // 20% max change
        this.learningRate = config.learningRate || 0.1;
    }
    
    async startDynamicPricing() {
        setInterval(async () => {
            await this.adjustPrices();
        }, this.priceAdjustmentInterval);
    }
    
    async adjustPrices() {
        const models = await this.getActiveModels();
        
        for (const modelId of models) {
            try {
                const adjustment = await this.calculateAdjustment(modelId);
                
                if (Math.abs(adjustment.change) > 0.01) {
                    await this.applyAdjustment(modelId, adjustment);
                }
            } catch (error) {
                console.error(`Price adjustment failed for ${modelId}:`, error);
            }
        }
    }
    
    async calculateAdjustment(modelId) {
        const metrics = await this.collectMetrics(modelId);
        const currentPrice = await this.getCurrentPrice(modelId);
        
        // Calculate optimal price using reinforcement learning
        const features = this.extractFeatures(metrics);
        const optimalPrice = await this.predictOptimalPrice(features);
        
        // Calculate adjustment
        let priceChange = (optimalPrice - currentPrice) / currentPrice;
        
        // Limit change rate
        priceChange = Math.max(-this.maxPriceChange, 
                              Math.min(this.maxPriceChange, priceChange));
        
        return {
            modelId,
            currentPrice,
            newPrice: currentPrice * (1 + priceChange),
            change: priceChange,
            confidence: this.calculateConfidence(metrics),
            reasoning: this.explainAdjustment(metrics, priceChange)
        };
    }
    
    extractFeatures(metrics) {
        return {
            // Demand features
            jobsInQueue: metrics.queueDepth,
            avgWaitTime: metrics.avgWaitTime,
            demandGrowth: metrics.demandGrowth,
            
            // Supply features
            availableCapacity: metrics.availableCapacity,
            competitorCount: metrics.competitorCount,
            avgCompetitorPrice: metrics.avgCompetitorPrice,
            
            // Performance features
            winRate: metrics.winRate,
            completionRate: metrics.completionRate,
            avgProfit: metrics.avgProfit,
            
            // Time features
            hourOfDay: new Date().getHours(),
            dayOfWeek: new Date().getDay(),
            isWeekend: [0, 6].includes(new Date().getDay())
        };
    }
    
    async predictOptimalPrice(features) {
        // Use ML model or heuristics
        let basePrice = features.avgCompetitorPrice || 0.01;
        
        // Adjust based on demand
        if (features.jobsInQueue > 10) {
            basePrice *= 1 + (features.jobsInQueue / 100);
        }
        
        // Adjust based on win rate
        if (features.winRate < 0.3) {
            basePrice *= 0.95; // Lower price to win more
        } else if (features.winRate > 0.7) {
            basePrice *= 1.05; // Can afford higher price
        }
        
        // Time-based adjustments
        if (features.isWeekend) {
            basePrice *= 0.9; // Weekend discount
        }
        
        // Capacity-based adjustments
        if (features.availableCapacity < 0.2) {
            basePrice *= 1.1; // Premium for scarce capacity
        }
        
        return basePrice;
    }
}
```

## Pricing Strategies

### Cost-Plus Pricing
```javascript
class CostPlusPricing {
    constructor() {
        this.costCalculator = new CostCalculator();
        this.targetMargin = 0.3; // 30% margin
    }
    
    async calculatePrice(jobRequest) {
        // Calculate all costs
        const costs = await this.calculateCosts(jobRequest);
        
        // Add target margin
        const price = costs.total * (1 + this.targetMargin);
        
        return {
            costs,
            margin: this.targetMargin,
            price,
            profitability: this.assessProfitability(price, costs)
        };
    }
    
    async calculateCosts(jobRequest) {
        const costs = {
            compute: await this.calculateComputeCost(jobRequest),
            infrastructure: await this.calculateInfrastructureCost(jobRequest),
            network: await this.calculateNetworkCost(jobRequest),
            storage: await this.calculateStorageCost(jobRequest),
            overhead: await this.calculateOverheadCost(jobRequest)
        };
        
        // Add risk buffer
        costs.riskBuffer = (costs.compute + costs.infrastructure) * 0.1;
        
        // Calculate total
        costs.total = Object.values(costs).reduce((sum, cost) => sum + cost, 0);
        
        return costs;
    }
    
    async calculateComputeCost(jobRequest) {
        const model = await this.getModelSpecs(jobRequest.modelId);
        
        // GPU cost
        const gpuHours = jobRequest.estimatedDuration / 3600;
        const gpuCost = model.gpuRequirement * this.config.gpuHourlyRate * gpuHours;
        
        // CPU cost
        const cpuCost = model.cpuRequirement * this.config.cpuHourlyRate * gpuHours;
        
        // Memory cost
        const memoryCost = model.memoryRequirement * this.config.memoryHourlyRate * gpuHours;
        
        return gpuCost + cpuCost + memoryCost;
    }
    
    assessProfitability(price, costs) {
        const profit = price - costs.total;
        const margin = profit / price;
        const roi = profit / costs.total;
        
        return {
            profit,
            margin,
            roi,
            breakEvenPoint: costs.total,
            viable: margin >= this.targetMargin
        };
    }
}
```

### Value-Based Pricing
```javascript
class ValueBasedPricing {
    constructor() {
        this.valueMetrics = new ValueMetrics();
        this.customerSegments = new CustomerSegmentation();
    }
    
    async calculatePrice(jobRequest, customer) {
        // Identify customer segment
        const segment = await this.customerSegments.classify(customer);
        
        // Calculate value delivered
        const value = await this.calculateValue(jobRequest, segment);
        
        // Determine price based on value
        const price = this.priceFromValue(value, segment);
        
        return {
            segment,
            value,
            price,
            justification: this.explainPricing(value, segment)
        };
    }
    
    async calculateValue(jobRequest, segment) {
        const value = {
            timeValue: await this.calculateTimeValue(jobRequest, segment),
            qualityValue: await this.calculateQualityValue(jobRequest, segment),
            convenienceValue: await this.calculateConvenienceValue(jobRequest, segment),
            businessValue: await this.calculateBusinessValue(jobRequest, segment)
        };
        
        // Weight by segment priorities
        value.total = this.weightedValue(value, segment.priorities);
        
        return value;
    }
    
    calculateTimeValue(jobRequest, segment) {
        // Value of faster processing
        const standardTime = 3600; // 1 hour baseline
        const ourTime = jobRequest.estimatedDuration;
        const timeSaved = Math.max(0, standardTime - ourTime);
        
        // Convert time saved to value
        const hourlyValue = segment.type === 'enterprise' ? 500 : 
                          segment.type === 'professional' ? 100 : 20;
        
        return (timeSaved / 3600) * hourlyValue;
    }
    
    calculateQualityValue(jobRequest, segment) {
        // Premium for higher quality models
        const qualityPremium = {
            'gpt-4': 0.5,
            'claude-2': 0.4,
            'llama-2-70b': 0.2,
            'default': 0
        };
        
        const basePremium = qualityPremium[jobRequest.modelId] || 0;
        
        // Adjust by segment sensitivity to quality
        return basePremium * segment.qualitySensitivity;
    }
    
    priceFromValue(value, segment) {
        // Base price on value captured
        let captureRate = 0.3; // Capture 30% of value
        
        // Adjust capture rate by segment
        if (segment.type === 'enterprise') {
            captureRate = 0.4; // Can capture more from enterprise
        } else if (segment.type === 'hobbyist') {
            captureRate = 0.2; // More price sensitive
        }
        
        const basePrice = value.total * captureRate;
        
        // Apply psychological pricing
        return this.applyPsychologicalPricing(basePrice);
    }
    
    applyPsychologicalPricing(price) {
        // Round to psychological price points
        if (price < 0.01) return 0.009;
        if (price < 0.1) return Math.floor(price * 100) / 100;
        if (price < 1) return Math.floor(price * 10) / 10;
        if (price < 10) return Math.floor(price);
        
        // Use charm pricing
        return Math.floor(price) - 0.01;
    }
}
```

### Competitive Pricing
```javascript
class CompetitivePricing {
    constructor() {
        this.competitorMonitor = new CompetitorMonitor();
        this.positioningStrategy = 'competitive'; // 'premium', 'competitive', 'budget'
    }
    
    async calculatePrice(jobRequest) {
        // Get competitor prices
        const competitorPrices = await this.getCompetitorPrices(jobRequest);
        
        // Analyze competitive landscape
        const analysis = this.analyzeCompetition(competitorPrices);
        
        // Determine our price
        const price = this.setCompetitivePrice(analysis);
        
        return {
            competitorPrices,
            analysis,
            price,
            positioning: this.explainPositioning(price, analysis)
        };
    }
    
    async getCompetitorPrices(jobRequest) {
        // Query recent jobs for same model
        const recentJobs = await this.queryRecentJobs(jobRequest.modelId, 24);
        
        // Group by host (competitor)
        const byCompetitor = new Map();
        
        for (const job of recentJobs) {
            if (!byCompetitor.has(job.host)) {
                byCompetitor.set(job.host, []);
            }
            byCompetitor.get(job.host).push({
                price: job.payment,
                timestamp: job.timestamp,
                completed: job.status === 'completed',
                rating: job.rating
            });
        }
        
        // Calculate average price per competitor
        return Array.from(byCompetitor.entries()).map(([host, jobs]) => ({
            host,
            avgPrice: jobs.reduce((sum, j) => sum + j.price, 0) / jobs.length,
            jobCount: jobs.length,
            successRate: jobs.filter(j => j.completed).length / jobs.length,
            avgRating: jobs.filter(j => j.rating).reduce((sum, j) => sum + j.rating, 0) / 
                      jobs.filter(j => j.rating).length
        }));
    }
    
    analyzeCompetition(competitorPrices) {
        const prices = competitorPrices.map(c => c.avgPrice).sort((a, b) => a - b);
        
        return {
            count: prices.length,
            min: prices[0],
            max: prices[prices.length - 1],
            median: prices[Math.floor(prices.length / 2)],
            mean: prices.reduce((a, b) => a + b, 0) / prices.length,
            percentiles: {
                p25: prices[Math.floor(prices.length * 0.25)],
                p50: prices[Math.floor(prices.length * 0.50)],
                p75: prices[Math.floor(prices.length * 0.75)]
            },
            topPerformers: competitorPrices
                .filter(c => c.successRate > 0.9)
                .sort((a, b) => b.avgRating - a.avgRating)
                .slice(0, 3)
        };
    }
    
    setCompetitivePrice(analysis) {
        let targetPrice;
        
        switch (this.positioningStrategy) {
            case 'premium':
                // Price above 75th percentile
                targetPrice = analysis.percentiles.p75 * 1.2;
                break;
                
            case 'competitive':
                // Price around median
                targetPrice = analysis.median * this.getCompetitiveMultiplier();
                break;
                
            case 'budget':
                // Price below 25th percentile
                targetPrice = analysis.percentiles.p25 * 0.9;
                break;
                
            default:
                targetPrice = analysis.median;
        }
        
        // Ensure minimum profitability
        const minPrice = this.calculateMinimumPrice();
        return Math.max(targetPrice, minPrice);
    }
    
    getCompetitiveMultiplier() {
        // Adjust based on our performance metrics
        const ourMetrics = this.getOurPerformanceMetrics();
        
        if (ourMetrics.successRate > 0.95 && ourMetrics.avgRating > 4.5) {
            return 1.1; // Premium for quality
        } else if (ourMetrics.successRate < 0.8) {
            return 0.9; // Discount for lower reliability
        }
        
        return 1.0; // Match market
    }
}
```

### Bundle Pricing
```javascript
class BundlePricing {
    constructor() {
        this.bundles = new Map();
        this.discountStrategy = new DiscountStrategy();
    }
    
    createBundle(name, components) {
        const bundle = {
            name,
            components,
            basePrice: this.calculateBasePrice(components),
            discount: this.calculateBundleDiscount(components),
            validUntil: Date.now() + 30 * 24 * 60 * 60 * 1000 // 30 days
        };
        
        bundle.bundlePrice = bundle.basePrice * (1 - bundle.discount);
        bundle.savings = bundle.basePrice - bundle.bundlePrice;
        
        this.bundles.set(name, bundle);
        return bundle;
    }
    
    calculateBundleDiscount(components) {
        // Base discount on bundle size
        let discount = 0.05 * (components.length - 1); // 5% per additional item
        
        // Cap at maximum discount
        discount = Math.min(discount, 0.3); // 30% max
        
        // Additional discount for commitment
        if (components.some(c => c.commitment === 'monthly')) {
            discount += 0.05;
        }
        
        return discount;
    }
    
    // Example bundles
    setupStandardBundles() {
        // Startup bundle
        this.createBundle('startup', [
            { model: 'gpt-3.5-turbo', credits: 1000, commitment: 'none' },
            { model: 'stable-diffusion', credits: 100, commitment: 'none' },
            { support: 'email', commitment: 'none' }
        ]);
        
        // Professional bundle
        this.createBundle('professional', [
            { model: 'gpt-4', credits: 5000, commitment: 'monthly' },
            { model: 'claude-2', credits: 2000, commitment: 'monthly' },
            { model: 'stable-diffusion-xl', credits: 500, commitment: 'monthly' },
            { support: 'priority', commitment: 'monthly' }
        ]);
        
        // Enterprise bundle
        this.createBundle('enterprise', [
            { model: 'all', credits: 50000, commitment: 'annual' },
            { support: 'dedicated', commitment: 'annual' },
            { sla: '99.9%', commitment: 'annual' },
            { training: 'included', commitment: 'annual' }
        ]);
    }
    
    recommendBundle(customer) {
        const usage = customer.historicalUsage;
        const needs = this.analyzeCustomerNeeds(usage);
        
        // Find best matching bundle
        let bestBundle = null;
        let bestScore = 0;
        
        for (const [name, bundle] of this.bundles) {
            const score = this.scoreBundleMatch(bundle, needs);
            if (score > bestScore) {
                bestScore = score;
                bestBundle = bundle;
            }
        }
        
        return {
            recommended: bestBundle,
            matchScore: bestScore,
            savings: bestBundle.savings,
            reasoning: this.explainRecommendation(bestBundle, needs)
        };
    }
}
```

## Revenue Optimization

### Yield Management
```javascript
class YieldManagement {
    constructor() {
        this.capacityManager = new CapacityManager();
        this.demandForecaster = new DemandForecaster();
    }
    
    async optimizeYield(timeWindow) {
        const forecast = await this.demandForecaster.forecast(timeWindow);
        const capacity = await this.capacityManager.getAvailableCapacity(timeWindow);
        
        // Segment time windows
        const segments = this.segmentTimeWindows(timeWindow);
        
        // Optimize pricing for each segment
        const pricingPlan = [];
        
        for (const segment of segments) {
            const segmentDemand = forecast.getSegmentDemand(segment);
            const segmentCapacity = capacity.getSegmentCapacity(segment);
            
            const optimalPrice = this.calculateOptimalPrice(
                segmentDemand,
                segmentCapacity,
                segment
            );
            
            pricingPlan.push({
                segment,
                price: optimalPrice,
                expectedRevenue: this.calculateExpectedRevenue(
                    optimalPrice,
                    segmentDemand,
                    segmentCapacity
                )
            });
        }
        
        return {
            forecast,
            capacity,
            pricingPlan,
            totalExpectedRevenue: pricingPlan.reduce((sum, p) => sum + p.expectedRevenue, 0)
        };
    }
    
    calculateOptimalPrice(demand, capacity, segment) {
        // Use price elasticity to find revenue-maximizing price
        const elasticity = this.estimateElasticity(segment);
        const utilizationTarget = 0.85; // Target 85% utilization
        
        // If demand exceeds capacity, increase price
        if (demand > capacity * utilizationTarget) {
            const excessDemand = demand - (capacity * utilizationTarget);
            const priceIncrease = (excessDemand / demand) / elasticity;
            return segment.basePrice * (1 + priceIncrease);
        }
        
        // If capacity exceeds demand, decrease price
        if (demand < capacity * 0.5) {
            const excessCapacity = (capacity * 0.5) - demand;
            const priceDecrease = (excessCapacity / capacity) / elasticity;
            return segment.basePrice * (1 - priceDecrease);
        }
        
        return segment.basePrice;
    }
    
    estimateElasticity(segment) {
        // Price elasticity by time segment
        if (segment.isPeakHour) return 0.5; // Less elastic during peak
        if (segment.isWeekend) return 1.5; // More elastic on weekends
        return 1.0; // Normal elasticity
    }
}
```

### Customer Lifetime Value Pricing
```javascript
class CLVPricing {
    constructor() {
        this.customerAnalytics = new CustomerAnalytics();
        this.retentionModel = new RetentionModel();
    }
    
    async calculateCLVBasedPrice(customer, jobRequest) {
        // Calculate customer lifetime value
        const clv = await this.calculateCLV(customer);
        
        // Determine customer stage
        const stage = this.determineCustomerStage(customer);
        
        // Set price based on CLV and stage
        const price = this.optimizePriceForCLV(clv, stage, jobRequest);
        
        return {
            customerLifetimeValue: clv,
            stage,
            price,
            strategy: this.explainStrategy(clv, stage)
        };
    }
    
    async calculateCLV(customer) {
        const history = await this.customerAnalytics.getHistory(customer);
        
        // Historical value
        const historicalValue = history.totalRevenue;
        
        // Predicted future value
        const retentionProbability = await this.retentionModel.predict(customer);
        const avgMonthlyRevenue = history.totalRevenue / history.months;
        const expectedLifetime = 1 / (1 - retentionProbability); // months
        
        const futureValue = avgMonthlyRevenue * expectedLifetime * retentionProbability;
        
        // Discount future value
        const discountRate = 0.02; // 2% monthly
        const discountedFutureValue = futureValue / (1 + discountRate);
        
        return {
            historical: historicalValue,
            predicted: discountedFutureValue,
            total: historicalValue + discountedFutureValue,
            confidence: this.calculateConfidence(history)
        };
    }
    
    determineCustomerStage(customer) {
        const history = customer.history;
        
        if (history.jobCount === 0) return 'new';
        if (history.jobCount < 5) return 'trial';
        if (history.months < 3) return 'early';
        if (history.churnRisk > 0.7) return 'at-risk';
        if (history.totalRevenue > 10000) return 'vip';
        
        return 'established';
    }
    
    optimizePriceForCLV(clv, stage, jobRequest) {
        const basePrice = this.getBasePrice(jobRequest);
        
        switch (stage) {
            case 'new':
            case 'trial':
                // Aggressive pricing to acquire
                return basePrice * 0.7;
                
            case 'early':
                // Competitive pricing to retain
                return basePrice * 0.9;
                
            case 'established':
                // Fair market pricing
                return basePrice;
                
            case 'at-risk':
                // Retention pricing
                return basePrice * 0.8;
                
            case 'vip':
                // Can charge premium but offer perks
                return basePrice * 1.1;
                
            default:
                return basePrice;
        }
    }
}
```

### A/B Testing Pricing
```javascript
class PricingABTest {
    constructor() {
        this.experiments = new Map();
        this.metrics = new MetricsCollector();
    }
    
    async createPricingExperiment(config) {
        const experiment = {
            id: crypto.randomUUID(),
            name: config.name,
            startTime: Date.now(),
            duration: config.duration || 7 * 24 * 60 * 60 * 1000, // 7 days
            variants: config.variants,
            allocation: config.allocation || this.equalAllocation(config.variants),
            metrics: ['conversionRate', 'avgRevenue', 'winRate', 'profitMargin'],
            status: 'running'
        };
        
        this.experiments.set(experiment.id, experiment);
        
        // Start collecting metrics
        this.startMetricsCollection(experiment);
        
        return experiment;
    }
    
    async assignVariant(customer, experimentId) {
        const experiment = this.experiments.get(experimentId);
        if (!experiment || experiment.status !== 'running') {
            return null;
        }
        
        // Use consistent hashing for assignment
        const hash = this.hashCustomer(customer.id + experimentId);
        const bucket = hash % 100;
        
        // Find variant based on allocation
        let cumulative = 0;
        for (const [variant, allocation] of Object.entries(experiment.allocation)) {
            cumulative += allocation;
            if (bucket < cumulative) {
                return {
                    variant,
                    price: experiment.variants[variant].price
                };
            }
        }
    }
    
    async analyzeExperiment(experimentId) {
        const experiment = this.experiments.get(experimentId);
        const results = {};
        
        // Collect metrics for each variant
        for (const variant of Object.keys(experiment.variants)) {
            const metrics = await this.metrics.getVariantMetrics(experimentId, variant);
            
            results[variant] = {
                sampleSize: metrics.count,
                conversionRate: metrics.conversions / metrics.impressions,
                avgRevenue: metrics.revenue / metrics.conversions,
                winRate: metrics.wins / metrics.bids,
                profitMargin: (metrics.revenue - metrics.costs) / metrics.revenue,
                confidence: this.calculateStatisticalSignificance(metrics)
            };
        }
        
        // Determine winner
        const winner = this.determineWinner(results);
        
        return {
            experiment,
            results,
            winner,
            recommendation: this.generateRecommendation(winner, results)
        };
    }
    
    calculateStatisticalSignificance(metrics) {
        // Simplified confidence calculation
        const sampleSize = metrics.count;
        const conversionRate = metrics.conversions / metrics.impressions;
        const standardError = Math.sqrt(conversionRate * (1 - conversionRate) / sampleSize);
        
        // 95% confidence interval
        const marginOfError = 1.96 * standardError;
        
        return {
            lower: conversionRate - marginOfError,
            upper: conversionRate + marginOfError,
            significant: sampleSize > 100 && marginOfError < 0.05
        };
    }
}
```

## Pricing Optimization

### Multi-Objective Optimization
```javascript
class PricingOptimizer {
    constructor() {
        this.objectives = {
            revenue: { weight: 0.4, target: 'maximize' },
            utilization: { weight: 0.3, target: 'maximize' },
            marketShare: { weight: 0.2, target: 'maximize' },
            customerSatisfaction: { weight: 0.1, target: 'maximize' }
        };
    }
    
    async optimizePricing() {
        const models = await this.getActiveModels();
        const optimizedPrices = {};
        
        for (const modelId of models) {
            const context = await this.gatherContext(modelId);
            const optimalPrice = await this.findOptimalPrice(modelId, context);
            
            optimizedPrices[modelId] = {
                current: context.currentPrice,
                optimal: optimalPrice,
                change: (optimalPrice - context.currentPrice) / context.currentPrice,
                expectedImpact: this.predictImpact(context, optimalPrice)
            };
        }
        
        return optimizedPrices;
    }
    
    async findOptimalPrice(modelId, context) {
        // Use gradient descent to find optimal price
        let price = context.currentPrice;
        let learningRate = 0.01;
        const maxIterations = 100;
        
        for (let i = 0; i < maxIterations; i++) {
            const gradient = await this.calculateGradient(price, context);
            
            // Update price
            price = price - learningRate * gradient;
            
            // Ensure price stays within bounds
            price = Math.max(context.minPrice, Math.min(context.maxPrice, price));
            
            // Check convergence
            if (Math.abs(gradient) < 0.0001) break;
        }
        
        return price;
    }
    
    async calculateGradient(price, context) {
        const epsilon = 0.001;
        
        // Calculate objective at price + epsilon
        const objPlus = await this.calculateObjective(price + epsilon, context);
        
        // Calculate objective at price - epsilon
        const objMinus = await this.calculateObjective(price - epsilon, context);
        
        // Numerical gradient
        return (objPlus - objMinus) / (2 * epsilon);
    }
    
    async calculateObjective(price, context) {
        // Predict metrics at given price
        const predicted = await this.predictMetrics(price, context);
        
        // Calculate weighted objective
        let objective = 0;
        
        for (const [metric, config] of Object.entries(this.objectives)) {
            const value = predicted[metric];
            const normalized = this.normalize(value, metric, context);
            
            if (config.target === 'maximize') {
                objective += config.weight * normalized;
            } else {
                objective += config.weight * (1 - normalized);
            }
        }
        
        return objective;
    }
}
```

## Pricing Checklist

### Strategy Development
- [ ] Market analysis completed
- [ ] Competitor prices monitored
- [ ] Cost structure analyzed
- [ ] Value proposition defined
- [ ] Customer segments identified
- [ ] Pricing objectives set

### Implementation
- [ ] Dynamic pricing engine deployed
- [ ] A/B testing framework ready
- [ ] Price monitoring active
- [ ] Competitor tracking automated
- [ ] Revenue optimization running
- [ ] Alert thresholds configured

### Monitoring
- [ ] Win rate tracked
- [ ] Revenue per job monitored
- [ ] Profit margins calculated
- [ ] Customer satisfaction measured
- [ ] Market share estimated
- [ ] Price elasticity analyzed

## Anti-Patterns to Avoid

### ❌ Pricing Mistakes
```javascript
// Race to the bottom
price = competitorPrice * 0.5; // Unsustainable

// Ignoring costs
price = marketPrice; // What about profitability?

// Static pricing
const FIXED_PRICE = 0.01; // Missing opportunities

// Complexity overload
price = base * factor1 * factor2 * factor3...; // Confusing
```

### ✅ Pricing Best Practices
```javascript
// Sustainable competitive pricing
price = Math.max(competitorPrice * 0.9, minProfitablePrice);

// Cost-aware pricing
price = totalCosts * (1 + targetMargin);

// Dynamic response to market
price = await dynamicPricingEngine.calculate(context);

// Clear, simple pricing
price = basePrice * (1 + demandMultiplier);
```

## Tools and Resources

### Pricing Analytics Tools
```javascript
class PricingDashboard {
    async generateReport() {
        return {
            overview: {
                avgPrice: await this.getAvgPrice(),
                priceRange: await this.getPriceRange(),
                priceVolatility: await this.getPriceVolatility()
            },
            performance: {
                revenue: await this.getRevenue(),
                winRate: await this.getWinRate(),
                profitMargin: await this.getProfitMargin()
            },
            competitive: {
                marketPosition: await this.getMarketPosition(),
                priceComparison: await this.getPriceComparison()
            },
            recommendations: await this.generateRecommendations()
        };
    }
}
```

## Next Steps

1. Implement [Staking Economics](staking-economics.md)
2. Review [Risk Management](risk-management.md) strategies
3. Set up pricing experiments
4. Monitor pricing performance

## Additional Resources

- [The Strategy and Tactics of Pricing](https://www.amazon.com/Strategy-Tactics-Pricing-Profitable-Decision/dp/0136106811)
- [Dynamic Pricing Strategies](https://www.mckinsey.com/industries/retail/our-insights/how-retailers-can-drive-profitable-growth-through-dynamic-pricing)
- [Behavioral Pricing](https://hbr.org/2017/10/how-to-price-your-product)
- [Revenue Management](https://www.amazon.com/Revenue-Management-Hard-Core-Tactics-Advantage/dp/1563273381)

---

Remember: **Price is what you pay, value is what you get.** Focus on delivering value while optimizing for profitability.