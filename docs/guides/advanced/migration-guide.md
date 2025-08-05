# Migration Guide

This guide covers migration scenarios for the Fabstir platform, including upgrading contracts, migrating from other platforms, and handling breaking changes.

## Prerequisites

- Understanding of current system architecture
- Access to migration tools
- Backup of critical data
- Test environment for validation

## Migration Scenarios

### 1. Contract Upgrades (V1 → V2)

#### Pre-Migration Checklist
```javascript
class MigrationChecker {
    async runPreMigrationChecks() {
        const checks = {
            currentVersion: await this.getCurrentVersion(),
            targetVersion: await this.getTargetVersion(),
            dataIntegrity: await this.checkDataIntegrity(),
            compatibility: await this.checkCompatibility(),
            backupStatus: await this.verifyBackups(),
            activeJobs: await this.checkActiveJobs()
        };
        
        const issues = this.analyzeChecks(checks);
        
        if (issues.length > 0) {
            console.error('Pre-migration issues found:');
            issues.forEach(issue => console.error(`- ${issue}`));
            return false;
        }
        
        console.log('✅ All pre-migration checks passed');
        return true;
    }
    
    async getCurrentVersion() {
        const contracts = {
            nodeRegistry: await this.getContractVersion(NODE_REGISTRY_ADDRESS),
            jobMarketplace: await this.getContractVersion(JOB_MARKETPLACE_ADDRESS),
            paymentEscrow: await this.getContractVersion(PAYMENT_ESCROW_ADDRESS)
        };
        
        return contracts;
    }
    
    async checkDataIntegrity() {
        // Verify critical data
        const checks = await Promise.all([
            this.verifyNodeRegistrations(),
            this.verifyActiveJobs(),
            this.verifyEscrowBalances(),
            this.verifyReputationScores()
        ]);
        
        return checks.every(check => check.valid);
    }
    
    async checkActiveJobs() {
        const activeJobs = await sdk.jobs.query({ status: 'active' });
        
        if (activeJobs.length > 0) {
            console.warn(`⚠️ ${activeJobs.length} active jobs found`);
            console.log('Consider waiting for completion or implementing job migration');
            
            return {
                count: activeJobs.length,
                estimatedCompletionTime: this.estimateCompletionTime(activeJobs),
                recommendation: 'Wait for completion or prepare job migration strategy'
            };
        }
        
        return { count: 0 };
    }
}
```

#### State Migration Process
```javascript
class StateMigrator {
    constructor(oldContracts, newContracts) {
        this.old = oldContracts;
        this.new = newContracts;
        this.batchSize = 100;
        this.migrationState = new Map();
    }
    
    async migrateAll() {
        console.log('Starting state migration...');
        
        // Step 1: Pause old contracts
        await this.pauseOldContracts();
        
        // Step 2: Migrate each component
        const migrations = [
            this.migrateNodes(),
            this.migrateJobs(),
            this.migrateEscrow(),
            this.migrateReputation(),
            this.migrateGovernance()
        ];
        
        const results = await Promise.allSettled(migrations);
        
        // Step 3: Verify migration
        const verification = await this.verifyMigration();
        
        // Step 4: Enable new contracts
        if (verification.success) {
            await this.enableNewContracts();
        } else {
            await this.rollbackMigration();
        }
        
        return {
            results,
            verification,
            success: verification.success
        };
    }
    
    async migrateNodes() {
        console.log('Migrating node registrations...');
        
        const totalNodes = await this.old.nodeRegistry.getTotalNodes();
        let migrated = 0;
        
        for (let i = 0; i < totalNodes; i += this.batchSize) {
            const batch = await this.getNodeBatch(i, Math.min(i + this.batchSize, totalNodes));
            
            // Prepare batch migration data
            const migrationData = batch.map(node => ({
                operator: node.operator,
                peerId: node.peerId,
                stake: node.stake,
                models: node.models,
                region: node.region,
                reputation: node.reputation
            }));
            
            // Execute batch migration
            const tx = await this.new.nodeRegistry.batchMigrateNodes(migrationData);
            await tx.wait();
            
            migrated += batch.length;
            console.log(`Migrated ${migrated}/${totalNodes} nodes`);
            
            // Save checkpoint
            await this.saveCheckpoint('nodes', i);
        }
        
        return { migrated, total: totalNodes };
    }
    
    async migrateJobs() {
        console.log('Migrating job history...');
        
        // Only migrate completed jobs
        const completedJobs = await this.getCompletedJobs();
        const batches = this.createBatches(completedJobs, this.batchSize);
        
        for (const [index, batch] of batches.entries()) {
            const jobData = batch.map(job => ({
                id: job.id,
                renter: job.renter,
                host: job.assignedHost,
                modelId: job.modelId,
                payment: job.payment,
                completedAt: job.completedAt,
                resultHash: job.resultHash
            }));
            
            const tx = await this.new.jobMarketplace.importHistoricalJobs(jobData);
            await tx.wait();
            
            console.log(`Migrated job batch ${index + 1}/${batches.length}`);
        }
        
        return { migrated: completedJobs.length };
    }
    
    async migrateEscrow() {
        console.log('Migrating escrow balances...');
        
        // Get all escrow balances
        const balances = await this.old.paymentEscrow.getAllBalances();
        
        // Transfer funds to new escrow
        for (const balance of balances) {
            if (balance.amount > 0) {
                // Withdraw from old
                const withdrawTx = await this.old.paymentEscrow.emergencyWithdraw(
                    balance.user,
                    balance.token,
                    balance.amount
                );
                await withdrawTx.wait();
                
                // Deposit to new
                const depositTx = await this.new.paymentEscrow.migrateDeposit(
                    balance.user,
                    balance.token,
                    balance.amount
                );
                await depositTx.wait();
                
                console.log(`Migrated ${balance.amount} ${balance.token} for ${balance.user}`);
            }
        }
        
        return { migrated: balances.length };
    }
    
    async verifyMigration() {
        console.log('Verifying migration integrity...');
        
        const checks = {
            nodeCounts: await this.verifyNodeCounts(),
            escrowBalances: await this.verifyEscrowBalances(),
            reputationScores: await this.verifyReputationScores(),
            stateHashes: await this.verifyStateHashes()
        };
        
        const allValid = Object.values(checks).every(check => check.valid);
        
        return {
            success: allValid,
            checks,
            timestamp: Date.now()
        };
    }
    
    async rollbackMigration() {
        console.error('Migration failed - initiating rollback...');
        
        // Re-enable old contracts
        await this.enableOldContracts();
        
        // Restore from checkpoints
        const checkpoints = await this.loadCheckpoints();
        
        for (const [component, checkpoint] of checkpoints) {
            await this.restoreFromCheckpoint(component, checkpoint);
        }
        
        console.log('Rollback completed');
    }
}

// Execute migration
async function executeMigration() {
    const checker = new MigrationChecker();
    const canMigrate = await checker.runPreMigrationChecks();
    
    if (!canMigrate) {
        throw new Error('Pre-migration checks failed');
    }
    
    const migrator = new StateMigrator(oldContracts, newContracts);
    const result = await migrator.migrateAll();
    
    if (result.success) {
        console.log('✅ Migration completed successfully');
        await notifyUsers('Migration completed - new contracts are live');
    } else {
        console.error('❌ Migration failed');
        await notifyUsers('Migration failed - system reverted to previous version');
    }
    
    return result;
}
```

### 2. Platform Migration (Competitor → Fabstir)

#### Data Export from Other Platforms
```javascript
class PlatformMigrator {
    constructor(sourcePlatform) {
        this.source = sourcePlatform;
        this.dataMappers = {
            'openai': new OpenAIMapper(),
            'huggingface': new HuggingFaceMapper(),
            'replicate': new ReplicateMapper()
        };
    }
    
    async exportFromSource(accountId) {
        console.log(`Exporting data from ${this.source}...`);
        
        const mapper = this.dataMappers[this.source];
        if (!mapper) {
            throw new Error(`Unsupported platform: ${this.source}`);
        }
        
        // Export different data types
        const data = {
            profile: await mapper.exportProfile(accountId),
            history: await mapper.exportHistory(accountId),
            models: await mapper.exportModels(accountId),
            apiKeys: await mapper.exportAPIKeys(accountId),
            billing: await mapper.exportBilling(accountId)
        };
        
        // Convert to Fabstir format
        const converted = await this.convertToFabstirFormat(data);
        
        return converted;
    }
    
    async convertToFabstirFormat(sourceData) {
        return {
            user: {
                address: sourceData.profile.ethereumAddress || null,
                email: sourceData.profile.email,
                preferences: this.mapPreferences(sourceData.profile.settings)
            },
            jobs: sourceData.history.requests.map(req => ({
                modelId: this.mapModelId(req.model),
                prompt: req.prompt,
                timestamp: req.timestamp,
                cost: this.convertCost(req.cost),
                result: req.response
            })),
            models: sourceData.models.map(model => ({
                id: this.mapModelId(model.id),
                usage: model.usage,
                preferences: model.settings
            })),
            credits: this.convertCredits(sourceData.billing.balance)
        };
    }
    
    mapModelId(sourceModelId) {
        const modelMap = {
            // OpenAI mappings
            'gpt-4': 'gpt-4',
            'gpt-3.5-turbo': 'gpt-3.5-turbo',
            'dall-e-3': 'dall-e-3',
            
            // HuggingFace mappings
            'meta-llama/Llama-2-70b': 'llama-2-70b',
            'stabilityai/stable-diffusion-xl': 'stable-diffusion-xl',
            
            // Replicate mappings
            'meta/llama-2-70b-chat': 'llama-2-70b',
            'stability-ai/sdxl': 'stable-diffusion-xl'
        };
        
        return modelMap[sourceModelId] || 'gpt-3.5-turbo';
    }
    
    convertCost(sourceCost) {
        // Convert USD to ETH equivalent
        const ethPrice = 2000; // Fetch current price
        return (sourceCost / ethPrice).toFixed(6);
    }
}

// Import to Fabstir
class FabstirImporter {
    constructor(sdk) {
        this.sdk = sdk;
    }
    
    async importUserData(migratedData) {
        console.log('Importing data to Fabstir...');
        
        const results = {
            profile: await this.createProfile(migratedData.user),
            jobs: await this.importJobHistory(migratedData.jobs),
            preferences: await this.setPreferences(migratedData.user.preferences),
            credits: await this.allocateCredits(migratedData.credits)
        };
        
        // Generate migration report
        const report = this.generateReport(results);
        
        return report;
    }
    
    async importJobHistory(jobs) {
        // Create historical records for analytics
        const imported = [];
        
        for (const job of jobs) {
            try {
                const record = await this.sdk.analytics.importHistoricalJob({
                    modelId: job.modelId,
                    prompt: job.prompt,
                    timestamp: job.timestamp,
                    cost: job.cost,
                    resultSummary: this.summarizeResult(job.result)
                });
                
                imported.push(record);
            } catch (error) {
                console.error(`Failed to import job: ${error.message}`);
            }
        }
        
        return {
            total: jobs.length,
            imported: imported.length,
            failed: jobs.length - imported.length
        };
    }
    
    async allocateCredits(ethAmount) {
        // Provide migration bonus
        const bonus = ethAmount * 0.1; // 10% bonus
        const total = ethAmount + bonus;
        
        console.log(`Allocating ${total} ETH (includes ${bonus} ETH migration bonus)`);
        
        // Create credit allocation
        const allocation = await this.sdk.credits.allocate({
            amount: total,
            type: 'migration',
            source: 'platform_migration',
            expiresAt: Date.now() + 90 * 24 * 60 * 60 * 1000 // 90 days
        });
        
        return allocation;
    }
}
```

### 3. Breaking Changes Migration

#### API Version Migration
```javascript
class APIVersionMigrator {
    constructor(fromVersion, toVersion) {
        this.fromVersion = fromVersion;
        this.toVersion = toVersion;
        this.deprecations = new Map();
        this.breakingChanges = new Map();
        
        this.loadMigrationRules();
    }
    
    loadMigrationRules() {
        // V1 → V2 migration rules
        this.breakingChanges.set('v1->v2', {
            endpoints: {
                '/api/v1/jobs/create': {
                    newEndpoint: '/api/v2/jobs',
                    method: 'POST',
                    parameterChanges: {
                        'model_id': 'modelId',
                        'max_tokens': 'parameters.maxTokens',
                        'payment_amount': 'payment.amount'
                    }
                }
            },
            responseFormats: {
                'job': {
                    'job_id': 'id',
                    'created_at': 'createdAt',
                    'assigned_node': 'assignedHost'
                }
            },
            authentication: {
                oldHeader: 'X-API-Key',
                newHeader: 'Authorization',
                format: 'Bearer {apiKey}'
            }
        });
    }
    
    async migrateRequest(request) {
        const rules = this.breakingChanges.get(`${this.fromVersion}->${this.toVersion}`);
        if (!rules) {
            throw new Error(`No migration path from ${this.fromVersion} to ${this.toVersion}`);
        }
        
        // Migrate endpoint
        const migratedEndpoint = this.migrateEndpoint(request.endpoint, rules.endpoints);
        
        // Migrate parameters
        const migratedParams = this.migrateParameters(request.params, rules.parameterChanges);
        
        // Migrate authentication
        const migratedAuth = this.migrateAuth(request.headers, rules.authentication);
        
        return {
            endpoint: migratedEndpoint.endpoint,
            method: migratedEndpoint.method,
            params: migratedParams,
            headers: migratedAuth
        };
    }
    
    migrateParameters(oldParams, paramChanges) {
        const newParams = {};
        
        for (const [oldKey, value] of Object.entries(oldParams)) {
            const newKey = paramChanges[oldKey];
            
            if (newKey) {
                // Handle nested parameters
                if (newKey.includes('.')) {
                    const [parent, child] = newKey.split('.');
                    newParams[parent] = newParams[parent] || {};
                    newParams[parent][child] = value;
                } else {
                    newParams[newKey] = value;
                }
            } else if (!this.deprecations.has(oldKey)) {
                // Keep parameter if not deprecated
                newParams[oldKey] = value;
            }
        }
        
        return newParams;
    }
    
    generateMigrationCode(language = 'javascript') {
        const templates = {
            javascript: this.generateJavaScriptMigration(),
            python: this.generatePythonMigration(),
            go: this.generateGoMigration()
        };
        
        return templates[language];
    }
    
    generateJavaScriptMigration() {
        return `
// Fabstir API ${this.fromVersion} → ${this.toVersion} Migration

// Old code (${this.fromVersion})
const oldClient = new FabstirClient({
    apiKey: 'your-api-key',
    version: '${this.fromVersion}'
});

const job = await oldClient.createJob({
    model_id: 'gpt-4',
    prompt: 'Hello world',
    max_tokens: 100,
    payment_amount: 0.01
});

// New code (${this.toVersion})
const newClient = new FabstirClient({
    apiKey: 'your-api-key',
    version: '${this.toVersion}'
});

const job = await newClient.jobs.create({
    modelId: 'gpt-4',
    prompt: 'Hello world',
    parameters: {
        maxTokens: 100
    },
    payment: {
        amount: 0.01,
        token: 'ETH'
    }
});

// Migration helper
class MigrationHelper {
    static migrateJobCreation(oldParams) {
        return {
            modelId: oldParams.model_id,
            prompt: oldParams.prompt,
            parameters: {
                maxTokens: oldParams.max_tokens,
                temperature: oldParams.temperature || 0.7
            },
            payment: {
                amount: oldParams.payment_amount,
                token: 'ETH'
            }
        };
    }
}
        `;
    }
}
```

#### Contract Interface Changes
```javascript
class ContractInterfaceMigrator {
    async analyzeInterfaceChanges(oldABI, newABI) {
        const changes = {
            added: [],
            removed: [],
            modified: [],
            breaking: []
        };
        
        const oldFunctions = this.extractFunctions(oldABI);
        const newFunctions = this.extractFunctions(newABI);
        
        // Find added functions
        for (const [name, func] of newFunctions) {
            if (!oldFunctions.has(name)) {
                changes.added.push(func);
            }
        }
        
        // Find removed functions
        for (const [name, func] of oldFunctions) {
            if (!newFunctions.has(name)) {
                changes.removed.push(func);
                changes.breaking.push({
                    type: 'function_removed',
                    name: name,
                    impact: 'high'
                });
            }
        }
        
        // Find modified functions
        for (const [name, newFunc] of newFunctions) {
            const oldFunc = oldFunctions.get(name);
            if (oldFunc && !this.functionsEqual(oldFunc, newFunc)) {
                changes.modified.push({
                    old: oldFunc,
                    new: newFunc
                });
                
                // Check if modification is breaking
                if (this.isBreakingChange(oldFunc, newFunc)) {
                    changes.breaking.push({
                        type: 'function_modified',
                        name: name,
                        details: this.getBreakingChangeDetails(oldFunc, newFunc)
                    });
                }
            }
        }
        
        return changes;
    }
    
    generateAdapterContract(changes) {
        // Generate a compatibility adapter contract
        return `
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./INewContract.sol";
import "./IOldContract.sol";

/**
 * @title ContractAdapter
 * @notice Provides backwards compatibility for v1 integrations
 */
contract ContractAdapter is IOldContract {
    INewContract public immutable newContract;
    
    constructor(address _newContract) {
        newContract = INewContract(_newContract);
    }
    
    // Adapter functions for breaking changes
    ${this.generateAdapterFunctions(changes)}
    
    // Deprecated function warnings
    ${this.generateDeprecationWarnings(changes)}
}
        `;
    }
    
    generateAdapterFunctions(changes) {
        return changes.breaking
            .filter(change => change.type === 'function_modified')
            .map(change => this.generateAdapterFunction(change))
            .join('\n\n');
    }
}
```

### 4. Data Format Migration

#### Schema Evolution
```javascript
class SchemaEvolution {
    constructor() {
        this.migrations = [];
        this.version = 0;
    }
    
    addMigration(version, up, down) {
        this.migrations.push({
            version,
            up,
            down,
            checksum: this.calculateChecksum(up)
        });
    }
    
    async migrate(data, targetVersion) {
        const currentVersion = data._version || 0;
        
        if (currentVersion === targetVersion) {
            return data;
        }
        
        let migratedData = { ...data };
        
        if (currentVersion < targetVersion) {
            // Migrate up
            for (let v = currentVersion + 1; v <= targetVersion; v++) {
                const migration = this.migrations.find(m => m.version === v);
                if (migration) {
                    migratedData = await migration.up(migratedData);
                    migratedData._version = v;
                }
            }
        } else {
            // Migrate down
            for (let v = currentVersion; v > targetVersion; v--) {
                const migration = this.migrations.find(m => m.version === v);
                if (migration) {
                    migratedData = await migration.down(migratedData);
                    migratedData._version = v - 1;
                }
            }
        }
        
        return migratedData;
    }
}

// Example migrations
const jobSchemaEvolution = new SchemaEvolution();

// V1 → V2: Add metadata field
jobSchemaEvolution.addMigration(2, 
    async (data) => ({
        ...data,
        metadata: {
            createdAt: data.timestamp || Date.now(),
            updatedAt: Date.now(),
            version: '2.0'
        }
    }),
    async (data) => {
        const { metadata, ...rest } = data;
        return {
            ...rest,
            timestamp: metadata?.createdAt
        };
    }
);

// V2 → V3: Restructure payment info
jobSchemaEvolution.addMigration(3,
    async (data) => ({
        ...data,
        payment: {
            amount: data.paymentAmount || data.payment,
            token: data.paymentToken || 'ETH',
            usdValue: await calculateUSDValue(data.paymentAmount)
        }
    }),
    async (data) => ({
        ...data,
        paymentAmount: data.payment?.amount,
        paymentToken: data.payment?.token
    })
);
```

## Migration Tools

### Automated Migration Script
```javascript
#!/usr/bin/env node
const { program } = require('commander');
const { MigrationOrchestrator } = require('./migrations');

program
    .version('1.0.0')
    .description('Fabstir Migration Tool');

program
    .command('check')
    .description('Run pre-migration checks')
    .option('--verbose', 'Show detailed output')
    .action(async (options) => {
        const orchestrator = new MigrationOrchestrator();
        const results = await orchestrator.runChecks(options);
        
        console.log(results.summary);
        if (options.verbose) {
            console.log(JSON.stringify(results, null, 2));
        }
    });

program
    .command('migrate <type>')
    .description('Execute migration')
    .option('--dry-run', 'Simulate migration without making changes')
    .option('--batch-size <size>', 'Number of items per batch', parseInt, 100)
    .option('--checkpoint <file>', 'Resume from checkpoint')
    .action(async (type, options) => {
        const orchestrator = new MigrationOrchestrator();
        
        try {
            const result = await orchestrator.migrate(type, options);
            console.log('Migration completed:', result);
        } catch (error) {
            console.error('Migration failed:', error);
            process.exit(1);
        }
    });

program
    .command('rollback <type>')
    .description('Rollback migration')
    .option('--to-version <version>', 'Target version')
    .action(async (type, options) => {
        const orchestrator = new MigrationOrchestrator();
        const result = await orchestrator.rollback(type, options);
        console.log('Rollback completed:', result);
    });

program
    .command('verify')
    .description('Verify migration integrity')
    .action(async () => {
        const orchestrator = new MigrationOrchestrator();
        const verification = await orchestrator.verify();
        
        if (verification.success) {
            console.log('✅ Migration verified successfully');
        } else {
            console.error('❌ Verification failed');
            console.error(verification.errors);
        }
    });

program.parse(process.argv);
```

### Migration Dashboard
```javascript
class MigrationDashboard {
    constructor() {
        this.server = express();
        this.setupRoutes();
        this.setupWebSocket();
    }
    
    setupRoutes() {
        // Migration status endpoint
        this.server.get('/api/migration/status', async (req, res) => {
            const status = await this.getMigrationStatus();
            res.json(status);
        });
        
        // Progress tracking
        this.server.get('/api/migration/progress', async (req, res) => {
            const progress = await this.getProgress();
            res.json(progress);
        });
        
        // Checkpoint management
        this.server.post('/api/migration/checkpoint', async (req, res) => {
            const checkpoint = await this.createCheckpoint();
            res.json({ checkpoint });
        });
    }
    
    setupWebSocket() {
        this.io = require('socket.io')(this.server);
        
        this.io.on('connection', (socket) => {
            console.log('Dashboard client connected');
            
            // Stream migration progress
            this.streamProgress(socket);
            
            // Handle control commands
            socket.on('pause', () => this.pauseMigration());
            socket.on('resume', () => this.resumeMigration());
            socket.on('rollback', () => this.initRollback());
        });
    }
    
    async streamProgress(socket) {
        const interval = setInterval(async () => {
            const progress = await this.getProgress();
            socket.emit('progress', progress);
            
            if (progress.completed) {
                clearInterval(interval);
            }
        }, 1000);
    }
    
    async getMigrationStatus() {
        return {
            active: this.migrationActive,
            type: this.migrationType,
            startTime: this.startTime,
            estimatedCompletion: this.estimateCompletion(),
            components: await this.getComponentStatus(),
            errors: await this.getErrors(),
            warnings: await this.getWarnings()
        };
    }
}
```

## Best Practices

### 1. Migration Planning
```javascript
class MigrationPlanner {
    async createMigrationPlan(scope) {
        const plan = {
            phases: [],
            timeline: {},
            risks: [],
            rollbackStrategy: {},
            communicationPlan: {}
        };
        
        // Phase 1: Preparation
        plan.phases.push({
            name: 'Preparation',
            duration: '1 week',
            tasks: [
                'Audit current system',
                'Identify dependencies',
                'Create test environment',
                'Develop migration scripts',
                'Train team'
            ]
        });
        
        // Phase 2: Testing
        plan.phases.push({
            name: 'Testing',
            duration: '2 weeks',
            tasks: [
                'Run migration in test environment',
                'Validate data integrity',
                'Performance testing',
                'Security audit',
                'User acceptance testing'
            ]
        });
        
        // Phase 3: Execution
        plan.phases.push({
            name: 'Execution',
            duration: '1 day',
            tasks: [
                'Final backup',
                'Maintenance mode',
                'Execute migration',
                'Verify migration',
                'Monitor system'
            ]
        });
        
        return plan;
    }
}
```

### 2. Zero-Downtime Migration
```javascript
class ZeroDowntimeMigration {
    async execute() {
        // Step 1: Deploy new version alongside old
        await this.deployNewVersion();
        
        // Step 2: Set up data replication
        await this.setupReplication();
        
        // Step 3: Gradually shift traffic
        for (let percentage = 10; percentage <= 100; percentage += 10) {
            await this.shiftTraffic(percentage);
            await this.monitorHealth();
            
            if (await this.detectIssues()) {
                await this.rollbackTraffic(percentage - 10);
                throw new Error('Issues detected during migration');
            }
            
            // Wait before next increment
            await new Promise(resolve => setTimeout(resolve, 300000)); // 5 minutes
        }
        
        // Step 4: Decommission old version
        await this.decommissionOldVersion();
    }
    
    async shiftTraffic(percentage) {
        // Update load balancer
        await this.updateLoadBalancer({
            old: 100 - percentage,
            new: percentage
        });
        
        console.log(`Traffic distribution: ${percentage}% to new version`);
    }
}
```

### 3. Data Validation
```javascript
class DataValidator {
    async validateMigration(before, after) {
        const validations = {
            recordCount: this.validateRecordCount(before, after),
            dataIntegrity: await this.validateIntegrity(before, after),
            relationships: await this.validateRelationships(after),
            businessRules: await this.validateBusinessRules(after)
        };
        
        const report = {
            timestamp: Date.now(),
            validations,
            success: Object.values(validations).every(v => v.passed),
            details: this.generateDetailedReport(validations)
        };
        
        return report;
    }
    
    async validateIntegrity(before, after) {
        // Check critical fields
        const criticalFields = ['id', 'stake', 'payment', 'reputation'];
        const mismatches = [];
        
        for (const record of before) {
            const afterRecord = after.find(a => a.id === record.id);
            if (!afterRecord) {
                mismatches.push({ type: 'missing', record });
                continue;
            }
            
            for (const field of criticalFields) {
                if (record[field] !== afterRecord[field]) {
                    mismatches.push({
                        type: 'mismatch',
                        field,
                        before: record[field],
                        after: afterRecord[field]
                    });
                }
            }
        }
        
        return {
            passed: mismatches.length === 0,
            mismatches
        };
    }
}
```

## Common Issues

### Issue: Gas Limit Exceeded
```javascript
// Solution: Implement chunked migration
async function migrateInChunks(data, chunkSize = 50) {
    const chunks = [];
    for (let i = 0; i < data.length; i += chunkSize) {
        chunks.push(data.slice(i, i + chunkSize));
    }
    
    for (const [index, chunk] of chunks.entries()) {
        console.log(`Processing chunk ${index + 1}/${chunks.length}`);
        
        const gasEstimate = await contract.estimateGas.batchMigrate(chunk);
        const tx = await contract.batchMigrate(chunk, {
            gasLimit: gasEstimate.mul(110).div(100) // 10% buffer
        });
        
        await tx.wait();
    }
}
```

### Issue: State Inconsistency
```javascript
// Solution: Implement transaction atomicity
class AtomicMigration {
    async executeAtomic(operations) {
        const snapshot = await this.createSnapshot();
        
        try {
            for (const op of operations) {
                await op.execute();
            }
            
            // Verify consistency
            const consistent = await this.verifyConsistency();
            if (!consistent) {
                throw new Error('State inconsistency detected');
            }
            
        } catch (error) {
            // Rollback to snapshot
            await this.restoreSnapshot(snapshot);
            throw error;
        }
    }
}
```

## Migration Checklist

### Pre-Migration
- [ ] Complete system audit
- [ ] Create comprehensive backups
- [ ] Test migration in staging
- [ ] Prepare rollback plan
- [ ] Notify users of maintenance
- [ ] Set up monitoring
- [ ] Verify team availability

### During Migration
- [ ] Enable maintenance mode
- [ ] Execute pre-migration checks
- [ ] Run migration scripts
- [ ] Monitor progress
- [ ] Validate data integrity
- [ ] Test critical functions
- [ ] Update documentation

### Post-Migration
- [ ] Verify all systems operational
- [ ] Run comprehensive tests
- [ ] Monitor for issues
- [ ] Collect performance metrics
- [ ] Update user documentation
- [ ] Decommission old systems
- [ ] Conduct retrospective

## Next Steps

1. **[Monitoring Setup](monitoring-setup.md)** - Monitor post-migration health
2. **[Governance Participation](governance-participation.md)** - Vote on migration proposals
3. **[SDK Usage](../developers/sdk-usage.md)** - Update SDK integration

## Resources

- [Migration Tools Repository](https://github.com/fabstir/migration-tools)
- [Migration Best Practices](https://fabstir.com/docs/migration)
- [Community Migration Experiences](https://forum.fabstir.com/migrations)
- [Emergency Support](https://discord.gg/fabstir-emergency)

---

Need migration help? Contact our [Migration Support Team](https://fabstir.com/migration-support) →