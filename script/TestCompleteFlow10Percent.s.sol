// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceFAB.sol";
import "../src/NodeRegistryFAB.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestCompleteFlow10Percent is Script {
    // New deployed contracts
    address constant TREASURY_MANAGER = 0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078;
    address constant PAYMENT_ESCROW = 0xF382E11ebdB90e6cDE55521C659B70eEAc1C9ac3;
    address constant JOB_MARKETPLACE_FAB = 0x870E74D1Fe7D9097deC27651f67422B598b689Cd;
    
    // Existing contracts
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    
    // Test accounts
    address constant HOST = 0x4594F755F593B517Bb3194F4DeC20C48a3f04504;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("TESTING 10% FEE SYSTEM");
        console.log("========================================");
        console.log("Deployer (Renter):", deployer);
        console.log("Host:", HOST);
        
        vm.startBroadcast(deployerPrivateKey);
        
        IERC20 usdc = IERC20(USDC);
        JobMarketplaceFAB marketplace = JobMarketplaceFAB(JOB_MARKETPLACE_FAB);
        
        // Check initial balances
        uint256 initialRenterBalance = usdc.balanceOf(deployer);
        uint256 initialHostBalance = usdc.balanceOf(HOST);
        uint256 initialTreasuryBalance = usdc.balanceOf(TREASURY_MANAGER);
        
        console.log("\nInitial Balances:");
        console.log("  Renter USDC:", initialRenterBalance / 1e6);
        console.log("  Host USDC:", initialHostBalance / 1e6);
        console.log("  Treasury USDC:", initialTreasuryBalance / 1e6);
        
        // Step 1: Post job with 100 USDC
        uint256 paymentAmount = 100 * 1e6; // 100 USDC
        console.log("\n1. Posting job with 100 USDC...");
        
        // Approve USDC
        usdc.approve(JOB_MARKETPLACE_FAB, paymentAmount);
        
        // Prepare job details
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: "gpt-4",
            prompt: "Test 10% fee collection",
            maxTokens: 100,
            temperature: 70,
            seed: 12345,
            resultFormat: "text"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 8,
            maxTimeToComplete: 3600,
            minReputationScore: 0,
            requiresProof: false
        });
        
        bytes32 jobId = marketplace.postJobWithToken(details, requirements, USDC, paymentAmount);
        console.log("   Job posted with ID:", vm.toString(jobId));
        
        // Step 2: Claim job as host
        console.log("\n2. Host claiming job...");
        vm.stopBroadcast();
        
        // Switch to host account
        uint256 hostPrivateKey = 0x2e23e02afe383b50b28be2e042cd42de5f6575dd96c88a93a88e5e003e3eaffc;
        vm.startBroadcast(hostPrivateKey);
        
        marketplace.claimJob(1); // Internal job ID is 1
        console.log("   Job claimed by host");
        
        // Step 3: Complete job
        console.log("\n3. Completing job...");
        marketplace.completeJob(1, "result_hash", "");
        console.log("   Job completed!");
        
        vm.stopBroadcast();
        
        // Check final balances
        vm.startBroadcast(deployerPrivateKey);
        
        uint256 finalRenterBalance = usdc.balanceOf(deployer);
        uint256 finalHostBalance = usdc.balanceOf(HOST);
        uint256 finalTreasuryBalance = usdc.balanceOf(TREASURY_MANAGER);
        uint256 finalEscrowBalance = usdc.balanceOf(PAYMENT_ESCROW);
        
        console.log("\n========================================");
        console.log("FINAL BALANCES & FEE VERIFICATION");
        console.log("========================================");
        
        console.log("\nBalance Changes:");
        console.log("  Renter paid: 100 USDC");
        console.log("  Host balance increased by:", (finalHostBalance - initialHostBalance) / 1e6);
        console.log("  Treasury balance increased by:", (finalTreasuryBalance - initialTreasuryBalance) / 1e6);
        console.log("  Escrow remaining:", finalEscrowBalance / 1e6);
        
        uint256 hostReceived = finalHostBalance - initialHostBalance;
        uint256 treasuryReceived = finalTreasuryBalance - initialTreasuryBalance;
        uint256 renterPaid = initialRenterBalance - finalRenterBalance;
        
        console.log("\nFee Calculation:");
        console.log("  Total Payment: 100 USDC");
        console.log("  Host Received:", hostReceived / 1e6);
        console.log("  Treasury Received (10% fee):", treasuryReceived / 1e6);
        console.log("  Expected: Host=90 USDC, Treasury=10 USDC");
        
        require(hostReceived == 90 * 1e6, "Host should receive 90 USDC");
        require(treasuryReceived == 10 * 1e6, "Treasury should receive 10 USDC");
        
        console.log("\n[SUCCESS] 10% FEE SYSTEM WORKING CORRECTLY!");
        
        vm.stopBroadcast();
    }
}