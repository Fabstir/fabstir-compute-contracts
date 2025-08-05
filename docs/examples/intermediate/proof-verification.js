/**
 * Example: Proof Verification
 * Purpose: Demonstrates EZKL proof generation and verification for AI inference validation
 * Prerequisites:
 *   - EZKL setup (optional for mock mode)
 *   - Understanding of zero-knowledge proofs
 *   - Completed inference jobs
 */

const { ethers } = require('ethers');
const crypto = require('crypto');
const fs = require('fs').promises;
require('dotenv').config({ path: '../.env' });

// Contract ABIs
const PROOF_SYSTEM_ABI = [
    'function submitProof(uint256 jobId, bytes proof, bytes publicInputs) returns (bool)',
    'function verifyProof(bytes proof, bytes publicInputs) view returns (bool)',
    'function getProofStatus(uint256 jobId) view returns (tuple(bool submitted, bool verified, uint256 timestamp, address prover))',
    'function getVerifierAddress(string modelId) view returns (address)',
    'function registerVerifier(string modelId, address verifier)',
    'function challengeProof(uint256 jobId, bytes counterProof)',
    'event ProofSubmitted(uint256 indexed jobId, address indexed prover, bool valid)',
    'event ProofChallenged(uint256 indexed jobId, address indexed challenger)',
    'event VerifierRegistered(string modelId, address verifier)'
];

const JOB_MARKETPLACE_ABI = [
    'function getJob(uint256 jobId) view returns (tuple(uint256 id, address poster, string modelId, uint256 payment, uint256 maxTokens, uint256 deadline, address assignedHost, uint8 status, bytes inputData, bytes outputData, uint256 postedAt, uint256 completedAt))',
    'function completeJobWithProof(uint256 jobId, bytes outputData, bytes proof)'
];

// EZKL Verifier ABI (simplified)
const EZKL_VERIFIER_ABI = [
    'function verify(bytes proof, uint256[] publicSignals) view returns (bool)'
];

// Configuration
const config = {
    rpcUrl: process.env.RPC_URL || 'https://base-mainnet.g.alchemy.com/v2/YOUR_KEY',
    chainId: parseInt(process.env.CHAIN_ID || '8453'),
    proofSystem: process.env.PROOF_SYSTEM || '0x...',
    jobMarketplace: process.env.JOB_MARKETPLACE || '0x...',
    
    // Proof settings
    useMockProofs: true, // Set to false when EZKL is available
    proofGenerationTimeout: 60000, // 1 minute
    
    // Gas settings
    gasLimit: 500000, // Higher for proof verification
    maxFeePerGas: ethers.parseUnits('50', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
};

// Proof generator (mock implementation)
class ProofGenerator {
    constructor(modelId) {
        this.modelId = modelId;
        this.proofCache = new Map();
    }
    
    /**
     * Generate a proof for AI inference
     * In production, this would use EZKL to generate real ZK proofs
     */
    async generateProof(input, output, metadata = {}) {
        console.log('   🔨 Generating proof...');
        
        if (config.useMockProofs) {
            return this.generateMockProof(input, output, metadata);
        }
        
        // Real EZKL implementation would go here
        return this.generateEZKLProof(input, output, metadata);
    }
    
    generateMockProof(input, output, metadata) {
        // Create deterministic mock proof
        const proofData = {
            modelId: this.modelId,
            inputHash: ethers.keccak256(ethers.toUtf8Bytes(input)),
            outputHash: ethers.keccak256(ethers.toUtf8Bytes(output)),
            timestamp: Date.now(),
            metadata
        };
        
        // Simulate proof generation delay
        const delay = Math.random() * 2000 + 1000; // 1-3 seconds
        
        return new Promise(resolve => {
            setTimeout(() => {
                const proof = ethers.hexlify(ethers.toUtf8Bytes(
                    JSON.stringify(proofData)
                ));
                
                const publicInputs = ethers.AbiCoder.defaultAbiCoder().encode(
                    ['bytes32', 'bytes32', 'uint256'],
                    [proofData.inputHash, proofData.outputHash, proofData.timestamp]
                );
                
                resolve({ proof, publicInputs, proofData });
            }, delay);
        });
    }
    
    async generateEZKLProof(input, output, metadata) {
        // This would interact with EZKL CLI or API
        // Example structure:
        /*
        const ezkl = new EZKL({
            model: this.modelId,
            circuit: `./circuits/${this.modelId}.circuit`,
            pk: `./keys/${this.modelId}.pk`
        });
        
        const witness = await ezkl.genWitness(input, output);
        const proof = await ezkl.prove(witness);
        
        return {
            proof: proof.proof,
            publicInputs: proof.publicSignals,
            proofData: { witness, metadata }
        };
        */
        
        throw new Error('Real EZKL proof generation not implemented in this example');
    }
    
    /**
     * Verify a proof locally (before submitting on-chain)
     */
    async verifyProofLocally(proof, publicInputs) {
        if (config.useMockProofs) {
            // Mock verification - check structure
            try {
                const proofData = JSON.parse(ethers.toUtf8String(proof));
                return proofData.modelId === this.modelId;
            } catch {
                return false;
            }
        }
        
        // Real EZKL verification
        // return await ezkl.verify(proof, publicInputs);
        return true;
    }
}

// Proof verifier class
class ProofVerifier {
    constructor(proofSystem, provider) {
        this.proofSystem = proofSystem;
        this.provider = provider;
        this.verifierCache = new Map();
    }
    
    async getVerifier(modelId) {
        if (!this.verifierCache.has(modelId)) {
            const verifierAddress = await this.proofSystem.getVerifierAddress(modelId);
            if (verifierAddress === ethers.ZeroAddress) {
                throw new Error(`No verifier registered for model: ${modelId}`);
            }
            
            const verifier = new ethers.Contract(
                verifierAddress,
                EZKL_VERIFIER_ABI,
                this.provider
            );
            
            this.verifierCache.set(modelId, verifier);
        }
        
        return this.verifierCache.get(modelId);
    }
    
    async verifyOnChain(proof, publicInputs) {
        console.log('   🔍 Verifying proof on-chain...');
        
        try {
            const isValid = await this.proofSystem.verifyProof(proof, publicInputs);
            console.log(`   ${isValid ? '✅' : '❌'} Proof is ${isValid ? 'valid' : 'invalid'}`);
            return isValid;
        } catch (error) {
            console.error('   ❌ Verification failed:', error.message);
            return false;
        }
    }
    
    async getProofDetails(jobId) {
        const status = await this.proofSystem.getProofStatus(jobId);
        
        return {
            submitted: status.submitted,
            verified: status.verified,
            timestamp: status.timestamp,
            prover: status.prover,
            age: status.submitted ? Date.now() / 1000 - Number(status.timestamp) : null
        };
    }
}

// Example: Generate and submit proof for completed job
async function submitJobProof(contracts, jobId, wallet) {
    console.log(`\n🎯 Submitting Proof for Job #${jobId}`);
    
    // 1. Get job details
    const job = await contracts.marketplace.getJob(jobId);
    
    if (job.status !== 2) { // Not completed
        throw new Error('Job is not completed');
    }
    
    if (job.assignedHost.toLowerCase() !== wallet.address.toLowerCase()) {
        throw new Error('You are not the assigned host for this job');
    }
    
    // 2. Decode input and output
    const [input] = ethers.AbiCoder.defaultAbiCoder().decode(
        ['string', 'uint256', 'string'],
        job.inputData
    );
    
    const [output] = ethers.AbiCoder.defaultAbiCoder().decode(
        ['string', 'uint256', 'uint256', 'string'],
        job.outputData
    );
    
    console.log('   Job Details:');
    console.log(`   • Model: ${job.modelId}`);
    console.log(`   • Input: "${input.substring(0, 50)}..."`);
    console.log(`   • Output: "${output.substring(0, 50)}..."`);
    
    // 3. Generate proof
    const generator = new ProofGenerator(job.modelId);
    const { proof, publicInputs, proofData } = await generator.generateProof(
        input,
        output,
        { jobId, model: job.modelId }
    );
    
    console.log(`   • Proof size: ${proof.length} bytes`);
    console.log(`   • Public inputs: ${publicInputs.length} bytes`);
    
    // 4. Verify locally first
    console.log('\n   📝 Local verification...');
    const locallyValid = await generator.verifyProofLocally(proof, publicInputs);
    
    if (!locallyValid) {
        throw new Error('Proof failed local verification');
    }
    console.log('   ✅ Proof valid locally');
    
    // 5. Submit proof on-chain
    console.log('\n   📤 Submitting proof on-chain...');
    const tx = await contracts.proofSystem.submitProof(
        jobId,
        proof,
        publicInputs,
        {
            gasLimit: config.gasLimit,
            maxFeePerGas: config.maxFeePerGas,
            maxPriorityFeePerGas: config.maxPriorityFeePerGas
        }
    );
    
    console.log(`   Transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`   ✅ Proof submitted in block ${receipt.blockNumber}`);
    
    // 6. Verify submission
    const proofStatus = await contracts.proofSystem.getProofStatus(jobId);
    console.log('\n   📊 Proof Status:');
    console.log(`   • Submitted: ${proofStatus.submitted}`);
    console.log(`   • Verified: ${proofStatus.verified}`);
    console.log(`   • Prover: ${proofStatus.prover}`);
    
    return { proof, publicInputs, receipt };
}

// Example: Batch proof verification
async function batchVerifyProofs(contracts, proofs) {
    console.log(`\n🔍 Batch Verification of ${proofs.length} Proofs`);
    
    const verifier = new ProofVerifier(contracts.proofSystem, contracts.proofSystem.provider);
    const results = [];
    
    for (let i = 0; i < proofs.length; i++) {
        const { proof, publicInputs, jobId } = proofs[i];
        console.log(`\n   Proof ${i + 1}/${proofs.length} (Job #${jobId}):`);
        
        try {
            // Check if already verified
            const status = await verifier.getProofDetails(jobId);
            
            if (status.submitted && status.verified) {
                console.log('   ✅ Already verified');
                results.push({ jobId, verified: true, cached: true });
                continue;
            }
            
            // Verify on-chain
            const isValid = await verifier.verifyOnChain(proof, publicInputs);
            results.push({ jobId, verified: isValid, cached: false });
            
        } catch (error) {
            console.log(`   ❌ Error: ${error.message}`);
            results.push({ jobId, verified: false, error: error.message });
        }
    }
    
    // Summary
    console.log('\n   📊 Verification Summary:');
    const verified = results.filter(r => r.verified).length;
    const failed = results.filter(r => !r.verified).length;
    console.log(`   • Verified: ${verified}`);
    console.log(`   • Failed: ${failed}`);
    console.log(`   • Success rate: ${((verified / results.length) * 100).toFixed(1)}%`);
    
    return results;
}

// Example: Challenge invalid proof
async function challengeProof(contracts, jobId, wallet) {
    console.log(`\n⚔️ Challenging Proof for Job #${jobId}`);
    
    // 1. Get proof status
    const status = await contracts.proofSystem.getProofStatus(jobId);
    
    if (!status.submitted) {
        throw new Error('No proof submitted for this job');
    }
    
    console.log('   Current proof status:');
    console.log(`   • Verified: ${status.verified}`);
    console.log(`   • Prover: ${status.prover}`);
    
    // 2. Generate counter-proof (mock)
    console.log('\n   🔨 Generating counter-proof...');
    const job = await contracts.marketplace.getJob(jobId);
    
    // In reality, this would involve proving the original proof is invalid
    const counterProof = ethers.hexlify(ethers.randomBytes(256));
    
    // 3. Submit challenge
    console.log('   📤 Submitting challenge...');
    const tx = await contracts.proofSystem.challengeProof(jobId, counterProof, {
        gasLimit: config.gasLimit,
        maxFeePerGas: config.maxFeePerGas,
        maxPriorityFeePerGas: config.maxPriorityFeePerGas
    });
    
    console.log(`   Transaction: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`   ✅ Challenge submitted`);
    
    return receipt;
}

// Example: Monitor proof events
async function monitorProofEvents(contracts, wallet) {
    console.log('\n📡 Monitoring Proof Events...');
    
    // Set up event listeners
    contracts.proofSystem.on('ProofSubmitted', async (jobId, prover, valid, event) => {
        console.log(`\n🔔 Proof Submitted:`);
        console.log(`   • Job ID: ${jobId}`);
        console.log(`   • Prover: ${prover}`);
        console.log(`   • Valid: ${valid}`);
        
        if (prover.toLowerCase() === wallet.address.toLowerCase()) {
            console.log('   • 🎉 This is your proof!');
        }
    });
    
    contracts.proofSystem.on('ProofChallenged', (jobId, challenger, event) => {
        console.log(`\n⚔️ Proof Challenged:`);
        console.log(`   • Job ID: ${jobId}`);
        console.log(`   • Challenger: ${challenger}`);
    });
    
    contracts.proofSystem.on('VerifierRegistered', (modelId, verifier, event) => {
        console.log(`\n📝 New Verifier Registered:`);
        console.log(`   • Model: ${modelId}`);
        console.log(`   • Verifier: ${verifier}`);
    });
    
    console.log('   Listening for events... (Press Ctrl+C to stop)');
}

// Main function
async function main() {
    try {
        console.log('🔐 Fabstir Proof Verification Example\n');
        
        // 1. Setup
        console.log('1️⃣ Setting up connection...');
        const provider = new ethers.JsonRpcProvider(config.rpcUrl);
        const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
        
        console.log(`   Account: ${wallet.address}`);
        console.log(`   Network: ${config.chainId === 8453 ? 'Base Mainnet' : 'Base Sepolia'}`);
        console.log(`   Mode: ${config.useMockProofs ? 'Mock Proofs' : 'Real EZKL'}`);
        
        // 2. Initialize contracts
        console.log('\n2️⃣ Initializing contracts...');
        const proofSystem = new ethers.Contract(
            config.proofSystem,
            PROOF_SYSTEM_ABI,
            wallet
        );
        
        const marketplace = new ethers.Contract(
            config.jobMarketplace,
            JOB_MARKETPLACE_ABI,
            wallet
        );
        
        const contracts = { proofSystem, marketplace };
        
        // 3. Example: Submit proof for a completed job
        const exampleJobId = 42; // Replace with actual job ID
        try {
            const proofData = await submitJobProof(contracts, exampleJobId, wallet);
            
            // 4. Batch verification example
            const mockProofs = [
                { ...proofData, jobId: exampleJobId },
                // Add more proofs here for batch verification
            ];
            
            await batchVerifyProofs(contracts, mockProofs);
            
        } catch (error) {
            console.log(`\n⚠️  Skipping proof submission: ${error.message}`);
        }
        
        // 5. Check verifier registrations
        console.log('\n3️⃣ Checking registered verifiers...');
        const models = ['gpt-4', 'claude-2', 'llama-2-70b'];
        
        for (const model of models) {
            try {
                const verifier = await proofSystem.getVerifierAddress(model);
                console.log(`   ${model}: ${verifier === ethers.ZeroAddress ? 'Not registered' : verifier}`);
            } catch {
                console.log(`   ${model}: Not registered`);
            }
        }
        
        // 6. Set up monitoring
        await monitorProofEvents(contracts, wallet);
        
        // 7. Summary
        console.log('\n📊 Proof System Summary:');
        console.log('   ✅ Demonstrated proof generation');
        console.log('   ✅ Showed on-chain verification');
        console.log('   ✅ Explained batch verification');
        console.log('   ✅ Set up event monitoring');
        
        console.log('\n💡 Best Practices:');
        console.log('   • Always verify proofs locally before on-chain submission');
        console.log('   • Batch verify when possible to save gas');
        console.log('   • Cache verified proofs to avoid re-verification');
        console.log('   • Monitor proof events for challenges');
        console.log('   • Use appropriate proof systems for different models');
        
        // Keep script running
        await new Promise(() => {});
        
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
    ProofGenerator,
    ProofVerifier,
    submitJobProof,
    batchVerifyProofs
};

/**
 * Expected Output:
 * 
 * 🔐 Fabstir Proof Verification Example
 * 
 * 1️⃣ Setting up connection...
 *    Account: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 *    Network: Base Mainnet
 *    Mode: Mock Proofs
 * 
 * 2️⃣ Initializing contracts...
 * 
 * 🎯 Submitting Proof for Job #42
 *    Job Details:
 *    • Model: gpt-4
 *    • Input: "Explain quantum computing in simple terms..."
 *    • Output: "Quantum computing uses quantum mechanics prin..."
 *    🔨 Generating proof...
 *    • Proof size: 420 bytes
 *    • Public inputs: 128 bytes
 * 
 *    📝 Local verification...
 *    ✅ Proof valid locally
 * 
 *    📤 Submitting proof on-chain...
 *    Transaction: 0xabc123...
 *    ✅ Proof submitted in block 12345690
 * 
 *    📊 Proof Status:
 *    • Submitted: true
 *    • Verified: true
 *    • Prover: 0x742d35Cc6634C0532925a3b844Bc9e7595f6789
 * 
 * 🔍 Batch Verification of 1 Proofs
 * 
 *    Proof 1/1 (Job #42):
 *    ✅ Already verified
 * 
 *    📊 Verification Summary:
 *    • Verified: 1
 *    • Failed: 0
 *    • Success rate: 100.0%
 * 
 * 3️⃣ Checking registered verifiers...
 *    gpt-4: 0x1234...5678
 *    claude-2: 0x9abc...def0
 *    llama-2-70b: Not registered
 * 
 * 📡 Monitoring Proof Events...
 *    Listening for events... (Press Ctrl+C to stop)
 * 
 * 🔔 Proof Submitted:
 *    • Job ID: 43
 *    • Prover: 0x5678...9012
 *    • Valid: true
 * 
 * 📊 Proof System Summary:
 *    ✅ Demonstrated proof generation
 *    ✅ Showed on-chain verification
 *    ✅ Explained batch verification
 *    ✅ Set up event monitoring
 * 
 * 💡 Best Practices:
 *    • Always verify proofs locally before on-chain submission
 *    • Batch verify when possible to save gas
 *    • Cache verified proofs to avoid re-verification
 *    • Monitor proof events for challenges
 *    • Use appropriate proof systems for different models
 */