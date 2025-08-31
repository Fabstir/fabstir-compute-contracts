// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";

contract ProofStructTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5();
    }
    
    function test_ProofSubmissionStructCompiles() public {
        // Create a ProofSubmission struct
        JobMarketplaceFABWithS5.ProofSubmission memory proof;
        
        // Set all fields
        proof.proofHash = keccak256("test proof");
        proof.tokensClaimed = 1000;
        proof.timestamp = block.timestamp;
        proof.verified = false;
        
        // Verify fields
        assertEq(proof.proofHash, keccak256("test proof"));
        assertEq(proof.tokensClaimed, 1000);
        assertEq(proof.timestamp, block.timestamp);
        assertEq(proof.verified, false);
    }
    
    function test_ProofSubmissionFieldTypes() public {
        // Test field type boundaries
        JobMarketplaceFABWithS5.ProofSubmission memory proof;
        
        // Test bytes32 field
        proof.proofHash = bytes32(type(uint256).max);
        assertEq(proof.proofHash, bytes32(type(uint256).max));
        
        // Test uint256 fields
        proof.tokensClaimed = type(uint256).max;
        assertEq(proof.tokensClaimed, type(uint256).max);
        
        proof.timestamp = type(uint256).max;
        assertEq(proof.timestamp, type(uint256).max);
        
        // Test bool field
        proof.verified = true;
        assertTrue(proof.verified);
        
        proof.verified = false;
        assertFalse(proof.verified);
    }
    
    function test_CanAccessSessionProofsMapping() public {
        uint256 jobId = 1;
        
        // This test will fail until mapping is added
        // Access the sessionProofs mapping (returns array)
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = marketplace.sessionProofs(jobId);
        
        // Check empty array
        assertEq(proofs.length, 0);
    }
    
    function test_ProofSubmissionArrayOperations() public {
        // Test that we can work with arrays of ProofSubmission
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = new JobMarketplaceFABWithS5.ProofSubmission[](3);
        
        // Create three proof submissions
        proofs[0] = JobMarketplaceFABWithS5.ProofSubmission({
            proofHash: keccak256("proof1"),
            tokensClaimed: 100,
            timestamp: block.timestamp,
            verified: true
        });
        
        proofs[1] = JobMarketplaceFABWithS5.ProofSubmission({
            proofHash: keccak256("proof2"),
            tokensClaimed: 200,
            timestamp: block.timestamp + 100,
            verified: false
        });
        
        proofs[2] = JobMarketplaceFABWithS5.ProofSubmission({
            proofHash: keccak256("proof3"),
            tokensClaimed: 300,
            timestamp: block.timestamp + 200,
            verified: true
        });
        
        // Verify array operations work
        assertEq(proofs.length, 3);
        assertEq(proofs[0].tokensClaimed, 100);
        assertEq(proofs[1].tokensClaimed, 200);
        assertEq(proofs[2].tokensClaimed, 300);
        
        // Verify different hashes
        assertTrue(proofs[0].proofHash != proofs[1].proofHash);
        assertTrue(proofs[1].proofHash != proofs[2].proofHash);
    }
    
    function test_ProofSubmissionDefaultValues() public {
        // Test default values when creating struct
        JobMarketplaceFABWithS5.ProofSubmission memory proof;
        
        // Check defaults
        assertEq(proof.proofHash, bytes32(0));
        assertEq(proof.tokensClaimed, 0);
        assertEq(proof.timestamp, 0);
        assertEq(proof.verified, false);
    }
    
    function test_ProofHashUniqueness() public {
        // Test that proof hashes can be unique
        bytes32 hash1 = keccak256(abi.encodePacked("proof", uint256(1)));
        bytes32 hash2 = keccak256(abi.encodePacked("proof", uint256(2)));
        bytes32 hash3 = keccak256(abi.encodePacked("proof", uint256(3)));
        
        JobMarketplaceFABWithS5.ProofSubmission memory proof1;
        JobMarketplaceFABWithS5.ProofSubmission memory proof2;
        JobMarketplaceFABWithS5.ProofSubmission memory proof3;
        
        proof1.proofHash = hash1;
        proof2.proofHash = hash2;
        proof3.proofHash = hash3;
        
        // Verify all hashes are different
        assertTrue(proof1.proofHash != proof2.proofHash);
        assertTrue(proof2.proofHash != proof3.proofHash);
        assertTrue(proof1.proofHash != proof3.proofHash);
    }
}