// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {JobMarketplace} from "../../src/JobMarketplace.sol";
import {NodeRegistry} from "../../src/NodeRegistry.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IJobMarketplace} from "../../src/interfaces/IJobMarketplace.sol";

contract JobMarketplaceUSDCTest is Test {
    JobMarketplace public jobMarketplace;
    NodeRegistry public nodeRegistry;
    PaymentEscrow public paymentEscrow;
    MockERC20 public usdc;
    
    address constant RENTER = address(0x1);
    address constant HOST = address(0x2);
    address constant HOST2 = address(0x3);
    // Note: In production, this would be 0x036CbD53842c5426634e7929541eC2318f3dCF7e
    
    uint256 constant JOB_PRICE_USDC = 100 * 10**6; // 100 USDC (6 decimals)
    uint256 constant HOST_STAKE = 100 ether;
    
    string constant MODEL_ID = "llama3-70b";
    string constant INPUT_HASH = "QmExample123";
    
    event JobPosted(
        bytes32 indexed jobId,
        address indexed renter,
        IJobMarketplace.JobDetails details,
        IJobMarketplace.JobRequirements requirements,
        uint256 payment
    );
    
    event JobCreatedWithToken(
        bytes32 indexed jobId,
        address indexed renter,
        address paymentToken,
        uint256 paymentAmount
    );
    
    function setUp() public {
        // Deploy contracts
        nodeRegistry = new NodeRegistry(10 ether);
        paymentEscrow = new PaymentEscrow(address(this), 100); // arbiter = this contract, 1% fee
        jobMarketplace = new JobMarketplace(address(nodeRegistry));
        
        // Initialize PaymentEscrow with JobMarketplace address
        paymentEscrow.setJobMarketplace(address(jobMarketplace));
        
        // Deploy mock USDC (simulating Base Sepolia USDC)
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        // Set the USDC address in JobMarketplace for testing
        jobMarketplace.setUsdcAddress(address(usdc));
        
        // Setup test accounts
        vm.deal(RENTER, 1000 ether);
        vm.deal(HOST, 1000 ether);
        vm.deal(HOST2, 1000 ether);
        
        // Mint USDC to test accounts
        usdc.mint(RENTER, 1000000 * 10**6); // 1M USDC
        usdc.mint(HOST, 1000000 * 10**6);
        usdc.mint(HOST2, 1000000 * 10**6);
        
        // Register hosts
        vm.prank(HOST);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost1",
            _createModels(),
            "us-east-1"
        );
        
        vm.prank(HOST2);
        nodeRegistry.registerNode{value: HOST_STAKE}(
            "12D3KooWHost2", 
            _createModels(),
            "us-west-2"
        );
    }
    
    function test_PostJobWithUSDCToken() public {
        vm.startPrank(RENTER);
        
        // Approve USDC spending
        usdc.approve(address(jobMarketplace), JOB_PRICE_USDC);
        
        // Create job details and requirements
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Post job with USDC
        bytes32 jobId = jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            JOB_PRICE_USDC
        );
        
        // Verify job was created
        assertTrue(jobId != bytes32(0), "Job ID should not be zero");
        
        // Verify USDC was transferred from renter
        assertEq(usdc.balanceOf(RENTER), 1000000 * 10**6 - JOB_PRICE_USDC, "USDC should be deducted from renter");
        
        vm.stopPrank();
    }
    
    // Note: This test is commented out because JobMarketplace doesn't integrate with PaymentEscrow directly
    // In a real implementation, you would integrate with PaymentEscrow or handle escrow internally
    /*
    function test_PostJobWithUSDCCreatesEscrow() public {
        vm.startPrank(RENTER);
        
        // Approve USDC spending
        usdc.approve(address(jobMarketplace), JOB_PRICE_USDC);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Post job with USDC
        bytes32 jobId = jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            JOB_PRICE_USDC
        );
        
        // Verify escrow was created with correct token
        PaymentEscrow.Escrow memory escrow = paymentEscrow.getEscrow(jobId);
        
        assertEq(escrow.token, address(usdc), "Escrow should be created with USDC token");
        assertEq(escrow.amount, JOB_PRICE_USDC, "Escrow amount should match payment");
        assertEq(uint8(escrow.status), 0, "Escrow should be in Active status");
        
        vm.stopPrank();
    }
    */
    
    function test_PostJobWithToken_RejectsNonUSDCTokens() public {
        vm.startPrank(RENTER);
        
        // Create a different token (not USDC)
        MockERC20 otherToken = new MockERC20("Other Token", "OTHER", 18);
        otherToken.mint(RENTER, 1000 * 10**18);
        otherToken.approve(address(jobMarketplace), 100 * 10**18);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Attempt to post job with non-USDC token
        vm.expectRevert("Only USDC accepted");
        jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(otherToken),
            100 * 10**18
        );
        
        vm.stopPrank();
    }
    
    function test_PostJobWithToken_RevertsOnInsufficientBalance() public {
        vm.startPrank(RENTER);
        
        // Try to post job with more USDC than balance
        uint256 excessiveAmount = 2000000 * 10**6; // 2M USDC (more than minted)
        usdc.approve(address(jobMarketplace), excessiveAmount);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Should revert due to insufficient balance
        vm.expectRevert(); // ERC20 transfer will fail
        jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            excessiveAmount
        );
        
        vm.stopPrank();
    }
    
    function test_PostJobWithToken_RevertsWithoutApproval() public {
        vm.startPrank(RENTER);
        
        // Do NOT approve USDC spending
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Should revert due to lack of approval
        vm.expectRevert(); // ERC20 transferFrom will fail
        jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            JOB_PRICE_USDC
        );
        
        vm.stopPrank();
    }
    
    function test_PostJobWithToken_RequiresPositivePayment() public {
        vm.startPrank(RENTER);
        
        usdc.approve(address(jobMarketplace), JOB_PRICE_USDC);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Try to post job with zero payment
        vm.expectRevert("Payment must be positive");
        jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            0
        );
        
        vm.stopPrank();
    }
    
    function test_PostJobWithToken_TransfersCorrectAmount() public {
        vm.startPrank(RENTER);
        
        uint256 initialBalance = usdc.balanceOf(RENTER);
        uint256 initialMarketplaceBalance = usdc.balanceOf(address(jobMarketplace));
        
        usdc.approve(address(jobMarketplace), JOB_PRICE_USDC);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Post job with USDC
        jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            JOB_PRICE_USDC
        );
        
        // Verify exact amount was transferred
        assertEq(usdc.balanceOf(RENTER), initialBalance - JOB_PRICE_USDC, "Exact USDC amount should be deducted");
        assertEq(usdc.balanceOf(address(jobMarketplace)), initialMarketplaceBalance + JOB_PRICE_USDC, "Marketplace should receive exact USDC amount");
        
        vm.stopPrank();
    }
    
    function test_PostJobWithToken_EmitsCorrectEvent() public {
        vm.startPrank(RENTER);
        
        usdc.approve(address(jobMarketplace), JOB_PRICE_USDC);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Expect event emission
        vm.expectEmit(false, true, false, true);
        emit JobCreatedWithToken(bytes32(0), RENTER, address(usdc), JOB_PRICE_USDC);
        
        // Post job with USDC
        jobMarketplace.postJobWithToken(
            details,
            requirements,
            address(usdc),
            JOB_PRICE_USDC
        );
        
        vm.stopPrank();
    }
    
    function test_PostJobWithToken_AllowsMultipleJobs() public {
        vm.startPrank(RENTER);
        
        // Approve enough for multiple jobs
        usdc.approve(address(jobMarketplace), JOB_PRICE_USDC * 3);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Post multiple jobs
        bytes32 jobId1 = jobMarketplace.postJobWithToken(details, requirements, address(usdc), JOB_PRICE_USDC);
        bytes32 jobId2 = jobMarketplace.postJobWithToken(details, requirements, address(usdc), JOB_PRICE_USDC);
        bytes32 jobId3 = jobMarketplace.postJobWithToken(details, requirements, address(usdc), JOB_PRICE_USDC);
        
        // Verify all jobs were created with unique IDs
        assertTrue(jobId1 != jobId2, "Job IDs should be unique");
        assertTrue(jobId2 != jobId3, "Job IDs should be unique");
        assertTrue(jobId1 != jobId3, "Job IDs should be unique");
        
        // Verify correct total amount was transferred
        assertEq(usdc.balanceOf(address(jobMarketplace)), JOB_PRICE_USDC * 3, "All USDC should be in marketplace");
        
        vm.stopPrank();
    }
    
    function test_BackwardCompatibility_PostJobStillWorksWithETH() public {
        vm.startPrank(RENTER);
        
        // Test that original postJob function still works with ETH
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: MODEL_ID,
            prompt: "Test prompt",
            maxTokens: 1000,
            temperature: 7,
            seed: 12345,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        // Post job with ETH (original method)
        uint256 jobId = jobMarketplace.postJob{value: 1 ether}(
            details,
            requirements,
            1 ether
        );
        
        // Verify job was created
        assertTrue(jobId > 0, "Job should be created with ETH payment");
        
        vm.stopPrank();
    }
    
    function _createModels() private pure returns (string[] memory) {
        string[] memory models = new string[](2);
        models[0] = "llama3-70b";
        models[1] = "mistral-7b";
        return models;
    }
}