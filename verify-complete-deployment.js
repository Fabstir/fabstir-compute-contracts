const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
    console.log('===================================');
    console.log('Checking All Deployed Contracts');
    console.log('===================================\n');

    const RPC_URL = 'https://sepolia.base.org';
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    
    // All deployed contracts
    const contracts = {
        // New S5-enabled contracts
        'JobMarketplaceFABWithS5 (Configured)': '0xFB7Ec1170194343C21d189Be525520E043b0d8d6',
        'JobMarketplaceFABWithS5 (Fresh)': '0xfeE935BA04dF7002253fcF2D0799B9c75B45686A',
        
        // New support contracts from latest deployment
        'HostEarnings (Latest)': '0x1D82773725496a5703310956d14159934E7da96A',
        'HostEarnings (Newest)': '0x52FD3EA9CF7f1fCf430E2B408D2607FD1Db58201',
        'PaymentEscrowWithEarnings (Latest)': '0x843570E1aefAA53E21635C68c12b05ec82286ce1',
        
        // Previous earnings system
        'HostEarnings (Old)': '0x4050FaDdd250dB75B0B4242B0748EB8681C72F41',
        'PaymentEscrowWithEarnings (Old)': '0x272Ba93B150301e1FA8B800c781426E4F11583ea',
        
        // Supporting contracts
        'NodeRegistryFAB': '0x87516C13Ea2f99de598665e14cab64E191A0f8c4',
        'USDC': '0x036CbD53842c5426634e7929541eC2318f3dCF7e'
    };
    
    console.log('Checking contract deployment status:\n');
    
    for (const [name, address] of Object.entries(contracts)) {
        const code = await provider.getCode(address);
        const isDeployed = code.length > 2;
        console.log(`${isDeployed ? '✓' : '✗'} ${name}: ${address}`);
    }
    
    console.log('\n===================================');
    console.log('Recommended Configuration');
    console.log('===================================\n');
    
    console.log('Use EITHER of these S5-enabled configurations:\n');
    
    console.log('Option 1 - Fully Configured (uses old support contracts):');
    console.log('  JobMarketplaceFABWithS5: 0xFB7Ec1170194343C21d189Be525520E043b0d8d6');
    console.log('  HostEarnings: 0x4050FaDdd250dB75B0B4242B0748EB8681C72F41');
    console.log('  PaymentEscrow: 0x272Ba93B150301e1FA8B800c781426E4F11583ea');
    console.log('  Status: Ready to use\n');
    
    console.log('Option 2 - Fresh Deployment (partially configured):');
    console.log('  JobMarketplaceFABWithS5: 0xfeE935BA04dF7002253fcF2D0799B9c75B45686A');
    console.log('  HostEarnings: 0x1D82773725496a5703310956d14159934E7da96A');
    console.log('  PaymentEscrow: 0x843570E1aefAA53E21635C68c12b05ec82286ce1');
    console.log('  Status: Needs PaymentEscrow configuration\n');
    
    // Test the configured one
    console.log('Testing Option 1 (Fully Configured)...');
    const jobMarketplaceABI = [
        'function getJob(uint256) view returns (address, uint256, uint8, address, string, string, uint256)',
        'function nodeRegistry() view returns (address)',
        'function hostEarnings() view returns (address)',
        'function paymentEscrow() view returns (address)',
        'function usdcAddress() view returns (address)'
    ];
    
    const marketplace = new ethers.Contract('0xFB7Ec1170194343C21d189Be525520E043b0d8d6', jobMarketplaceABI, provider);
    
    try {
        const nodeRegistry = await marketplace.nodeRegistry();
        const hostEarnings = await marketplace.hostEarnings();
        const paymentEscrow = await marketplace.paymentEscrow();
        const usdc = await marketplace.usdcAddress();
        
        console.log('✓ Configuration verified:');
        console.log(`  - NodeRegistry: ${nodeRegistry}`);
        console.log(`  - HostEarnings: ${hostEarnings}`);
        console.log(`  - PaymentEscrow: ${paymentEscrow}`);
        console.log(`  - USDC: ${usdc}`);
        
        // Test getJob
        const job = await marketplace.getJob(1);
        console.log('✓ getJob(1) works - returns CID fields');
        console.log(`  - promptCID: ${job[4] || '(empty)'}`);
        console.log(`  - responseCID: ${job[5] || '(empty)'}`);
        
    } catch (error) {
        console.log('✗ Configuration error:', error.message);
    }
}

main()
    .then(() => {
        console.log('\n✅ Verification complete!');
        process.exit(0);
    })
    .catch((error) => {
        console.error('Error:', error);
        process.exit(1);
    });