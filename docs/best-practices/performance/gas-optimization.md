# Gas Optimization Best Practices

This guide covers strategies to minimize gas costs when interacting with Fabstir smart contracts.

## Why It Matters

Gas optimization directly impacts:
- **Operating costs** - Every transaction costs real money
- **User experience** - High gas fees deter users
- **Scalability** - Efficient contracts handle more volume
- **Competitive advantage** - Lower costs attract more users
- **Profitability** - Reduced expenses improve margins

## Gas Cost Fundamentals

### Understanding Gas Consumption
```solidity
// Gas costs for common operations (approximate)
Operation               Gas Cost
---------              ---------
SSTORE (new slot)      20,000
SSTORE (update)        5,000
SLOAD                  2,100
CALL                   2,600 + called gas
CREATE                 32,000
SELFDESTRUCT          5,000 + refunds
LOG (per topic)        375
Memory expansion       3 per word + quadratic
```

### Gas Profiling Tools
```javascript
class GasProfiler {
    constructor(provider) {
        this.provider = provider;
        this.baselines = new Map();
    }
    
    async profileTransaction(tx) {
        // Get pre-execution state
        const beforeBalance = await this.provider.getBalance(tx.from);
        const gasPrice = tx.maxFeePerGas || await this.provider.getGasPrice();
        
        // Execute transaction
        const receipt = await tx.wait();
        
        // Calculate actual cost
        const afterBalance = await this.provider.getBalance(tx.from);
        const actualCost = beforeBalance - afterBalance - tx.value;
        
        return {
            gasUsed: receipt.gasUsed,
            gasPrice: gasPrice,
            actualCost: actualCost,
            efficiency: receipt.gasUsed / receipt.gasLimit,
            breakdown: await this.getGasBreakdown(receipt)
        };
    }
    
    async getGasBreakdown(receipt) {
        const trace = await this.provider.send('debug_traceTransaction', [
            receipt.transactionHash,
            { tracer: 'callTracer' }
        ]);
        
        return this.analyzeTrace(trace);
    }
    
    analyzeTrace(trace) {
        const breakdown = {
            computation: 0,
            storage: 0,
            memory: 0,
            calls: 0
        };
        
        // Analyze opcode costs
        for (const op of trace.structLogs) {
            if (op.op.startsWith('SSTORE')) breakdown.storage += op.gasCost;
            else if (op.op.startsWith('CALL')) breakdown.calls += op.gasCost;
            else if (op.op.startsWith('M')) breakdown.memory += op.gasCost;
            else breakdown.computation += op.gasCost;
        }
        
        return breakdown;
    }
}
```

## Smart Contract Optimization

### Storage Optimization
```solidity
// ❌ BAD: Inefficient storage layout
contract InefficientStorage {
    uint8 a;     // Slot 0 (1 byte used, 31 wasted)
    uint256 b;   // Slot 1
    uint8 c;     // Slot 2 (1 byte used, 31 wasted)
    uint256 d;   // Slot 3
    // Total: 4 storage slots
}

// ✅ GOOD: Packed storage
contract EfficientStorage {
    uint8 a;     // Slot 0, bytes 0
    uint8 c;     // Slot 0, bytes 1
    uint256 b;   // Slot 1
    uint256 d;   // Slot 2
    // Total: 3 storage slots (25% savings)
}

// ✅ BETTER: Using packed structs
contract OptimalStorage {
    struct PackedData {
        uint128 amount;    // 16 bytes
        uint64 timestamp;  // 8 bytes
        uint32 count;      // 4 bytes
        uint32 flags;      // 4 bytes
    } // Total: 32 bytes = 1 slot
    
    mapping(address => PackedData) public userData;
}
```

### Efficient Loops and Batching
```solidity
// ❌ BAD: Individual transactions
contract InefficientPayments {
    function payUser(address user, uint256 amount) external {
        require(balances[msg.sender] >= amount);
        balances[msg.sender] -= amount;
        balances[user] += amount;
        emit Payment(msg.sender, user, amount);
    }
}

// ✅ GOOD: Batch operations
contract EfficientPayments {
    function batchPay(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        uint256 totalAmount;
        uint256 length = recipients.length;
        
        // Single balance check
        for (uint256 i; i < length;) {
            totalAmount += amounts[i];
            unchecked { ++i; }
        }
        
        require(balances[msg.sender] >= totalAmount);
        balances[msg.sender] -= totalAmount;
        
        // Batch transfers
        for (uint256 i; i < length;) {
            balances[recipients[i]] += amounts[i];
            unchecked { ++i; }
        }
        
        emit BatchPayment(msg.sender, recipients, amounts);
    }
}
```

### Memory vs Storage
```solidity
// ❌ BAD: Excessive storage reads
contract InefficientReads {
    struct Job {
        address renter;
        uint256 payment;
        uint256 deadline;
        string modelId;
    }
    
    mapping(uint256 => Job) public jobs;
    
    function processJob(uint256 jobId) external {
        require(jobs[jobId].deadline > block.timestamp); // SLOAD
        require(jobs[jobId].payment > 0);                // SLOAD
        require(jobs[jobId].renter != address(0));       // SLOAD
        // Multiple expensive storage reads
    }
}

// ✅ GOOD: Cache in memory
contract EfficientReads {
    function processJob(uint256 jobId) external {
        Job memory job = jobs[jobId]; // Single SLOAD
        
        require(job.deadline > block.timestamp);
        require(job.payment > 0);
        require(job.renter != address(0));
        // All checks use memory
    }
}
```

## Transaction Optimization

### Optimal Gas Price Strategy
```javascript
class GasPriceOptimizer {
    constructor(provider) {
        this.provider = provider;
        this.history = [];
        this.predictions = new GasPricePredictor();
    }
    
    async getOptimalGasPrice(urgency = 'standard') {
        const block = await this.provider.getBlock('latest');
        const baseFee = block.baseFeePerGas;
        
        // Get recent gas prices
        const recentPrices = await this.getRecentGasPrices();
        
        // Calculate percentiles
        const percentiles = {
            slow: this.percentile(recentPrices, 25),
            standard: this.percentile(recentPrices, 50),
            fast: this.percentile(recentPrices, 75),
            urgent: this.percentile(recentPrices, 90)
        };
        
        // Add priority fee based on urgency
        const priorityFee = this.calculatePriorityFee(urgency, percentiles);
        
        return {
            maxFeePerGas: baseFee * 2n + priorityFee,
            maxPriorityFeePerGas: priorityFee,
            estimatedCost: this.estimateCost(baseFee, priorityFee)
        };
    }
    
    async shouldDelay(gasPrice, threshold) {
        // Check if we should wait for lower gas
        const prediction = await this.predictions.predict(60); // 60 min
        
        if (prediction.expectedPrice < gasPrice * 0.8) {
            return {
                shouldWait: true,
                expectedSavings: gasPrice - prediction.expectedPrice,
                waitTime: prediction.timeToTarget
            };
        }
        
        return { shouldWait: false };
    }
    
    calculatePriorityFee(urgency, percentiles) {
        const tips = {
            slow: ethers.parseUnits("1", "gwei"),
            standard: ethers.parseUnits("2", "gwei"),
            fast: ethers.parseUnits("3", "gwei"),
            urgent: ethers.parseUnits("5", "gwei")
        };
        
        return tips[urgency];
    }
}
```

### Transaction Batching
```javascript
class TransactionBatcher {
    constructor(signer, maxBatchSize = 100) {
        this.signer = signer;
        this.maxBatchSize = maxBatchSize;
        this.queue = [];
        this.processing = false;
    }
    
    async addTransaction(tx) {
        this.queue.push(tx);
        
        if (this.queue.length >= this.maxBatchSize) {
            await this.processBatch();
        }
    }
    
    async processBatch() {
        if (this.processing || this.queue.length === 0) return;
        
        this.processing = true;
        const batch = this.queue.splice(0, this.maxBatchSize);
        
        try {
            // Encode batch transaction
            const batchTx = await this.encodeBatch(batch);
            
            // Estimate gas for batch
            const gasEstimate = await this.estimateBatchGas(batchTx);
            
            // Compare with individual costs
            const individualCost = await this.calculateIndividualCost(batch);
            const batchCost = gasEstimate * await this.getGasPrice();
            
            console.log(`Batch savings: ${ethers.formatEther(
                individualCost - batchCost
            )} ETH (${Math.round((1 - batchCost/individualCost) * 100)}%)`);
            
            // Execute batch
            const tx = await this.signer.sendTransaction({
                ...batchTx,
                gasLimit: gasEstimate * 110n / 100n // 10% buffer
            });
            
            await tx.wait();
            
        } finally {
            this.processing = false;
        }
    }
    
    async encodeBatch(transactions) {
        // Use multicall pattern
        const multicall = new ethers.Contract(
            MULTICALL_ADDRESS,
            ['function aggregate(tuple(address target, bytes callData)[] calls)'],
            this.signer
        );
        
        const calls = transactions.map(tx => ({
            target: tx.to,
            callData: tx.data
        }));
        
        return await multicall.populateTransaction.aggregate(calls);
    }
}
```

### Calldata Optimization
```solidity
// ❌ BAD: Expensive calldata
contract InefficientCalldata {
    function updateJob(
        uint256 jobId,
        string memory newDescription,  // Dynamic size
        string memory newRequirements, // Dynamic size
        address newAssignee
    ) external {
        // Strings in calldata are expensive
    }
}

// ✅ GOOD: Optimized calldata
contract EfficientCalldata {
    function updateJob(
        uint256 jobId,
        bytes32 descriptionHash,  // Fixed size
        bytes32 requirementsHash, // Fixed size  
        address newAssignee
    ) external {
        // Fixed-size parameters are cheaper
    }
    
    // For complex data, use IPFS
    function updateJobWithIPFS(
        uint256 jobId,
        bytes32 ipfsHash  // Store detailed data off-chain
    ) external {
        jobs[jobId].dataHash = ipfsHash;
        emit JobUpdated(jobId, ipfsHash);
    }
}
```

## Client-Side Optimization

### Smart Gas Estimation
```javascript
class SmartGasEstimator {
    constructor(contract) {
        this.contract = contract;
        this.cache = new Map();
    }
    
    async estimateWithCache(method, params) {
        const key = this.getCacheKey(method, params);
        
        // Check cache
        const cached = this.cache.get(key);
        if (cached && cached.expiry > Date.now()) {
            return cached.estimate;
        }
        
        // Estimate gas
        const estimate = await this.estimateGas(method, params);
        
        // Cache result
        this.cache.set(key, {
            estimate,
            expiry: Date.now() + 300000 // 5 minutes
        });
        
        return estimate;
    }
    
    async estimateGas(method, params) {
        try {
            // Try static call first
            await this.contract.callStatic[method](...params);
            
            // If successful, estimate gas
            const estimate = await this.contract.estimateGas[method](...params);
            
            // Add dynamic buffer based on method
            const buffer = this.getMethodBuffer(method);
            
            return estimate * (100n + buffer) / 100n;
            
        } catch (error) {
            // If static call fails, estimate higher
            console.warn('Static call failed, using high estimate');
            return this.getFailsafeEstimate(method);
        }
    }
    
    getMethodBuffer(method) {
        const buffers = {
            'claim': 20n,          // 20% buffer for claims
            'register': 15n,       // 15% for registration
            'updateStatus': 10n,   // 10% for simple updates
            'batchProcess': 30n    // 30% for complex operations
        };
        
        return buffers[method] || 10n;
    }
}
```

### Simulation Before Execution
```javascript
class TransactionSimulator {
    constructor(provider) {
        this.provider = provider;
        this.forkCache = new Map();
    }
    
    async simulate(transaction) {
        // Create local fork
        const forkId = await this.createFork();
        
        try {
            // Simulate transaction
            const result = await this.provider.send('eth_call', [
                transaction,
                'latest',
                { 
                    [transaction.from]: {
                        balance: '0x' + (10n ** 18n).toString(16)
                    }
                }
            ]);
            
            // Analyze gas usage
            const trace = await this.provider.send('debug_traceCall', [
                transaction,
                'latest',
                { tracer: 'prestateTracer' }
            ]);
            
            return {
                success: true,
                result,
                gasUsed: trace.gas,
                stateChanges: trace.stateDiff
            };
            
        } catch (error) {
            return {
                success: false,
                error: error.message,
                revertReason: await this.getRevertReason(error)
            };
        } finally {
            await this.deleteFork(forkId);
        }
    }
    
    async getRevertReason(error) {
        if (error.data) {
            try {
                const reason = ethers.AbiCoder.defaultAbiCoder().decode(
                    ['string'],
                    ethers.dataSlice(error.data, 4)
                )[0];
                return reason;
            } catch {
                return 'Unknown revert reason';
            }
        }
        return error.message;
    }
}
```

## Gas Optimization Patterns

### Lazy Evaluation Pattern
```solidity
// ❌ BAD: Compute everything upfront
contract EagerComputation {
    function processJobs(uint256[] memory jobIds) external {
        for (uint i = 0; i < jobIds.length; i++) {
            Job memory job = jobs[jobIds[i]];
            uint256 reward = calculateReward(job);     // Always computed
            uint256 penalty = calculatePenalty(job);   // Always computed
            uint256 bonus = calculateBonus(job);       // Always computed
            
            if (job.status == Status.Completed) {
                balances[job.host] += reward + bonus;
            }
        }
    }
}

// ✅ GOOD: Compute only when needed
contract LazyComputation {
    function processJobs(uint256[] memory jobIds) external {
        for (uint i = 0; i < jobIds.length; i++) {
            Job memory job = jobs[jobIds[i]];
            
            if (job.status == Status.Completed) {
                uint256 reward = calculateReward(job);  // Only when needed
                uint256 bonus = calculateBonus(job);    // Only when needed
                balances[job.host] += reward + bonus;
            }
            // Penalty calculation skipped entirely
        }
    }
}
```

### Event-Based Storage Pattern
```solidity
// ❌ BAD: Store everything on-chain
contract ExpensiveStorage {
    struct JobResult {
        string output;
        uint256 processingTime;
        bytes metadata;
    }
    
    mapping(uint256 => JobResult) public results;
}

// ✅ GOOD: Store hashes, emit details
contract EfficientStorage {
    mapping(uint256 => bytes32) public resultHashes;
    
    event JobCompleted(
        uint256 indexed jobId,
        bytes32 indexed resultHash,
        string output,
        uint256 processingTime,
        bytes metadata
    );
    
    function completeJob(
        uint256 jobId,
        string calldata output,
        bytes calldata metadata
    ) external {
        bytes32 hash = keccak256(abi.encode(output, metadata));
        resultHashes[jobId] = hash;
        
        emit JobCompleted(jobId, hash, output, block.timestamp, metadata);
    }
}
```

### Proxy Pattern for Upgrades
```solidity
// Gas-efficient upgradeable pattern
contract GasEfficientProxy {
    // Single storage slot for implementation
    bytes32 private constant IMPLEMENTATION_SLOT = 
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    function _getImplementation() private view returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }
    
    fallback() external payable {
        address impl = _getImplementation();
        assembly {
            // Copy calldata
            calldatacopy(0, 0, calldatasize())
            
            // Delegatecall to implementation
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            
            // Copy return data
            returndatacopy(0, 0, returndatasize())
            
            // Return or revert
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
```

## Monitoring and Analysis

### Gas Usage Dashboard
```javascript
class GasMonitor {
    constructor() {
        this.metrics = new MetricsCollector();
        this.alerts = new AlertManager();
    }
    
    async monitorGasUsage() {
        // Track gas prices
        setInterval(async () => {
            const gasPrice = await this.getGasPrice();
            this.metrics.record('gas_price', gasPrice);
            
            // Alert on spikes
            if (gasPrice > this.getThreshold()) {
                await this.alerts.send({
                    type: 'gas_spike',
                    price: gasPrice,
                    threshold: this.getThreshold()
                });
            }
        }, 60000); // Every minute
    }
    
    async analyzeTransaction(txHash) {
        const receipt = await this.provider.getTransactionReceipt(txHash);
        const tx = await this.provider.getTransaction(txHash);
        
        const analysis = {
            gasUsed: receipt.gasUsed,
            gasPrice: tx.gasPrice,
            totalCost: receipt.gasUsed * tx.gasPrice,
            efficiency: receipt.gasUsed / tx.gasLimit,
            status: receipt.status,
            logs: receipt.logs.length
        };
        
        // Compare with baseline
        const baseline = await this.getBaseline(tx.to, tx.data);
        analysis.vsBaseline = {
            gasUsed: (analysis.gasUsed / baseline.gasUsed - 1) * 100,
            cost: (analysis.totalCost / baseline.cost - 1) * 100
        };
        
        return analysis;
    }
}
```

## Optimization Checklist

### Smart Contract Level
- [ ] Storage variables packed efficiently
- [ ] Using mappings over arrays where appropriate
- [ ] Avoiding unnecessary storage operations
- [ ] Short-circuiting conditions
- [ ] Using events instead of storage
- [ ] Implementing batch operations

### Transaction Level
- [ ] Batching multiple operations
- [ ] Optimal gas price selection
- [ ] Calldata optimization
- [ ] Using multicall patterns
- [ ] Avoiding duplicate checks
- [ ] Caching repeated calculations

### Client Level
- [ ] Simulating before sending
- [ ] Implementing retry logic
- [ ] Monitoring gas prices
- [ ] Using gas price oracles
- [ ] Queueing non-urgent transactions
- [ ] Implementing circuit breakers

## Common Anti-Patterns

### ❌ Gas Wasters
```javascript
// Unnecessary storage operations
for (let i = 0; i < items.length; i++) {
    contract.updateItem(i, items[i]); // Multiple transactions
}

// Not checking gas price
await contract.method({ gasPrice: ethers.parseUnits("200", "gwei") });

// Redundant operations
await contract.approve(spender, 0); // Reset
await contract.approve(spender, amount); // Set new

// Large calldata
await contract.storeData(JSON.stringify(largeObject));
```

### ✅ Gas Savers
```javascript
// Batch operations
await contract.updateItems(items); // Single transaction

// Dynamic gas pricing
const gasPrice = await getOptimalGasPrice();
await contract.method({ maxFeePerGas: gasPrice });

// Direct operations
await contract.approve(spender, amount); // Direct set

// Off-chain storage
const ipfsHash = await ipfs.add(largeObject);
await contract.storeHash(ipfsHash);
```

## Tools and Resources

### Gas Analysis Tools
- **Hardhat Gas Reporter**: Automated gas reporting
- **Tenderly**: Transaction simulation and gas profiling
- **ETH Gas Station**: Real-time gas price data
- **GasHawk**: Transaction timing optimization
- **Blocknative**: Gas price predictions

### Optimization Scripts
```bash
# Analyze contract gas usage
forge test --gas-report

# Profile specific function
forge test --match-test testFunction --gas-report

# Compare implementations
forge snapshot --diff

# Check storage layout
forge inspect Contract storage-layout
```

## Best Practices Summary

1. **Always simulate before executing**
2. **Batch operations whenever possible**
3. **Pack storage variables efficiently**
4. **Use events for data availability**
5. **Monitor gas prices continuously**
6. **Implement circuit breakers for gas spikes**
7. **Cache gas estimates appropriately**
8. **Profile and benchmark regularly**

## Next Steps

1. Review [Node Optimization](node-optimization.md) for infrastructure efficiency
2. Implement [Scalability Patterns](scalability-patterns.md)
3. Set up [Monitoring & Alerting](../operations/monitoring-alerting.md)
4. Study [Pricing Strategies](../economics/pricing-strategies.md)

## Additional Resources

- [EIP-1559 Gas Pricing](https://eips.ethereum.org/EIPS/eip-1559)
- [Ethereum Yellow Paper](https://ethereum.github.io/yellowpaper/paper.pdf)
- [Gas Optimization Techniques](https://github.com/iskdrews/awesome-solidity-gas-optimization)
- [OpenZeppelin Gas Station Network](https://docs.opengsn.org/)

---

Remember: **Every wei saved is a wei earned.** Continuous optimization and monitoring are key to maintaining cost-effective operations.