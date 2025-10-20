// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ProofSystem.sol";

contract ProofReplayTest is Test {
    ProofSystem public proofSystem;
    
    address public prover = address(0x1234);
    
    function setUp() public {
        proofSystem = new ProofSystem();
    }
    
    function test_SameProofCannotBeVerifiedTwice() public {
        // Create a proof
        bytes memory proof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            proof[i] = bytes1(uint8(i));
        }
        
        // First verification should succeed
        bool firstResult = proofSystem.verifyEKZL(proof, prover, 100);
        assertTrue(firstResult, "First verification should succeed");
        
        // Extract proof hash and record it
        bytes32 proofHash;
        assembly {
            proofHash := mload(add(proof, 32))
        }
        proofSystem.recordVerifiedProof(proofHash);
        
        // Second verification with same proof should fail
        bool secondResult = proofSystem.verifyEKZL(proof, prover, 100);
        assertFalse(secondResult, "Same proof should not verify twice");
    }
    
    function test_DifferentProofsCanBeVerified() public {
        // Create first proof
        bytes memory proof1 = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            proof1[i] = bytes1(uint8(i));
        }
        
        // Create different proof
        bytes memory proof2 = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            proof2[i] = bytes1(uint8(i + 100));
        }
        
        // Both should verify initially
        bool result1 = proofSystem.verifyEKZL(proof1, prover, 100);
        assertTrue(result1, "First proof should verify");
        
        bool result2 = proofSystem.verifyEKZL(proof2, prover, 200);
        assertTrue(result2, "Different proof should also verify");
    }
    
    function test_ProofHashExtraction() public {
        // Create a specific proof
        bytes memory proof = new bytes(64);
        // Set first 32 bytes to a known pattern
        for (uint i = 0; i < 32; i++) {
            proof[i] = bytes1(uint8(i + 1));
        }
        
        // Verify proof
        bool result = proofSystem.verifyEKZL(proof, prover, 100);
        assertTrue(result, "Proof should verify");
        
        // Extract and record the hash
        bytes32 expectedHash;
        assembly {
            expectedHash := mload(add(proof, 32))
        }
        proofSystem.recordVerifiedProof(expectedHash);
        
        // Check that it's recorded
        assertTrue(proofSystem.verifiedProofs(expectedHash), "Proof hash should be recorded");
    }
    
    function test_VerifiedProofsMappingUpdates() public {
        // Create three different proofs
        bytes32 hash1 = keccak256("proof1");
        bytes32 hash2 = keccak256("proof2");
        bytes32 hash3 = keccak256("proof3");
        
        // Initially all should be false
        assertFalse(proofSystem.verifiedProofs(hash1), "Hash1 should not be verified initially");
        assertFalse(proofSystem.verifiedProofs(hash2), "Hash2 should not be verified initially");
        assertFalse(proofSystem.verifiedProofs(hash3), "Hash3 should not be verified initially");
        
        // Record first proof
        proofSystem.recordVerifiedProof(hash1);
        assertTrue(proofSystem.verifiedProofs(hash1), "Hash1 should be verified after recording");
        assertFalse(proofSystem.verifiedProofs(hash2), "Hash2 should still not be verified");
        assertFalse(proofSystem.verifiedProofs(hash3), "Hash3 should still not be verified");
        
        // Record second proof
        proofSystem.recordVerifiedProof(hash2);
        assertTrue(proofSystem.verifiedProofs(hash1), "Hash1 should remain verified");
        assertTrue(proofSystem.verifiedProofs(hash2), "Hash2 should be verified after recording");
        assertFalse(proofSystem.verifiedProofs(hash3), "Hash3 should still not be verified");
    }
    
    function test_ProofVerifiedEventEmission() public {
        bytes32 testHash = keccak256("test");
        
        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit ProofSystem.ProofVerified(testHash, address(this), 0);
        
        proofSystem.recordVerifiedProof(testHash);
    }
    
    function test_ReplayAttackPrevention() public {
        // Create a valuable proof (high token claim)
        bytes memory proof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            proof[i] = bytes1(uint8(i));
        }
        
        // First use succeeds
        bool firstUse = proofSystem.verifyEKZL(proof, prover, 1000);
        assertTrue(firstUse, "First use should succeed");
        
        // Record the proof as used
        bytes32 proofHash;
        assembly {
            proofHash := mload(add(proof, 32))
        }
        proofSystem.recordVerifiedProof(proofHash);
        
        // Attacker tries to reuse the same proof
        address attacker = address(0x9999);
        bool replayAttempt = proofSystem.verifyEKZL(proof, attacker, 1000);
        assertFalse(replayAttempt, "Replay attack should be prevented");
    }
}