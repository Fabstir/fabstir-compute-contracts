// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/NodeRegistry.sol";
import "../../src/JobMarketplace.sol";
import "../../src/PaymentEscrow.sol";
import "../../src/ReputationSystem.sol";
import "../../src/ProofSystem.sol";
import "../../src/Governance.sol";
import "../../src/GovernanceToken.sol";
import "../../src/interfaces/INodeRegistry.sol";
import "../../src/interfaces/IJobMarketplace.sol";
import "../../src/interfaces/IPaymentEscrow.sol";

contract TestBreakers is Test {
    // Contracts
    NodeRegistry public nodeRegistry;
    JobMarketplace public jobMarketplace;
    PaymentEscrow public paymentEscrow;
    ReputationSystem public reputationSystem;
    ProofSystem public proofSystem;
    Governance public governance;

    // Test users
    address public owner;
    address public admin;
    address public guardian;
    address public node1;
    address public node2;
    address public client1;
    address public attacker;

    // Constants
    uint256 constant STAKE_AMOUNT = 10 ether;
    uint256 constant JOB_PAYMENT = 1 ether;

    // Circuit breaker thresholds
    uint256 constant FAILURE_THRESHOLD = 5;
    uint256 constant SUSPICIOUS_ACTIVITY_THRESHOLD = 10;
    uint256 constant COOLDOWN_PERIOD = 1 hours;

    // Events
    event CircuitBreakerTriggered(string reason, uint256 level);
    event CircuitBreakerReset(address by);
    event EmergencyPause(address by, string reason);
    event EmergencyUnpause(address by);

    function setUp() public {
        owner = address(this);
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        node1 = makeAddr("node1");
        node2 = makeAddr("node2");
        client1 = makeAddr("client1");
        attacker = makeAddr("attacker");

        // Fund accounts
        vm.deal(node1, 100 ether);
        vm.deal(node2, 100 ether);
        vm.deal(client1, 100 ether);
        vm.deal(attacker, 100 ether);

        // Deploy contracts
        nodeRegistry = new NodeRegistry(STAKE_AMOUNT);
        paymentEscrow = new PaymentEscrow(address(this), 250);
        jobMarketplace = new JobMarketplace(address(nodeRegistry));
        reputationSystem = new ReputationSystem(
            address(nodeRegistry),
            address(jobMarketplace),
            address(0) // governance set later
        );
        proofSystem = new ProofSystem(
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem)
        );
        
        // Deploy governance token and governance
        GovernanceToken token = new GovernanceToken("Fabstir", "FAB", 1000000 ether);
        governance = new Governance(
            address(token),
            address(nodeRegistry),
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem),
            address(proofSystem)
        );

        // Setup permissions
        paymentEscrow.setJobMarketplace(address(jobMarketplace));
        jobMarketplace.setReputationSystem(address(reputationSystem));
        jobMarketplace.setGovernance(address(governance));
        reputationSystem.addAuthorizedContract(address(jobMarketplace));
        proofSystem.grantRole(keccak256("VERIFIER_ROLE"), address(jobMarketplace));
    }

    // ========== Emergency Pause Tests ==========

    function test_CircuitBreaker_EmergencyPause() public {
        // Owner can trigger emergency pause
        vm.prank(owner);
        jobMarketplace.emergencyPause("System anomaly detected");

        assertTrue(jobMarketplace.isPaused());

        // Operations should fail when paused
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Test prompt",
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 300,
            requiresProof: false
        });

        vm.prank(client1);
        vm.expectRevert("Contract is paused");
        jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );
    }

    function test_CircuitBreaker_GuardianPause() public {
        // Set guardian role
        vm.prank(owner);
        jobMarketplace.grantRole(keccak256("GUARDIAN_ROLE"), guardian);

        // Guardian can pause
        vm.prank(guardian);
        jobMarketplace.emergencyPause("Guardian intervention");
        assertTrue(jobMarketplace.isPaused());

        // Random user cannot pause
        vm.prank(attacker);
        vm.expectRevert("Not authorized to pause");
        jobMarketplace.emergencyPause("Attack");
    }

    function test_CircuitBreaker_UnpauseWithCooldown() public {
        // Pause the system
        vm.prank(owner);
        jobMarketplace.emergencyPause("Test pause");

        // Cannot unpause immediately
        vm.prank(owner);
        vm.expectRevert("Cooldown period not elapsed");
        jobMarketplace.unpause();

        // Can unpause after cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        vm.prank(owner);
        jobMarketplace.unpause();

        assertFalse(jobMarketplace.isPaused());
    }

    // ========== Automatic Circuit Breakers ==========

    function test_CircuitBreaker_HighFailureRate() public {
        _registerNode(node1);
        _registerNode(node2);

        // Create multiple job failures
        for (uint i = 0; i < FAILURE_THRESHOLD; i++) {
            vm.prank(client1);
            uint256 jobId = _postJob();
            
            vm.prank(node1);
            jobMarketplace.claimJob(jobId);
            
            // Fast forward past deadline
            vm.warp(block.timestamp + 301);
            
            // Mark as failed
            vm.prank(address(jobMarketplace));
            jobMarketplace.markJobFailed(jobId, "Timeout");
        }

        // System should auto-pause after threshold
        assertTrue(jobMarketplace.isPaused());
    }

    function test_CircuitBreaker_RapidJobPosting() public {
        // Attacker tries to spam jobs
        vm.deal(attacker, 100 ether);
        vm.startPrank(attacker);
        
        // First few jobs work
        for (uint i = 0; i < 3; i++) {
            _postJob();
        }
        
        // Rate limiter kicks in
        vm.expectRevert("Rate limit exceeded");
        _postJob();
        
        vm.stopPrank();

        // After cooldown, can post again
        vm.warp(block.timestamp + 1 hours);
        vm.prank(attacker);
        _postJob(); // Should work
    }

    function test_CircuitBreaker_SuspiciousPaymentPatterns() public {
        _registerNode(node1);

        // Create pattern of immediate payment releases (suspicious)
        for (uint i = 0; i < SUSPICIOUS_ACTIVITY_THRESHOLD; i++) {
            // Wait between posts to avoid rate limit
            if (i > 0 && i % 3 == 0) {
                vm.warp(block.timestamp + 61); // Move past rapid post window
            }
            
            vm.prank(client1);
            uint256 jobId = _postJob();
            
            vm.prank(node1);
            jobMarketplace.claimJob(jobId);
            
            vm.prank(node1);
            jobMarketplace.submitResult(jobId, "QmQuickResult", "");
            
            // Immediate release (suspicious)
            vm.prank(client1);
            jobMarketplace.releasePayment(jobId);
        }
        
        // Should trigger circuit breaker
        assertTrue(jobMarketplace.isThrottled());
    }

    // ========== Selective Circuit Breakers ==========

    function test_CircuitBreaker_SelectivePause() public {
        // Register node first
        _registerNode(node1);
        
        // Create job before pause
        vm.prank(client1);
        uint256 jobId = _postJob();
        
        // Pause only job posting, not claiming
        vm.prank(owner);
        jobMarketplace.pauseFunction("postJob");

        // Posting should fail
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Test prompt",
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 300,
            requiresProof: false
        });

        vm.prank(client1);
        vm.expectRevert("Function is paused");
        jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );

        // Claiming should still work
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);
    }

    function test_CircuitBreaker_NodeRegistrationPause() public {
        // Detect registration spam
        for (uint i = 0; i < 10; i++) {
            address spamNode = makeAddr(string.concat("spam", vm.toString(i)));
            vm.deal(spamNode, 100 ether);
            
            vm.prank(spamNode);
            nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("spam_metadata");
        }

        // Should trigger registration pause
        assertTrue(nodeRegistry.isRegistrationPaused());

        // New registrations should fail
        vm.prank(node1);
        vm.expectRevert("Registration is paused");
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("metadata");
    }

    // ========== Multi-Level Circuit Breakers ==========

    function test_CircuitBreaker_WarningLevel() public {
        // Trigger warning level (no pause, just monitoring)
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(attacker);
            _postJob();
            vm.stopPrank();
        }

        // Should not pause but monitor the attacker
        assertFalse(jobMarketplace.isPaused());
        assertTrue(jobMarketplace.isMonitoring(attacker));
    }

    function test_CircuitBreaker_ThrottleLevel() public {
        _registerNode(node1);

        // Create job first
        uint256 jobId = _postJob();
        
        // Claim it normally
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);
        
        // Now set throttle level
        vm.prank(owner);
        jobMarketplace.setCircuitBreakerLevel(1); // Throttle mode

        // Second claim too quickly should fail
        uint256 jobId2 = _postJob();
        
        vm.prank(node1);
        vm.expectRevert("Please wait before next operation");
        jobMarketplace.claimJob(jobId2);

        // After cooldown, should work
        vm.warp(block.timestamp + 5 minutes);
        vm.prank(node1);
        jobMarketplace.claimJob(jobId2);
    }

    // ========== Recovery Mechanisms ==========

    function test_CircuitBreaker_AutoRecovery() public {
        // Trigger circuit breaker
        vm.prank(owner);
        jobMarketplace.emergencyPause("Auto-recovery test");

        // Set auto-recovery
        vm.prank(owner);
        jobMarketplace.enableAutoRecovery(2 hours);

        // Should auto-unpause after period
        vm.warp(block.timestamp + 2 hours + 1);
        
        // Register node and create a job to trigger recovery check
        _registerNode(node1);
        vm.prank(client1);
        uint256 jobId = _postJob();
        
        // The claimJob should trigger recovery check and succeed
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);

        assertFalse(jobMarketplace.isPaused());
    }

    function test_CircuitBreaker_GracefulDegradation() public {
        // First create a job before enabling degraded mode
        _registerNode(node1);
        uint256 jobId = _postJob();
        
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);
        
        // Enable degraded mode
        vm.prank(owner);
        jobMarketplace.enableDegradedMode();

        // Can complete existing jobs
        vm.prank(node1);
        jobMarketplace.submitResult(jobId, "QmResult", "");

        // Cannot create new jobs
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Test prompt",
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 300,
            requiresProof: false
        });

        vm.prank(client1);
        vm.expectRevert("Degraded mode: new jobs disabled");
        jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );
    }

    // ========== Circuit Breaker State Management ==========

    function test_CircuitBreaker_StateTransitions() public {
        // Normal -> Warning
        vm.prank(owner);
        jobMarketplace.setCircuitBreakerLevel(0);
        assertEq(jobMarketplace.getCircuitBreakerLevel(), 0);

        // Warning -> Throttle
        vm.prank(owner);
        jobMarketplace.setCircuitBreakerLevel(1);
        assertEq(jobMarketplace.getCircuitBreakerLevel(), 1);

        // Throttle -> Pause
        vm.prank(owner);
        jobMarketplace.setCircuitBreakerLevel(2);
        assertTrue(jobMarketplace.isPaused());

        // Cannot skip levels going up
        vm.prank(owner);
        jobMarketplace.setCircuitBreakerLevel(0);
        
        vm.expectRevert("Cannot skip circuit breaker levels");
        jobMarketplace.setCircuitBreakerLevel(2);
    }

    function test_CircuitBreaker_MetricsAndMonitoring() public {
        // Operations should update metrics
        _registerNode(node1);
        uint256 jobId = _postJob();
        
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);

        // Get circuit breaker metrics
        (
            uint256 failureCount,
            uint256 successCount,
            uint256 suspiciousActivities,
            uint256 lastIncidentTime
        ) = jobMarketplace.getCircuitBreakerMetrics();

        assertEq(successCount, 2); // Post and claim
        assertEq(failureCount, 0);
        assertEq(suspiciousActivities, 0);
    }

    // ========== Integration with Governance ==========

    function test_CircuitBreaker_GovernanceOverride() public {
        // Pause system
        vm.prank(owner);
        jobMarketplace.emergencyPause("Test");

        // Governance can force unpause
        vm.prank(address(governance));
        jobMarketplace.governanceOverridePause();

        assertFalse(jobMarketplace.isPaused());
    }

    function test_CircuitBreaker_ThresholdAdjustment() public {
        // Only governance can adjust thresholds
        vm.prank(attacker);
        vm.expectRevert("Only governance");
        jobMarketplace.setFailureThreshold(10);

        // Governance can adjust
        vm.prank(address(governance));
        jobMarketplace.setFailureThreshold(10);
        
        assertEq(jobMarketplace.failureThreshold(), 10);
    }

    // ========== Helper Functions ==========

    function _registerNode(address node) internal {
        if (!nodeRegistry.isNodeActive(node)) {
            vm.prank(node);
            nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("metadata");
        }
    }

    function _postJob() internal returns (uint256) {
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Test prompt",
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 300,
            requiresProof: false
        });

        return jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );
    }
}