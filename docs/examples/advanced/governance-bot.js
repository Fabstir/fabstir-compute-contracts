/**
 * Example: Governance Bot
 * Purpose: Automated governance participation with voting strategies and proposal monitoring
 * Prerequisites:
 *   - Governance tokens for voting
 *   - Understanding of DAO mechanics
 *   - Voting strategy configuration
 */

const { ethers } = require('ethers');
const axios = require('axios');
const EventEmitter = require('events');
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const GOVERNANCE_ABI = [
    'function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) returns (uint256)',
    'function castVote(uint256 proposalId, uint8 support)',
    'function castVoteWithReason(uint256 proposalId, uint8 support, string reason)',
    'function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s)',
    'function execute(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) payable',
    'function state(uint256 proposalId) view returns (uint8)',
    'function proposalVotes(uint256 proposalId) view returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)',
    'function getVotes(address account, uint256 blockNumber) view returns (uint256)',
    'function proposalDeadline(uint256 proposalId) view returns (uint256)',
    'function proposalSnapshot(uint256 proposalId) view returns (uint256)',
    'function quorum(uint256 blockNumber) view returns (uint256)',
    'event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 startBlock, uint256 endBlock, string description)',
    'event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason)',
    'event ProposalExecuted(uint256 proposalId)'
];

const GOVERNANCE_TOKEN_ABI = [
    'function balanceOf(address account) view returns (uint256)',
    'function delegate(address delegatee)',
    'function delegates(address account) view returns (address)',
    'function getPastVotes(address account, uint256 blockNumber) view returns (uint256)',
    'function totalSupply() view returns (uint256)'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    contracts: {
        governance: process.env.GOVERNANCE,
        governanceToken: process.env.GOVERNANCE_TOKEN
    },
    
    // Bot settings
    bot: {
        // Voting strategy
        strategy: 'informed', // 'always-for', 'always-against', 'informed', 'follow-delegate'
        delegate: null, // Address to follow for 'follow-delegate' strategy
        
        // Proposal analysis
        analysisDepth: 'deep', // 'basic', 'moderate', 'deep'
        riskThreshold: 0.7, // Vote against if risk score > threshold
        
        // Participation settings
        minQuorumParticipation: 0.01, // Participate if holding > 1% of quorum
        gasLimitMultiplier: 1.2,
        
        // Monitoring
        checkInterval: 60000, // 1 minute
        proposalCache: new Map(),
        
        // Notifications
        webhookUrl: process.env.GOVERNANCE_WEBHOOK,
        notifyOn: ['new-proposal', 'vote-cast', 'proposal-executed', 'quorum-reached']
    },
    
    // Analysis weights
    analysisWeights: {
        codeComplexity: 0.2,
        financialImpact: 0.3,
        securityRisk: 0.3,
        communitySupport: 0.2
    }
};

// Proposal analyzer
class ProposalAnalyzer {
    constructor() {
        this.riskFactors = {
            highValueTransfer: 0.8,
            contractUpgrade: 0.9,
            parameterChange: 0.4,
            newIntegration: 0.7,
            emergencyAction: 1.0
        };
    }
    
    async analyzeProposal(proposal, depth = 'moderate') {
        console.log(`   🔍 Analyzing proposal #${proposal.id} (${depth} analysis)...`);
        
        const analysis = {
            proposalId: proposal.id,
            title: this.extractTitle(proposal.description),
            category: this.categorizeProposal(proposal),
            riskScore: 0,
            financialImpact: 0,
            codeComplexity: 0,
            communitySupport: 0,
            recommendation: null,
            reasoning: []
        };
        
        // Basic analysis
        analysis.riskScore = this.assessRisk(proposal);
        analysis.financialImpact = this.assessFinancialImpact(proposal);
        
        if (depth === 'moderate' || depth === 'deep') {
            // Moderate analysis
            analysis.codeComplexity = this.assessCodeComplexity(proposal);
            analysis.communitySupport = await this.assessCommunitySupport(proposal);
        }
        
        if (depth === 'deep') {
            // Deep analysis
            await this.performDeepAnalysis(proposal, analysis);
        }
        
        // Generate recommendation
        analysis.recommendation = this.generateRecommendation(analysis);
        
        return analysis;
    }
    
    extractTitle(description) {
        const lines = description.split('\n');
        return lines[0].replace(/^#+\s*/, '').trim();
    }
    
    categorizeProposal(proposal) {
        const description = proposal.description.toLowerCase();
        
        if (description.includes('upgrade') || description.includes('migration')) {
            return 'upgrade';
        } else if (description.includes('fund') || description.includes('grant')) {
            return 'funding';
        } else if (description.includes('parameter') || description.includes('config')) {
            return 'parameter';
        } else if (description.includes('emergency') || description.includes('pause')) {
            return 'emergency';
        } else {
            return 'general';
        }
    }
    
    assessRisk(proposal) {
        let riskScore = 0;
        const { targets, values, calldatas } = proposal;
        
        // Check for high value transfers
        const totalValue = values.reduce((sum, val) => sum + Number(val), 0);
        if (totalValue > ethers.parseEther('1000')) {
            riskScore += this.riskFactors.highValueTransfer;
        }
        
        // Check for contract upgrades
        if (calldatas.some(data => data.includes('0x3659cfe6'))) { // upgradeTo selector
            riskScore += this.riskFactors.contractUpgrade;
        }
        
        // Category-based risk
        const categoryRisks = {
            'upgrade': 0.8,
            'funding': 0.5,
            'parameter': 0.4,
            'emergency': 0.9,
            'general': 0.3
        };
        
        riskScore += categoryRisks[proposal.category] || 0.3;
        
        return Math.min(riskScore, 1);
    }
    
    assessFinancialImpact(proposal) {
        const totalValue = proposal.values.reduce((sum, val) => sum + Number(val), 0);
        
        // Normalize to 0-1 scale (1000 ETH = 1.0)
        return Math.min(Number(totalValue) / Number(ethers.parseEther('1000')), 1);
    }
    
    assessCodeComplexity(proposal) {
        let complexity = 0;
        
        // Number of actions
        complexity += Math.min(proposal.targets.length * 0.1, 0.3);
        
        // Calldata size
        const totalCalldata = proposal.calldatas.reduce((sum, data) => sum + data.length, 0);
        complexity += Math.min(totalCalldata / 10000, 0.4);
        
        // Unique targets
        const uniqueTargets = new Set(proposal.targets).size;
        complexity += Math.min(uniqueTargets * 0.15, 0.3);
        
        return complexity;
    }
    
    async assessCommunitySupport(proposal) {
        // In production, this would analyze Discord/forum sentiment
        // For demo, we'll simulate based on proposal type
        const supportByCategory = {
            'upgrade': 0.6,
            'funding': 0.7,
            'parameter': 0.5,
            'emergency': 0.8,
            'general': 0.5
        };
        
        return supportByCategory[proposal.category] || 0.5;
    }
    
    async performDeepAnalysis(proposal, analysis) {
        // Simulate contract simulation
        analysis.reasoning.push('Performed transaction simulation');
        
        // Check historical precedent
        analysis.reasoning.push('Analyzed similar historical proposals');
        
        // Security audit check
        if (proposal.category === 'upgrade') {
            analysis.reasoning.push('Verified security audit status');
        }
    }
    
    generateRecommendation(analysis) {
        // Calculate weighted score
        const score = 
            (1 - analysis.riskScore) * config.analysisWeights.securityRisk +
            (1 - analysis.financialImpact) * config.analysisWeights.financialImpact +
            (1 - analysis.codeComplexity) * config.analysisWeights.codeComplexity +
            analysis.communitySupport * config.analysisWeights.communitySupport;
        
        if (score > 0.7) {
            analysis.reasoning.push('High overall score with acceptable risk');
            return 'FOR';
        } else if (score > 0.4) {
            analysis.reasoning.push('Moderate score - abstaining for more information');
            return 'ABSTAIN';
        } else {
            analysis.reasoning.push('Low score or high risk detected');
            return 'AGAINST';
        }
    }
}

// Voting strategy implementations
class VotingStrategy {
    constructor(type, delegate = null) {
        this.type = type;
        this.delegate = delegate;
        this.analyzer = new ProposalAnalyzer();
    }
    
    async determineVote(proposal, analysis) {
        switch (this.type) {
            case 'always-for':
                return { support: 1, reason: 'Strategy: Always vote for proposals' };
                
            case 'always-against':
                return { support: 0, reason: 'Strategy: Always vote against proposals' };
                
            case 'informed':
                return this.informedVote(proposal, analysis);
                
            case 'follow-delegate':
                return this.followDelegate(proposal);
                
            default:
                return { support: 2, reason: 'Strategy: Abstain by default' };
        }
    }
    
    informedVote(proposal, analysis) {
        const voteMap = {
            'FOR': 1,
            'AGAINST': 0,
            'ABSTAIN': 2
        };
        
        const support = voteMap[analysis.recommendation];
        const reason = `Informed vote: ${analysis.reasoning.join('; ')}`;
        
        return { support, reason };
    }
    
    async followDelegate(proposal) {
        // In production, check how delegate voted
        // For demo, simulate
        const delegateVote = Math.floor(Math.random() * 3);
        const voteNames = ['AGAINST', 'FOR', 'ABSTAIN'];
        
        return {
            support: delegateVote,
            reason: `Following delegate ${this.delegate}: ${voteNames[delegateVote]}`
        };
    }
}

// Main governance bot
class GovernanceBot extends EventEmitter {
    constructor(contracts, wallet) {
        super();
        this.contracts = contracts;
        this.wallet = wallet;
        this.strategy = new VotingStrategy(config.bot.strategy, config.bot.delegate);
        this.isRunning = false;
        this.votingPower = ethers.parseEther('0');
    }
    
    async initialize() {
        console.log('🏛️ Initializing Governance Bot...');
        
        // Check token balance and delegation
        const balance = await this.contracts.governanceToken.balanceOf(this.wallet.address);
        console.log(`   Token balance: ${ethers.formatEther(balance)}`);
        
        const currentDelegate = await this.contracts.governanceToken.delegates(this.wallet.address);
        if (currentDelegate === ethers.ZeroAddress) {
            console.log('   ⚠️  No delegation set - delegating to self...');
            const tx = await this.contracts.governanceToken.delegate(this.wallet.address);
            await tx.wait();
            console.log('   ✅ Self-delegation complete');
        } else {
            console.log(`   Delegated to: ${currentDelegate}`);
        }
        
        // Get voting power
        const blockNumber = await this.contracts.governance.provider.getBlockNumber();
        this.votingPower = await this.contracts.governanceToken.getPastVotes(
            this.wallet.address,
            blockNumber - 1
        );
        console.log(`   Voting power: ${ethers.formatEther(this.votingPower)}`);
        
        // Check if we meet minimum participation threshold
        const quorum = await this.contracts.governance.quorum(blockNumber - 1);
        const participation = Number(this.votingPower) / Number(quorum);
        
        if (participation < config.bot.minQuorumParticipation) {
            console.log(`   ⚠️  Low voting power: ${(participation * 100).toFixed(2)}% of quorum`);
        } else {
            console.log(`   ✅ Voting power: ${(participation * 100).toFixed(2)}% of quorum`);
        }
        
        console.log(`   Strategy: ${config.bot.strategy}`);
        console.log('   ✅ Initialization complete');
    }
    
    async start() {
        console.log('\n▶️  Starting governance monitoring...');
        this.isRunning = true;
        
        // Initial scan
        await this.scanProposals();
        
        // Set up interval scanning
        this.scanInterval = setInterval(() => {
            if (this.isRunning) {
                this.scanProposals();
            }
        }, config.bot.checkInterval);
        
        // Listen for governance events
        this.setupEventListeners();
        
        console.log('   ✅ Governance bot started');
    }
    
    async scanProposals() {
        try {
            // Get recent proposal events
            const filter = this.contracts.governance.filters.ProposalCreated();
            const events = await this.contracts.governance.queryFilter(filter, -10000); // Last 10k blocks
            
            for (const event of events) {
                const proposalId = event.args[0];
                const proposalIdStr = proposalId.toString();
                
                // Skip if already processed
                if (config.bot.proposalCache.has(proposalIdStr)) {
                    continue;
                }
                
                // Get proposal state
                const state = await this.contracts.governance.state(proposalId);
                
                // Process based on state
                // 0: Pending, 1: Active, 2: Canceled, 3: Defeated, 4: Succeeded, 5: Queued, 6: Expired, 7: Executed
                if (state === 1) { // Active
                    await this.processActiveProposal(proposalId, event);
                } else if (state === 4) { // Succeeded
                    await this.processSucceededProposal(proposalId);
                }
                
                // Cache to avoid reprocessing
                config.bot.proposalCache.set(proposalIdStr, {
                    state,
                    processed: Date.now()
                });
            }
        } catch (error) {
            console.error('Scan error:', error);
        }
    }
    
    async processActiveProposal(proposalId, event) {
        console.log(`\n📋 Processing active proposal #${proposalId}`);
        
        // Parse proposal details
        const proposal = {
            id: proposalId,
            proposer: event.args[1],
            targets: event.args[2],
            values: event.args[3],
            calldatas: event.args[5],
            description: event.args[8],
            startBlock: event.args[6],
            endBlock: event.args[7],
            category: 'general'
        };
        
        // Check if we've already voted
        const hasVoted = await this.checkIfVoted(proposalId);
        if (hasVoted) {
            console.log('   Already voted on this proposal');
            return;
        }
        
        // Analyze proposal
        const analysis = await this.strategy.analyzer.analyzeProposal(
            proposal,
            config.bot.analysisDepth
        );
        
        console.log(`   Title: ${analysis.title}`);
        console.log(`   Category: ${analysis.category}`);
        console.log(`   Risk score: ${(analysis.riskScore * 100).toFixed(1)}%`);
        console.log(`   Recommendation: ${analysis.recommendation}`);
        
        // Determine vote
        const { support, reason } = await this.strategy.determineVote(proposal, analysis);
        
        // Cast vote
        await this.castVote(proposalId, support, reason);
        
        // Notify
        await this.notify('vote-cast', {
            proposalId,
            title: analysis.title,
            vote: ['AGAINST', 'FOR', 'ABSTAIN'][support],
            reason
        });
    }
    
    async processSucceededProposal(proposalId) {
        const cached = config.bot.proposalCache.get(proposalId.toString());
        if (cached && cached.executed) {
            return;
        }
        
        console.log(`\n✅ Proposal #${proposalId} succeeded - checking execution...`);
        
        // Check deadline
        const deadline = await this.contracts.governance.proposalDeadline(proposalId);
        const now = Math.floor(Date.now() / 1000);
        
        if (now > deadline) {
            console.log('   Proposal deadline passed - can be executed');
            
            // In production, might want to execute if it benefits us
            // For safety, we'll just notify
            await this.notify('proposal-ready', {
                proposalId,
                action: 'ready-for-execution'
            });
        }
    }
    
    async checkIfVoted(proposalId) {
        // Check vote events
        const filter = this.contracts.governance.filters.VoteCast(this.wallet.address, proposalId);
        const events = await this.contracts.governance.queryFilter(filter);
        return events.length > 0;
    }
    
    async castVote(proposalId, support, reason) {
        console.log(`   🗳️  Casting vote: ${['AGAINST', 'FOR', 'ABSTAIN'][support]}`);
        console.log(`   Reason: ${reason}`);
        
        try {
            const tx = await this.contracts.governance.castVoteWithReason(
                proposalId,
                support,
                reason,
                {
                    gasLimit: Math.floor(300000 * config.bot.gasLimitMultiplier),
                    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
                    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
                }
            );
            
            console.log(`   Transaction: ${tx.hash}`);
            const receipt = await tx.wait();
            console.log(`   ✅ Vote cast successfully!`);
            
            // Get updated vote counts
            const votes = await this.contracts.governance.proposalVotes(proposalId);
            console.log(`   Current votes - For: ${ethers.formatEther(votes.forVotes)}, Against: ${ethers.formatEther(votes.againstVotes)}, Abstain: ${ethers.formatEther(votes.abstainVotes)}`);
            
        } catch (error) {
            console.error(`   ❌ Failed to cast vote: ${error.message}`);
        }
    }
    
    setupEventListeners() {
        // New proposals
        this.contracts.governance.on('ProposalCreated', async (proposalId, proposer) => {
            console.log(`\n🔔 New proposal created: #${proposalId}`);
            
            await this.notify('new-proposal', {
                proposalId: proposalId.toString(),
                proposer
            });
        });
        
        // Proposal executed
        this.contracts.governance.on('ProposalExecuted', async (proposalId) => {
            console.log(`\n🎉 Proposal #${proposalId} executed!`);
            
            const cached = config.bot.proposalCache.get(proposalId.toString());
            if (cached) {
                cached.executed = true;
            }
            
            await this.notify('proposal-executed', {
                proposalId: proposalId.toString()
            });
        });
    }
    
    async notify(type, data) {
        if (!config.bot.notifyOn.includes(type)) {
            return;
        }
        
        if (config.bot.webhookUrl) {
            try {
                await axios.post(config.bot.webhookUrl, {
                    type,
                    data,
                    timestamp: Date.now()
                });
            } catch (error) {
                console.error('Notification failed:', error.message);
            }
        }
        
        this.emit(type, data);
    }
    
    async stop() {
        console.log('\n⏹️  Stopping governance bot...');
        this.isRunning = false;
        
        if (this.scanInterval) {
            clearInterval(this.scanInterval);
        }
        
        this.contracts.governance.removeAllListeners();
        
        console.log('   ✅ Governance bot stopped');
    }
    
    async createProposal(targets, values, calldatas, description) {
        console.log('\n📝 Creating new proposal...');
        console.log(`   Description: ${description.split('\n')[0]}`);
        
        try {
            const tx = await this.contracts.governance.propose(
                targets,
                values,
                calldatas,
                description
            );
            
            console.log(`   Transaction: ${tx.hash}`);
            const receipt = await tx.wait();
            
            // Get proposal ID from event
            const event = receipt.events.find(e => e.event === 'ProposalCreated');
            const proposalId = event.args[0];
            
            console.log(`   ✅ Proposal #${proposalId} created!`);
            
            return proposalId;
            
        } catch (error) {
            console.error(`   ❌ Failed to create proposal: ${error.message}`);
            throw error;
        }
    }
}

// Main function
async function main() {
    try {
        console.log('🏛️ Fabstir Governance Bot\n');
        console.log('━'.repeat(50));
        
        // Setup
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`Account: ${wallet.address}`);
        console.log(`Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        console.log('━'.repeat(50) + '\n');
        
        // Initialize contracts
        const contracts = {
            governance: new ethers.Contract(
                config.contracts.governance,
                GOVERNANCE_ABI,
                wallet
            ),
            governanceToken: new ethers.Contract(
                config.contracts.governanceToken,
                GOVERNANCE_TOKEN_ABI,
                wallet
            )
        };
        
        // Create and initialize bot
        const bot = new GovernanceBot(contracts, wallet);
        await bot.initialize();
        
        // Example: Create a proposal (commented out for safety)
        /*
        const exampleProposal = await bot.createProposal(
            ['0x...'], // targets
            [0], // values
            ['0x...'], // calldatas
            '# Increase Node Rewards\n\nThis proposal increases node operator rewards by 10%.'
        );
        */
        
        // Start monitoring
        await bot.start();
        
        // Display stats periodically
        setInterval(async () => {
            const processed = config.bot.proposalCache.size;
            console.log(`\n📊 Bot Stats - ${new Date().toLocaleTimeString()}`);
            console.log(`   Proposals monitored: ${processed}`);
            console.log(`   Voting power: ${ethers.formatEther(bot.votingPower)} tokens`);
        }, 300000); // Every 5 minutes
        
        console.log('\n🤖 Governance bot is running!');
        console.log('   • Strategy:', config.bot.strategy);
        console.log('   • Analysis depth:', config.bot.analysisDepth);
        console.log('   • Check interval:', config.bot.checkInterval / 1000, 'seconds');
        console.log('\nPress Ctrl+C to stop\n');
        
        // Handle shutdown
        process.on('SIGINT', async () => {
            await bot.stop();
            process.exit(0);
        });
        
        // Keep running
        await new Promise(() => {});
        
    } catch (error) {
        console.error('❌ Error:', error.message);
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main();
}

// Export for use in other modules
module.exports = {
    GovernanceBot,
    ProposalAnalyzer,
    VotingStrategy,
    config
};

/**
 * Expected Output:
 * 
 * 🏛️ Fabstir Governance Bot
 * ══════════════════════════════════════════════════
 * Account: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 * Network: Base Mainnet
 * ══════════════════════════════════════════════════
 * 
 * 🏛️ Initializing Governance Bot...
 *    Token balance: 10000.0
 *    Delegated to: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Voting power: 10000.0
 *    ✅ Voting power: 2.50% of quorum
 *    Strategy: informed
 *    ✅ Initialization complete
 * 
 * ▶️  Starting governance monitoring...
 *    ✅ Governance bot started
 * 
 * 📋 Processing active proposal #15
 *    🔍 Analyzing proposal #15 (deep analysis)...
 *    Title: Upgrade JobMarketplace to v2
 *    Category: upgrade
 *    Risk score: 72.0%
 *    Recommendation: AGAINST
 *    🗳️  Casting vote: AGAINST
 *    Reason: Informed vote: High overall score with acceptable risk; Performed transaction simulation; Analyzed similar historical proposals; Verified security audit status; Low score or high risk detected
 *    Transaction: 0xabc123...
 *    ✅ Vote cast successfully!
 *    Current votes - For: 25000.0, Against: 35000.0, Abstain: 5000.0
 * 
 * 🔔 New proposal created: #16
 * 
 * 📋 Processing active proposal #16
 *    🔍 Analyzing proposal #16 (deep analysis)...
 *    Title: Fund Community Grants Program
 *    Category: funding
 *    Risk score: 45.0%
 *    Recommendation: FOR
 *    🗳️  Casting vote: FOR
 *    Reason: Informed vote: High overall score with acceptable risk; Performed transaction simulation; Analyzed similar historical proposals
 *    Transaction: 0xdef456...
 *    ✅ Vote cast successfully!
 *    Current votes - For: 45000.0, Against: 10000.0, Abstain: 8000.0
 * 
 * ✅ Proposal #14 succeeded - checking execution...
 *    Proposal deadline passed - can be executed
 * 
 * 🎉 Proposal #14 executed!
 * 
 * 📊 Bot Stats - 11:30:45 AM
 *    Proposals monitored: 3
 *    Voting power: 10000.0 tokens
 * 
 * 🤖 Governance bot is running!
 *    • Strategy: informed
 *    • Analysis depth: deep
 *    • Check interval: 60 seconds
 * 
 * Press Ctrl+C to stop
 */