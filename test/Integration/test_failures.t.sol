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

contract TestFailuresMinimal6 is Test {
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
    address public client1;

    // Constants
    uint256 constant STAKE_AMOUNT = 10 ether;
    uint256 constant JOB_PAYMENT = 1 ether;

    function setUp() public {
        owner = address(this);
        node1 = makeAddr("node1");
        client1 = makeAddr("client1");

        // Fund accounts
        vm.deal(node1, 100 ether);
        vm.deal(client1, 100 ether);

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
        jobMarketplace.setGovernance(address(jobMarketplace)); // JobMarketplace acts as its own governance for slashing
        nodeRegistry.setGovernance(address(jobMarketplace)); // NodeRegistry needs JobMarketplace as governance for slashing
        reputationSystem.addAuthorizedContract(address(jobMarketplace));
        proofSystem.grantVerifierRole(address(jobMarketplace));
    }

    // ========== Sybil Attack Prevention Tests ==========

    function test_Failure_DetectSybilNodes() public {
        address controller = makeAddr("controller");
        vm.deal(controller, 1000 ether);

        // Register multiple nodes from same controller
        for (uint i = 0; i < 5; i++) {
            address sybilNode = makeAddr(string.concat("sybil", vm.toString(i)));
            vm.deal(sybilNode, 100 ether);
            
            vm.prank(controller);
            nodeRegistry.registerControlledNode{value: STAKE_AMOUNT}(
                string.concat("sybil", vm.toString(i)),
                sybilNode
            );
        }

        // System should detect and flag sybil behavior
        assertTrue(nodeRegistry.isSuspiciousController(controller));
    }

    function test_Failure_PreventSybilJobClaiming() public {
        address controller = makeAddr("controller");
        vm.deal(controller, 1000 ether);

        // Register sybil nodes
        address sybil1 = makeAddr("sybil1");
        address sybil2 = makeAddr("sybil2");
        vm.deal(sybil1, 100 ether);
        vm.deal(sybil2, 100 ether);

        vm.prank(controller);
        nodeRegistry.registerControlledNode{value: STAKE_AMOUNT}("sybil1", sybil1);
        vm.prank(controller);
        nodeRegistry.registerControlledNode{value: STAKE_AMOUNT}("sybil2", sybil2);

        vm.prank(client1);
        uint256 jobId = _postJob(client1);

        // First sybil claims job
        vm.prank(sybil1);
        jobMarketplace.claimJob(jobId);

        // Mark job as failed
        vm.prank(address(jobMarketplace));
        jobMarketplace.markJobFailed(jobId, "Failed");

        // Second sybil from same controller shouldn't be able to claim
        vm.prank(sybil2);
        vm.expectRevert("Sybil attack detected");
        jobMarketplace.claimJob(jobId);
    }

    // ========== Helper Functions ==========

    function _registerNode(address node) internal {
        if (!nodeRegistry.isNodeActive(node)) {
            vm.prank(node);
            nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("metadata");
        }
    }

    function _postJob(address client) internal returns (uint256) {
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