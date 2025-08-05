# Key Management Best Practices

This guide covers secure management of private keys and wallets for Fabstir platform operations.

## Why It Matters

Poor key management is the #1 cause of crypto losses:
- **$3.8 billion** lost to poor key management in 2023
- **90% of hacks** involve compromised private keys
- **Irreversible losses** - no undo button in blockchain
- **Instant theft** - automated bots drain wallets in seconds

## Key Management Hierarchy

### Recommended Key Structure
```
Treasury (Cold Storage)
├── Multi-sig Hardware Wallet (3-of-5)
│   └── Used for: Large stakes, treasury funds
│
Operations (Warm Storage)  
├── Hardware Wallet with API
│   └── Used for: Daily operations, node stakes
│
Hot Wallets (Automated)
├── Isolated VM/Container Keys
│   └── Used for: Job processing, small payments
│
Development (Never Production)
└── Test keys only
```

## Hardware Wallet Best Practices

### Setup and Configuration
```javascript
// ❌ BAD: Software wallet for production
const wallet = new ethers.Wallet(privateKey);

// ✅ GOOD: Hardware wallet integration
import { LedgerSigner } from "@ethersproject/hardware-wallets";

class SecureWalletManager {
    async connectHardwareWallet() {
        // Ledger integration
        const ledger = new LedgerSigner(provider, "m/44'/60'/0'/0/0");
        
        // Verify connection
        const address = await ledger.getAddress();
        console.log("Connected to hardware wallet:", address);
        
        // Confirm on device
        const message = "Confirm wallet connection for Fabstir";
        const signature = await ledger.signMessage(message);
        
        return ledger;
    }
    
    async executeSecureTransaction(signer, transaction) {
        // Display on hardware wallet
        console.log("Review transaction on hardware wallet:");
        console.log("- To:", transaction.to);
        console.log("- Value:", ethers.formatEther(transaction.value));
        console.log("- Data:", transaction.data);
        
        // User confirms on device
        const tx = await signer.sendTransaction(transaction);
        return tx;
    }
}
```

### Multi-Signature Setup
```javascript
import { GnosisSafe } from "@gnosis.pm/safe-core-sdk";

class MultiSigManager {
    async setupMultiSig(owners, threshold) {
        // Deploy Safe with multiple owners
        const safeFactory = await SafeFactory.create({ ethAdapter });
        
        const safeAccountConfig = {
            owners: owners,
            threshold: threshold, // e.g., 3 of 5
            fallbackHandler: this.getFallbackHandler()
        };
        
        const safe = await safeFactory.deploySafe({ safeAccountConfig });
        console.log("Multi-sig deployed:", safe.getAddress());
        
        return safe;
    }
    
    async proposeTransaction(safe, transaction) {
        // Create transaction
        const safeTransaction = await safe.createTransaction({
            to: transaction.to,
            data: transaction.data,
            value: transaction.value
        });
        
        // Sign with first owner
        const hash = await safe.signTransactionHash(safeTransaction);
        
        // Notify other owners
        await this.notifyOwners(safe, safeTransaction, hash);
        
        return safeTransaction;
    }
    
    async executeMultiSigTransaction(safe, safeTransaction, signatures) {
        // Verify we have threshold signatures
        if (signatures.length < safe.getThreshold()) {
            throw new Error("Insufficient signatures");
        }
        
        // Execute transaction
        const executeTx = await safe.executeTransaction(safeTransaction);
        return executeTx;
    }
}
```

## Hot Wallet Security

### Isolated Key Management
```javascript
class IsolatedKeyManager {
    constructor(config) {
        this.vaultUrl = config.vaultUrl;
        this.namespace = config.namespace;
        this.cache = new Map();
    }
    
    async getOperationalKey(purpose) {
        // Never store keys in memory longer than needed
        const cacheKey = `${this.namespace}:${purpose}`;
        
        // Check if we have a recent key
        const cached = this.cache.get(cacheKey);
        if (cached && cached.expiry > Date.now()) {
            return cached.signer;
        }
        
        // Fetch from secure vault
        const key = await this.fetchFromVault(purpose);
        const signer = new ethers.Wallet(key.privateKey);
        
        // Cache with short TTL
        this.cache.set(cacheKey, {
            signer,
            expiry: Date.now() + 300000 // 5 minutes
        });
        
        // Schedule cleanup
        setTimeout(() => {
            this.cache.delete(cacheKey);
            key.privateKey = null; // Clear from memory
        }, 300000);
        
        return signer;
    }
    
    async fetchFromVault(purpose) {
        // Use HashiCorp Vault or AWS KMS
        const response = await fetch(`${this.vaultUrl}/v1/secret/data/${purpose}`, {
            headers: {
                'X-Vault-Token': process.env.VAULT_TOKEN
            }
        });
        
        const data = await response.json();
        return {
            privateKey: data.data.data.privateKey,
            address: data.data.data.address,
            limits: data.data.data.limits
        };
    }
    
    async rotateKey(purpose) {
        // Generate new key
        const newWallet = ethers.Wallet.createRandom();
        
        // Store in vault
        await this.storeInVault(purpose, {
            privateKey: newWallet.privateKey,
            address: newWallet.address,
            rotatedAt: Date.now()
        });
        
        // Clear cache
        this.cache.delete(`${this.namespace}:${purpose}`);
        
        return newWallet.address;
    }
}
```

### Key Derivation and Segregation
```javascript
class KeyDerivationManager {
    constructor(masterSeed) {
        // Master seed never leaves secure enclave
        this.masterNode = ethers.HDNodeWallet.fromSeed(masterSeed);
    }
    
    deriveKeyForPurpose(purpose, index = 0) {
        // Deterministic derivation paths for different purposes
        const paths = {
            treasury: "m/44'/60'/0'/0/0",      // Never used in code
            operations: "m/44'/60'/1'/0/",     // For operational funds
            nodes: "m/44'/60'/2'/0/",          // Node-specific keys  
            jobs: "m/44'/60'/3'/0/",           // Job processing
            monitoring: "m/44'/60'/4'/0/"      // Read-only operations
        };
        
        const path = paths[purpose] + index;
        const childNode = this.masterNode.derivePath(path);
        
        return {
            address: childNode.address,
            publicKey: childNode.publicKey,
            // Private key only returned for specific purposes
            privateKey: ['jobs', 'monitoring'].includes(purpose) 
                ? childNode.privateKey 
                : null
        };
    }
    
    generateNodeKeys(nodeCount) {
        const keys = [];
        
        for (let i = 0; i < nodeCount; i++) {
            const key = this.deriveKeyForPurpose('nodes', i);
            keys.push({
                nodeId: i,
                address: key.address,
                purpose: `node-${i}`,
                limits: {
                    dailySpend: ethers.parseEther("1"),
                    maxTransaction: ethers.parseEther("0.1")
                }
            });
        }
        
        return keys;
    }
}
```

## Secure Key Storage

### Environment-Based Security
```javascript
class SecureEnvironment {
    static validateEnvironment() {
        const required = [
            'NODE_ENV',
            'VAULT_URL',
            'KMS_KEY_ID'
        ];
        
        const missing = required.filter(key => !process.env[key]);
        if (missing.length > 0) {
            throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
        }
        
        // Never allow production keys in development
        if (process.env.NODE_ENV === 'development') {
            if (process.env.PRIVATE_KEY?.includes('mainnet')) {
                throw new Error('Production keys detected in development environment!');
            }
        }
    }
    
    static async loadSecureConfig() {
        this.validateEnvironment();
        
        // Load from secure parameter store
        const config = await this.loadFromParameterStore();
        
        // Validate configuration
        this.validateConfig(config);
        
        return config;
    }
    
    static async loadFromParameterStore() {
        // AWS Systems Manager Parameter Store
        const ssm = new AWS.SSM();
        
        const params = await ssm.getParameters({
            Names: [
                '/fabstir/prod/vault-token',
                '/fabstir/prod/kms-key',
                '/fabstir/prod/multisig-address'
            ],
            WithDecryption: true
        }).promise();
        
        return params.Parameters.reduce((config, param) => {
            const key = param.Name.split('/').pop();
            config[key] = param.Value;
            return config;
        }, {});
    }
}
```

### Key Encryption at Rest
```javascript
import { createCipheriv, createDecipheriv, randomBytes, scrypt } from 'crypto';

class KeyEncryption {
    static async encryptKey(privateKey, password) {
        // Derive encryption key from password
        const salt = randomBytes(16);
        const key = await this.deriveKey(password, salt);
        
        // Encrypt private key
        const iv = randomBytes(16);
        const cipher = createCipheriv('aes-256-gcm', key, iv);
        
        const encrypted = Buffer.concat([
            cipher.update(privateKey, 'utf8'),
            cipher.final()
        ]);
        
        const authTag = cipher.getAuthTag();
        
        return {
            encrypted: encrypted.toString('base64'),
            salt: salt.toString('base64'),
            iv: iv.toString('base64'),
            authTag: authTag.toString('base64'),
            algorithm: 'aes-256-gcm',
            iterations: 100000
        };
    }
    
    static async decryptKey(encryptedData, password) {
        // Derive key from password
        const salt = Buffer.from(encryptedData.salt, 'base64');
        const key = await this.deriveKey(password, salt);
        
        // Decrypt
        const decipher = createDecipheriv(
            encryptedData.algorithm,
            key,
            Buffer.from(encryptedData.iv, 'base64')
        );
        
        decipher.setAuthTag(Buffer.from(encryptedData.authTag, 'base64'));
        
        const decrypted = Buffer.concat([
            decipher.update(Buffer.from(encryptedData.encrypted, 'base64')),
            decipher.final()
        ]);
        
        return decrypted.toString('utf8');
    }
    
    static deriveKey(password, salt) {
        return new Promise((resolve, reject) => {
            scrypt(password, salt, 32, { N: 2**14 }, (err, derivedKey) => {
                if (err) reject(err);
                else resolve(derivedKey);
            });
        });
    }
}
```

## Access Control Implementation

### Role-Based Key Access
```javascript
class KeyAccessControl {
    constructor() {
        this.permissions = new Map();
        this.accessLog = [];
    }
    
    defineRole(role, permissions) {
        this.permissions.set(role, {
            purposes: permissions.purposes || [],
            limits: permissions.limits || {},
            requiresMFA: permissions.requiresMFA || false,
            requiresApproval: permissions.requiresApproval || false
        });
    }
    
    async requestKeyAccess(user, purpose, amount = 0) {
        // Check user role
        const userRole = await this.getUserRole(user);
        const rolePerms = this.permissions.get(userRole);
        
        if (!rolePerms) {
            throw new Error(`No permissions defined for role: ${userRole}`);
        }
        
        // Check purpose permission
        if (!rolePerms.purposes.includes(purpose)) {
            throw new Error(`Role ${userRole} cannot access keys for ${purpose}`);
        }
        
        // Check amount limits
        if (amount > 0 && rolePerms.limits[purpose]) {
            if (amount > rolePerms.limits[purpose]) {
                throw new Error(`Amount exceeds limit for ${purpose}`);
            }
        }
        
        // MFA check
        if (rolePerms.requiresMFA) {
            await this.verifyMFA(user);
        }
        
        // Approval check
        if (rolePerms.requiresApproval) {
            await this.requestApproval(user, purpose, amount);
        }
        
        // Log access
        this.logAccess(user, purpose, amount);
        
        return true;
    }
    
    async verifyMFA(user) {
        // Implement 2FA verification
        const token = await this.getMFAToken(user);
        const verified = await this.verifyTOTP(user, token);
        
        if (!verified) {
            throw new Error('MFA verification failed');
        }
    }
    
    logAccess(user, purpose, amount) {
        this.accessLog.push({
            user,
            purpose,
            amount,
            timestamp: Date.now(),
            ip: this.getClientIP(),
            userAgent: this.getUserAgent()
        });
        
        // Alert on suspicious activity
        this.checkSuspiciousActivity(user);
    }
}
```

## Key Rotation Procedures

### Automated Key Rotation
```javascript
class KeyRotationManager {
    constructor(config) {
        this.rotationSchedule = config.rotationSchedule;
        this.gracePeriod = config.gracePeriod || 86400000; // 24 hours
    }
    
    async rotateKeys() {
        console.log('Starting key rotation...');
        
        // 1. Generate new keys
        const newKeys = await this.generateNewKeys();
        
        // 2. Update contracts
        await this.updateContracts(newKeys);
        
        // 3. Distribute to systems
        await this.distributeKeys(newKeys);
        
        // 4. Monitor transition
        await this.monitorTransition(newKeys);
        
        // 5. Revoke old keys
        setTimeout(() => {
            this.revokeOldKeys();
        }, this.gracePeriod);
        
        return newKeys;
    }
    
    async generateNewKeys() {
        const keys = {};
        
        for (const purpose of ['operations', 'nodes', 'jobs']) {
            const wallet = ethers.Wallet.createRandom();
            
            keys[purpose] = {
                address: wallet.address,
                publicKey: wallet.publicKey,
                encryptedPrivateKey: await this.encryptForStorage(wallet.privateKey),
                createdAt: Date.now(),
                expiresAt: Date.now() + this.rotationSchedule[purpose]
            };
        }
        
        return keys;
    }
    
    async updateContracts(newKeys) {
        // Update authorized addresses in smart contracts
        const batch = [];
        
        for (const [purpose, key] of Object.entries(newKeys)) {
            if (purpose === 'operations') {
                batch.push(
                    this.contracts.accessControl.grantRole(
                        OPERATOR_ROLE,
                        key.address
                    )
                );
            }
        }
        
        // Execute batch update
        await this.executeBatchUpdate(batch);
    }
    
    async monitorTransition(newKeys) {
        const monitoring = setInterval(async () => {
            const stats = await this.getTransitionStats();
            
            console.log('Key rotation progress:');
            console.log(`- New keys active: ${stats.newKeyUsage}%`);
            console.log(`- Old keys active: ${stats.oldKeyUsage}%`);
            
            if (stats.newKeyUsage > 95) {
                clearInterval(monitoring);
                console.log('Key rotation successful');
            }
        }, 300000); // Check every 5 minutes
    }
}
```

## Emergency Key Recovery

### Backup and Recovery Strategy
```javascript
class KeyRecoverySystem {
    async setupRecovery(threshold = 3, shares = 5) {
        // Shamir's Secret Sharing
        const secret = await this.getMasterSecret();
        const shares = this.splitSecret(secret, threshold, shares);
        
        // Distribute shares to trustees
        const trustees = await this.selectTrustees(shares.length);
        
        for (let i = 0; i < shares.length; i++) {
            await this.distributeShare(trustees[i], shares[i], i);
        }
        
        // Store recovery metadata
        await this.storeRecoveryMetadata({
            threshold,
            totalShares: shares.length,
            trustees: trustees.map(t => t.id),
            createdAt: Date.now()
        });
    }
    
    async recoverKeys(shares) {
        // Validate shares
        if (shares.length < this.threshold) {
            throw new Error(`Need at least ${this.threshold} shares`);
        }
        
        // Verify share authenticity
        for (const share of shares) {
            await this.verifyShare(share);
        }
        
        // Reconstruct secret
        const secret = this.combineShares(shares);
        
        // Derive keys from secret
        const keys = await this.deriveKeysFromSecret(secret);
        
        // Log recovery event
        await this.logRecoveryEvent(shares);
        
        return keys;
    }
    
    async emergencyKeyRevocation() {
        console.error('EMERGENCY: Revoking all keys');
        
        // 1. Pause all contracts
        await this.pauseAllContracts();
        
        // 2. Revoke all operational keys
        const revokedKeys = await this.revokeAllKeys();
        
        // 3. Deploy emergency multisig
        const emergencyMultisig = await this.deployEmergencyMultisig();
        
        // 4. Transfer control to emergency multisig
        await this.transferControl(emergencyMultisig);
        
        // 5. Notify all stakeholders
        await this.notifyEmergency(revokedKeys);
        
        return {
            revokedKeys,
            emergencyMultisig,
            timestamp: Date.now()
        };
    }
}
```

## Security Checklist

### Initial Setup
- [ ] Hardware wallet purchased from official source
- [ ] Hardware wallet firmware updated
- [ ] Recovery phrase secured in multiple locations
- [ ] Multi-sig wallet deployed and tested
- [ ] Key derivation paths documented
- [ ] Access control roles defined

### Operational Security
- [ ] Keys never stored in plain text
- [ ] Environment variables encrypted
- [ ] Key access logging enabled
- [ ] MFA required for sensitive operations
- [ ] Regular key rotation scheduled
- [ ] Backup procedures tested

### Monitoring
- [ ] Key usage monitoring active
- [ ] Anomaly detection configured
- [ ] Access logs reviewed regularly
- [ ] Failed access attempts alerted
- [ ] Key expiration tracking
- [ ] Compliance reporting automated

## Anti-Patterns to Avoid

### ❌ Never Do This
```javascript
// Hardcoded keys
const PRIVATE_KEY = "0xac09...";

// Keys in version control
const config = {
    privateKey: process.env.PRIVATE_KEY // Still visible in logs
};

// Reusing keys across environments
const key = isProd ? PROD_KEY : PROD_KEY; // Same key!

// Long-lived keys in memory
this.privateKey = wallet.privateKey; // Stays in memory

// Logging keys
console.log(`Using key: ${privateKey}`); // Never log keys!
```

### ✅ Always Do This
```javascript
// Use secure key management
const signer = await keyManager.getSigner('operations');

// Encrypted environment variables
const key = await decrypt(process.env.ENCRYPTED_KEY);

// Separate keys per environment
const key = await getKeyForEnvironment(process.env.NODE_ENV);

// Clear keys after use
const key = await getKey();
try {
    await useKey(key);
} finally {
    key.clear(); // Explicitly clear
}

// Log key metadata only
console.log(`Using key: ${keyAddress} (${keyPurpose})`);
```

## Tools and Services

### Key Management Solutions
- **Hardware Wallets**: Ledger, Trezor, GridPlus
- **Multi-sig**: Gnosis Safe, Argent
- **Cloud HSM**: AWS CloudHSM, Azure Key Vault
- **Key Management**: HashiCorp Vault, Keywhiz
- **Secret Scanning**: TruffleHog, GitGuardian

### Security Tools
```bash
# Scan for exposed keys
trufflehog git https://github.com/yourrepo

# Encrypt files
gpg --encrypt --recipient team@fabstir.com sensitive.json

# Generate secure passwords
openssl rand -base64 32

# Hardware wallet CLI
ledger-live-cli list

# Key rotation script
./scripts/rotate-keys.sh --purpose operations --schedule weekly
```

## Recovery Procedures

### Lost Key Recovery
1. Gather recovery shares from trustees
2. Verify trustee identities
3. Reconstruct master secret
4. Derive operational keys
5. Update all systems
6. Revoke compromised keys
7. Audit access logs

### Compromised Key Response
1. **Immediate**: Revoke key access
2. **Pause**: Stop affected operations
3. **Assess**: Determine exposure scope
4. **Rotate**: Generate new keys
5. **Update**: Deploy new keys
6. **Monitor**: Watch for unauthorized usage
7. **Report**: Document incident

## Next Steps

1. Review [Operational Security](operational-security.md) practices
2. Implement [Monitoring & Alerting](../operations/monitoring-alerting.md)
3. Create [Incident Response](../operations/incident-response.md) plan
4. Set up [Backup & Recovery](../operations/backup-recovery.md)

## Additional Resources

- [NIST Key Management Guidelines](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-57pt1r5.pdf)
- [Ethereum Key Management](https://ethereum.org/en/security/)
- [Hardware Wallet Comparison](https://www.ledger.com/academy/hardware-wallet-comparison)
- [Multi-sig Best Practices](https://blog.gnosis.pm/multisig-best-practices-2e5e1e6b3e60)

---

Remember: **Your keys, your coins. Not your keys, not your coins.** Treat key management as the foundation of your security.