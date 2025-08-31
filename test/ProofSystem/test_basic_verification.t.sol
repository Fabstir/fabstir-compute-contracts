// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ProofSystem.sol";

contract BasicVerificationTest is Test {
    ProofSystem public proofSystem;
    
    address public prover = address(0x1234);
    
    function setUp() public {
        proofSystem = new ProofSystem();
    }
    
    function test_VerificationWithValidProof() public {
        // Create a valid proof (at least 64 bytes)
        bytes memory proof = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            proof[i] = bytes1(uint8(i));
        }
        
        // Should verify successfully
        bool result = proofSystem.verifyEKZL(proof, prover, 100);
        assertTrue(result, "Valid proof should verify");
    }
    
    function test_RejectionOfShortProofs() public {
        // Create a short proof (less than 64 bytes)
        bytes memory shortProof = new bytes(32);
        
        // Should reject short proof
        bool result = proofSystem.verifyEKZL(shortProof, prover, 100);
        assertFalse(result, "Short proof should be rejected");
    }
    
    function test_RejectionOfZeroTokenClaims() public {
        // Create a valid-sized proof
        bytes memory proof = new bytes(64);
        
        // Should reject zero token claims
        bool result = proofSystem.verifyEKZL(proof, prover, 0);
        assertFalse(result, "Zero token claims should be rejected");
    }
    
    function test_RejectionOfZeroAddressProver() public {
        // Create a valid proof
        bytes memory proof = new bytes(64);
        
        // Should reject zero address prover
        bool result = proofSystem.verifyEKZL(proof, address(0), 100);
        assertFalse(result, "Zero address prover should be rejected");
    }
    
    function test_ReturnValueCorrectness() public {
        // Test with valid proof
        bytes memory validProof = new bytes(64);
        bool validResult = proofSystem.verifyEKZL(validProof, prover, 100);
        assertTrue(validResult, "Should return true for valid proof");
        
        // Test with invalid proof (too short)
        bytes memory invalidProof = new bytes(10);
        bool invalidResult = proofSystem.verifyEKZL(invalidProof, prover, 100);
        assertFalse(invalidResult, "Should return false for invalid proof");
    }
    
    function test_DifferentProofSizesHandling() public {
        // Test exactly 64 bytes
        bytes memory proof64 = new bytes(64);
        bool result64 = proofSystem.verifyEKZL(proof64, prover, 100);
        assertTrue(result64, "64-byte proof should verify");
        
        // Test 128 bytes
        bytes memory proof128 = new bytes(128);
        bool result128 = proofSystem.verifyEKZL(proof128, prover, 100);
        assertTrue(result128, "128-byte proof should verify");
        
        // Test 63 bytes (just under minimum)
        bytes memory proof63 = new bytes(63);
        bool result63 = proofSystem.verifyEKZL(proof63, prover, 100);
        assertFalse(result63, "63-byte proof should fail");
    }
}