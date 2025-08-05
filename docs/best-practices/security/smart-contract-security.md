# Smart Contract Security Best Practices

This guide covers essential security practices for interacting with Fabstir smart contracts in production environments.

## Why It Matters

Smart contract vulnerabilities can lead to:
- **Irreversible fund loss** - Transactions cannot be reversed
- **System manipulation** - Exploits can drain rewards or corrupt state
- **Reputation damage** - Security breaches erode user trust
- **Regulatory issues** - Negligence can lead to legal liability

## Core Security Principles

### 1. Never Trust, Always Verify
```javascript
// ❌ BAD: Trusting external data
async function claimRewards(amount) {
    await contract.claim(amount);
}

// ✅ GOOD: Verify before acting
async function claimRewards() {
    const pendingRewards = await contract.getPendingRewards(address);
    const verified = await verifyRewardCalculation(pendingRewards);
    
    if (verified && pendingRewards > 0) {
        await contract.claim();
    }
}
```

### 2. Check Effects Before Interactions
```javascript
// ❌ BAD: Acting without checking state
async function registerNode(stake) {
    await contract.register(peerId, { value: stake });
}

// ✅ GOOD: Check conditions first
async function registerNode(stake) {
    // Check current state
    const isRegistered = await contract.isNodeRegistered(address);
    if (isRegistered) {
        throw new Error("Node already registered");
    }
    
    // Verify stake amount
    const minStake = await contract.getMinimumStake();
    if (stake < minStake) {
        throw new Error(`Stake must be at least ${minStake}`);
    }
    
    // Simulate transaction
    try {
        await contract.callStatic.register(peerId, { value: stake });
    } catch (error) {
        throw new Error(`Registration would fail: ${error.message}`);
    }
    
    // Execute with gas buffer
    const gasEstimate = await contract.estimateGas.register(peerId, { value: stake });
    await contract.register(peerId, { 
        value: stake,
        gasLimit: gasEstimate.mul(110).div(100) // 10% buffer
    });
}
```

## Transaction Security Patterns

### Safe Transaction Execution
```javascript
class SafeTransactionManager {
    constructor(signer, config = {}) {
        this.signer = signer;
        this.config = {
            maxGasPrice: ethers.parseUnits("100", "gwei"),
            timeout: 300000, // 5 minutes
            confirmations: 2,
            retries: 3,
            ...config
        };
    }
    
    async executeTransaction(contract, method, params, options = {}) {
        // 1. Pre-flight checks
        await this.preflightChecks(contract, method, params);
        
        // 2. Gas estimation with safety
        const gasLimit = await this.estimateGasSafely(contract, method, params);
        
        // 3. Nonce management
        const nonce = await this.getNonceSafely();
        
        // 4. Build transaction
        const tx = {
            gasLimit,
            nonce,
            maxFeePerGas: await this.getGasPrice(),
            maxPriorityFeePerGas: ethers.parseUnits("2", "gwei"),
            ...options
        };
        
        // 5. Execute with monitoring
        return await this.executeWithMonitoring(contract, method, params, tx);
    }
    
    async preflightChecks(contract, method, params) {
        // Check contract is deployed
        const code = await this.signer.provider.getCode(contract.address);
        if (code === "0x") {
            throw new Error("Contract not deployed");
        }
        
        // Simulate transaction
        try {
            await contract.callStatic[method](...params);
        } catch (error) {
            throw new Error(`Transaction would revert: ${error.message}`);
        }
        
        // Check gas price
        const gasPrice = await this.getGasPrice();
        if (gasPrice > this.config.maxGasPrice) {
            throw new Error(`Gas price too high: ${gasPrice}`);
        }
    }
    
    async estimateGasSafely(contract, method, params) {
        const estimate = await contract.estimateGas[method](...params);
        
        // Add buffer based on operation type
        const buffer = this.getGasBuffer(method);
        return estimate.mul(100 + buffer).div(100);
    }
    
    getGasBuffer(method) {
        const highComplexityMethods = ["batchProcess", "migrate", "upgrade"];
        const mediumComplexityMethods = ["claim", "register", "update"];
        
        if (highComplexityMethods.includes(method)) return 50; // 50% buffer
        if (mediumComplexityMethods.includes(method)) return 20; // 20% buffer
        return 10; // 10% default buffer
    }
}
```

### Reentrancy Protection
```javascript
class ReentrancyGuard {
    constructor() {
        this.locked = new Set();
    }
    
    async executeWithGuard(id, callback) {
        if (this.locked.has(id)) {
            throw new Error("Reentrancy detected");
        }
        
        this.locked.add(id);
        try {
            return await callback();
        } finally {
            this.locked.delete(id);
        }
    }
}

// Usage
const guard = new ReentrancyGuard();

async function claimAndReinvest(jobId) {
    return await guard.executeWithGuard(`claim-${jobId}`, async () => {
        // Claim rewards
        const tx1 = await contract.claimRewards(jobId);
        await tx1.wait();
        
        // Reinvest
        const rewards = await contract.getClaimedAmount(jobId);
        const tx2 = await contract.reinvest(rewards);
        await tx2.wait();
    });
}
```

## Input Validation

### Comprehensive Validation Framework
```javascript
class InputValidator {
    static validateAddress(address, label = "address") {
        if (!ethers.isAddress(address)) {
            throw new Error(`Invalid ${label}: ${address}`);
        }
        
        // Check for zero address
        if (address === ethers.ZeroAddress) {
            throw new Error(`${label} cannot be zero address`);
        }
        
        // Check checksum
        if (address !== ethers.getAddress(address)) {
            console.warn(`${label} has invalid checksum, using: ${ethers.getAddress(address)}`);
            return ethers.getAddress(address);
        }
        
        return address;
    }
    
    static validateAmount(amount, min = "0", max = null, label = "amount") {
        const value = ethers.parseEther(amount.toString());
        
        if (value < ethers.parseEther(min)) {
            throw new Error(`${label} must be at least ${min} ETH`);
        }
        
        if (max && value > ethers.parseEther(max)) {
            throw new Error(`${label} must not exceed ${max} ETH`);
        }
        
        return value;
    }
    
    static validateJobParameters(params) {
        const validated = {};
        
        // Model ID validation
        if (!params.modelId || !/^[a-zA-Z0-9-]+$/.test(params.modelId)) {
            throw new Error("Invalid model ID format");
        }
        validated.modelId = params.modelId;
        
        // Prompt validation
        if (!params.prompt || params.prompt.length > 10000) {
            throw new Error("Prompt must be 1-10000 characters");
        }
        validated.prompt = this.sanitizeString(params.prompt);
        
        // Payment validation
        validated.payment = this.validateAmount(params.payment, "0.001", "1000", "payment");
        
        // Deadline validation
        const deadline = params.deadline || Date.now() + 3600000; // 1 hour default
        if (deadline <= Date.now()) {
            throw new Error("Deadline must be in the future");
        }
        validated.deadline = deadline;
        
        return validated;
    }
    
    static sanitizeString(input) {
        // Remove null bytes
        let sanitized = input.replace(/\0/g, '');
        
        // Limit length
        if (sanitized.length > 10000) {
            sanitized = sanitized.substring(0, 10000);
        }
        
        // Basic XSS prevention (if used in web context)
        sanitized = sanitized.replace(/[<>]/g, '');
        
        return sanitized;
    }
}
```

## Access Control Patterns

### Role-Based Security
```javascript
class AccessController {
    constructor(contracts) {
        this.contracts = contracts;
        this.roleCache = new Map();
    }
    
    async hasRole(address, role) {
        const cacheKey = `${address}-${role}`;
        
        // Check cache
        if (this.roleCache.has(cacheKey)) {
            const cached = this.roleCache.get(cacheKey);
            if (cached.expiry > Date.now()) {
                return cached.hasRole;
            }
        }
        
        // Fetch from contract
        const hasRole = await this.contracts.accessControl.hasRole(role, address);
        
        // Cache for 5 minutes
        this.roleCache.set(cacheKey, {
            hasRole,
            expiry: Date.now() + 300000
        });
        
        return hasRole;
    }
    
    async requireRole(address, role, action) {
        const hasRole = await this.hasRole(address, role);
        if (!hasRole) {
            throw new Error(`Address ${address} lacks required role ${role} for ${action}`);
        }
    }
    
    async executeWithRole(role, action, callback) {
        const signer = await this.contracts.signer.getAddress();
        await this.requireRole(signer, role, action);
        
        console.log(`Executing ${action} with role ${role}`);
        return await callback();
    }
}

// Usage
const accessControl = new AccessController(contracts);

async function adminFunction() {
    return await accessControl.executeWithRole("ADMIN_ROLE", "updateFees", async () => {
        await contracts.marketplace.setFeePercentage(250); // 2.5%
    });
}
```

## Emergency Response Procedures

### Circuit Breaker Implementation
```javascript
class CircuitBreaker {
    constructor(threshold = 5, timeout = 60000) {
        this.failureCount = 0;
        this.threshold = threshold;
        this.timeout = timeout;
        this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
        this.nextAttempt = 0;
    }
    
    async execute(operation, fallback = null) {
        if (this.state === 'OPEN') {
            if (Date.now() < this.nextAttempt) {
                if (fallback) return fallback();
                throw new Error('Circuit breaker is OPEN');
            }
            this.state = 'HALF_OPEN';
        }
        
        try {
            const result = await operation();
            this.onSuccess();
            return result;
        } catch (error) {
            this.onFailure();
            if (fallback) return fallback();
            throw error;
        }
    }
    
    onSuccess() {
        this.failureCount = 0;
        this.state = 'CLOSED';
    }
    
    onFailure() {
        this.failureCount++;
        if (this.failureCount >= this.threshold) {
            this.state = 'OPEN';
            this.nextAttempt = Date.now() + this.timeout;
            console.error(`Circuit breaker opened! Will retry at ${new Date(this.nextAttempt)}`);
        }
    }
}

// Usage
const breaker = new CircuitBreaker();

async function robustContractCall() {
    return await breaker.execute(
        async () => {
            return await contract.riskyOperation();
        },
        () => {
            console.warn("Using fallback due to circuit breaker");
            return { success: false, reason: "Circuit breaker open" };
        }
    );
}
```

### Emergency Pause Mechanism
```javascript
class EmergencyManager {
    constructor(contracts, config) {
        this.contracts = contracts;
        this.config = config;
        this.monitoring = new ContractMonitor();
    }
    
    async checkEmergencyConditions() {
        const conditions = await Promise.all([
            this.checkAbnormalActivity(),
            this.checkContractBalance(),
            this.checkGasPrice(),
            this.checkExternalDependencies()
        ]);
        
        return conditions.some(c => c.requiresEmergency);
    }
    
    async checkAbnormalActivity() {
        const recentTransactions = await this.monitoring.getRecentTransactions();
        const normalRate = 100; // transactions per hour
        
        if (recentTransactions.length > normalRate * 10) {
            return {
                requiresEmergency: true,
                reason: "Abnormal transaction volume detected"
            };
        }
        
        return { requiresEmergency: false };
    }
    
    async initiateEmergencyPause(reason) {
        console.error(`EMERGENCY PAUSE INITIATED: ${reason}`);
        
        // 1. Pause contracts
        const pauseTxs = await Promise.all([
            this.contracts.marketplace.pause(),
            this.contracts.registry.pause(),
            this.contracts.escrow.pause()
        ]);
        
        // 2. Wait for confirmations
        await Promise.all(pauseTxs.map(tx => tx.wait(3)));
        
        // 3. Notify stakeholders
        await this.notifyEmergency(reason);
        
        // 4. Log incident
        await this.logIncident({
            type: 'EMERGENCY_PAUSE',
            reason,
            timestamp: Date.now(),
            contracts: pauseTxs.map(tx => tx.hash)
        });
        
        return true;
    }
}
```

## Security Monitoring

### Real-time Threat Detection
```javascript
class SecurityMonitor {
    constructor(contracts) {
        this.contracts = contracts;
        this.patterns = new ThreatPatterns();
        this.alerts = [];
    }
    
    async startMonitoring() {
        // Monitor critical events
        this.contracts.marketplace.on("JobPosted", this.analyzeJobPosting.bind(this));
        this.contracts.escrow.on("PaymentReleased", this.analyzePayment.bind(this));
        this.contracts.registry.on("NodeSlashed", this.analyzeSlashing.bind(this));
        
        // Periodic security checks
        setInterval(() => this.runSecurityScan(), 60000); // Every minute
    }
    
    async analyzeJobPosting(jobId, renter, payment, details, event) {
        const threats = [];
        
        // Check for spam patterns
        const recentJobs = await this.getRecentJobsBy(renter);
        if (recentJobs.length > 10) {
            threats.push({
                severity: 'MEDIUM',
                type: 'SPAM_ATTACK',
                details: `${renter} posted ${recentJobs.length} jobs in last hour`
            });
        }
        
        // Check for price manipulation
        const avgPrice = await this.getAveragePrice(details.modelId);
        const deviation = (payment - avgPrice) / avgPrice;
        if (Math.abs(deviation) > 0.5) {
            threats.push({
                severity: 'LOW',
                type: 'PRICE_ANOMALY',
                details: `Price deviates ${deviation * 100}% from average`
            });
        }
        
        if (threats.length > 0) {
            await this.handleThreats(threats, event);
        }
    }
    
    async runSecurityScan() {
        const scans = await Promise.all([
            this.scanForReentrancy(),
            this.scanForUnauthorizedAccess(),
            this.scanForAbnormalBalances(),
            this.scanForContractUpgrades()
        ]);
        
        const issues = scans.flat().filter(s => s.issue);
        if (issues.length > 0) {
            await this.escalateSecurityIssues(issues);
        }
    }
}
```

## Security Checklist

### Pre-Deployment
- [ ] Smart contracts audited by reputable firm
- [ ] Formal verification completed for critical functions
- [ ] Multi-sig controls implemented
- [ ] Emergency pause mechanisms tested
- [ ] Access control roles configured
- [ ] Monitoring infrastructure deployed

### Transaction Security
- [ ] Input validation on all parameters
- [ ] Gas estimation with appropriate buffers
- [ ] Transaction simulation before execution
- [ ] Nonce management implemented
- [ ] Retry logic with exponential backoff
- [ ] Circuit breakers configured

### Operational Security
- [ ] Role-based access control active
- [ ] Audit logging enabled
- [ ] Anomaly detection running
- [ ] Emergency response procedures documented
- [ ] Incident response team identified
- [ ] Communication channels established

### Continuous Security
- [ ] Regular security audits scheduled
- [ ] Dependency scanning automated
- [ ] Threat modeling updated quarterly
- [ ] Security training completed
- [ ] Bug bounty program active
- [ ] Post-mortem process defined

## Anti-Patterns to Avoid

### ❌ Dangerous Patterns
```javascript
// Never store private keys in code
const PRIVATE_KEY = "0x123..."; // NEVER DO THIS

// Avoid unbounded loops
for (let i = 0; i < users.length; i++) { // Could run out of gas
    await contract.pay(users[i]);
}

// Don't skip error handling
await contract.riskyOperation(); // What if this fails?

// Avoid using tx.origin
require(tx.origin == owner); // Vulnerable to phishing
```

### ✅ Safe Alternatives
```javascript
// Use environment variables or key management service
const signer = new ethers.Wallet(process.env.PRIVATE_KEY);

// Use pagination
const batchSize = 100;
for (let i = 0; i < users.length; i += batchSize) {
    const batch = users.slice(i, i + batchSize);
    await contract.payBatch(batch);
}

// Always handle errors
try {
    await contract.riskyOperation();
} catch (error) {
    await handleOperationFailure(error);
}

// Use msg.sender
require(msg.sender == owner); // Safe from phishing
```

## Tools and Resources

### Security Tools
- **Slither**: Static analysis for Solidity
- **Mythril**: Security analysis tool
- **Echidna**: Smart contract fuzzer
- **Tenderly**: Transaction simulation and debugging
- **OpenZeppelin Defender**: Security operations platform

### Monitoring Services
- **Forta**: Real-time threat detection
- **Etherscan**: Transaction monitoring
- **Alchemy Notify**: Webhook notifications
- **Chainlink Keepers**: Automated maintenance

### Development Tools
```bash
# Install security tools
npm install --save-dev @openzeppelin/hardhat-upgrades
npm install --save-dev hardhat-gas-reporter
npm install --save-dev solidity-coverage

# Run security checks
npm run audit
forge test --gas-report
slither . --print human-summary
```

## Next Steps

1. Review [Key Management](key-management.md) best practices
2. Implement [Operational Security](operational-security.md) measures
3. Set up [Monitoring & Alerting](../operations/monitoring-alerting.md)
4. Create [Incident Response](../operations/incident-response.md) procedures

## Additional Resources

- [Ethereum Smart Contract Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- [OpenZeppelin Security](https://docs.openzeppelin.com/contracts/4.x/)
- [Trail of Bits Security Guidance](https://github.com/crytic/building-secure-contracts)
- [Fabstir Security Audits](https://github.com/fabstir/audits)

---

Remember: **Security is everyone's responsibility.** Stay informed, stay cautious, and never compromise on security for convenience.