/**
 * Example: Reputation Tracking
 * Purpose: Monitor and improve node reputation through performance tracking and optimization
 * Prerequisites:
 *   - Active node with completed jobs
 *   - Access to ReputationSystem contract
 *   - Historical performance data
 */

const { ethers } = require('ethers');
const fs = require('fs').promises;
const path = require('path');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const REPUTATION_SYSTEM_ABI = [
    'function getNodeStats(address node) view returns (tuple(uint256 jobsCompleted, uint256 jobsFailed, uint256 totalEarned, uint256 avgCompletionTime, uint256 lastJobTimestamp, uint256 reputationScore))',
    'function getReputationHistory(address node, uint256 limit) view returns (tuple(uint256 timestamp, uint256 score, string reason)[])',
    'function getTopNodes(uint256 limit) view returns (tuple(address node, uint256 score, uint256 jobsCompleted)[])',
    'function calculateReputationScore(address node) view returns (uint256)',
    'event ReputationUpdated(address indexed node, uint256 oldScore, uint256 newScore, string reason)'
];

const JOB_MARKETPLACE_ABI = [
    'function getNodeJobs(address node, uint256 offset, uint256 limit) view returns (uint256[])',
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    reputationSystem: process.env.REPUTATION_SYSTEM || '0x...',
    jobMarketplace: process.env.JOB_MARKETPLACE || '0x...',
    
    // Monitoring settings
    checkInterval: 60000, // 1 minute
    historyLimit: 100,
    dataDir: './reputation-data',
    
    // Reputation thresholds
    excellentScore: 900,
    goodScore: 700,
    averageScore: 500,
    poorScore: 300
};

// Performance metrics calculator
class PerformanceMetrics {
    constructor() {
        this.metrics = {
            completionRate: 0,
            avgCompletionTime: 0,
            avgEarningsPerJob: 0,
            successStreak: 0,
            failureRate: 0,
            uptimePercentage: 0,
            modelSpecialization: new Map()
        };
    }
    
    async calculate(stats, jobs) {
        const total = stats.jobsCompleted + stats.jobsFailed;
        
        if (total > 0) {
            this.metrics.completionRate = (stats.jobsCompleted / total) * 100;
            this.metrics.failureRate = (stats.jobsFailed / total) * 100;
        }
        
        if (stats.jobsCompleted > 0) {
            this.metrics.avgEarningsPerJob = stats.totalEarned / stats.jobsCompleted;
            this.metrics.avgCompletionTime = stats.avgCompletionTime;
        }
        
        // Analyze job patterns
        this.analyzeJobPatterns(jobs);
        
        return this.metrics;
    }
    
    analyzeJobPatterns(jobs) {
        const modelCount = new Map();
        let currentStreak = 0;
        let maxStreak = 0;
        
        for (const job of jobs) {
            // Count model usage
            const count = modelCount.get(job.modelId) || 0;
            modelCount.set(job.modelId, count + 1);
            
            // Track success streaks
            if (job.status === 2) { // Completed
                currentStreak++;
                maxStreak = Math.max(maxStreak, currentStreak);
            } else if (job.status === 3) { // Failed/Cancelled
                currentStreak = 0;
            }
        }
        
        this.metrics.successStreak = maxStreak;
        this.metrics.modelSpecialization = modelCount;
    }
}

// Reputation analyzer
class ReputationAnalyzer {
    constructor(reputationSystem) {
        this.reputationSystem = reputationSystem;
        this.recommendations = [];
    }
    
    async analyze(nodeAddress, stats, metrics) {
        console.log('\n📊 Reputation Analysis');
        
        // Get current score
        const score = stats.reputationScore;
        console.log(`   Current Score: ${score}/1000`);
        
        // Determine tier
        const tier = this.getTier(score);
        console.log(`   Tier: ${tier.name} ${tier.emoji}`);
        console.log(`   Rank: ${tier.description}`);
        
        // Performance analysis
        console.log('\n   Performance Metrics:');
        console.log(`   • Completion Rate: ${metrics.completionRate.toFixed(1)}%`);
        console.log(`   • Average Completion Time: ${Math.floor(metrics.avgCompletionTime / 60)} minutes`);
        console.log(`   • Average Earnings: ${ethers.formatEther(metrics.avgEarningsPerJob)} ETH/job`);
        console.log(`   • Success Streak: ${metrics.successStreak} jobs`);
        
        // Generate recommendations
        this.generateRecommendations(score, stats, metrics);
        
        if (this.recommendations.length > 0) {
            console.log('\n   💡 Recommendations:');
            this.recommendations.forEach((rec, i) => {
                console.log(`   ${i + 1}. ${rec}`);
            });
        }
        
        return {
            score,
            tier,
            metrics,
            recommendations: this.recommendations
        };
    }
    
    getTier(score) {
        if (score >= config.excellentScore) {
            return {
                name: 'Elite',
                emoji: '⭐',
                description: 'Top tier node with priority access'
            };
        } else if (score >= config.goodScore) {
            return {
                name: 'Professional',
                emoji: '🏆',
                description: 'Reliable node with good track record'
            };
        } else if (score >= config.averageScore) {
            return {
                name: 'Standard',
                emoji: '✅',
                description: 'Average performing node'
            };
        } else if (score >= config.poorScore) {
            return {
                name: 'Developing',
                emoji: '📈',
                description: 'New or improving node'
            };
        } else {
            return {
                name: 'At Risk',
                emoji: '⚠️',
                description: 'Poor performance, needs improvement'
            };
        }
    }
    
    generateRecommendations(score, stats, metrics) {
        this.recommendations = [];
        
        // Completion rate recommendations
        if (metrics.completionRate < 95) {
            this.recommendations.push(
                `Improve completion rate (current: ${metrics.completionRate.toFixed(1)}%). Avoid claiming jobs you can't complete.`
            );
        }
        
        // Speed recommendations
        if (metrics.avgCompletionTime > 1800) { // 30 minutes
            this.recommendations.push(
                'Reduce average completion time. Consider upgrading hardware or optimizing inference pipeline.'
            );
        }
        
        // Activity recommendations
        const daysSinceLastJob = (Date.now() / 1000 - stats.lastJobTimestamp) / 86400;
        if (daysSinceLastJob > 7) {
            this.recommendations.push(
                `Increase activity. Last job was ${Math.floor(daysSinceLastJob)} days ago.`
            );
        }
        
        // Specialization recommendations
        if (metrics.modelSpecialization.size > 5) {
            this.recommendations.push(
                'Consider specializing in fewer models for better optimization and caching.'
            );
        }
        
        // Score-based recommendations
        if (score < config.goodScore) {
            this.recommendations.push(
                'Focus on successfully completing smaller jobs to build reputation.'
            );
        }
        
        if (score >= config.excellentScore) {
            this.recommendations.push(
                'Maintain excellent performance to keep Elite status and premium job access.'
            );
        }
    }
}

// Historical data tracker
class HistoricalTracker {
    constructor(dataDir) {
        this.dataDir = dataDir;
        this.dataFile = path.join(dataDir, 'reputation-history.json');
    }
    
    async initialize() {
        try {
            await fs.mkdir(this.dataDir, { recursive: true });
        } catch (error) {
            // Directory might already exist
        }
    }
    
    async saveSnapshot(data) {
        try {
            // Load existing data
            let history = [];
            try {
                const existing = await fs.readFile(this.dataFile, 'utf8');
                history = JSON.parse(existing);
            } catch {
                // File doesn't exist yet
            }
            
            // Add new snapshot
            history.push({
                timestamp: Date.now(),
                ...data
            });
            
            // Keep only last 1000 entries
            if (history.length > 1000) {
                history = history.slice(-1000);
            }
            
            // Save updated history
            await fs.writeFile(this.dataFile, JSON.stringify(history, null, 2));
            
        } catch (error) {
            console.error('Failed to save historical data:', error);
        }
    }
    
    async loadHistory() {
        try {
            const data = await fs.readFile(this.dataFile, 'utf8');
            return JSON.parse(data);
        } catch {
            return [];
        }
    }
    
    async generateReport(history) {
        if (history.length < 2) {
            return null;
        }
        
        // Calculate trends
        const recent = history.slice(-24); // Last 24 snapshots
        const older = history.slice(-48, -24); // Previous 24
        
        const recentAvgScore = recent.reduce((sum, h) => sum + h.score, 0) / recent.length;
        const olderAvgScore = older.length > 0 
            ? older.reduce((sum, h) => sum + h.score, 0) / older.length 
            : recentAvgScore;
        
        const scoreTrend = recentAvgScore - olderAvgScore;
        const trendDirection = scoreTrend > 0 ? 'improving' : scoreTrend < 0 ? 'declining' : 'stable';
        
        return {
            currentScore: history[history.length - 1].score,
            avgScore24h: recentAvgScore,
            scoreTrend,
            trendDirection,
            totalSnapshots: history.length,
            oldestSnapshot: new Date(history[0].timestamp),
            latestSnapshot: new Date(history[history.length - 1].timestamp)
        };
    }
}

// Real-time monitor
class ReputationMonitor {
    constructor(contracts, wallet) {
        this.contracts = contracts;
        this.wallet = wallet;
        this.isRunning = false;
    }
    
    async start() {
        console.log('\n🔍 Starting reputation monitor...');
        this.isRunning = true;
        
        // Initial check
        await this.check();
        
        // Set up interval
        this.interval = setInterval(async () => {
            if (this.isRunning) {
                await this.check();
            }
        }, config.checkInterval);
        
        // Listen for reputation events
        this.contracts.reputationSystem.on('ReputationUpdated', (node, oldScore, newScore, reason) => {
            if (node.toLowerCase() === this.wallet.address.toLowerCase()) {
                console.log(`\n🔔 Reputation Update!`);
                console.log(`   Old Score: ${oldScore}`);
                console.log(`   New Score: ${newScore}`);
                console.log(`   Change: ${newScore > oldScore ? '+' : ''}${newScore - oldScore}`);
                console.log(`   Reason: ${reason}`);
            }
        });
    }
    
    async check() {
        try {
            const stats = await this.contracts.reputationSystem.getNodeStats(this.wallet.address);
            const score = Number(stats.reputationScore);
            
            // Simple console update
            process.stdout.write(`\r⏱️  Score: ${score}/1000 | Jobs: ${stats.jobsCompleted} | Monitoring...`);
            
        } catch (error) {
            console.error('\nMonitor error:', error.message);
        }
    }
    
    stop() {
        this.isRunning = false;
        if (this.interval) {
            clearInterval(this.interval);
        }
        this.contracts.reputationSystem.removeAllListeners();
        console.log('\n✋ Monitor stopped');
    }
}

// Main function
async function main() {
    try {
        console.log('🌟 Fabstir Reputation Tracking Example\n');
        
        // 1. Setup
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`   Node: ${wallet.address}`);
        console.log(`   Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        
        // 2. Initialize contracts
        console.log('\n2️⃣ Initializing contracts...');
        const reputationSystem = new ethers.Contract(
            config.reputationSystem,
            REPUTATION_SYSTEM_ABI,
            provider
        );
        
        const jobMarketplace = new ethers.Contract(
            config.jobMarketplace,
            JOB_MARKETPLACE_ABI,
            provider
        );
        
        // 3. Get current stats
        console.log('\n3️⃣ Fetching reputation data...');
        const stats = await reputationSystem.getNodeStats(wallet.address);
        
        console.log('   Basic Stats:');
        console.log(`   • Jobs Completed: ${stats.jobsCompleted}`);
        console.log(`   • Jobs Failed: ${stats.jobsFailed}`);
        console.log(`   • Total Earned: ${ethers.formatEther(stats.totalEarned)} ETH`);
        console.log(`   • Reputation Score: ${stats.reputationScore}/1000`);
        
        // 4. Get job history
        console.log('\n4️⃣ Analyzing job history...');
        const jobIds = await jobMarketplace.getNodeJobs(wallet.address, 0, 50);
        const jobs = [];
        
        for (const jobId of jobIds.slice(0, 10)) { // Analyze last 10 jobs
            const job = await jobMarketplace.getJob(jobId);
            jobs.push(job);
        }
        
        // 5. Calculate metrics
        const metricsCalculator = new PerformanceMetrics();
        const metrics = await metricsCalculator.calculate(stats, jobs);
        
        // 6. Analyze reputation
        const analyzer = new ReputationAnalyzer(reputationSystem);
        const analysis = await analyzer.analyze(wallet.address, stats, metrics);
        
        // 7. Track historical data
        console.log('\n5️⃣ Tracking historical data...');
        const tracker = new HistoricalTracker(config.dataDir);
        await tracker.initialize();
        
        await tracker.saveSnapshot({
            score: Number(stats.reputationScore),
            jobsCompleted: Number(stats.jobsCompleted),
            totalEarned: stats.totalEarned.toString(),
            metrics: {
                completionRate: metrics.completionRate,
                avgCompletionTime: metrics.avgCompletionTime
            }
        });
        
        const history = await tracker.loadHistory();
        const report = await tracker.generateReport(history);
        
        if (report) {
            console.log('   Historical Trends:');
            console.log(`   • 24h Average Score: ${report.avgScore24h.toFixed(0)}`);
            console.log(`   • Trend: ${report.trendDirection} (${report.scoreTrend > 0 ? '+' : ''}${report.scoreTrend.toFixed(0)})`);
            console.log(`   • Data Points: ${report.totalSnapshots}`);
        }
        
        // 8. Compare with top nodes
        console.log('\n6️⃣ Comparing with top nodes...');
        const topNodes = await reputationSystem.getTopNodes(10);
        const ourRank = topNodes.findIndex(n => n.node.toLowerCase() === wallet.address.toLowerCase()) + 1;
        
        if (ourRank > 0) {
            console.log(`   Your Rank: #${ourRank} out of top 10`);
        } else {
            console.log(`   Your Rank: Not in top 10`);
        }
        
        console.log('   Top 5 Nodes:');
        topNodes.slice(0, 5).forEach((node, i) => {
            const isUs = node.node.toLowerCase() === wallet.address.toLowerCase();
            console.log(`   ${i + 1}. ${node.node.slice(0, 6)}...${node.node.slice(-4)} - Score: ${node.score}${isUs ? ' (You)' : ''}`);
        });
        
        // 9. Start monitor (optional)
        const readline = require('readline').createInterface({
            input: process.stdin,
            output: process.stdout
        });
        
        await new Promise(resolve => {
            readline.question('\n❓ Start real-time monitoring? (y/n): ', answer => {
                readline.close();
                if (answer.toLowerCase() === 'y') {
                    const monitor = new ReputationMonitor({ reputationSystem, jobMarketplace }, wallet);
                    monitor.start();
                    
                    console.log('\n📡 Monitoring active. Press Ctrl+C to stop.\n');
                    
                    process.on('SIGINT', () => {
                        monitor.stop();
                        process.exit(0);
                    });
                } else {
                    resolve();
                }
            });
        });
        
        // 10. Summary
        console.log('\n📈 Reputation Summary:');
        console.log(`   Current Score: ${stats.reputationScore}/1000`);
        console.log(`   Tier: ${analysis.tier.name} ${analysis.tier.emoji}`);
        console.log(`   Performance: ${metrics.completionRate.toFixed(1)}% success rate`);
        console.log(`   Earnings: ${ethers.formatEther(stats.totalEarned)} ETH total`);
        
        console.log('\n✨ Keep up the good work to improve your reputation!');
        
    } catch (error) {
        console.error('\n❌ Error:', error.message);
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = { 
    main, 
    config,
    PerformanceMetrics,
    ReputationAnalyzer,
    HistoricalTracker,
    ReputationMonitor
};

/**
 * Expected Output:
 * 
 * 🌟 Fabstir Reputation Tracking Example
 * 
 * 1️⃣ Setting up connection...
 *    Node: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 * 
 * 2️⃣ Initializing contracts...
 * 
 * 3️⃣ Fetching reputation data...
 *    Basic Stats:
 *    • Jobs Completed: 247
 *    • Jobs Failed: 3
 *    • Total Earned: 48.75 ETH
 *    • Reputation Score: 875/1000
 * 
 * 4️⃣ Analyzing job history...
 * 
 * 📊 Reputation Analysis
 *    Current Score: 875/1000
 *    Tier: Professional 🏆
 *    Rank: Reliable node with good track record
 * 
 *    Performance Metrics:
 *    • Completion Rate: 98.8%
 *    • Average Completion Time: 12 minutes
 *    • Average Earnings: 0.197 ETH/job
 *    • Success Streak: 42 jobs
 * 
 *    💡 Recommendations:
 *    1. Maintain excellent performance to reach Elite status (25 points away).
 *    2. Consider specializing in fewer models for better optimization and caching.
 * 
 * 5️⃣ Tracking historical data...
 *    Historical Trends:
 *    • 24h Average Score: 872
 *    • Trend: improving (+3)
 *    • Data Points: 156
 * 
 * 6️⃣ Comparing with top nodes...
 *    Your Rank: #7 out of top 10
 *    Top 5 Nodes:
 *    1. 0x1234...5678 - Score: 980
 *    2. 0x9abc...def0 - Score: 965
 *    3. 0x5678...9012 - Score: 952
 *    4. 0x3456...7890 - Score: 945
 *    5. 0xabcd...ef12 - Score: 920
 * 
 * ❓ Start real-time monitoring? (y/n): y
 * 
 * 📡 Monitoring active. Press Ctrl+C to stop.
 * 
 * ⏱️  Score: 875/1000 | Jobs: 247 | Monitoring...
 * 
 * 🔔 Reputation Update!
 *    Old Score: 875
 *    New Score: 878
 *    Change: +3
 *    Reason: Job completed successfully
 * 
 * ✋ Monitor stopped
 * 
 * 📈 Reputation Summary:
 *    Current Score: 878/1000
 *    Tier: Professional 🏆
 *    Performance: 98.8% success rate
 *    Earnings: 48.75 ETH total
 * 
 * ✨ Keep up the good work to improve your reputation!
 */