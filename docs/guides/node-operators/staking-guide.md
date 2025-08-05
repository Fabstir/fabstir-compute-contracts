# Node Staking Guide

This guide covers everything about staking for Fabstir compute nodes, including requirements, strategies, and risk management.

## Prerequisites

- Base wallet with sufficient ETH
- Understanding of [Running a Node](running-a-node.md)
- Hardware wallet (recommended for mainnet)

## Staking Overview

### Requirements
- **Minimum Stake**: 100 ETH (mainnet) / 0.1 ETH (testnet)
- **Lock Period**: None (but active jobs prevent withdrawal)
- **Slashing Risk**: Yes (for malicious behavior)
- **Rewards**: Earned through job completion, not staking

### Economic Model
```
Stake (100 ETH) → Node Registration → Claim Jobs → Complete Jobs → Earn Fees
                                           ↓
                                    Risk: Slashing
```

## Step 1: Prepare Your Stake

### Calculate Required ETH
```javascript
const calculateStakeRequirement = () => {
    const minimumStake = 100; // ETH
    const gasBuffer = 0.5;    // ETH for operations
    const emergencyFund = 1;  // ETH for unexpected costs
    
    const total = minimumStake + gasBuffer + emergencyFund;
    
    console.log("Stake Breakdown:");
    console.log(`Minimum Stake: ${minimumStake} ETH`);
    console.log(`Gas Buffer: ${gasBuffer} ETH`);
    console.log(`Emergency Fund: ${emergencyFund} ETH`);
    console.log(`Total Required: ${total} ETH`);
    
    return total;
};
```

### Acquire ETH on Base
Options for getting ETH on Base:

1. **Bridge from Ethereum**
```bash
# Using Base Bridge
# Visit: https://bridge.base.org
# Connect wallet → Select amount → Bridge ETH
```

2. **Direct Purchase**
- Buy on Coinbase → Withdraw to Base
- Use other CEXs supporting Base

3. **Cross-chain Swap**
```javascript
// Example using a DEX aggregator
const swapToBase = async () => {
    // Use services like:
    // - Stargate Finance
    // - Across Protocol
    // - Synapse Protocol
};
```

### Security Setup
```javascript
// Best practice: Use a dedicated staking wallet
const setupStakingWallet = () => {
    // 1. Create new wallet for node operations
    const nodeWallet = ethers.Wallet.createRandom();
    
    // 2. Use hardware wallet for stake custody
    // Connect Ledger/Trezor for mainnet
    
    // 3. Set up multisig for team operations
    // Consider Gnosis Safe on Base
};
```

## Step 2: Check Staking Requirements

### Verify Current Stake Amount
```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function checkStakeRequirements() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    
    const nodeRegistryABI = [
        "function requiredStake() view returns (uint256)",
        "function MIN_STAKE() view returns (uint256)"
    ];
    
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        provider
    );
    
    try {
        // Try both function names (contract might use either)
        const stake = await nodeRegistry.requiredStake()
            .catch(() => nodeRegistry.MIN_STAKE());
        
        console.log("Current stake requirement:", ethers.formatEther(stake), "ETH");
        
        // Check your balance
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        const balance = await provider.getBalance(wallet.address);
        
        console.log("Your balance:", ethers.formatEther(balance), "ETH");
        console.log("Can stake:", balance >= stake ? "✓ Yes" : "✗ No");
        
        if (balance < stake) {
            const needed = stake - balance;
            console.log("Need", ethers.formatEther(needed), "more ETH");
        }
        
    } catch (error) {
        console.error("Error checking requirements:", error);
    }
}

checkStakeRequirements();
```

## Step 3: Stake Your ETH

### Simple Registration
```javascript
async function stakeAndRegister() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    const nodeRegistryABI = [
        "function registerNode(string _peerId, string[] _models, string _region) payable",
        "event NodeRegistered(address indexed node, string metadata)"
    ];
    
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        wallet
    );
    
    // Registration parameters
    const peerId = "QmYourIPFSPeerIdHere";
    const models = ["gpt-4", "llama-2-70b"];
    const region = "us-east-1";
    const stakeAmount = ethers.parseEther("100");
    
    console.log("Registering node with stake...");
    console.log("Amount:", ethers.formatEther(stakeAmount), "ETH");
    
    // Estimate gas
    const gasEstimate = await nodeRegistry.registerNode.estimateGas(
        peerId,
        models,
        region,
        { value: stakeAmount }
    );
    
    console.log("Estimated gas:", gasEstimate.toString());
    
    // Send transaction
    const tx = await nodeRegistry.registerNode(
        peerId,
        models,
        region,
        { 
            value: stakeAmount,
            gasLimit: gasEstimate * 110n / 100n // 10% buffer
        }
    );
    
    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();
    console.log("Node registered! Gas used:", receipt.gasUsed.toString());
}
```

### Advanced Registration with Checks
```javascript
async function safeStakeAndRegister() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    // Pre-flight checks
    const checks = await performPreflightChecks(wallet.address);
    if (!checks.passed) {
        console.error("Pre-flight checks failed:", checks.errors);
        return;
    }
    
    // Use flashloan for registration if needed
    if (checks.needsFlashLoan) {
        await registerWithFlashLoan(wallet);
        return;
    }
    
    // Normal registration
    await stakeAndRegister();
}

async function performPreflightChecks(address) {
    const checks = {
        passed: true,
        errors: [],
        needsFlashLoan: false
    };
    
    // Check 1: Not already registered
    const node = await nodeRegistry.getNode(address);
    if (node.operator !== ethers.ZeroAddress) {
        checks.passed = false;
        checks.errors.push("Already registered");
    }
    
    // Check 2: Sufficient balance
    const balance = await provider.getBalance(address);
    const required = ethers.parseEther("100.1"); // Stake + gas
    
    if (balance < required) {
        checks.passed = false;
        checks.errors.push("Insufficient balance");
        
        // Check if close enough for flash loan
        if (balance > ethers.parseEther("99")) {
            checks.needsFlashLoan = true;
        }
    }
    
    // Check 3: Gas price reasonable
    const feeData = await provider.getFeeData();
    const gasPrice = feeData.gasPrice;
    const maxGasPrice = ethers.parseUnits("50", "gwei");
    
    if (gasPrice > maxGasPrice) {
        checks.passed = false;
        checks.errors.push("Gas price too high");
    }
    
    return checks;
}
```

## Step 4: Manage Your Stake

### Monitor Stake Status
```javascript
async function monitorStake() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    
    const nodeRegistryABI = [
        "function getNode(address) view returns (tuple(address operator, string peerId, uint256 stake, bool active, string[] models, string region))",
        "function getNodeStake(address) view returns (uint256)"
    ];
    
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        provider
    );
    
    const address = process.env.NODE_ADDRESS;
    
    // Get current stake
    const stake = await nodeRegistry.getNodeStake(address);
    console.log("Current stake:", ethers.formatEther(stake), "ETH");
    
    // Get full node info
    const node = await nodeRegistry.getNode(address);
    console.log("Node status:", {
        active: node.active,
        models: node.models,
        region: node.region
    });
    
    // Calculate stake value
    const ethPrice = await getETHPrice(); // Implement price fetching
    const stakeValue = parseFloat(ethers.formatEther(stake)) * ethPrice;
    console.log("Stake value: $", stakeValue.toFixed(2));
}
```

### Add Additional Stake
```javascript
async function addStake(additionalETH) {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    
    const nodeRegistryABI = [
        "function restoreStake() payable",
        "event StakeRestored(address indexed node, uint256 amount)"
    ];
    
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        wallet
    );
    
    const amount = ethers.parseEther(additionalETH.toString());
    
    console.log("Adding stake:", additionalETH, "ETH");
    
    const tx = await nodeRegistry.restoreStake({ value: amount });
    console.log("Transaction:", tx.hash);
    
    const receipt = await tx.wait();
    console.log("Stake added successfully!");
}
```

## Step 5: Risk Management

### Slashing Protection
```javascript
// Monitor for potential slashing events
async function setupSlashingMonitor() {
    const nodeRegistryABI = [
        "event NodeSlashed(address indexed node, uint256 amount, string reason)"
    ];
    
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        provider
    );
    
    // Listen for slashing events
    nodeRegistry.on("NodeSlashed", (node, amount, reason) => {
        if (node === process.env.NODE_ADDRESS) {
            console.error("⚠️ YOUR NODE WAS SLASHED!");
            console.error("Amount:", ethers.formatEther(amount), "ETH");
            console.error("Reason:", reason);
            
            // Send alerts
            sendDiscordAlert(`Node slashed: ${reason}`);
            sendEmailAlert(`Slashing event: ${amount} ETH`);
            
            // Check if need to restore stake
            checkAndRestoreStake();
        }
    });
}

// Automatic stake restoration
async function checkAndRestoreStake() {
    const currentStake = await nodeRegistry.getNodeStake(address);
    const requiredStake = await nodeRegistry.requiredStake();
    
    if (currentStake < requiredStake) {
        const needed = requiredStake - currentStake;
        console.log("Need to restore:", ethers.formatEther(needed), "ETH");
        
        // Check reserve wallet
        const reserveBalance = await provider.getBalance(RESERVE_WALLET);
        if (reserveBalance >= needed) {
            await addStake(ethers.formatEther(needed));
        } else {
            console.error("Insufficient reserve funds!");
        }
    }
}
```

### Stake Insurance Strategies

#### 1. Reserve Fund
```javascript
const RESERVE_RATIO = 0.1; // Keep 10% in reserve

function calculateReserve(stakeAmount) {
    return stakeAmount * RESERVE_RATIO;
}
```

#### 2. Stake Pooling
```javascript
// Join a staking pool to share risks
const joinStakePool = async (poolAddress) => {
    // Pools can provide:
    // - Shared slashing risk
    // - Lower individual stake requirements
    // - Professional node operation
};
```

#### 3. Hedging Strategies
```javascript
// Use DeFi to hedge stake value
const hedgeStakeValue = async () => {
    // Options:
    // 1. Buy ETH put options
    // 2. Stake stablecoins as collateral
    // 3. Use perpetual futures for hedging
};
```

## Staking ROI Calculator

```javascript
class StakingCalculator {
    constructor(stakeAmount, avgJobsPerDay, avgPaymentPerJob) {
        this.stakeAmount = stakeAmount;
        this.avgJobsPerDay = avgJobsPerDay;
        this.avgPaymentPerJob = avgPaymentPerJob;
        this.platformFee = 0.025; // 2.5%
    }
    
    calculateDailyEarnings() {
        const grossEarnings = this.avgJobsPerDay * this.avgPaymentPerJob;
        const netEarnings = grossEarnings * (1 - this.platformFee);
        return netEarnings;
    }
    
    calculateROI(days) {
        const totalEarnings = this.calculateDailyEarnings() * days;
        const roi = (totalEarnings / this.stakeAmount) * 100;
        return {
            earnings: totalEarnings,
            roi: roi.toFixed(2) + '%',
            breakeven: this.stakeAmount / this.calculateDailyEarnings()
        };
    }
    
    projectReturns() {
        console.log("Staking Projections:");
        console.log("Stake:", this.stakeAmount, "ETH");
        console.log("Daily earnings:", this.calculateDailyEarnings().toFixed(4), "ETH");
        
        const periods = [30, 90, 180, 365];
        periods.forEach(days => {
            const projection = this.calculateROI(days);
            console.log(`\n${days} days:`);
            console.log("- Earnings:", projection.earnings.toFixed(4), "ETH");
            console.log("- ROI:", projection.roi);
        });
        
        console.log("\nBreakeven:", this.calculateROI(0).breakeven.toFixed(0), "days");
    }
}

// Example usage
const calculator = new StakingCalculator(
    100,    // 100 ETH stake
    50,     // 50 jobs per day
    0.01    // 0.01 ETH average per job
);
calculator.projectReturns();
```

## Common Issues & Solutions

### Issue: Transaction Fails with "Insufficient stake"
```javascript
// Solution: Check exact requirement
const exactStake = await nodeRegistry.MIN_STAKE();
console.log("Exact stake needed:", exactStake.toString());

// Add small buffer for gas
const stakeWithBuffer = exactStake + ethers.parseEther("0.001");
```

### Issue: Can't Withdraw Stake
```javascript
// Check for active jobs
async function checkActiveJobs(nodeAddress) {
    const jobMarketplaceABI = ["function getActiveJobIds() view returns (uint256[])"];
    const jobMarketplace = new ethers.Contract(JOB_MARKETPLACE_ADDRESS, jobMarketplaceABI, provider);
    
    const activeJobs = await jobMarketplace.getActiveJobIds();
    // Check if any assigned to your node
    
    if (hasActiveJobs) {
        console.log("Cannot withdraw: Active jobs in progress");
    }
}
```

### Issue: Slashing Due to Downtime
```javascript
// Prevention: Implement redundancy
const setupRedundancy = () => {
    // 1. Use monitoring with auto-restart
    // 2. Have backup nodes ready
    // 3. Use cloud providers with SLA
    // 4. Implement graceful shutdown
};
```

## Best Practices

### 1. Stake Management
- Keep 10-20% reserve for emergencies
- Monitor stake value and health
- Set up automated top-ups
- Use hardware wallets for large stakes

### 2. Risk Mitigation
- Understand slashing conditions
- Maintain high uptime (>99.9%)
- Complete jobs reliably
- Monitor reputation score

### 3. Tax Considerations
```javascript
// Track all staking events for tax
const trackStakingEvents = () => {
    // Log:
    // - Initial stake date and amount
    // - Additional stakes
    // - Slashing events
    // - Withdrawal dates
    // - ETH price at each event
};
```

## Next Steps

1. **[Claiming Jobs](claiming-jobs.md)** - Maximize earnings
2. **[Node Monitoring](../advanced/monitoring-setup.md)** - Protect your stake
3. **[Governance](../advanced/governance-participation.md)** - Influence staking rules

## Resources

- [Ethereum Staking Calculator](https://stakingcalculator.com)
- [Base Network Statistics](https://basescan.org/stat/supply)
- [DeFi Hedging Strategies](https://defillama.com)
- [Tax Guide for Stakers](https://tokentax.co)

---

Questions about staking? Join our [Discord](https://discord.gg/fabstir) →