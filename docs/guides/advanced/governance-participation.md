# Governance Participation Guide

This guide covers how to participate in Fabstir's decentralized governance system, from voting on proposals to creating your own governance initiatives.

## Prerequisites

- FABSTIR governance tokens
- Understanding of DAO governance
- Base wallet with ETH for gas
- Basic knowledge of proposal mechanics

## Governance Overview

### System Architecture
```
Token Holders → Delegate Voting Power → Create Proposals → Vote → Execute
      ↓                ↓                      ↓            ↓         ↓
   Staking        Self/Others            Discussion    Quorum   Timelock
```

### Key Parameters
```javascript
const GOVERNANCE_PARAMS = {
    proposalThreshold: 100000,      // Tokens needed to propose
    quorumVotes: 4000000,          // 4% of supply
    votingDelay: 13140,            // ~2 days (blocks)
    votingPeriod: 45818,           // ~7 days (blocks)
    timelockDelay: 172800,         // 2 days (seconds)
    proposalMaxOperations: 10      // Max actions per proposal
};
```

## Getting Started

### Step 1: Acquire Governance Tokens

#### Check Token Balance
```javascript
const { ethers } = require("ethers");
const { FabstirSDK } = require("@fabstir/sdk");

async function checkGovernanceTokens() {
    const sdk = new FabstirSDK({
        network: "mainnet",
        privateKey: process.env.PRIVATE_KEY
    });
    
    // Get token balance
    const balance = await sdk.governance.getTokenBalance();
    console.log(`Your balance: ${balance} FABSTIR`);
    
    // Get voting power (includes delegated tokens)
    const votingPower = await sdk.governance.getVotingPower();
    console.log(`Your voting power: ${votingPower} votes`);
    
    // Check if can propose
    const canPropose = votingPower >= GOVERNANCE_PARAMS.proposalThreshold;
    console.log(`Can create proposals: ${canPropose}`);
    
    return { balance, votingPower, canPropose };
}
```

#### Earn Governance Tokens
```javascript
// Methods to earn FABSTIR tokens:

// 1. Node Operation Rewards
const nodeRewards = await sdk.governance.getNodeRewards(nodeAddress);
console.log(`Pending rewards: ${nodeRewards} FABSTIR`);

// 2. Liquidity Mining
const lpRewards = await sdk.governance.getLPRewards(lpTokenAddress);
console.log(`LP rewards: ${lpRewards} FABSTIR`);

// 3. Community Contributions
// Tokens distributed for valuable contributions

// 4. Purchase on DEX
const dexUrl = "https://app.uniswap.org/swap?outputCurrency=FABSTIR_ADDRESS";
```

### Step 2: Delegate Voting Power

#### Self-Delegation
```javascript
async function setupVotingPower() {
    const governanceToken = new ethers.Contract(
        GOVERNANCE_TOKEN_ADDRESS,
        ["function delegate(address delegatee)"],
        signer
    );
    
    // Delegate to yourself to activate voting power
    const tx = await governanceToken.delegate(signer.address);
    await tx.wait();
    
    console.log("Voting power activated!");
}
```

#### Delegate to Others
```javascript
async function delegateToExpert(delegateAddress) {
    // Find trusted delegates
    const delegates = await sdk.governance.getTopDelegates();
    
    // Review delegate history
    const delegateInfo = await sdk.governance.getDelegateInfo(delegateAddress);
    console.log(`Delegate ${delegateAddress}:`);
    console.log(`- Total voting power: ${delegateInfo.votingPower}`);
    console.log(`- Proposals created: ${delegateInfo.proposalsCreated}`);
    console.log(`- Participation rate: ${delegateInfo.participationRate}%`);
    
    // Delegate tokens
    const tx = await governanceToken.delegate(delegateAddress);
    await tx.wait();
    
    console.log(`Delegated to ${delegateAddress}`);
}
```

## Voting on Proposals

### Browse Active Proposals
```javascript
async function getActiveProposals() {
    const proposals = await sdk.governance.getProposals({
        status: 'active',
        orderBy: 'endBlock',
        limit: 10
    });
    
    for (const proposal of proposals) {
        console.log(`\nProposal #${proposal.id}: ${proposal.title}`);
        console.log(`Description: ${proposal.description}`);
        console.log(`Current votes: For ${proposal.forVotes}, Against ${proposal.againstVotes}`);
        console.log(`Ends in: ${proposal.endBlock - currentBlock} blocks`);
        console.log(`Actions: ${proposal.actions.length}`);
        
        // Show proposed changes
        for (const action of proposal.actions) {
            console.log(`- ${action.signature} on ${action.target}`);
        }
    }
    
    return proposals;
}
```

### Analyze Proposal Impact
```javascript
class ProposalAnalyzer {
    async analyzeProposal(proposalId) {
        const proposal = await sdk.governance.getProposal(proposalId);
        const analysis = {
            id: proposalId,
            title: proposal.title,
            impacts: [],
            risks: [],
            benefits: []
        };
        
        // Analyze each action
        for (const action of proposal.actions) {
            const impact = await this.analyzeAction(action);
            analysis.impacts.push(impact);
            
            if (impact.risk > 0.5) {
                analysis.risks.push(impact.riskDescription);
            }
            
            if (impact.benefit > 0.5) {
                analysis.benefits.push(impact.benefitDescription);
            }
        }
        
        // Calculate overall scores
        analysis.riskScore = this.calculateRiskScore(analysis.impacts);
        analysis.benefitScore = this.calculateBenefitScore(analysis.impacts);
        analysis.recommendation = this.getRecommendation(analysis);
        
        return analysis;
    }
    
    async analyzeAction(action) {
        // Decode function call
        const { functionName, params } = this.decodeAction(action);
        
        // Analyze based on function type
        if (functionName === 'setMinimumStake') {
            return this.analyzeStakeChange(params[0]);
        } else if (functionName === 'updateFee') {
            return this.analyzeFeeChange(params[0]);
        } else if (functionName === 'addModel') {
            return this.analyzeModelAddition(params);
        }
        
        return { risk: 0.5, benefit: 0.5 };
    }
    
    analyzeStakeChange(newStake) {
        const currentStake = 100; // ETH
        const change = (newStake - currentStake) / currentStake;
        
        return {
            type: 'stake_change',
            risk: change > 0 ? 0.7 : 0.3, // Higher stake = barrier to entry
            benefit: change < 0 ? 0.7 : 0.3, // Lower stake = more nodes
            riskDescription: change > 0 
                ? `Increases barrier to entry by ${change * 100}%`
                : `May reduce network security`,
            benefitDescription: change < 0
                ? `Enables ${Math.abs(change * 100)}% more potential nodes`
                : `Improves node commitment`
        };
    }
}
```

### Cast Your Vote
```javascript
async function voteOnProposal(proposalId, support, reason = "") {
    // 0 = Against, 1 = For, 2 = Abstain
    const voteOptions = {
        against: 0,
        for: 1,
        abstain: 2
    };
    
    try {
        // Check voting power
        const votingPower = await sdk.governance.getVotingPower();
        if (votingPower === 0) {
            throw new Error("No voting power - delegate tokens first");
        }
        
        // Cast vote
        const tx = await sdk.governance.vote(
            proposalId,
            voteOptions[support],
            reason
        );
        
        console.log(`Voting ${support} on proposal ${proposalId}...`);
        const receipt = await tx.wait();
        
        console.log(`Vote cast! You voted with ${votingPower} votes`);
        
        // Get updated tally
        const proposal = await sdk.governance.getProposal(proposalId);
        console.log(`New tally: For ${proposal.forVotes}, Against ${proposal.againstVotes}`);
        
        return receipt;
        
    } catch (error) {
        console.error("Voting failed:", error.message);
        throw error;
    }
}

// Vote with reason (on-chain)
await voteOnProposal(
    123,
    'for',
    'This proposal improves decentralization by lowering barriers to entry'
);
```

### Monitor Voting Progress
```javascript
class VoteMonitor {
    constructor(sdk) {
        this.sdk = sdk;
        this.proposals = new Map();
    }
    
    async trackProposal(proposalId) {
        const proposal = await this.sdk.governance.getProposal(proposalId);
        this.proposals.set(proposalId, proposal);
        
        // Set up monitoring
        const interval = setInterval(async () => {
            const updated = await this.updateProposal(proposalId);
            
            if (updated.state !== 'Active') {
                clearInterval(interval);
                this.onProposalEnded(updated);
            }
        }, 60000); // Check every minute
        
        return proposal;
    }
    
    async updateProposal(proposalId) {
        const proposal = await this.sdk.governance.getProposal(proposalId);
        const previous = this.proposals.get(proposalId);
        
        // Calculate changes
        const changes = {
            forVotes: proposal.forVotes - previous.forVotes,
            againstVotes: proposal.againstVotes - previous.againstVotes,
            abstainVotes: proposal.abstainVotes - previous.abstainVotes
        };
        
        // Check if quorum reached
        const quorumReached = proposal.forVotes + proposal.againstVotes >= GOVERNANCE_PARAMS.quorumVotes;
        
        // Calculate time remaining
        const blocksRemaining = proposal.endBlock - await this.getCurrentBlock();
        const timeRemaining = blocksRemaining * 12; // ~12 seconds per block
        
        console.log(`Proposal ${proposalId} Update:`);
        console.log(`For: ${proposal.forVotes} (+${changes.forVotes})`);
        console.log(`Against: ${proposal.againstVotes} (+${changes.againstVotes})`);
        console.log(`Quorum: ${quorumReached ? 'YES' : 'NO'}`);
        console.log(`Time remaining: ${Math.floor(timeRemaining / 3600)}h`);
        
        this.proposals.set(proposalId, proposal);
        return proposal;
    }
    
    onProposalEnded(proposal) {
        const passed = proposal.forVotes > proposal.againstVotes && 
                      (proposal.forVotes + proposal.againstVotes) >= GOVERNANCE_PARAMS.quorumVotes;
        
        console.log(`\nProposal ${proposal.id} ended!`);
        console.log(`Result: ${passed ? 'PASSED' : 'FAILED'}`);
        console.log(`Final tally: ${proposal.forVotes} FOR, ${proposal.againstVotes} AGAINST`);
        
        if (passed) {
            console.log(`Execution available after timelock (2 days)`);
        }
    }
}
```

## Creating Proposals

### Proposal Creation Process
```javascript
class ProposalCreator {
    constructor(sdk) {
        this.sdk = sdk;
    }
    
    async createProposal(config) {
        // Step 1: Validate voting power
        const votingPower = await this.sdk.governance.getVotingPower();
        if (votingPower < GOVERNANCE_PARAMS.proposalThreshold) {
            throw new Error(`Need ${GOVERNANCE_PARAMS.proposalThreshold} votes, have ${votingPower}`);
        }
        
        // Step 2: Prepare proposal data
        const proposal = {
            title: config.title,
            description: this.formatDescription(config),
            actions: await this.prepareActions(config.changes)
        };
        
        // Step 3: Simulate proposal
        const simulation = await this.simulateProposal(proposal);
        console.log("Simulation results:", simulation);
        
        // Step 4: Create proposal
        const tx = await this.sdk.governance.createProposal(proposal);
        const receipt = await tx.wait();
        
        // Extract proposal ID
        const proposalId = this.extractProposalId(receipt);
        console.log(`Proposal created! ID: ${proposalId}`);
        
        // Step 5: Promote proposal
        await this.promoteProposal(proposalId, config);
        
        return proposalId;
    }
    
    formatDescription(config) {
        return `
# ${config.title}

## Summary
${config.summary}

## Motivation
${config.motivation}

## Specification
${config.specification}

## Security Considerations
${config.security || 'No security impacts identified.'}

## Discussion
Forum: ${config.forumLink}
        `.trim();
    }
    
    async prepareActions(changes) {
        const actions = [];
        
        for (const change of changes) {
            const action = {
                target: change.contract,
                value: change.value || 0,
                signature: change.signature,
                data: this.encodeCalldata(change.signature, change.params)
            };
            
            // Validate action
            await this.validateAction(action);
            actions.push(action);
        }
        
        return actions;
    }
    
    async simulateProposal(proposal) {
        // Fork current state and simulate
        const simulation = await this.sdk.governance.simulateProposal(proposal);
        
        return {
            gasEstimate: simulation.gasUsed,
            stateChanges: simulation.stateChanges,
            warnings: simulation.warnings,
            errors: simulation.errors
        };
    }
}

// Example: Create a fee reduction proposal
const creator = new ProposalCreator(sdk);

await creator.createProposal({
    title: "Reduce Platform Fee to 2%",
    summary: "Lower the platform fee from 2.5% to 2% to increase competitiveness",
    motivation: "Current fees are higher than competitors, limiting growth",
    specification: "Update PaymentEscrow.platformFee from 250 to 200 basis points",
    security: "No security impact. Fee reduction only affects revenue.",
    forumLink: "https://forum.fabstir.com/proposals/reduce-platform-fee",
    changes: [{
        contract: PAYMENT_ESCROW_ADDRESS,
        signature: "setPlatformFee(uint256)",
        params: [200] // 2%
    }]
});
```

### Complex Proposal Example
```javascript
// Multi-action proposal for protocol upgrade
async function createProtocolUpgrade() {
    const proposal = {
        title: "Protocol Upgrade v2.0",
        summary: "Major upgrade including new models, reduced fees, and improved rewards",
        motivation: "Enhance competitiveness and node operator satisfaction",
        specification: `
1. Add support for Claude-3 and GPT-5 models
2. Reduce platform fee from 2.5% to 2%
3. Increase node rewards by 20%
4. Implement progressive staking tiers
        `,
        changes: [
            {
                contract: NODE_REGISTRY_ADDRESS,
                signature: "addSupportedModel(string,uint256)",
                params: ["claude-3", ethers.parseEther("0.02")]
            },
            {
                contract: NODE_REGISTRY_ADDRESS,
                signature: "addSupportedModel(string,uint256)",
                params: ["gpt-5", ethers.parseEther("0.05")]
            },
            {
                contract: PAYMENT_ESCROW_ADDRESS,
                signature: "setPlatformFee(uint256)",
                params: [200]
            },
            {
                contract: REPUTATION_SYSTEM_ADDRESS,
                signature: "setRewardMultiplier(uint256)",
                params: [120] // 20% increase
            },
            {
                contract: NODE_REGISTRY_ADDRESS,
                signature: "setStakingTiers(uint256[],uint256[])",
                params: [
                    [ethers.parseEther("50"), ethers.parseEther("100"), ethers.parseEther("500")],
                    [100, 110, 125] // Reward multipliers
                ]
            }
        ]
    };
    
    return await creator.createProposal(proposal);
}
```

## Proposal Lifecycle

### Monitor Your Proposals
```javascript
class ProposalManager {
    async getMyProposals(address) {
        const proposals = await sdk.governance.getProposalsByProposer(address);
        
        const summary = {
            total: proposals.length,
            active: 0,
            passed: 0,
            failed: 0,
            executed: 0
        };
        
        for (const proposal of proposals) {
            console.log(`\nProposal #${proposal.id}: ${proposal.title}`);
            console.log(`State: ${proposal.state}`);
            console.log(`Votes: ${proposal.forVotes} FOR, ${proposal.againstVotes} AGAINST`);
            
            summary[proposal.state.toLowerCase()]++;
            
            if (proposal.state === 'Succeeded') {
                console.log('Ready for execution!');
            }
        }
        
        return { proposals, summary };
    }
    
    async executeProposal(proposalId) {
        const proposal = await sdk.governance.getProposal(proposalId);
        
        // Check if can execute
        if (proposal.state !== 'Succeeded') {
            throw new Error(`Proposal not in executable state: ${proposal.state}`);
        }
        
        // Check timelock
        const timelockDelay = await sdk.governance.getTimelockDelay();
        const canExecuteAt = proposal.endBlock + timelockDelay;
        const currentBlock = await sdk.provider.getBlockNumber();
        
        if (currentBlock < canExecuteAt) {
            const blocksToWait = canExecuteAt - currentBlock;
            throw new Error(`Timelock active. Wait ${blocksToWait} blocks (~${blocksToWait * 12}s)`);
        }
        
        // Execute
        console.log('Executing proposal...');
        const tx = await sdk.governance.execute(proposalId);
        const receipt = await tx.wait();
        
        console.log('Proposal executed successfully!');
        console.log('Gas used:', receipt.gasUsed.toString());
        
        return receipt;
    }
}
```

### Cancel Proposal (if needed)
```javascript
async function cancelProposal(proposalId) {
    // Only proposer can cancel before voting starts
    const proposal = await sdk.governance.getProposal(proposalId);
    
    if (proposal.proposer !== signer.address) {
        throw new Error("Only proposer can cancel");
    }
    
    if (proposal.state !== 'Pending') {
        throw new Error("Can only cancel pending proposals");
    }
    
    const tx = await sdk.governance.cancel(proposalId);
    await tx.wait();
    
    console.log(`Proposal ${proposalId} cancelled`);
}
```

## Advanced Governance

### Delegation Strategies
```javascript
class DelegationStrategy {
    async optimizeDelegation(myTokens) {
        // Get top delegates
        const delegates = await sdk.governance.getTopDelegates({
            limit: 20,
            minVotingPower: 10000
        });
        
        // Score delegates
        const scored = await Promise.all(
            delegates.map(async (delegate) => {
                const score = await this.scoreDelegate(delegate);
                return { ...delegate, score };
            })
        );
        
        // Sort by score
        scored.sort((a, b) => b.score - a.score);
        
        // Recommend delegation split
        const recommendations = this.calculateOptimalSplit(myTokens, scored);
        
        return recommendations;
    }
    
    async scoreDelegate(delegate) {
        const metrics = {
            participationRate: delegate.participationRate * 0.3,
            proposalQuality: await this.getProposalQuality(delegate.address) * 0.3,
            alignmentScore: await this.getAlignmentScore(delegate.address) * 0.2,
            consistency: delegate.consistency * 0.2
        };
        
        return Object.values(metrics).reduce((sum, val) => sum + val, 0);
    }
    
    calculateOptimalSplit(tokens, delegates) {
        // Diversify delegation for risk management
        const recommendations = [];
        
        if (tokens < 10000) {
            // Small holder: delegate to top delegate
            recommendations.push({
                delegate: delegates[0].address,
                amount: tokens,
                reason: "Single delegation for small holdings"
            });
        } else {
            // Split among top 3-5 delegates
            const topDelegates = delegates.slice(0, 5);
            const baseAmount = Math.floor(tokens / topDelegates.length);
            
            topDelegates.forEach((delegate, index) => {
                recommendations.push({
                    delegate: delegate.address,
                    amount: baseAmount,
                    reason: `Diversified delegation - Rank #${index + 1}`
                });
            });
        }
        
        return recommendations;
    }
}
```

### Governance Analytics
```javascript
class GovernanceAnalytics {
    async getGovernanceHealth() {
        const metrics = {
            participation: await this.getParticipationMetrics(),
            decentralization: await this.getDecentralizationScore(),
            proposalActivity: await this.getProposalMetrics(),
            executionSuccess: await this.getExecutionMetrics()
        };
        
        const healthScore = this.calculateHealthScore(metrics);
        
        return {
            score: healthScore,
            metrics,
            recommendations: this.getRecommendations(metrics)
        };
    }
    
    async getParticipationMetrics() {
        const recentProposals = await sdk.governance.getProposals({
            status: 'executed',
            limit: 10
        });
        
        const avgTurnout = recentProposals.reduce((sum, p) => {
            const totalVotes = p.forVotes + p.againstVotes + p.abstainVotes;
            const turnout = totalVotes / TOTAL_SUPPLY;
            return sum + turnout;
        }, 0) / recentProposals.length;
        
        return {
            averageTurnout: avgTurnout * 100,
            trend: await this.getTurnoutTrend(),
            uniqueVoters: await this.getUniqueVoters()
        };
    }
    
    async getDecentralizationScore() {
        const delegates = await sdk.governance.getTopDelegates({ limit: 100 });
        
        // Calculate Gini coefficient
        const totalPower = delegates.reduce((sum, d) => sum + d.votingPower, 0);
        const gini = this.calculateGini(delegates.map(d => d.votingPower));
        
        // Check concentration
        const top10Power = delegates.slice(0, 10)
            .reduce((sum, d) => sum + d.votingPower, 0);
        const top10Concentration = top10Power / totalPower;
        
        return {
            giniCoefficient: gini,
            top10Concentration: top10Concentration * 100,
            nakamotoCoefficient: this.getNakamotoCoefficient(delegates),
            score: (1 - gini) * (1 - top10Concentration)
        };
    }
}
```

### Proposal Templates
```javascript
const PROPOSAL_TEMPLATES = {
    parameterChange: {
        title: "Update {PARAMETER} to {NEW_VALUE}",
        template: `
## Summary
This proposal updates {PARAMETER} from {OLD_VALUE} to {NEW_VALUE}.

## Motivation
{MOTIVATION}

## Impact Analysis
- **Affected Users**: {AFFECTED_USERS}
- **Economic Impact**: {ECONOMIC_IMPACT}
- **Risk Assessment**: {RISK_ASSESSMENT}

## Implementation
{IMPLEMENTATION_DETAILS}
        `
    },
    
    featureAddition: {
        title: "Add {FEATURE_NAME} Feature",
        template: `
## Summary
This proposal adds {FEATURE_NAME} to the protocol.

## Motivation
{MOTIVATION}

## Technical Specification
{TECHNICAL_SPEC}

## Security Considerations
{SECURITY_REVIEW}

## Timeline
- Development: {DEV_TIME}
- Testing: {TEST_TIME}
- Deployment: {DEPLOY_TIME}
        `
    },
    
    treasuryAllocation: {
        title: "Allocate {AMOUNT} from Treasury for {PURPOSE}",
        template: `
## Summary
Allocate {AMOUNT} FABSTIR tokens from the treasury for {PURPOSE}.

## Budget Breakdown
{BUDGET_DETAILS}

## Expected Outcomes
{EXPECTED_OUTCOMES}

## Success Metrics
{SUCCESS_METRICS}

## Accountability
{ACCOUNTABILITY_MEASURES}
        `
    }
};

// Use template
function createProposalFromTemplate(type, values) {
    const template = PROPOSAL_TEMPLATES[type];
    let description = template.template;
    
    // Replace placeholders
    Object.entries(values).forEach(([key, value]) => {
        description = description.replace(new RegExp(`{${key}}`, 'g'), value);
    });
    
    return {
        title: template.title.replace(/{(\w+)}/g, (match, key) => values[key]),
        description
    };
}
```

## Best Practices

### 1. Research Before Voting
```javascript
async function researchProposal(proposalId) {
    // Get proposal details
    const proposal = await sdk.governance.getProposal(proposalId);
    
    // Check proposer history
    const proposerHistory = await sdk.governance.getProposerHistory(proposal.proposer);
    console.log(`Proposer success rate: ${proposerHistory.successRate}%`);
    
    // Get community sentiment
    const discussion = await fetchForumDiscussion(proposal.discussionLink);
    console.log(`Community sentiment: ${discussion.sentiment}`);
    
    // Analyze code changes
    if (proposal.actions.some(a => a.signature.includes('upgrade'))) {
        const audit = await checkSecurityAudit(proposal.id);
        console.log(`Security audit: ${audit.status}`);
    }
    
    // Check similar past proposals
    const similar = await findSimilarProposals(proposal);
    console.log(`Similar proposals: ${similar.length}`);
    
    return {
        proposerReputation: proposerHistory.reputation,
        communitySupport: discussion.supportRatio,
        technicalRisk: calculateTechnicalRisk(proposal),
        recommendation: generateRecommendation(proposal)
    };
}
```

### 2. Effective Proposal Writing
```javascript
class ProposalWriter {
    writeEffectiveProposal(idea) {
        return {
            // Clear, specific title
            title: this.craftTitle(idea),
            
            // Structured description
            description: `
## 🎯 Objective
${idea.objective}

## 📊 Current State
${idea.currentState}

## 🚀 Proposed Changes
${this.formatChanges(idea.changes)}

## 💡 Benefits
${this.listBenefits(idea.benefits)}

## ⚠️ Risks & Mitigations
${this.formatRisks(idea.risks)}

## 📈 Success Metrics
${this.defineMetrics(idea.metrics)}

## 🗓️ Timeline
${this.createTimeline(idea.timeline)}

## 💬 Community Discussion
Forum Thread: ${idea.forumLink}
Discord Channel: ${idea.discordChannel}
            `,
            
            // Precise actions
            actions: this.validateActions(idea.actions)
        };
    }
    
    craftTitle(idea) {
        // Keep it under 100 chars, clear and actionable
        const action = idea.type === 'add' ? 'Add' : 
                      idea.type === 'update' ? 'Update' : 
                      idea.type === 'remove' ? 'Remove' : 'Implement';
        
        return `${action} ${idea.feature} - ${idea.benefit}`;
    }
}
```

### 3. Building Consensus
```javascript
class ConsensusBuilder {
    async buildSupport(proposalDraft) {
        // 1. Gather feedback early
        const feedback = await this.gatherFeedback(proposalDraft);
        
        // 2. Address concerns
        const revised = await this.reviseDraft(proposalDraft, feedback);
        
        // 3. Find co-sponsors
        const sponsors = await this.findSponsors(revised);
        
        // 4. Create discussion thread
        const thread = await this.createDiscussion(revised);
        
        // 5. Schedule community calls
        const calls = await this.scheduleCalls(revised);
        
        return {
            finalDraft: revised,
            supporters: sponsors,
            discussionUrl: thread.url,
            communityCallSchedule: calls
        };
    }
    
    async gatherFeedback(draft) {
        // Post draft in governance forum
        const post = await this.forum.createDraft(draft);
        
        // Collect feedback for 1 week
        await this.waitForFeedback(7 * 24 * 60 * 60 * 1000);
        
        // Analyze feedback
        const feedback = await this.forum.getFeedback(post.id);
        
        return {
            supporters: feedback.filter(f => f.sentiment === 'positive'),
            concerns: feedback.filter(f => f.sentiment === 'negative'),
            suggestions: feedback.filter(f => f.type === 'suggestion')
        };
    }
}
```

## Common Patterns

### Emergency Proposals
```javascript
async function createEmergencyProposal(issue) {
    // For critical security issues
    if (issue.severity !== 'CRITICAL') {
        throw new Error('Emergency proposals only for critical issues');
    }
    
    const proposal = {
        title: `[EMERGENCY] ${issue.title}`,
        description: `
## ⚠️ CRITICAL SECURITY ISSUE

**Severity**: CRITICAL
**Affected Components**: ${issue.components.join(', ')}
**Immediate Action Required**: YES

## Issue Description
${issue.description}

## Proposed Fix
${issue.fix}

## Timeline
This proposal requests expedited voting due to critical security implications.
        `,
        actions: issue.actions,
        expedited: true
    };
    
    // Create with higher gas for priority
    return await sdk.governance.createProposal(proposal, {
        maxPriorityFeePerGas: ethers.parseUnits("50", "gwei")
    });
}
```

### Progressive Rollouts
```javascript
async function createProgressiveRollout(feature) {
    const phases = [
        {
            title: `Phase 1: Enable ${feature} for 10% of nodes`,
            delay: 0,
            actions: [{
                target: FEATURE_FLAGS_ADDRESS,
                signature: "setRolloutPercentage(string,uint256)",
                params: [feature, 10]
            }]
        },
        {
            title: `Phase 2: Expand to 50% if metrics are positive`,
            delay: 7 * 24 * 60 * 60, // 1 week
            condition: "metrics.successRate > 0.95",
            actions: [{
                target: FEATURE_FLAGS_ADDRESS,
                signature: "setRolloutPercentage(string,uint256)",
                params: [feature, 50]
            }]
        },
        {
            title: `Phase 3: Full rollout`,
            delay: 14 * 24 * 60 * 60, // 2 weeks
            condition: "metrics.successRate > 0.98",
            actions: [{
                target: FEATURE_FLAGS_ADDRESS,
                signature: "setRolloutPercentage(string,uint256)",
                params: [feature, 100]
            }]
        }
    ];
    
    return await createPhaseProposals(phases);
}
```

## Governance Tools

### Delegation Dashboard
```javascript
class DelegationDashboard {
    async render() {
        const myDelegation = await this.getMyDelegation();
        const delegatePerformance = await this.analyzeDelegatePerformance();
        
        console.log('\n=== Your Delegation Status ===');
        console.log(`Current Delegate: ${myDelegation.delegate}`);
        console.log(`Delegated Power: ${myDelegation.amount} FABSTIR`);
        console.log(`Active Since: ${myDelegation.since}`);
        
        console.log('\n=== Delegate Performance ===');
        console.log(`Participation Rate: ${delegatePerformance.participationRate}%`);
        console.log(`Alignment Score: ${delegatePerformance.alignmentScore}%`);
        console.log(`Recent Votes: ${delegatePerformance.recentVotes.length}`);
        
        if (delegatePerformance.recommendation) {
            console.log(`\n⚠️ Recommendation: ${delegatePerformance.recommendation}`);
        }
    }
}
```

### Proposal Simulator
```javascript
class ProposalSimulator {
    async simulate(proposal) {
        console.log('Simulating proposal execution...');
        
        // Fork current state
        const fork = await this.createStateFork();
        
        // Execute actions in simulation
        const results = [];
        for (const action of proposal.actions) {
            const result = await this.simulateAction(fork, action);
            results.push(result);
        }
        
        // Analyze state changes
        const analysis = await this.analyzeStateChanges(fork, results);
        
        return {
            success: results.every(r => r.success),
            gasUsed: results.reduce((sum, r) => sum + r.gasUsed, 0),
            stateChanges: analysis.changes,
            warnings: analysis.warnings,
            recommendation: this.generateRecommendation(analysis)
        };
    }
}
```

## Next Steps

1. **[Monitoring Setup](monitoring-setup.md)** - Monitor governance events
2. **[Migration Guide](migration-guide.md)** - Migrate from v1 governance
3. **[Contract Integration](../developers/contract-integration.md)** - Build governance tools

## Resources

- [Governance Forum](https://forum.fabstir.com)
- [Delegate Registry](https://delegates.fabstir.com)
- [Proposal Archive](https://proposals.fabstir.com)
- [Governance Analytics](https://stats.fabstir.com/governance)

---

Questions? Join our [Governance Discord](https://discord.gg/fabstir-gov) →