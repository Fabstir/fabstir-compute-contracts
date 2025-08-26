const { ethers } = require('ethers');
const fs = require('fs');

async function main() {
    console.log('===================================');
    console.log('Verifying S5 Contract Deployments');
    console.log('===================================\n');

    const RPC_URL = 'https://sepolia.base.org';
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    
    // Deployed contracts
    const contracts = [
        { address: '0x2d599218CAf48B4204A7C459c56f485688D4d527', name: 'First deployment' },
        { address: '0xFB7Ec1170194343C21d189Be525520E043b0d8d6', name: 'Second deployment' }
    ];
    
    // Load ABI
    const jobMarketplaceArtifact = JSON.parse(
        fs.readFileSync('./out/JobMarketplaceFABWithS5.sol/JobMarketplaceFABWithS5.json', 'utf8')
    );
    
    for (const contractInfo of contracts) {
        console.log(`\nChecking ${contractInfo.name}: ${contractInfo.address}`);
        console.log('-------------------------------------------');
        
        const contract = new ethers.Contract(contractInfo.address, jobMarketplaceArtifact.abi, provider);
        
        try {
            // Check bytecode
            const code = await provider.getCode(contractInfo.address);
            console.log('✓ Contract deployed:', code.length > 2 ? 'Yes' : 'No');
            
            if (code.length > 2) {
                // Check configuration
                const nodeRegistry = await contract.nodeRegistry();
                const hostEarnings = await contract.hostEarnings();
                const paymentEscrow = await contract.paymentEscrow();
                const usdcAddress = await contract.usdcAddress();
                
                console.log('Configuration:');
                console.log('  NodeRegistry:', nodeRegistry);
                console.log('  HostEarnings:', hostEarnings);
                console.log('  PaymentEscrow:', paymentEscrow);
                console.log('  USDC:', usdcAddress);
                
                // Test getJob function
                try {
                    const job = await contract.getJob(1);
                    console.log('  getJob(1) works: ✓');
                } catch (e) {
                    console.log('  getJob(1): No job or error');
                }
            }
        } catch (error) {
            console.log('Error checking contract:', error.message);
        }
    }
    
    console.log('\n===================================');
    console.log('Verification Complete');
    console.log('===================================\n');
    
    // Return the best configured contract
    return '0xFB7Ec1170194343C21d189Be525520E043b0d8d6'; // Second deployment seems more configured
}

main()
    .then((address) => {
        console.log('Recommended contract:', address);
        process.exit(0);
    })
    .catch((error) => {
        console.error('Verification failed:', error);
        process.exit(1);
    });