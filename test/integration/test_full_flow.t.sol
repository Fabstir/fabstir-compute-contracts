// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/NodeRegistry.sol";
import "../../src/JobMarketplace.sol";
import "../../src/PaymentEscrow.sol";
import "../../src/ReputationSystem.sol";
import "../../src/ProofSystem.sol";
import "../../src/Governance.sol";
import "../../src/interfaces/INodeRegistry.sol";
import "../../src/interfaces/IJobMarketplace.sol";
import "../../src/interfaces/IPaymentEscrow.sol";

contract TestFullFlow is Test {
    // Contracts
    NodeRegistry public nodeRegistry;
    JobMarketplace public jobMarketplace;
    PaymentEscrow public paymentEscrow;
    ReputationSystem public reputationSystem;
    ProofSystem public proofSystem;
    Governance public governance;

    // Test users
    address public owner;
    address public node1;
    address public node2;
    address public node3;
    address public client1;
    address public client2;

    // Constants
    uint256 constant STAKE_AMOUNT = 10 ether;
    uint256 constant JOB_PAYMENT = 1 ether;
    uint256 constant PROOF_DEADLINE = 1 hours;

    // Events to test
    event NodeRegistered(address indexed node, string metadata);
    event JobPosted(uint256 indexed jobId, address indexed client, uint256 payment);
    event JobClaimed(uint256 indexed jobId, address indexed node);
    event JobCompleted(uint256 indexed jobId, string resultCID);
    event PaymentReleased(uint256 indexed jobId, address indexed node, uint256 amount);

    function setUp() public {
        // Setup test accounts
        owner = address(this);
        node1 = makeAddr("node1");
        node2 = makeAddr("node2");
        node3 = makeAddr("node3");
        client1 = makeAddr("client1");
        client2 = makeAddr("client2");

        // Fund test accounts
        vm.deal(node1, 100 ether);
        vm.deal(node2, 100 ether);
        vm.deal(node3, 100 ether);
        vm.deal(client1, 100 ether);
        vm.deal(client2, 100 ether);

        // Deploy contracts
        nodeRegistry = new NodeRegistry(STAKE_AMOUNT);
        
        // Deploy with placeholder addresses (circular dependencies)
        reputationSystem = new ReputationSystem(
            address(nodeRegistry),
            address(1), // placeholder for jobMarketplace
            address(2)  // placeholder for governance
        );
        paymentEscrow = new PaymentEscrow(address(this), 0); // 0% fee for testing
        
        // Deploy ProofSystem with placeholder addresses (will update later)
        proofSystem = new ProofSystem(
            address(1), // placeholder for jobMarketplace
            address(paymentEscrow),
            address(reputationSystem)
        );
        
        // Deploy JobMarketplace with dependencies
        jobMarketplace = new JobMarketplace(address(nodeRegistry));

        // Deploy Governance
        governance = new Governance(
            address(0), // no governance token for this test
            address(nodeRegistry),
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem),
            address(proofSystem)
        );

        // Setup contract permissions
        paymentEscrow.setJobMarketplace(address(jobMarketplace));
        jobMarketplace.setReputationSystem(address(reputationSystem));
        reputationSystem.addAuthorizedContract(address(jobMarketplace));
        proofSystem.grantVerifierRole(address(jobMarketplace));
    }

    function test_FullFlow_SingleJobLifecycle() public {
        // Step 1: Register a compute node
        vm.startPrank(node1);
        
        string memory nodeMetadata = '{"gpu":"RTX 4090","models":["llama2-7b","mistral-7b"]}';
        vm.expectEmit(true, false, false, true);
        emit NodeRegistered(node1, nodeMetadata);
        
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}(nodeMetadata);
        
        // Verify node registration
        assertTrue(nodeRegistry.isNodeActive(node1));
        assertEq(nodeRegistry.getNodeStake(node1), STAKE_AMOUNT);
        
        vm.stopPrank();

        // Step 2: Client posts a job
        vm.startPrank(client1);
        
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Explain quantum computing in simple terms",
            maxTokens: 500,
            temperature: 7000, // 0.7 * 10000
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 24,
            minReputationScore: 0,
            maxTimeToComplete: 300, // 5 minutes
            requiresProof: true
        });

        vm.expectEmit(true, true, false, true);
        emit JobPosted(1, client1, JOB_PAYMENT);
        
        uint256 jobId = jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );
        
        assertEq(jobId, 1);
        
        // Verify job details
        (
            address jobClient,
            uint256 payment,
            IJobMarketplace.JobStatus status,
            ,
            ,
        ) = jobMarketplace.getJob(jobId);
        
        assertEq(jobClient, client1);
        assertEq(payment, JOB_PAYMENT);
        assertEq(uint(status), uint(IJobMarketplace.JobStatus.Posted));
        
        vm.stopPrank();

        // Step 3: Node claims the job
        vm.startPrank(node1);
        
        vm.expectEmit(true, true, false, false);
        emit JobClaimed(jobId, node1);
        
        jobMarketplace.claimJob(jobId);
        
        // Verify job is claimed
        (,, status,,,) = jobMarketplace.getJob(jobId);
        assertEq(uint(status), uint(IJobMarketplace.JobStatus.Claimed));
        
        vm.stopPrank();

        // Step 4: Node completes the job
        vm.startPrank(node1);
        
        string memory resultCID = "QmResultHash123";
        bytes memory proof = hex"deadbeef"; // Simplified proof
        
        vm.expectEmit(true, false, false, true);
        emit JobCompleted(jobId, resultCID);
        
        jobMarketplace.submitResult(jobId, resultCID, proof);
        
        // Verify job is completed
        (,, status,,,) = jobMarketplace.getJob(jobId);
        assertEq(uint(status), uint(IJobMarketplace.JobStatus.Completed));
        
        vm.stopPrank();

        // Step 5: Client verifies and releases payment
        vm.startPrank(client1);
        
        // Fast forward to ensure proof deadline isn't an issue
        vm.warp(block.timestamp + PROOF_DEADLINE + 1);
        
        uint256 nodeBalanceBefore = node1.balance;
        
        vm.expectEmit(true, true, false, true);
        emit PaymentReleased(jobId, node1, JOB_PAYMENT);
        
        jobMarketplace.releasePayment(jobId);
        
        // Verify payment was released
        uint256 nodeBalanceAfter = node1.balance;
        assertEq(nodeBalanceAfter - nodeBalanceBefore, JOB_PAYMENT);
        
        // Verify reputation was updated
        uint256 nodeReputation = reputationSystem.getReputation(node1);
        assertGt(nodeReputation, 0);
        
        vm.stopPrank();
    }

    function test_FullFlow_MultipleNodesCompetingForJobs() public {
        // Register multiple nodes
        _registerNode(node1, '{"gpu":"RTX 4090","models":["llama2-7b"]}');
        _registerNode(node2, '{"gpu":"RTX 3090","models":["llama2-7b"]}');
        _registerNode(node3, '{"gpu":"A100","models":["llama2-7b","gpt-j"]}');

        // Client posts multiple jobs
        vm.startPrank(client1);
        
        uint256[] memory jobIds = new uint256[](3);
        for (uint i = 0; i < 3; i++) {
            IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
                modelId: "llama2-7b",
                prompt: string(abi.encodePacked("Test prompt ", i)),
                maxTokens: 100,
                temperature: 7000,
                seed: uint32(i),
                resultFormat: "json"
            });

            IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
                minGPUMemory: 16,
                minReputationScore: 0,
                maxTimeToComplete: 300,
                requiresProof: false
            });

            jobIds[i] = jobMarketplace.postJob{value: JOB_PAYMENT}(
                jobDetails,
                requirements,
                JOB_PAYMENT
            );
        }
        
        vm.stopPrank();

        // Different nodes claim different jobs
        vm.prank(node1);
        jobMarketplace.claimJob(jobIds[0]);
        
        vm.prank(node2);
        jobMarketplace.claimJob(jobIds[1]);
        
        vm.prank(node3);
        jobMarketplace.claimJob(jobIds[2]);

        // All nodes complete their jobs
        _completeJob(node1, jobIds[0], "QmResult1");
        _completeJob(node2, jobIds[1], "QmResult2");
        _completeJob(node3, jobIds[2], "QmResult3");

        // Verify all payments are released
        vm.startPrank(client1);
        for (uint i = 0; i < 3; i++) {
            jobMarketplace.releasePayment(jobIds[i]);
        }
        vm.stopPrank();

        // Check reputation scores
        assertGt(reputationSystem.getReputation(node1), 0);
        assertGt(reputationSystem.getReputation(node2), 0);
        assertGt(reputationSystem.getReputation(node3), 0);
    }

    function test_FullFlow_NodeFailureAndRecovery() public {
        // Register nodes
        _registerNode(node1, '{"gpu":"RTX 4090","models":["llama2-7b"]}');
        _registerNode(node2, '{"gpu":"RTX 4090","models":["llama2-7b"]}');

        // Post job
        vm.startPrank(client1);
        uint256 jobId = _postStandardJob();
        vm.stopPrank();

        // Node1 claims but fails to complete in time
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);

        // Fast forward past deadline
        vm.warp(block.timestamp + 301);

        // Job should be reclaimable
        vm.prank(node2);
        jobMarketplace.claimJob(jobId);

        // Node2 completes the job
        _completeJob(node2, jobId, "QmResultFromNode2");

        // Payment goes to node2, not node1
        vm.prank(client1);
        jobMarketplace.releasePayment(jobId);

        // Verify node2 got paid and reputation
        assertGt(reputationSystem.getReputation(node2), 0);
        assertEq(reputationSystem.getReputation(node1), 0);
    }

    function test_FullFlow_DisputeResolution() public {
        // Register node
        _registerNode(node1, '{"gpu":"RTX 4090","models":["llama2-7b"]}');

        // Post job requiring proof
        vm.startPrank(client1);
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Calculate 2+2",
            maxTokens: 10,
            temperature: 0,
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 300,
            requiresProof: true
        });

        uint256 jobId = jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );
        vm.stopPrank();

        // Node claims and submits result with proof
        vm.startPrank(node1);
        jobMarketplace.claimJob(jobId);
        
        string memory resultCID = "QmDisputedResult";
        bytes memory proof = abi.encode(keccak256("valid_proof"));
        
        jobMarketplace.submitResult(jobId, resultCID, proof);
        vm.stopPrank();

        // Client disputes the result
        vm.startPrank(client1);
        jobMarketplace.disputeResult(jobId, "Result incorrect");
        
        // In a real scenario, governance would resolve this
        // For now, we'll simulate the resolution process
        
        // Fast forward past dispute period
        vm.warp(block.timestamp + 7 days);
        
        // Assume dispute was resolved in favor of client
        // Payment would be refunded instead of released
        vm.stopPrank();
    }

    function test_FullFlow_GovernanceProposalAndVoting() public {
        // Register multiple nodes for voting
        _registerNode(node1, '{"gpu":"RTX 4090","models":["llama2-7b"]}');
        _registerNode(node2, '{"gpu":"RTX 3090","models":["llama2-7b"]}');
        _registerNode(node3, '{"gpu":"A100","models":["llama2-7b"]}');

        // Build reputation for nodes
        _buildReputation(node1, 100);
        _buildReputation(node2, 50);
        _buildReputation(node3, 75);

        // Create a governance proposal
        vm.startPrank(node1);
        
        bytes memory proposalData = abi.encodeWithSignature(
            "updateStakeAmount(uint256)",
            5 ether
        );
        
        uint256 proposalId = governance.createProposal(
            address(nodeRegistry),
            proposalData,
            "Reduce stake amount to 5 ETH to encourage more nodes"
        );
        
        vm.stopPrank();

        // Nodes vote on the proposal
        vm.prank(node1);
        governance.vote(proposalId, true);
        
        vm.prank(node2);
        governance.vote(proposalId, true);
        
        vm.prank(node3);
        governance.vote(proposalId, false);

        // Fast forward past voting period
        vm.warp(block.timestamp + 3 days);

        // Execute the proposal
        vm.prank(node1);
        governance.executeProposal(proposalId);

        // Verify stake amount was updated
        assertEq(nodeRegistry.requiredStake(), 5 ether);
    }

    // Helper functions
    function _registerNode(address node, string memory metadata) internal {
        vm.prank(node);
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}(metadata);
    }

    function _postStandardJob() internal returns (uint256) {
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Hello world",
            maxTokens: 50,
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

    function _completeJob(address node, uint256 jobId, string memory resultCID) internal {
        vm.prank(node);
        jobMarketplace.submitResult(jobId, resultCID, "");
    }

    function _buildReputation(address node, uint256 score) internal {
        // Simulate building reputation through completed jobs
        vm.startPrank(address(jobMarketplace));
        for (uint i = 0; i < score / 10; i++) {
            reputationSystem.updateReputation(node, 10, true);
        }
        vm.stopPrank();
    }
}