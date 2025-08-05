# Backup & Recovery Best Practices

This guide covers comprehensive backup strategies and disaster recovery procedures for Fabstir infrastructure.

## Why It Matters

Effective backup and recovery ensures:
- **Business continuity** - Minimize downtime during disasters
- **Data protection** - Prevent permanent data loss
- **Compliance** - Meet regulatory requirements
- **Customer trust** - Reliable service availability
- **Financial protection** - Avoid revenue loss from outages

## Backup Strategy Overview

### 3-2-1 Backup Rule
```yaml
backup_strategy:
  copies: 3          # Three copies of important data
  media_types: 2     # Two different storage media
  offsite: 1         # One offsite backup
  
  implementation:
    primary: "Production database"
    local_backup: "Local NAS/SAN storage"
    remote_backup: "Cloud storage (S3/GCS)"
    
  retention:
    hourly: 24       # Keep 24 hourly backups
    daily: 7         # Keep 7 daily backups
    weekly: 4        # Keep 4 weekly backups
    monthly: 12      # Keep 12 monthly backups
    yearly: 7        # Keep 7 yearly backups
```

### Backup Types and Schedules
```javascript
class BackupStrategy {
    constructor() {
        this.strategies = {
            // Full backup - complete data copy
            full: {
                schedule: '0 2 * * 0', // Weekly at 2 AM Sunday
                retention: 4, // Keep 4 weeks
                compression: true,
                encryption: true
            },
            
            // Incremental - changes since last backup
            incremental: {
                schedule: '0 */6 * * *', // Every 6 hours
                retention: 168, // Keep 7 days of hourly
                compression: true,
                encryption: true
            },
            
            // Differential - changes since last full
            differential: {
                schedule: '0 2 * * 1-6', // Daily except Sunday
                retention: 7,
                compression: true,
                encryption: true
            },
            
            // Continuous - real-time replication
            continuous: {
                type: 'streaming',
                targets: ['replica-1', 'replica-2'],
                lag_threshold: 1000 // 1 second max lag
            }
        };
    }
    
    async executeBackup(type, source) {
        const strategy = this.strategies[type];
        const backupId = crypto.randomUUID();
        
        console.log(`Starting ${type} backup ${backupId}`);
        
        try {
            // Pre-backup checks
            await this.preBackupChecks(source);
            
            // Create backup
            const backup = await this.createBackup(source, strategy);
            
            // Verify backup
            await this.verifyBackup(backup);
            
            // Store metadata
            await this.storeBackupMetadata({
                id: backupId,
                type,
                source,
                size: backup.size,
                checksum: backup.checksum,
                timestamp: Date.now(),
                location: backup.location
            });
            
            // Cleanup old backups
            await this.cleanupOldBackups(type, strategy.retention);
            
            console.log(`Backup ${backupId} completed successfully`);
            return backupId;
            
        } catch (error) {
            console.error(`Backup ${backupId} failed:`, error);
            await this.alertBackupFailure(type, error);
            throw error;
        }
    }
}
```

## Database Backup

### PostgreSQL Backup Implementation
```javascript
class DatabaseBackup {
    constructor(config) {
        this.config = config;
        this.s3 = new S3Client({ region: config.aws_region });
    }
    
    async backupPostgreSQL() {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `postgres-backup-${timestamp}.sql.gz`;
        
        try {
            // Create backup with pg_dump
            const dumpCommand = `
                PGPASSWORD=${this.config.db_password} \
                pg_dump \
                    -h ${this.config.db_host} \
                    -U ${this.config.db_user} \
                    -d ${this.config.db_name} \
                    --no-owner \
                    --no-privileges \
                    --verbose \
                    --format=custom \
                    --compress=9 \
                    --file=/tmp/${filename}
            `;
            
            await execAsync(dumpCommand);
            
            // Calculate checksum
            const checksum = await this.calculateChecksum(`/tmp/${filename}`);
            
            // Encrypt backup
            const encryptedFile = await this.encryptFile(
                `/tmp/${filename}`,
                this.config.encryption_key
            );
            
            // Upload to S3
            const uploadResult = await this.uploadToS3(
                encryptedFile,
                `database-backups/${filename}.enc`
            );
            
            // Verify upload
            await this.verifyS3Upload(uploadResult, checksum);
            
            // Clean up local files
            await fs.promises.unlink(`/tmp/${filename}`);
            await fs.promises.unlink(encryptedFile);
            
            return {
                filename,
                size: uploadResult.size,
                checksum,
                location: uploadResult.location,
                timestamp: Date.now()
            };
            
        } catch (error) {
            console.error('Database backup failed:', error);
            throw error;
        }
    }
    
    async performPointInTimeRecovery(targetTime) {
        console.log(`Starting PITR to ${targetTime}`);
        
        // Find base backup before target time
        const baseBackup = await this.findBaseBackup(targetTime);
        
        // Get WAL files for replay
        const walFiles = await this.getWALFiles(
            baseBackup.timestamp,
            targetTime
        );
        
        // Restore base backup
        await this.restoreBaseBackup(baseBackup);
        
        // Create recovery configuration
        const recoveryConf = `
            restore_command = 'aws s3 cp s3://bucket/wal/%f %p'
            recovery_target_time = '${targetTime}'
            recovery_target_action = 'promote'
        `;
        
        await fs.promises.writeFile(
            '/var/lib/postgresql/data/recovery.conf',
            recoveryConf
        );
        
        // Start PostgreSQL in recovery mode
        await this.startPostgreSQLRecovery();
        
        // Monitor recovery progress
        await this.monitorRecovery();
        
        console.log('PITR completed successfully');
    }
    
    async streamingReplication() {
        // Setup streaming replication for real-time backup
        const replicationSlot = 'fabstir_replica_1';
        
        // Create replication slot on primary
        await this.executeSql(`
            SELECT pg_create_physical_replication_slot('${replicationSlot}');
        `);
        
        // Configure standby
        const standbyConfig = `
            primary_conninfo = 'host=${this.config.primary_host} port=5432 user=replicator'
            primary_slot_name = '${replicationSlot}'
            hot_standby = on
            max_standby_streaming_delay = 30s
            wal_receiver_status_interval = 10s
        `;
        
        // Monitor replication lag
        setInterval(async () => {
            const lag = await this.getReplicationLag();
            
            if (lag > 5000) { // 5 seconds
                console.warn(`High replication lag: ${lag}ms`);
                await this.alert({
                    type: 'replication_lag',
                    severity: 'warning',
                    lag
                });
            }
        }, 10000);
    }
}
```

### MongoDB Backup Strategy
```javascript
class MongoDBBackup {
    constructor(config) {
        this.config = config;
        this.client = new MongoClient(config.connection_string);
    }
    
    async performBackup() {
        const backupId = new Date().toISOString();
        
        try {
            // For replica sets, backup from secondary
            const secondary = await this.selectSecondaryNode();
            
            // Create backup directory
            const backupDir = `/backup/mongodb/${backupId}`;
            await fs.promises.mkdir(backupDir, { recursive: true });
            
            // Perform backup with mongodump
            const dumpCommand = `
                mongodump \
                    --host ${secondary} \
                    --readPreference=secondary \
                    --oplog \
                    --gzip \
                    --out ${backupDir}
            `;
            
            await execAsync(dumpCommand);
            
            // Create tar archive
            const archivePath = `${backupDir}.tar.gz`;
            await this.createArchive(backupDir, archivePath);
            
            // Upload to cloud storage
            await this.uploadToCloudStorage(archivePath);
            
            // Cleanup
            await fs.promises.rm(backupDir, { recursive: true });
            await fs.promises.unlink(archivePath);
            
            return { backupId, size: archiveSize };
            
        } catch (error) {
            console.error('MongoDB backup failed:', error);
            throw error;
        }
    }
    
    async setupChangeStreams() {
        // Real-time backup using change streams
        const pipeline = [
            { $match: { 'ns.db': { $ne: 'admin' } } }
        ];
        
        const changeStream = this.client.watch(pipeline, {
            fullDocument: 'updateLookup',
            resumeAfter: await this.getResumeToken()
        });
        
        changeStream.on('change', async (change) => {
            try {
                // Store change in backup collection
                await this.storeChange(change);
                
                // Update resume token
                await this.updateResumeToken(change._id);
                
            } catch (error) {
                console.error('Change stream error:', error);
            }
        });
        
        changeStream.on('error', async (error) => {
            console.error('Change stream failed:', error);
            // Restart from last resume token
            await this.restartChangeStream();
        });
    }
}
```

## Application State Backup

### Configuration and Secrets Backup
```javascript
class ConfigurationBackup {
    constructor() {
        this.vault = new HashiCorpVault({
            endpoint: process.env.VAULT_ADDR,
            token: process.env.VAULT_TOKEN
        });
    }
    
    async backupConfigurations() {
        const backup = {
            timestamp: Date.now(),
            environment: process.env.NODE_ENV,
            configs: {},
            secrets: {}
        };
        
        // Backup application configs
        const configPaths = [
            '/config/app.json',
            '/config/database.json',
            '/config/services.json'
        ];
        
        for (const path of configPaths) {
            const config = await fs.promises.readFile(path, 'utf8');
            backup.configs[path] = JSON.parse(config);
        }
        
        // Backup secrets from Vault
        const secretPaths = await this.vault.list('secret/fabstir');
        
        for (const path of secretPaths) {
            // Don't backup the actual secrets, just the paths
            backup.secrets[path] = {
                version: await this.vault.getVersion(path),
                metadata: await this.vault.getMetadata(path)
            };
        }
        
        // Backup environment variables (sanitized)
        backup.environment = this.sanitizeEnvironment(process.env);
        
        // Encrypt and store
        const encrypted = await this.encrypt(JSON.stringify(backup));
        await this.storeBackup('configuration', encrypted);
        
        return backup.timestamp;
    }
    
    sanitizeEnvironment(env) {
        const sanitized = {};
        const sensitiveKeys = [
            'PASSWORD', 'SECRET', 'KEY', 'TOKEN', 'PRIVATE'
        ];
        
        for (const [key, value] of Object.entries(env)) {
            if (sensitiveKeys.some(sensitive => key.includes(sensitive))) {
                sanitized[key] = '***REDACTED***';
            } else {
                sanitized[key] = value;
            }
        }
        
        return sanitized;
    }
}
```

### File System Backup
```javascript
class FileSystemBackup {
    constructor() {
        this.rsync = new RsyncWrapper();
        this.restic = new ResticWrapper();
    }
    
    async performIncrementalBackup() {
        const sources = [
            '/var/lib/fabstir/data',
            '/var/lib/fabstir/models',
            '/var/log/fabstir'
        ];
        
        const excludes = [
            '*.tmp',
            '*.log.gz',
            'cache/*',
            'temp/*'
        ];
        
        // Use rsync for fast incremental backup
        for (const source of sources) {
            await this.rsync.sync({
                source,
                destination: '/backup/incremental',
                options: {
                    archive: true,
                    compress: true,
                    delete: true,
                    exclude: excludes,
                    checksum: true,
                    progress: true
                }
            });
        }
        
        // Create snapshot with restic
        const snapshot = await this.restic.backup({
            paths: sources,
            exclude: excludes,
            tags: ['automated', `env:${process.env.NODE_ENV}`]
        });
        
        // Prune old snapshots
        await this.restic.forget({
            keepHourly: 24,
            keepDaily: 7,
            keepWeekly: 4,
            keepMonthly: 12,
            prune: true
        });
        
        return snapshot;
    }
    
    async setupContinuousBackup() {
        // Use inotify for real-time file backup
        const watcher = new FileWatcher();
        
        watcher.on('change', async (event) => {
            if (this.shouldBackup(event.path)) {
                await this.backupFile(event.path);
            }
        });
        
        watcher.watch([
            '/var/lib/fabstir/data',
            '/etc/fabstir'
        ]);
    }
}
```

## Blockchain Data Backup

### Smart Contract State Backup
```javascript
class BlockchainBackup {
    constructor(provider, contracts) {
        this.provider = provider;
        this.contracts = contracts;
    }
    
    async backupContractState() {
        const backup = {
            timestamp: Date.now(),
            blockNumber: await this.provider.getBlockNumber(),
            contracts: {}
        };
        
        // Backup each contract's state
        for (const [name, contract] of Object.entries(this.contracts)) {
            console.log(`Backing up ${name} state...`);
            
            const state = {
                address: contract.address,
                balance: await this.provider.getBalance(contract.address),
                code: await this.provider.getCode(contract.address),
                storage: {},
                events: []
            };
            
            // Get storage slots
            if (this.storageLayouts[name]) {
                for (const variable of this.storageLayouts[name]) {
                    const value = await this.provider.getStorageAt(
                        contract.address,
                        variable.slot
                    );
                    state.storage[variable.name] = value;
                }
            }
            
            // Get recent events
            const filter = {
                address: contract.address,
                fromBlock: backup.blockNumber - 10000,
                toBlock: backup.blockNumber
            };
            
            state.events = await this.provider.getLogs(filter);
            
            backup.contracts[name] = state;
        }
        
        // Store backup
        await this.storeBlockchainBackup(backup);
        
        return backup;
    }
    
    async backupTransactionHistory() {
        const batchSize = 1000;
        let startBlock = await this.getLastBackedUpBlock();
        const currentBlock = await this.provider.getBlockNumber();
        
        while (startBlock < currentBlock) {
            const endBlock = Math.min(startBlock + batchSize, currentBlock);
            
            console.log(`Backing up blocks ${startBlock} to ${endBlock}`);
            
            const transactions = [];
            
            for (let blockNum = startBlock; blockNum <= endBlock; blockNum++) {
                const block = await this.provider.getBlock(blockNum, true);
                
                for (const tx of block.transactions) {
                    if (this.isOurTransaction(tx)) {
                        const receipt = await this.provider.getTransactionReceipt(tx.hash);
                        transactions.push({
                            transaction: tx,
                            receipt: receipt,
                            block: {
                                number: block.number,
                                timestamp: block.timestamp,
                                hash: block.hash
                            }
                        });
                    }
                }
            }
            
            // Store batch
            await this.storeTransactionBatch(transactions, startBlock, endBlock);
            
            startBlock = endBlock + 1;
        }
    }
}
```

## Recovery Procedures

### Disaster Recovery Plan
```javascript
class DisasterRecoveryPlan {
    constructor() {
        this.rto = 4 * 60 * 60 * 1000; // 4 hour Recovery Time Objective
        this.rpo = 1 * 60 * 60 * 1000; // 1 hour Recovery Point Objective
    }
    
    async executeRecoveryPlan(disaster) {
        console.log(`Executing disaster recovery for: ${disaster.type}`);
        
        const plan = {
            id: crypto.randomUUID(),
            disaster,
            startTime: Date.now(),
            steps: []
        };
        
        try {
            // Step 1: Assess damage
            const assessment = await this.assessDamage(disaster);
            plan.steps.push({
                name: 'damage_assessment',
                result: assessment,
                duration: Date.now() - plan.startTime
            });
            
            // Step 2: Activate DR site
            if (assessment.severity === 'critical') {
                await this.activateDRSite();
                plan.steps.push({
                    name: 'dr_site_activation',
                    result: 'activated',
                    duration: Date.now() - plan.startTime
                });
            }
            
            // Step 3: Restore data
            const restoreResult = await this.restoreData(assessment);
            plan.steps.push({
                name: 'data_restoration',
                result: restoreResult,
                duration: Date.now() - plan.startTime
            });
            
            // Step 4: Verify integrity
            const verification = await this.verifySystemIntegrity();
            plan.steps.push({
                name: 'integrity_verification',
                result: verification,
                duration: Date.now() - plan.startTime
            });
            
            // Step 5: Resume operations
            await this.resumeOperations();
            plan.steps.push({
                name: 'resume_operations',
                result: 'completed',
                duration: Date.now() - plan.startTime
            });
            
            plan.endTime = Date.now();
            plan.totalDuration = plan.endTime - plan.startTime;
            plan.success = true;
            
            // Verify RTO compliance
            if (plan.totalDuration > this.rto) {
                console.warn(`RTO exceeded: ${plan.totalDuration}ms > ${this.rto}ms`);
            }
            
            return plan;
            
        } catch (error) {
            plan.error = error.message;
            plan.success = false;
            throw error;
        } finally {
            await this.documentRecovery(plan);
        }
    }
    
    async restoreData(assessment) {
        const restoreTasks = [];
        
        // Restore databases
        if (assessment.databases.length > 0) {
            for (const db of assessment.databases) {
                restoreTasks.push(this.restoreDatabase(db));
            }
        }
        
        // Restore file systems
        if (assessment.filesystems.length > 0) {
            for (const fs of assessment.filesystems) {
                restoreTasks.push(this.restoreFileSystem(fs));
            }
        }
        
        // Restore configurations
        if (assessment.configurations.corrupted) {
            restoreTasks.push(this.restoreConfigurations());
        }
        
        // Execute restorations in parallel
        const results = await Promise.allSettled(restoreTasks);
        
        // Check for failures
        const failures = results.filter(r => r.status === 'rejected');
        if (failures.length > 0) {
            console.error(`${failures.length} restoration tasks failed`);
            // Continue with partial recovery
        }
        
        return {
            total: restoreTasks.length,
            successful: results.filter(r => r.status === 'fulfilled').length,
            failed: failures.length
        };
    }
}
```

### Automated Recovery Testing
```javascript
class RecoveryTesting {
    constructor() {
        this.testSchedule = '0 0 * * 0'; // Weekly Sunday midnight
        this.testScenarios = [
            'database_failure',
            'node_failure',
            'network_partition',
            'data_corruption',
            'ransomware_attack'
        ];
    }
    
    async runRecoveryTest(scenario) {
        console.log(`Starting recovery test: ${scenario}`);
        
        const test = {
            id: crypto.randomUUID(),
            scenario,
            startTime: Date.now(),
            environment: 'test',
            results: {}
        };
        
        try {
            // Create test environment
            const testEnv = await this.createTestEnvironment();
            
            // Inject failure
            await this.injectFailure(testEnv, scenario);
            
            // Execute recovery
            const recoveryStart = Date.now();
            await this.executeRecovery(testEnv, scenario);
            const recoveryTime = Date.now() - recoveryStart;
            
            // Verify recovery
            const verification = await this.verifyRecovery(testEnv);
            
            test.results = {
                recoveryTime,
                dataIntegrity: verification.dataIntegrity,
                serviceAvailability: verification.serviceAvailability,
                performanceImpact: verification.performanceImpact
            };
            
            // Check compliance
            test.rtoCompliant = recoveryTime <= this.rto;
            test.rpoCompliant = verification.dataLoss <= this.rpo;
            
            test.success = test.rtoCompliant && test.rpoCompliant;
            
        } catch (error) {
            test.error = error.message;
            test.success = false;
        } finally {
            // Cleanup test environment
            await this.cleanupTestEnvironment(testEnv);
            
            // Document results
            await this.documentTestResults(test);
        }
        
        return test;
    }
    
    async runChaosEngineering() {
        // Continuous recovery testing in production
        const chaos = new ChaosMonkey({
            enabled: process.env.CHAOS_ENABLED === 'true',
            probability: 0.01, // 1% chance per hour
            scenarios: [
                {
                    name: 'kill_process',
                    weight: 0.5,
                    action: () => process.exit(1)
                },
                {
                    name: 'network_latency',
                    weight: 0.3,
                    action: () => this.injectNetworkLatency(1000)
                },
                {
                    name: 'disk_pressure',
                    weight: 0.2,
                    action: () => this.fillDisk(0.9)
                }
            ]
        });
        
        chaos.start();
    }
}
```

## Backup Verification

### Integrity Verification
```javascript
class BackupVerification {
    constructor() {
        this.verificationSchedule = '0 4 * * *'; // Daily at 4 AM
    }
    
    async verifyBackup(backupId) {
        console.log(`Verifying backup ${backupId}`);
        
        const verification = {
            backupId,
            timestamp: Date.now(),
            checks: {}
        };
        
        try {
            // Check 1: File integrity
            verification.checks.integrity = await this.verifyIntegrity(backupId);
            
            // Check 2: Restore test
            verification.checks.restore = await this.testRestore(backupId);
            
            // Check 3: Data validation
            verification.checks.data = await this.validateData(backupId);
            
            // Check 4: Completeness
            verification.checks.completeness = await this.verifyCompleteness(backupId);
            
            verification.valid = Object.values(verification.checks)
                .every(check => check.passed);
            
            if (!verification.valid) {
                await this.handleInvalidBackup(backupId, verification);
            }
            
            return verification;
            
        } catch (error) {
            verification.error = error.message;
            verification.valid = false;
            throw error;
        } finally {
            await this.recordVerification(verification);
        }
    }
    
    async verifyIntegrity(backupId) {
        const metadata = await this.getBackupMetadata(backupId);
        const file = await this.downloadBackup(backupId);
        
        // Verify checksum
        const calculatedChecksum = await this.calculateChecksum(file);
        const checksumMatch = calculatedChecksum === metadata.checksum;
        
        // Verify encryption
        const encryptionValid = await this.verifyEncryption(file);
        
        // Verify compression
        const compressionValid = await this.verifyCompression(file);
        
        return {
            passed: checksumMatch && encryptionValid && compressionValid,
            checksum: {
                expected: metadata.checksum,
                actual: calculatedChecksum,
                match: checksumMatch
            },
            encryption: encryptionValid,
            compression: compressionValid
        };
    }
    
    async testRestore(backupId) {
        // Create isolated test environment
        const testEnv = await this.createTestEnvironment();
        
        try {
            // Restore backup
            const restoreStart = Date.now();
            await this.restoreBackup(backupId, testEnv);
            const restoreTime = Date.now() - restoreStart;
            
            // Verify restored data
            const dataValid = await this.verifyRestoredData(testEnv);
            
            // Test functionality
            const functionalityValid = await this.testFunctionality(testEnv);
            
            return {
                passed: dataValid && functionalityValid,
                restoreTime,
                dataValid,
                functionalityValid
            };
            
        } finally {
            await this.destroyTestEnvironment(testEnv);
        }
    }
}
```

## Backup Storage

### Multi-Cloud Storage Strategy
```javascript
class MultiCloudBackupStorage {
    constructor() {
        this.providers = {
            primary: new S3Storage({
                region: 'us-east-1',
                bucket: 'fabstir-backups-primary'
            }),
            secondary: new GCSStorage({
                project: 'fabstir-backup',
                bucket: 'fabstir-backups-secondary'
            }),
            tertiary: new AzureStorage({
                account: 'fabstirbackups',
                container: 'backups'
            })
        };
    }
    
    async storeBackup(backup) {
        const results = {
            stored: [],
            failed: []
        };
        
        // Store in all providers
        for (const [name, provider] of Object.entries(this.providers)) {
            try {
                const location = await provider.store(backup);
                results.stored.push({
                    provider: name,
                    location,
                    timestamp: Date.now()
                });
            } catch (error) {
                console.error(`Failed to store in ${name}:`, error);
                results.failed.push({
                    provider: name,
                    error: error.message
                });
            }
        }
        
        // Ensure at least 2 successful stores
        if (results.stored.length < 2) {
            throw new Error('Insufficient backup redundancy');
        }
        
        return results;
    }
    
    async retrieveBackup(backupId) {
        // Try providers in order
        for (const [name, provider] of Object.entries(this.providers)) {
            try {
                console.log(`Attempting to retrieve from ${name}`);
                const backup = await provider.retrieve(backupId);
                
                // Verify backup
                if (await this.verifyBackup(backup)) {
                    return backup;
                }
            } catch (error) {
                console.error(`Failed to retrieve from ${name}:`, error);
                continue;
            }
        }
        
        throw new Error('Unable to retrieve backup from any provider');
    }
    
    async syncProviders() {
        // Ensure all providers have all backups
        const inventories = {};
        
        // Get inventory from each provider
        for (const [name, provider] of Object.entries(this.providers)) {
            inventories[name] = await provider.listBackups();
        }
        
        // Find missing backups
        const allBackups = new Set();
        for (const inventory of Object.values(inventories)) {
            inventory.forEach(backup => allBackups.add(backup.id));
        }
        
        // Sync missing backups
        for (const backupId of allBackups) {
            for (const [name, provider] of Object.entries(this.providers)) {
                if (!inventories[name].some(b => b.id === backupId)) {
                    console.log(`Syncing ${backupId} to ${name}`);
                    await this.syncBackup(backupId, name);
                }
            }
        }
    }
}
```

## Recovery Checklist

### Pre-Disaster Preparation
- [ ] Backup strategy documented
- [ ] Automated backups configured
- [ ] Backup verification scheduled
- [ ] Recovery procedures tested
- [ ] DR site prepared
- [ ] Team trained on procedures

### During Disaster
- [ ] Assess damage scope
- [ ] Activate incident response
- [ ] Notify stakeholders
- [ ] Begin recovery procedures
- [ ] Document all actions
- [ ] Monitor progress

### Post-Recovery
- [ ] Verify data integrity
- [ ] Confirm service restoration
- [ ] Calculate data loss
- [ ] Document lessons learned
- [ ] Update procedures
- [ ] Schedule follow-up review

## Anti-Patterns to Avoid

### ❌ Backup Mistakes
```javascript
// No encryption
fs.copyFileSync('database.db', '/backup/database.db');

// No verification
await backup();
console.log('Backup complete'); // But is it valid?

// Single location
await s3.upload(backup); // What if S3 fails?

// No automation
// "We'll backup manually when we remember"

// No testing
// "The backups should work when we need them"
```

### ✅ Backup Best Practices
```javascript
// Encrypted backups
const encrypted = await encrypt(data, key);
await storeSecurely(encrypted);

// Verify every backup
const backup = await createBackup();
const valid = await verifyBackup(backup);
if (!valid) throw new Error('Invalid backup');

// Multiple locations
await Promise.all([
    s3.upload(backup),
    gcs.upload(backup),
    azure.upload(backup)
]);

// Automated backups
cron.schedule('0 2 * * *', performBackup);

// Regular testing
cron.schedule('0 0 * * 0', testRecovery);
```

## Backup Tools

### Essential Tools
- **Restic**: Encrypted, deduplicated backups
- **Borg**: Space-efficient backup
- **Rclone**: Multi-cloud sync
- **pgBackRest**: PostgreSQL backup
- **Velero**: Kubernetes backup

### Backup Scripts
```bash
#!/bin/bash
# Automated backup script

# Set variables
BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Database backup
pg_dump -h localhost -U postgres fabstir | \
  gzip | \
  openssl enc -aes-256-cbc -salt -pass pass:$BACKUP_KEY | \
  aws s3 cp - s3://backups/postgres_${DATE}.sql.gz.enc

# File backup
restic -r s3:s3.amazonaws.com/fabstir-backups backup \
  /var/lib/fabstir \
  --exclude="*.tmp" \
  --tag automated

# Cleanup old backups
restic -r s3:s3.amazonaws.com/fabstir-backups forget \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12 \
  --prune

# Verify latest backup
restic -r s3:s3.amazonaws.com/fabstir-backups check
```

## Next Steps

1. Create [Incident Response](incident-response.md) procedures
2. Review [Risk Management](../economics/risk-management.md) strategies
3. Implement [Pricing Strategies](../economics/pricing-strategies.md)
4. Study [Staking Economics](../economics/staking-economics.md)

## Additional Resources

- [Backup and Recovery Best Practices](https://www.postgresql.org/docs/current/backup.html)
- [Disaster Recovery Planning Guide](https://www.cisa.gov/sites/default/files/publications/disaster-recovery-plan-guide-508.pdf)
- [3-2-1 Backup Strategy](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/)
- [Chaos Engineering Principles](https://principlesofchaos.org/)

---

Remember: **Hope is not a backup strategy.** Regular testing and verification ensure your backups work when you need them most.