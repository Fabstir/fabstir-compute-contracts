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

contract TestGasUsage is Test {
    // Contracts
    NodeRegistry public nodeRegistry;
    JobMarketplace public jobMarketplace;
    PaymentEscrow public paymentEscrow;
    ReputationSystem public reputationSystem;
    ProofSystem public proofSystem;
    Governance public governance;

    // Test users
    address public owner;
    address[] public nodes;
    address[] public clients;

    // Constants
    uint256 constant STAKE_AMOUNT = 10 ether;
    uint256 constant JOB_PAYMENT = 1 ether;
    uint256 constant NUM_NODES = 10;
    uint256 constant NUM_CLIENTS = 5;

    // Gas limits for operations (in gas units)
    uint256 constant MAX_GAS_NODE_REGISTRATION = 300000;
    uint256 constant MAX_GAS_JOB_POSTING = 250000;
    uint256 constant MAX_GAS_JOB_CLAIM = 150000;
    uint256 constant MAX_GAS_JOB_COMPLETE = 200000;
    uint256 constant MAX_GAS_PAYMENT_RELEASE = 150000;
    uint256 constant MAX_GAS_BATCH_OPERATION = 1500000;

    function setUp() public {
        owner = address(this);

        // Create test users
        for (uint i = 0; i < NUM_NODES; i++) {
            address node = makeAddr(string.concat("node", vm.toString(i)));
            nodes.push(node);
            vm.deal(node, 100 ether);
        }

        for (uint i = 0; i < NUM_CLIENTS; i++) {
            address client = makeAddr(string.concat("client", vm.toString(i)));
            clients.push(client);
            vm.deal(client, 100 ether);
        }

        // Deploy contracts
        nodeRegistry = new NodeRegistry(STAKE_AMOUNT);
        reputationSystem = new ReputationSystem(
            address(nodeRegistry),
            address(1), // placeholder for jobMarketplace
            address(2)  // placeholder for governance
        );
        paymentEscrow = new PaymentEscrow(owner, 0);
        proofSystem = new ProofSystem(
            address(1), // placeholder for jobMarketplace
            address(paymentEscrow),
            address(reputationSystem)
        );
        
        jobMarketplace = new JobMarketplace(address(nodeRegistry));

        governance = new Governance(
            address(0), // no governance token
            address(nodeRegistry),
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem),
            address(proofSystem)
        );

        // Setup permissions
        paymentEscrow.setJobMarketplace(address(jobMarketplace));
        jobMarketplace.setReputationSystem(address(reputationSystem));
        reputationSystem.addAuthorizedContract(address(jobMarketplace));
        proofSystem.grantVerifierRole(address(jobMarketplace));
    }

    // ========== Individual Operation Gas Tests ==========

    function test_GasUsage_NodeRegistration() public {
        address node = nodes[0];
        
        vm.prank(node);
        uint256 gasBefore = gasleft();
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("metadata");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for node registration:", gasUsed);
        assertLt(gasUsed, MAX_GAS_NODE_REGISTRATION, "Node registration uses too much gas");
    }

    function test_GasUsage_JobPosting() public {
        _registerNode(nodes[0]);

        IJobMarketplace.JobDetails memory jobDetails = _createJobDetails();
        IJobMarketplace.JobRequirements memory requirements = _createJobRequirements();

        vm.prank(clients[0]);
        uint256 gasBefore = gasleft();
        jobMarketplace.postJob{value: JOB_PAYMENT}(jobDetails, requirements, JOB_PAYMENT);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for job posting:", gasUsed);
        assertLt(gasUsed, MAX_GAS_JOB_POSTING, "Job posting uses too much gas");
    }

    function test_GasUsage_JobClaim() public {
        _registerNode(nodes[0]);
        uint256 jobId = _postJob(clients[0]);

        vm.prank(nodes[0]);
        uint256 gasBefore = gasleft();
        jobMarketplace.claimJob(jobId);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for job claim:", gasUsed);
        assertLt(gasUsed, MAX_GAS_JOB_CLAIM, "Job claim uses too much gas");
    }

    function test_GasUsage_JobCompletion() public {
        _registerNode(nodes[0]);
        uint256 jobId = _postJob(clients[0]);
        
        vm.prank(nodes[0]);
        jobMarketplace.claimJob(jobId);

        vm.prank(nodes[0]);
        uint256 gasBefore = gasleft();
        jobMarketplace.submitResult(jobId, "QmResultHash", "");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for job completion:", gasUsed);
        assertLt(gasUsed, MAX_GAS_JOB_COMPLETE, "Job completion uses too much gas");
    }

    function test_GasUsage_PaymentRelease() public {
        _registerNode(nodes[0]);
        uint256 jobId = _postJob(clients[0]);
        
        vm.prank(nodes[0]);
        jobMarketplace.claimJob(jobId);
        
        vm.prank(nodes[0]);
        jobMarketplace.submitResult(jobId, "QmResultHash", "");

        vm.prank(clients[0]);
        uint256 gasBefore = gasleft();
        jobMarketplace.releasePayment(jobId);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for payment release:", gasUsed);
        assertLt(gasUsed, MAX_GAS_PAYMENT_RELEASE, "Payment release uses too much gas");
    }

    // ========== Batch Operation Gas Tests ==========

    function test_GasUsage_BatchNodeRegistration() public {
        uint256 totalGas = 0;
        
        // Register 5 nodes and measure total gas
        for (uint i = 0; i < 5; i++) {
            vm.prank(nodes[i]);
            uint256 gasBefore = gasleft();
            nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}(
                string.concat("node", vm.toString(i))
            );
            totalGas += gasBefore - gasleft();
        }

        console.log("Total gas for 5 node registrations:", totalGas);
        console.log("Average gas per registration:", totalGas / 5);
        
        // Should be more efficient than 5x single registration
        assertLt(totalGas, MAX_GAS_NODE_REGISTRATION * 5, "Batch registration not efficient");
    }

    function test_GasUsage_BatchJobPosting() public {
        // Register nodes first
        for (uint i = 0; i < 3; i++) {
            _registerNode(nodes[i]);
        }

        // Test actual batch posting if available
        IJobMarketplace.JobDetails[] memory jobDetailsList = new IJobMarketplace.JobDetails[](10);
        IJobMarketplace.JobRequirements[] memory requirementsList = new IJobMarketplace.JobRequirements[](10);
        uint256[] memory payments = new uint256[](10);
        
        for (uint i = 0; i < 10; i++) {
            jobDetailsList[i] = _createJobDetails();
            requirementsList[i] = _createJobRequirements();
            payments[i] = JOB_PAYMENT;
        }
        
        vm.prank(clients[0]);
        uint256 gasBefore = gasleft();
        
        // Use batch function for better gas efficiency
        jobMarketplace.batchPostJobs{value: 10 * JOB_PAYMENT}(
            jobDetailsList,
            requirementsList,
            payments
        );
        
        uint256 totalGas = gasBefore - gasleft();

        console.log("Total gas for 10 job postings (batch):", totalGas);
        console.log("Average gas per job:", totalGas / 10);
        
        assertLt(totalGas, MAX_GAS_BATCH_OPERATION, "Batch job posting uses too much gas");
    }

    function test_GasUsage_BatchPaymentRelease() public {
        // Setup: Register node and create completed jobs
        _registerNode(nodes[0]);
        
        // Create and complete 3 jobs
        uint256 job1 = _postJob(clients[0]);
        vm.prank(nodes[0]);
        jobMarketplace.claimJob(job1);
        vm.prank(nodes[0]);
        jobMarketplace.submitResult(job1, "QmResult1", "");
        
        uint256 job2 = _postJob(clients[0]);
        vm.prank(nodes[0]);
        jobMarketplace.claimJob(job2);
        vm.prank(nodes[0]);
        jobMarketplace.submitResult(job2, "QmResult2", "");
        
        uint256 job3 = _postJob(clients[0]);
        vm.prank(nodes[0]);
        jobMarketplace.claimJob(job3);
        vm.prank(nodes[0]);
        jobMarketplace.submitResult(job3, "QmResult3", "");

        // Measure gas for payment releases
        vm.startPrank(clients[0]);
        uint256 gasBefore = gasleft();
        
        jobMarketplace.releasePayment(job1);
        jobMarketplace.releasePayment(job2);
        jobMarketplace.releasePayment(job3);
        
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();
        
        console.log("Gas used for 3 payment releases:", gasUsed);
        assertLt(gasUsed, MAX_GAS_BATCH_OPERATION, "Multiple payment releases use too much gas");
    }

    // ========== Storage Optimization Tests ==========

    function test_GasUsage_StorageOptimization() public {
        // Test that repeated operations don't increase gas linearly due to storage
        uint256[] memory gasUsages = new uint256[](10);
        
        for (uint i = 0; i < 10; i++) {
            _registerNode(nodes[i % nodes.length]);
            
            uint256 gasBefore = gasleft();
            uint256 jobId = _postJob(clients[0]);
            gasUsages[i] = gasBefore - gasleft();
            
            // Complete the job to clear storage
            vm.prank(nodes[i % nodes.length]);
            jobMarketplace.claimJob(jobId);
            vm.prank(nodes[i % nodes.length]);
            jobMarketplace.submitResult(jobId, "QmResult", "");
            vm.prank(clients[0]);
            jobMarketplace.releasePayment(jobId);
        }

        // Gas usage should not increase significantly
        uint256 firstGas = gasUsages[0];
        uint256 lastGas = gasUsages[9];
        
        console.log("First job posting gas:", firstGas);
        console.log("Last job posting gas:", lastGas);
        
        // Allow for 10% increase due to storage growth
        assertLt(lastGas, firstGas * 110 / 100, "Gas usage increases too much with storage");
    }

    // ========== Complex Operation Gas Tests ==========

    function test_GasUsage_CompleteJobLifecycle() public {
        uint256 totalGas = 0;
        
        // Measure full lifecycle
        vm.prank(nodes[0]);
        uint256 gas1 = gasleft();
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("metadata");
        totalGas += gas1 - gasleft();

        uint256 gas2 = gasleft();
        uint256 jobId = _postJob(clients[0]);
        totalGas += gas2 - gasleft();

        vm.prank(nodes[0]);
        uint256 gas3 = gasleft();
        jobMarketplace.claimJob(jobId);
        totalGas += gas3 - gasleft();

        vm.prank(nodes[0]);
        uint256 gas4 = gasleft();
        jobMarketplace.submitResult(jobId, "QmResult", "");
        totalGas += gas4 - gasleft();

        vm.prank(clients[0]);
        uint256 gas5 = gasleft();
        jobMarketplace.releasePayment(jobId);
        totalGas += gas5 - gasleft();

        console.log("Total gas for complete job lifecycle:", totalGas);
        
        // Should be less than sum of individual limits
        uint256 maxTotal = MAX_GAS_NODE_REGISTRATION + MAX_GAS_JOB_POSTING + 
                          MAX_GAS_JOB_CLAIM + MAX_GAS_JOB_COMPLETE + MAX_GAS_PAYMENT_RELEASE;
        
        assertLt(totalGas, maxTotal * 80 / 100, "Complete lifecycle uses too much gas");
    }

    function test_GasUsage_GovernanceProposal() public {
        // Register nodes with reputation
        for (uint i = 0; i < 3; i++) {
            _registerNode(nodes[i]);
            _buildReputation(nodes[i], 100);
        }

        // Measure governance operations
        vm.prank(nodes[0]);
        uint256 gas1 = gasleft();
        uint256 proposalId = governance.createProposal(
            address(nodeRegistry),
            abi.encodeWithSignature("updateStakeAmount(uint256)", 5 ether),
            "Reduce stake"
        );
        uint256 createGas = gas1 - gasleft();

        // Measure voting
        uint256 totalVoteGas = 0;
        for (uint i = 0; i < 3; i++) {
            vm.prank(nodes[i]);
            uint256 gasB = gasleft();
            governance.vote(proposalId, true);
            totalVoteGas += gasB - gasleft();
        }

        // Fast forward and execute
        vm.warp(block.timestamp + 3 days);
        
        vm.prank(nodes[0]);
        uint256 gas2 = gasleft();
        governance.executeProposal(proposalId);
        uint256 executeGas = gas2 - gasleft();

        console.log("Gas for proposal creation:", createGas);
        console.log("Average gas for voting:", totalVoteGas / 3);
        console.log("Gas for proposal execution:", executeGas);
        
        assertLt(createGas + totalVoteGas + executeGas, MAX_GAS_BATCH_OPERATION, 
                "Governance operations use too much gas");
    }

    // ========== Gas Optimization Techniques ==========

    function test_GasUsage_PackedStorage() public {
        // Test that struct packing is optimized
        // This would drive implementation of efficient storage layout
        
        // Create a job and check storage slots used
        _registerNode(nodes[0]);
        uint256 jobId = _postJob(clients[0]);
        
        // If implementation uses packed storage, operations should be cheaper
        vm.prank(nodes[0]);
        uint256 gasBefore = gasleft();
        jobMarketplace.claimJob(jobId);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Packed storage should result in lower gas
        assertLt(gasUsed, 100000, "Storage not efficiently packed");
    }

    function test_GasUsage_ShortCircuitValidation() public {
        // Test that validation fails fast
        address unregisteredNode = makeAddr("unregistered");
        
        // First create a job so it exists
        _registerNode(nodes[0]);
        uint256 jobId = _postJob(clients[0]);
        
        vm.prank(unregisteredNode);
        uint256 gasBefore = gasleft();
        
        vm.expectRevert("Not a registered host");
        jobMarketplace.claimJob(jobId);
        
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for failed validation:", gasUsed);
        
        // Should fail quickly without expensive operations
        assertLt(gasUsed, 50000, "Validation doesn't fail fast enough");
    }

    // ========== Helper Functions ==========

    function _registerNode(address node) internal {
        if (!nodeRegistry.isNodeActive(node)) {
            vm.prank(node);
            nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("metadata");
        }
    }

    function _createJobDetails() internal pure returns (IJobMarketplace.JobDetails memory) {
        return IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Test prompt",
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });
    }

    function _createJobRequirements() internal pure returns (IJobMarketplace.JobRequirements memory) {
        return IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 300,
            requiresProof: false
        });
    }

    function _postJob(address client) internal returns (uint256) {
        IJobMarketplace.JobDetails memory jobDetails = _createJobDetails();
        IJobMarketplace.JobRequirements memory requirements = _createJobRequirements();
        
        vm.prank(client);
        return jobMarketplace.postJob{value: JOB_PAYMENT}(
            jobDetails,
            requirements,
            JOB_PAYMENT
        );
    }

    function _buildReputation(address node, uint256 score) internal {
        vm.startPrank(address(jobMarketplace));
        for (uint i = 0; i < score / 10; i++) {
            reputationSystem.updateReputation(node, 10, true);
        }
        vm.stopPrank();
    }

    function _hasBatchRelease() internal view returns (bool) {
        // For now, return false since batch release is not implemented
        return false;
    }
}