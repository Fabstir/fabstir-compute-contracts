#!/usr/bin/env node

/**
 * Deploy Fresh Test Environment
 * 
 * This script deploys a fresh set of contracts for testing
 * Can be run standalone or integrated into test suites
 * 
 * Usage:
 *   node scripts/deploy-fresh-test.js
 *   npm run deploy:test
 */

const { ethers } = require('ethers');
const fs = require('fs').promises;
const path = require('path');
require('dotenv').config();

// Contract ABIs (minimal for deployment)
const HOST_EARNINGS_ABI = require('../out/HostEarnings.sol/HostEarnings.json').abi;
const HOST_EARNINGS_BYTECODE = require('../out/HostEarnings.sol/HostEarnings.json').bytecode.object;

const PAYMENT_ESCROW_ABI = require('../out/PaymentEscrowWithEarnings.sol/PaymentEscrowWithEarnings.json').abi;
const PAYMENT_ESCROW_BYTECODE = require('../out/PaymentEscrowWithEarnings.sol/PaymentEscrowWithEarnings.json').bytecode.object;

const JOB_MARKETPLACE_ABI = require('../out/JobMarketplaceFABWithEarnings.sol/JobMarketplaceFABWithEarnings.json').abi;
const JOB_MARKETPLACE_BYTECODE = require('../out/JobMarketplaceFABWithEarnings.sol/JobMarketplaceFABWithEarnings.json').bytecode.object;

// Configuration
const CONFIG = {
    // Existing contracts to reuse
    NODE_REGISTRY: '0x87516C13Ea2f99de598665e14cab64E191A0f8c4',
    FAB_TOKEN: '0xC78949004B4EB6dEf2D66e49Cd81231472612D62',
    USDC: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
    TREASURY_MANAGER: '0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078',
    
    // Network configuration
    RPC_URL: process.env.RPC_URL || 'https://sepolia.base.org',
    PRIVATE_KEY: process.env.PRIVATE_KEY,
    
    // Deployment settings
    FEE_BASIS_POINTS: 1000, // 10% platform fee
    GAS_LIMIT: 3000000,
    
    // Output settings
    SAVE_TO_FILE: true,
    UPDATE_ENV: false
};

// Color codes for console output
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

async function deployContract(factory, name, ...args) {
    log(`  Deploying ${name}...`, 'cyan');
    const contract = await factory.deploy(...args);
    await contract.waitForDeployment();
    const address = await contract.getAddress();
    log(`  ✓ ${name} deployed at: ${address}`, 'green');
    return contract;
}

async function main() {
    try {
        log('\n================================================', 'bright');
        log('     FRESH TEST ENVIRONMENT DEPLOYMENT', 'bright');
        log('================================================\n', 'bright');
        
        // Validate environment
        if (!CONFIG.PRIVATE_KEY) {
            throw new Error('PRIVATE_KEY not found in environment variables');
        }
        
        // Setup provider and signer
        const provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
        const signer = new ethers.Wallet(CONFIG.PRIVATE_KEY, provider);
        
        // Get network info
        const network = await provider.getNetwork();
        const balance = await provider.getBalance(signer.address);
        
        log('Deployment Configuration:', 'yellow');
        log(`  Network: ${network.name} (Chain ID: ${network.chainId})`);
        log(`  Deployer: ${signer.address}`);
        log(`  Balance: ${ethers.formatEther(balance)} ETH`);
        log('');
        
        // Check balance
        if (balance < ethers.parseEther('0.01')) {
            throw new Error('Insufficient ETH balance for deployment (need at least 0.01 ETH)');
        }
        
        log('Starting Deployment...', 'yellow');
        log('');
        
        // 1. Deploy HostEarnings
        const HostEarningsFactory = new ethers.ContractFactory(
            HOST_EARNINGS_ABI,
            HOST_EARNINGS_BYTECODE,
            signer
        );
        const hostEarnings = await deployContract(HostEarningsFactory, 'HostEarnings');
        
        // 2. Deploy PaymentEscrowWithEarnings
        const PaymentEscrowFactory = new ethers.ContractFactory(
            PAYMENT_ESCROW_ABI,
            PAYMENT_ESCROW_BYTECODE,
            signer
        );
        const paymentEscrow = await deployContract(
            PaymentEscrowFactory,
            'PaymentEscrowWithEarnings',
            CONFIG.TREASURY_MANAGER,
            CONFIG.FEE_BASIS_POINTS
        );
        
        // 3. Deploy JobMarketplaceFABWithEarnings
        const JobMarketplaceFactory = new ethers.ContractFactory(
            JOB_MARKETPLACE_ABI,
            JOB_MARKETPLACE_BYTECODE,
            signer
        );
        const jobMarketplace = await deployContract(
            JobMarketplaceFactory,
            'JobMarketplaceFABWithEarnings',
            CONFIG.NODE_REGISTRY,
            await hostEarnings.getAddress()
        );
        
        log('');
        log('Configuring Contracts...', 'yellow');
        
        // Configure HostEarnings
        log('  Adding PaymentEscrow as authorized...', 'cyan');
        let tx = await hostEarnings.addAuthorized(await paymentEscrow.getAddress());
        await tx.wait();
        log('  ✓ HostEarnings configured', 'green');
        
        // Configure PaymentEscrow
        log('  Setting JobMarketplace in PaymentEscrow...', 'cyan');
        tx = await paymentEscrow.setJobMarketplace(await jobMarketplace.getAddress());
        await tx.wait();
        log('  ✓ PaymentEscrow configured', 'green');
        
        // Configure JobMarketplace
        log('  Setting PaymentEscrow in JobMarketplace...', 'cyan');
        tx = await jobMarketplace.setPaymentEscrow(await paymentEscrow.getAddress());
        await tx.wait();
        
        log('  Setting USDC address...', 'cyan');
        tx = await jobMarketplace.setUsdcAddress(CONFIG.USDC);
        await tx.wait();
        log('  ✓ JobMarketplace configured', 'green');
        
        // Prepare addresses object
        const addresses = {
            marketplace: await jobMarketplace.getAddress(),
            paymentEscrow: await paymentEscrow.getAddress(),
            hostEarnings: await hostEarnings.getAddress(),
            treasury: CONFIG.TREASURY_MANAGER,
            nodeRegistry: CONFIG.NODE_REGISTRY,
            fab: CONFIG.FAB_TOKEN,
            usdc: CONFIG.USDC,
            deployer: signer.address,
            timestamp: new Date().toISOString(),
            network: network.name,
            chainId: Number(network.chainId)
        };
        
        // Save to file if requested
        if (CONFIG.SAVE_TO_FILE) {
            const deploymentsDir = path.join(__dirname, '..', 'deployments');
            await fs.mkdir(deploymentsDir, { recursive: true });
            
            const filename = path.join(deploymentsDir, 'test-env-latest.json');
            await fs.writeFile(filename, JSON.stringify(addresses, null, 2));
            
            // Also save timestamped version
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const backupFilename = path.join(deploymentsDir, `test-env-${timestamp}.json`);
            await fs.writeFile(backupFilename, JSON.stringify(addresses, null, 2));
            
            log(`\n  Addresses saved to:`, 'green');
            log(`    ${filename}`);
            log(`    ${backupFilename}`);
        }
        
        // Print summary
        log('\n================================================', 'bright');
        log('        DEPLOYMENT SUCCESSFUL! 🚀', 'green');
        log('================================================\n', 'bright');
        
        log('New Contract Addresses:', 'yellow');
        log('------------------------');
        log(`JobMarketplace:   ${addresses.marketplace}`, 'cyan');
        log(`PaymentEscrow:    ${addresses.paymentEscrow}`, 'cyan');
        log(`HostEarnings:     ${addresses.hostEarnings}`, 'cyan');
        
        log('\nExisting Contracts Used:', 'yellow');
        log('-------------------------');
        log(`NodeRegistry:     ${CONFIG.NODE_REGISTRY}`);
        log(`FAB Token:        ${CONFIG.FAB_TOKEN}`);
        log(`USDC:            ${CONFIG.USDC}`);
        log(`TreasuryManager:  ${CONFIG.TREASURY_MANAGER}`);
        
        log('\n================================================', 'bright');
        log('  UPDATE YOUR CLIENT WITH THESE ADDRESSES!', 'yellow');
        log('================================================\n', 'bright');
        
        // Export commands for easy copying
        log('Environment Variables:', 'yellow');
        log('----------------------');
        log(`export JOB_MARKETPLACE_FAB="${addresses.marketplace}"`);
        log(`export PAYMENT_ESCROW="${addresses.paymentEscrow}"`);
        log(`export HOST_EARNINGS="${addresses.hostEarnings}"`);
        
        log('\nClient Configuration:', 'yellow');
        log('---------------------');
        log('```javascript');
        log('const contracts = {');
        log(`  marketplace: "${addresses.marketplace}",`);
        log(`  paymentEscrow: "${addresses.paymentEscrow}",`);
        log(`  hostEarnings: "${addresses.hostEarnings}",`);
        log(`  nodeRegistry: "${CONFIG.NODE_REGISTRY}",`);
        log(`  usdc: "${CONFIG.USDC}"`);
        log('};');
        log('```');
        
        log('\n✨ Fresh test environment ready!', 'green');
        log('   - Job IDs start from 1', 'green');
        log('   - No existing jobs', 'green');
        log('   - Clean state for testing', 'green');
        
        return addresses;
        
    } catch (error) {
        log(`\n❌ Deployment failed: ${error.message}`, 'red');
        console.error(error);
        process.exit(1);
    }
}

// Execute if run directly
if (require.main === module) {
    main()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

// Export for use in other scripts
module.exports = { deployFreshTestEnvironment: main };