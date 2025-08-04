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

contract TestValidation is Test {
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
    uint256 constant MAX_STRING_LENGTH = 1000;
    uint256 constant MAX_METADATA_LENGTH = 10000;

    function setUp() public {
        owner = address(this);
        node1 = makeAddr("node1");
        client1 = makeAddr("client1");

        // Fund accounts
        vm.deal(node1, 100 ether);
        vm.deal(client1, 2000 ether);

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
        reputationSystem.addAuthorizedContract(address(jobMarketplace));
        proofSystem.grantRole(keccak256("VERIFIER_ROLE"), address(jobMarketplace));
    }

    // ========== Address Validation ==========

    function test_Validation_ZeroAddressChecks() public {
        // NodeRegistry should not accept zero address governance
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        nodeRegistry.setGovernance(address(0));

        // PaymentEscrow should not accept zero address marketplace
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        paymentEscrow.setJobMarketplace(address(0));

        // ReputationSystem should not accept zero address authorized contract
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        reputationSystem.addAuthorizedContract(address(0));

        // ProofSystem should not grant role to zero address
        vm.prank(owner);
        vm.expectRevert("Invalid address");
        proofSystem.grantVerifierRole(address(0));
    }

    /* Commented out - selfdestruct behavior changed in EIP-6780
    function test_Validation_ContractAddressValidation() public {
        // Deploy a contract with no code (self-destruct scenario)
        EmptyContract empty = new EmptyContract();
        empty.destroy();

        // Should validate contract has code
        vm.prank(owner);
        vm.expectRevert("Not a contract");
        paymentEscrow.setJobMarketplace(address(empty));
    }
    */

    // ========== String Validation ==========

    function test_Validation_EmptyStringInputs() public {
        // Empty metadata in node registration
        vm.prank(node1);
        vm.expectRevert("Empty metadata");
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("");

        // Empty model ID in job
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "", // Empty
            prompt: "Test",
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });

        IJobMarketplace.JobRequirements memory requirements = _createJobRequirements();

        vm.prank(client1);
        vm.expectRevert("Invalid job details");
        jobMarketplace.postJob{value: JOB_PAYMENT}(jobDetails, requirements, JOB_PAYMENT);
    }

    function test_Validation_StringLengthLimits() public {
        // Create oversized metadata
        bytes memory largeMetadata = new bytes(MAX_METADATA_LENGTH + 1);
        for (uint i = 0; i < largeMetadata.length; i++) {
            largeMetadata[i] = bytes1(uint8(65));
        }

        // Node metadata too long
        vm.prank(node1);
        vm.expectRevert("Metadata too long");
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}(string(largeMetadata));

        // Job prompt too long
        _registerNode(node1);
        
        bytes memory largePrompt = new bytes(100001); // Over 100KB
        for (uint i = 0; i < largePrompt.length; i++) {
            largePrompt[i] = bytes1(uint8(65));
        }

        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: string(largePrompt),
            maxTokens: 100,
            temperature: 7000,
            seed: 42,
            resultFormat: "json"
        });

        vm.prank(client1);
        vm.expectRevert("Prompt too large");
        jobMarketplace.postJob{value: JOB_PAYMENT}(jobDetails, _createJobRequirements(), JOB_PAYMENT);
    }

    function test_Validation_SpecialCharacters() public {
        // Test various special characters that could cause issues
        string memory maliciousMetadata = "test\x00null\nbyte\rcarriage";
        
        vm.prank(node1);
        vm.expectRevert("Invalid characters");
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}(maliciousMetadata);
    }

    // ========== Numeric Validation ==========

    function test_Validation_NumericRanges() public {
        _registerNode(node1);

        // Temperature out of range (should be 0-20000 for 0.0-2.0)
        IJobMarketplace.JobDetails memory jobDetails = IJobMarketplace.JobDetails({
            modelId: "llama2-7b",
            prompt: "Test",
            maxTokens: 100,
            temperature: 30000, // Too high
            seed: 42,
            resultFormat: "json"
        });

        vm.prank(client1);
        vm.expectRevert("Temperature out of range");
        jobMarketplace.postJob{value: JOB_PAYMENT}(jobDetails, _createJobRequirements(), JOB_PAYMENT);

        // Max tokens out of range
        jobDetails.temperature = 7000;
        jobDetails.maxTokens = 1000001; // Over 1M

        vm.prank(client1);
        vm.expectRevert("Invalid max tokens");
        jobMarketplace.postJob{value: JOB_PAYMENT}(jobDetails, _createJobRequirements(), JOB_PAYMENT);
    }

    function test_Validation_StakeAmountBounds() public {
        // Try to update stake to zero
        vm.prank(owner);
        vm.expectRevert("Stake must be positive");
        nodeRegistry.updateStakeAmount(0);

        // Try to update stake to unreasonably high amount
        vm.prank(owner);
        vm.expectRevert("Stake too high");
        nodeRegistry.updateStakeAmount(10000 ether);
    }

    function test_Validation_PaymentBounds() public {
        _registerNode(node1);

        // Payment amount doesn't match value sent
        IJobMarketplace.JobDetails memory jobDetails = _createJobDetails();
        IJobMarketplace.JobRequirements memory requirements = _createJobRequirements();

        vm.prank(client1);
        vm.expectRevert("Payment mismatch");
        jobMarketplace.postJob{value: 2 ether}(jobDetails, requirements, JOB_PAYMENT);

        // Payment above maximum
        vm.prank(client1);
        vm.expectRevert("Payment too large");
        jobMarketplace.postJob{value: 1001 ether}(jobDetails, requirements, 1001 ether);
    }

    // ========== Array Validation ==========

    function test_Validation_EmptyArrays() public {
        // Batch operations with empty arrays
        uint256[] memory emptyJobIds = new uint256[](0);
        
        vm.prank(client1);
        vm.expectRevert("Empty array");
        jobMarketplace.batchReleasePayments(emptyJobIds);

        // Batch posting with empty array
        IJobMarketplace.JobDetails[] memory emptyJobs = new IJobMarketplace.JobDetails[](0);
        IJobMarketplace.JobRequirements[] memory emptyReqs = new IJobMarketplace.JobRequirements[](0);
        uint256[] memory emptyPayments = new uint256[](0);

        vm.prank(client1);
        vm.expectRevert("Empty array");
        jobMarketplace.batchPostJobs{value: 0}(emptyJobs, emptyReqs, emptyPayments);
    }

    function test_Validation_ArrayLengthMismatch() public {
        _registerNode(node1);

        // Arrays of different lengths
        IJobMarketplace.JobDetails[] memory jobs = new IJobMarketplace.JobDetails[](2);
        IJobMarketplace.JobRequirements[] memory reqs = new IJobMarketplace.JobRequirements[](3); // Different length
        uint256[] memory payments = new uint256[](2);

        for (uint i = 0; i < 2; i++) {
            jobs[i] = _createJobDetails();
            payments[i] = JOB_PAYMENT;
        }
        for (uint i = 0; i < 3; i++) {
            reqs[i] = _createJobRequirements();
        }

        vm.prank(client1);
        vm.expectRevert("Array length mismatch");
        jobMarketplace.batchPostJobs{value: 2 ether}(jobs, reqs, payments);
    }

    function test_Validation_ArraySizeLimits() public {
        // Try to post too many jobs at once
        uint256 tooMany = 101; // Assuming limit is 100
        IJobMarketplace.JobDetails[] memory jobs = new IJobMarketplace.JobDetails[](tooMany);
        IJobMarketplace.JobRequirements[] memory reqs = new IJobMarketplace.JobRequirements[](tooMany);
        uint256[] memory payments = new uint256[](tooMany);

        for (uint i = 0; i < tooMany; i++) {
            jobs[i] = _createJobDetails();
            reqs[i] = _createJobRequirements();
            payments[i] = JOB_PAYMENT;
        }

        vm.prank(client1);
        vm.expectRevert("Too many jobs");
        jobMarketplace.batchPostJobs{value: tooMany * JOB_PAYMENT}(jobs, reqs, payments);
    }

    // ========== Time Validation ==========

    function test_Validation_DeadlineBounds() public {
        _registerNode(node1);

        // Deadline too short
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 30, // 30 seconds too short
            requiresProof: false
        });

        vm.prank(client1);
        vm.expectRevert("Deadline too short");
        jobMarketplace.postJob{value: JOB_PAYMENT}(_createJobDetails(), requirements, JOB_PAYMENT);

        // Deadline too long
        requirements.maxTimeToComplete = 365 days;

        vm.prank(client1);
        vm.expectRevert("Deadline too long");
        jobMarketplace.postJob{value: JOB_PAYMENT}(_createJobDetails(), requirements, JOB_PAYMENT);
    }

    /* Commented out - createProposalWithDelay doesn't exist yet
    function test_Validation_ProposalTimingBounds() public {
        _registerNode(node1);
        _buildReputation(node1, 100);

        // Try to create proposal with invalid execution delay
        vm.prank(node1);
        vm.expectRevert("Invalid execution delay");
        governance.createProposalWithDelay(
            address(nodeRegistry),
            abi.encodeWithSignature("updateStakeAmount(uint256)", 5 ether),
            "Test",
            1 hours // Too short, should be at least 2 days
        );
    }
    */

    // ========== State Validation ==========

    function test_Validation_InvalidStateTransitions() public {
        _registerNode(node1);
        uint256 jobId = _postJob(client1);

        // Try to complete job without claiming
        vm.prank(node1);
        vm.expectRevert("Job not claimed");
        jobMarketplace.submitResult(jobId, "QmResult", "");

        // Claim the job
        vm.prank(node1);
        jobMarketplace.claimJob(jobId);

        // Try to claim again
        vm.prank(node1);
        vm.expectRevert("Job already claimed");
        jobMarketplace.claimJob(jobId);
    }

    function test_Validation_InvalidJobId() public {
        // Try operations on non-existent job
        uint256 fakeJobId = 99999;

        vm.prank(node1);
        vm.expectRevert("Job does not exist");
        jobMarketplace.claimJob(fakeJobId);

        vm.prank(client1);
        vm.expectRevert("Job does not exist");
        jobMarketplace.releasePayment(fakeJobId);
    }

    // ========== Enum Validation ==========

    function test_Validation_InvalidEnumValues() public {
        // This would test if we accept invalid enum values
        // Solidity 0.8+ handles this automatically, but we can test the behavior
        _registerNode(node1);
        
        // Create job with valid details
        uint256 jobId = _postJob(client1);
        
        // Try to query with invalid enum cast (this is mostly for documentation)
        (,, IJobMarketplace.JobStatus status,,,) = jobMarketplace.getJob(jobId);
        assertTrue(uint(status) <= 2); // Posted, Claimed, or Completed
    }

    // ========== Signature Validation ==========

    /* Commented out - delegateBySig doesn't exist yet
    function test_Validation_SignatureFormat() public {
        // Test delegation with invalid signature
        bytes memory invalidSig = hex"deadbeef"; // Too short
        
        vm.prank(node1);
        vm.expectRevert("Invalid signature length");
        governance.delegateBySig(node1, 1, block.timestamp + 1 days, invalidSig);

        // Test with signature of correct length but invalid format
        bytes memory badSig = new bytes(65);
        badSig[64] = bytes1(uint8(50)); // Invalid v value
        
        vm.prank(node1);
        vm.expectRevert("Invalid signature");
        governance.delegateBySig(node1, 1, block.timestamp + 1 days, badSig);
    }
    */

    // ========== Overflow Protection ==========

    function test_Validation_ArithmeticOverflow() public {
        _registerNode(node1);

        // Test payment calculation overflow
        IJobMarketplace.JobDetails memory jobDetails = _createJobDetails();
        IJobMarketplace.JobRequirements memory requirements = _createJobRequirements();

        // Give client1 enough funds for the test
        vm.deal(client1, 2000 ether);

        // This should be caught before any arithmetic
        vm.prank(client1);
        vm.expectRevert("Payment too large");
        jobMarketplace.postJob{value: 2000 ether}(
            jobDetails, 
            requirements, 
            2000 ether
        );
    }

    // ========== Helper Functions ==========

    function _registerNode(address node) internal {
        vm.prank(node);
        nodeRegistry.registerNodeSimple{value: STAKE_AMOUNT}("valid_metadata");
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
        vm.prank(client);
        return jobMarketplace.postJob{value: JOB_PAYMENT}(
            _createJobDetails(),
            _createJobRequirements(),
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
}

// Helper contract
contract EmptyContract {
    function destroy() external {
        selfdestruct(payable(msg.sender));
    }
}