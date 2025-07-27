// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {ProofSystem} from "../../src/ProofSystem.sol";
import {IJobMarketplace} from "../../src/interfaces/IJobMarketplace.sol";
import {TestSetup} from "../TestSetup.t.sol";

contract ProofSystemTest is TestSetup {
    ProofSystem public proofSystem;
    
    // Test accounts
    address public verifier = address(0x1234);
    address public challenger = address(0x5678);
    
    // EZKL proof components
    bytes32 public modelCommitment = keccak256("model_v1");
    bytes32 public inputHash = keccak256("test_input");
    bytes32 public outputHash = keccak256("test_output");
    
    event ProofSubmitted(
        uint256 indexed jobId,
        address indexed prover,
        bytes32 proofHash,
        uint256 timestamp
    );
    
    event ProofVerified(
        uint256 indexed jobId,
        address indexed verifier,
        bool isValid
    );
    
    event ProofChallenged(
        uint256 indexed jobId,
        address indexed challenger,
        bytes32 evidenceHash
    );
    
    event ChallengeResolved(
        uint256 indexed jobId,
        bool challengeSuccessful,
        address winner
    );
    
    event BatchVerificationCompleted(
        uint256[] jobIds,
        bool[] results,
        uint256 gasUsed
    );
    
    function setUp() public override {
        super.setUp();
        
        // Deploy ProofSystem
        proofSystem = new ProofSystem(
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem)
        );
        
        // Grant necessary roles
        jobMarketplace.grantRole(jobMarketplace.PROOF_SYSTEM_ROLE(), address(proofSystem));
        paymentEscrow.grantRole(paymentEscrow.PROOF_SYSTEM_ROLE(), address(proofSystem));
        
        // Grant verifier role
        proofSystem.grantVerifierRole(verifier);
        
        // Setup test accounts
        vm.deal(verifier, 10 ether);
        vm.deal(challenger, 10 ether);
        
        // Give challenger some tokens for staking
        token.mint(challenger, 1000e18);
        
        // Setup ProofSystem integration with JobMarketplace
        jobMarketplace.setProofSystem(address(proofSystem));
        
        // Register host1 and create a job
        vm.prank(host1);
        nodeRegistry.registerHost("host1-uri", 100e18);
        
        vm.prank(client);
        token.approve(address(paymentEscrow), 1000e18);
        jobId = jobMarketplace.postJob(
            "test-job",
            100e18,
            address(token),
            86400,
            modelCommitment,
            inputHash
        );
        
        vm.prank(host1);
        jobMarketplace.claimJob(jobId);
    }
    
    function test_SubmitProof() public {
        // Prepare EZKL proof data
        ProofSystem.EZKLProof memory proof = ProofSystem.EZKLProof({
            instances: new uint256[](3),
            proof: new uint256[](8),
            vk: new uint256[](12),
            modelCommitment: modelCommitment,
            inputHash: inputHash,
            outputHash: outputHash
        });
        
        // Fill proof data with test values
        for (uint i = 0; i < proof.instances.length; i++) {
            proof.instances[i] = uint256(keccak256(abi.encode("instance", i)));
        }
        for (uint i = 0; i < proof.proof.length; i++) {
            proof.proof[i] = uint256(keccak256(abi.encode("proof", i)));
        }
        for (uint i = 0; i < proof.vk.length; i++) {
            proof.vk[i] = uint256(keccak256(abi.encode("vk", i)));
        }
        
        // Submit proof
        vm.prank(host1);
        vm.expectEmit(true, true, true, true);
        emit ProofSubmitted(jobId, host1, keccak256(abi.encode(proof)), block.timestamp);
        
        proofSystem.submitProof(jobId, proof);
        
        // Verify proof was stored
        (address prover, uint256 submissionTime, ProofSystem.ProofStatus status) = 
            proofSystem.getProofInfo(jobId);
        
        assertEq(prover, host1);
        assertEq(submissionTime, block.timestamp);
        assertEq(uint8(status), uint8(ProofSystem.ProofStatus.Submitted));
    }
    
    function test_VerifyValidProof() public {
        // Submit proof first
        ProofSystem.EZKLProof memory proof = _createValidProof();
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        // Verify proof (in real implementation, this would call EZKL verifier)
        vm.prank(verifier);
        vm.expectEmit(true, true, true, true);
        emit ProofVerified(jobId, verifier, true);
        
        proofSystem.verifyProof(jobId);
        
        // Check status updated
        (,, ProofSystem.ProofStatus status) = proofSystem.getProofInfo(jobId);
        assertEq(uint8(status), uint8(ProofSystem.ProofStatus.Verified));
        
        // Check job can be completed
        assertTrue(proofSystem.canCompleteJob(jobId));
    }
    
    function test_RejectInvalidProof() public {
        // Submit invalid proof
        ProofSystem.EZKLProof memory proof = _createInvalidProof();
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        // Verify proof should fail
        vm.prank(verifier);
        vm.expectEmit(true, true, true, true);
        emit ProofVerified(jobId, verifier, false);
        
        proofSystem.verifyProof(jobId);
        
        // Check status
        (,, ProofSystem.ProofStatus status) = proofSystem.getProofInfo(jobId);
        assertEq(uint8(status), uint8(ProofSystem.ProofStatus.Invalid));
        
        // Job should not be completable
        assertFalse(proofSystem.canCompleteJob(jobId));
    }
    
    function test_BatchVerification() public {
        // Create multiple jobs
        uint256[] memory jobIds = new uint256[](3);
        jobIds[0] = jobId;
        
        // Create 2 more jobs
        for (uint i = 1; i < 3; i++) {
            vm.prank(client);
            token.approve(address(paymentEscrow), 100e18);
            jobIds[i] = jobMarketplace.postJob(
                string(abi.encodePacked("job-", i)),
                100e18,
                address(token),
                86400,
                modelCommitment,
                inputHash
            );
            
            vm.prank(host1);
            jobMarketplace.claimJob(jobIds[i]);
        }
        
        // Submit proofs for all jobs
        ProofSystem.EZKLProof[] memory proofs = new ProofSystem.EZKLProof[](3);
        proofs[0] = _createValidProof();
        proofs[1] = _createValidProof();
        proofs[2] = _createInvalidProof(); // Make last one invalid
        
        for (uint i = 0; i < jobIds.length; i++) {
            vm.prank(host1);
            proofSystem.submitProof(jobIds[i], proofs[i]);
        }
        
        // Batch verify
        vm.prank(verifier);
        vm.expectEmit(true, true, true, false); // Don't check gas usage exactly
        bool[] memory expectedResults = new bool[](3);
        expectedResults[0] = true;
        expectedResults[1] = true;
        expectedResults[2] = false;
        emit BatchVerificationCompleted(jobIds, expectedResults, 0); // Gas will be different
        
        bool[] memory results = proofSystem.batchVerifyProofs(jobIds);
        
        // Check results
        assertTrue(results[0]);
        assertTrue(results[1]);
        assertFalse(results[2]);
        
        // Check individual statuses
        (,, ProofSystem.ProofStatus status0) = proofSystem.getProofInfo(jobIds[0]);
        (,, ProofSystem.ProofStatus status1) = proofSystem.getProofInfo(jobIds[1]);
        (,, ProofSystem.ProofStatus status2) = proofSystem.getProofInfo(jobIds[2]);
        
        assertEq(uint8(status0), uint8(ProofSystem.ProofStatus.Verified));
        assertEq(uint8(status1), uint8(ProofSystem.ProofStatus.Verified));
        assertEq(uint8(status2), uint8(ProofSystem.ProofStatus.Invalid));
    }
    
    function test_ChallengeProof() public {
        // Submit and verify proof
        ProofSystem.EZKLProof memory proof = _createValidProof();
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        vm.prank(verifier);
        proofSystem.verifyProof(jobId);
        
        // Challenge the proof
        bytes32 evidenceHash = keccak256("counter_evidence");
        uint256 challengeStake = 10e18;
        
        // Debug: Check challenger balance before
        uint256 challengerBalance = token.balanceOf(challenger);
        require(challengerBalance >= challengeStake, "Challenger has insufficient balance");
        
        vm.startPrank(challenger);
        token.approve(address(proofSystem), challengeStake);
        
        vm.expectEmit(true, true, true, true);
        emit ProofChallenged(jobId, challenger, evidenceHash);
        
        uint256 challengeId = proofSystem.challengeProof(jobId, evidenceHash, challengeStake);
        vm.stopPrank();
        
        // Check challenge was created
        (
            address challengerAddr,
            uint256 stake,
            bytes32 evidence,
            ProofSystem.ChallengeStatus status,
            uint256 deadline
        ) = proofSystem.getChallengeInfo(challengeId);
        
        assertEq(challengerAddr, challenger);
        assertEq(stake, challengeStake);
        assertEq(evidence, evidenceHash);
        assertEq(uint8(status), uint8(ProofSystem.ChallengeStatus.Pending));
        assertEq(deadline, block.timestamp + 3 days);
    }
    
    function test_ResolveChallengeSuccess() public {
        // Setup: Submit, verify, and challenge proof
        _setupChallenge();
        
        // Resolve challenge in favor of challenger
        vm.prank(verifier);
        vm.expectEmit(true, true, true, true);
        emit ChallengeResolved(jobId, true, challenger);
        
        proofSystem.resolveChallenge(1, true); // challengeId = 1
        
        // Check challenge resolved
        (,,, ProofSystem.ChallengeStatus status,) = proofSystem.getChallengeInfo(1);
        assertEq(uint8(status), uint8(ProofSystem.ChallengeStatus.Successful));
        
        // Check proof marked invalid
        (,, ProofSystem.ProofStatus proofStatus) = proofSystem.getProofInfo(jobId);
        assertEq(uint8(proofStatus), uint8(ProofSystem.ProofStatus.Invalid));
        
        // Check challenger received reward (their stake back)
        assertEq(token.balanceOf(challenger), 1000e18); // Started with 1000e18, staked 10e18, got it back
    }
    
    function test_ResolveChallengeFailed() public {
        // Setup: Submit, verify, and challenge proof
        _setupChallenge();
        
        // Resolve challenge against challenger
        vm.prank(verifier);
        vm.expectEmit(true, true, true, true);
        emit ChallengeResolved(jobId, false, host1);
        
        proofSystem.resolveChallenge(1, false);
        
        // Check challenge failed
        (,,, ProofSystem.ChallengeStatus status,) = proofSystem.getChallengeInfo(1);
        assertEq(uint8(status), uint8(ProofSystem.ChallengeStatus.Failed));
        
        // Check proof still valid
        (,, ProofSystem.ProofStatus proofStatus) = proofSystem.getProofInfo(jobId);
        assertEq(uint8(proofStatus), uint8(ProofSystem.ProofStatus.Verified));
        
        // Check host received challenger's stake
        assertEq(token.balanceOf(host1), 10010e18); // Original 10000e18 + 10e18 challenge stake
    }
    
    function test_AutoExpireChallenge() public {
        // Setup challenge
        _setupChallenge();
        
        // Warp past deadline
        vm.warp(block.timestamp + 4 days);
        
        // Anyone can call expire
        vm.prank(address(0xdead));
        proofSystem.expireChallenge(1);
        
        // Check challenge expired (defaults to failed)
        (,,, ProofSystem.ChallengeStatus status,) = proofSystem.getChallengeInfo(1);
        assertEq(uint8(status), uint8(ProofSystem.ChallengeStatus.Failed));
        
        // Proof should still be valid
        (,, ProofSystem.ProofStatus proofStatus) = proofSystem.getProofInfo(jobId);
        assertEq(uint8(proofStatus), uint8(ProofSystem.ProofStatus.Verified));
    }
    
    function test_OnlyHostCanSubmitProof() public {
        ProofSystem.EZKLProof memory proof = _createValidProof();
        
        vm.prank(client);
        vm.expectRevert("Only assigned host can submit proof");
        proofSystem.submitProof(jobId, proof);
    }
    
    function test_CannotSubmitProofTwice() public {
        ProofSystem.EZKLProof memory proof = _createValidProof();
        
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        // Try to submit again
        vm.prank(host1);
        vm.expectRevert("Proof already submitted");
        proofSystem.submitProof(jobId, proof);
    }
    
    function test_ProofRequiredForJobCompletion() public {
        // Try to complete job without proof
        vm.prank(host1);
        vm.expectRevert("Valid proof required");
        jobMarketplace.completeJob(jobId, outputHash);
        
        // Submit and verify proof
        ProofSystem.EZKLProof memory proof = _createValidProof();
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        vm.prank(verifier);
        proofSystem.verifyProof(jobId);
        
        // Now job completion should work
        vm.prank(host1);
        jobMarketplace.completeJob(jobId, outputHash);
        
        // Check job completed
        (,,,, IJobMarketplace.JobStatus status,,,,) = jobMarketplace.getJob(jobId);
        assertEq(uint8(status), uint8(IJobMarketplace.JobStatus.Completed));
    }
    
    function test_ProofIntegrationWithReputation() public {
        // Submit invalid proof
        ProofSystem.EZKLProof memory proof = _createInvalidProof();
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        vm.prank(verifier);
        proofSystem.verifyProof(jobId);
        
        // Check reputation decreased
        uint256 reputation = reputationSystem.getReputation(host1);
        assertLt(reputation, 1000); // Should be less than initial reputation
    }
    
    // Helper functions
    function _createValidProof() internal view returns (ProofSystem.EZKLProof memory) {
        ProofSystem.EZKLProof memory proof = ProofSystem.EZKLProof({
            instances: new uint256[](3),
            proof: new uint256[](8),
            vk: new uint256[](12),
            modelCommitment: modelCommitment,
            inputHash: inputHash,
            outputHash: outputHash
        });
        
        // Valid proof data
        proof.instances[0] = uint256(modelCommitment);
        proof.instances[1] = uint256(inputHash);
        proof.instances[2] = uint256(outputHash);
        
        for (uint i = 0; i < proof.proof.length; i++) {
            proof.proof[i] = uint256(keccak256(abi.encode("valid_proof", i)));
        }
        for (uint i = 0; i < proof.vk.length; i++) {
            proof.vk[i] = uint256(keccak256(abi.encode("valid_vk", i)));
        }
        
        return proof;
    }
    
    function _createInvalidProof() internal view returns (ProofSystem.EZKLProof memory) {
        ProofSystem.EZKLProof memory proof = _createValidProof();
        // Corrupt the proof data
        proof.instances[2] = uint256(keccak256("wrong_output"));
        return proof;
    }
    
    function _setupChallenge() internal {
        // Submit and verify proof
        ProofSystem.EZKLProof memory proof = _createValidProof();
        vm.prank(host1);
        proofSystem.submitProof(jobId, proof);
        
        vm.prank(verifier);
        proofSystem.verifyProof(jobId);
        
        // Fund challenger if not already funded
        if (token.balanceOf(challenger) == 0) {
            token.mint(challenger, 1000e18);
        }
        
        // Challenge the proof
        vm.startPrank(challenger);
        token.approve(address(proofSystem), 10e18);
        proofSystem.challengeProof(jobId, keccak256("evidence"), 10e18);
        vm.stopPrank();
    }
}