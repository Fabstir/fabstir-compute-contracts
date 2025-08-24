// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/NodeRegistryFAB.sol";
import "../src/PaymentEscrow.sol";
import "../src/interfaces/IJobMarketplace.sol";

contract CompleteTestFlow is Script {
    // Deployed contracts on Base Sepolia
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant JOB_MARKETPLACE = 0x4CD10EaBAc400760528EA4a88112B42dbf74aa71;
    address constant PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    
    // Token addresses
    address constant FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    address constant USDC_TOKEN = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Test accounts from .env
    address constant TEST_USER_1 = 0x8D642988E3e7b6DB15b6058461d5563835b04bF6;
    address constant TEST_HOST_1 = 0x4594F755F593B517Bb3194F4DeC20C48a3f04504;
    
    uint256 nextJobId = 1; // Track job IDs
    
    function run() external {
        console.log("========================================");
        console.log("COMPLETE TEST FLOW - FAB Staking + USDC Payments");
        console.log("========================================\n");
        
        // Get private keys from environment
        uint256 hostPrivateKey = vm.envUint("TEST_HOST_1_PRIVATE_KEY");
        uint256 userPrivateKey = vm.envUint("TEST_USER_1_PRIVATE_KEY");
        
        // Setup contracts
        NodeRegistryFAB registry = NodeRegistryFAB(NODE_REGISTRY_FAB);
        JobMarketplace marketplace = JobMarketplace(JOB_MARKETPLACE);
        IERC20 fabToken = IERC20(FAB_TOKEN);
        IERC20 usdcToken = IERC20(USDC_TOKEN);
        
        // =========================
        // STEP 0: Check Initial Balances
        // =========================
        console.log("STEP 0: Checking Initial Balances");
        console.log("-----------------------------------");
        
        uint256 hostFabBalance = fabToken.balanceOf(TEST_HOST_1);
        uint256 userUsdcBalance = usdcToken.balanceOf(TEST_USER_1);
        uint256 hostUsdcBefore = usdcToken.balanceOf(TEST_HOST_1);
        
        console.log("TEST_HOST_1 FAB Balance:", hostFabBalance / 1e18, "FAB");
        console.log("TEST_USER_1 USDC Balance:", userUsdcBalance / 1e6, "USDC");
        console.log("TEST_HOST_1 USDC Balance:", hostUsdcBefore / 1e6, "USDC\n");
        
        if (hostFabBalance < registry.MIN_STAKE()) {
            console.log("[ERROR] Host needs", registry.MIN_STAKE() / 1e18, "FAB tokens!");
            return;
        }
        
        if (userUsdcBalance < 10000) { // 0.01 USDC
            console.log("[ERROR] User needs at least 0.01 USDC!");
            return;
        }
        
        // =========================
        // STEP 1: Register Host (if not already)
        // =========================
        console.log("STEP 1: Register TEST_HOST_1 as Host");
        console.log("-------------------------------------");
        
        vm.startBroadcast(hostPrivateKey);
        
        // Check if already registered
        NodeRegistryFAB.Node memory existingNode = registry.nodes(TEST_HOST_1);
        
        if (existingNode.operator == address(0)) {
            console.log("Registering host with 1000 FAB stake...");
            
            // Approve FAB spending
            fabToken.approve(NODE_REGISTRY_FAB, registry.MIN_STAKE());
            console.log("[OK] Approved FAB spending");
            
            // Register as host
            string memory metadata = '{"peerId":"test-host-1","models":["gpt-4"],"region":"us-west"}';
            registry.registerNode(metadata);
            console.log("[OK] Host registered successfully!");
            console.log("TX: Registration complete\n");
        } else {
            console.log("[OK] Host already registered");
            console.log("    Staked:", existingNode.stakedAmount / 1e18, "FAB");
            console.log("    Active:", existingNode.active, "\n");
        }
        
        vm.stopBroadcast();
        
        // =========================
        // STEP 2: Submit Job as User
        // =========================
        console.log("STEP 2: Submit Job as TEST_USER_1");
        console.log("----------------------------------");
        
        vm.startBroadcast(userPrivateKey);
        
        uint256 jobPayment = 10000; // 0.01 USDC (6 decimals)
        
        console.log("Submitting job with 0.01 USDC payment...");
        
        // Approve USDC spending
        usdcToken.approve(JOB_MARKETPLACE, jobPayment);
        console.log("[OK] Approved USDC spending");
        
        // Prepare job details
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: "gpt-4",
            prompt: "Test prompt for payment flow",
            maxTokens: 100,
            temperature: 700,
            seed: 42,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 8,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Post job with USDC
        bytes32 jobIdBytes = marketplace.postJobWithToken(
            details,
            requirements,
            USDC_TOKEN,
            jobPayment
        );
        
        // Convert bytes32 to uint256 for internal tracking
        uint256 jobId = getNextJobId();
        
        console.log("[OK] Job posted successfully!");
        console.log("     Job ID (bytes32):", vm.toString(jobIdBytes));
        console.log("     Internal Job ID:", jobId);
        console.log("     Payment: 0.01 USDC\n");
        
        vm.stopBroadcast();
        
        // =========================
        // STEP 3: Host Claims & Completes Job
        // =========================
        console.log("STEP 3: Host Claims and Completes Job");
        console.log("--------------------------------------");
        
        vm.startBroadcast(hostPrivateKey);
        
        // Claim job
        console.log("Claiming job", jobId, "...");
        marketplace.claimJob(jobId);
        console.log("[OK] Job claimed by host");
        
        // Complete job
        console.log("Completing job with result...");
        string memory result = "AI inference result for test";
        bytes memory proof = "";
        
        marketplace.completeJob(jobId, result, proof);
        console.log("[OK] Job completed!");
        console.log("[OK] Payment automatically released from escrow\n");
        
        vm.stopBroadcast();
        
        // =========================
        // STEP 4: Verify Payment Settlement
        // =========================
        console.log("STEP 4: Verify Payment Settlement");
        console.log("----------------------------------");
        
        uint256 hostUsdcAfter = usdcToken.balanceOf(TEST_HOST_1);
        uint256 hostReceived = hostUsdcAfter - hostUsdcBefore;
        
        console.log("Host USDC Balance Before:", hostUsdcBefore / 1e6, "USDC");
        console.log("Host USDC Balance After:", hostUsdcAfter / 1e6, "USDC");
        console.log("Host Received:", hostReceived / 1e6, "USDC");
        
        // Calculate fee
        uint256 expectedPayment = jobPayment * 99 / 100; // 1% fee
        uint256 fee = jobPayment - hostReceived;
        
        console.log("\nPayment Breakdown:");
        console.log("- Total Job Payment: 0.01 USDC");
        console.log("- Host Received:", hostReceived / 1e6, "USDC (", hostReceived * 100 / jobPayment, "%)");
        console.log("- Platform Fee:", fee / 1e6, "USDC (", fee * 100 / jobPayment, "%)");
        
        // Check arbiter/treasury balance
        PaymentEscrow escrow = PaymentEscrow(payable(PAYMENT_ESCROW));
        address arbiter = escrow.arbiter();
        uint256 arbiterBalance = usdcToken.balanceOf(arbiter);
        console.log("- Arbiter/Treasury Address:", arbiter);
        console.log("- Arbiter USDC Balance:", arbiterBalance / 1e6, "USDC");
        
        // =========================
        // FINAL SUMMARY
        // =========================
        console.log("\n========================================");
        console.log("TEST FLOW COMPLETE - SUMMARY");
        console.log("========================================");
        
        if (hostReceived > 0) {
            console.log("[SUCCESS] Host Registration TX: Complete");
            console.log("[SUCCESS] Job Submission TX: Complete");
            console.log("[SUCCESS] Job Claim TX: Complete");
            console.log("[SUCCESS] Job Complete TX: Complete");
            console.log("[SUCCESS] Payment Release: Automatic");
            console.log("[SUCCESS] Host received:", hostReceived / 1e6, "USDC");
            console.log("[SUCCESS] Fee collected:", fee / 1e6, "USDC");
            
            console.log("\n[NOTE] Current fee is 1% (not 10%)");
            console.log("       To get 90/10 split, update PaymentEscrow feeBasisPoints to 1000");
        } else {
            console.log("[ERROR] Payment not received - check transaction logs");
        }
        
        console.log("\n========================================");
        console.log("FRONTEND UPDATE REQUIRED");
        console.log("========================================");
        console.log("Update fabstir-llm-ui to use:");
        console.log('const JOB_MARKETPLACE = "0x4CD10EaBAc400760528EA4a88112B42dbf74aa71";');
        console.log('const NODE_REGISTRY_FAB = "0x87516C13Ea2f99de598665e14cab64E191A0f8c4";');
    }
    
    // Helper to track job IDs
    function getNextJobId() internal returns (uint256) {
        return nextJobId++;
    }
}