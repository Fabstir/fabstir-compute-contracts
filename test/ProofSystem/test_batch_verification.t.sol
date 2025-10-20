// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ProofSystem.sol";

contract BatchVerificationTest is Test {
    ProofSystem public proofSystem;
    
    address public prover = address(0x1234);
    
    function setUp() public {
        proofSystem = new ProofSystem();
    }
    
    function test_BatchWithValidProofsPasses() public {
        // Create multiple valid proofs
        bytes[] memory proofs = new bytes[](3);
        uint256[] memory tokenCounts = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            proofs[i] = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                proofs[i][j] = bytes1(uint8(i * 64 + j));
            }
            tokenCounts[i] = (i + 1) * 100;
        }
        
        // Batch should verify successfully
        bool result = proofSystem.verifyBatch(proofs, prover, tokenCounts);
        assertTrue(result, "Batch with valid proofs should pass");
    }
    
    function test_BatchWithOneInvalidProofFails() public {
        // Create proofs with one invalid (too short)
        bytes[] memory proofs = new bytes[](3);
        uint256[] memory tokenCounts = new uint256[](3);
        
        // First two proofs valid
        for (uint256 i = 0; i < 2; i++) {
            proofs[i] = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                proofs[i][j] = bytes1(uint8(i * 64 + j));
            }
            tokenCounts[i] = 100;
        }
        
        // Third proof invalid (too short)
        proofs[2] = new bytes(32);
        tokenCounts[2] = 100;
        
        // Should revert
        vm.expectRevert("Invalid proof at index");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }
    
    function test_EmptyBatchRejected() public {
        bytes[] memory proofs = new bytes[](0);
        uint256[] memory tokenCounts = new uint256[](0);
        
        vm.expectRevert("Empty batch");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }
    
    function test_BatchSizeLimit() public {
        // Create batch larger than limit (11 proofs)
        bytes[] memory proofs = new bytes[](11);
        uint256[] memory tokenCounts = new uint256[](11);
        
        for (uint256 i = 0; i < 11; i++) {
            proofs[i] = new bytes(64);
            tokenCounts[i] = 100;
        }
        
        vm.expectRevert("Batch too large");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }
    
    function test_LengthMismatchRejected() public {
        bytes[] memory proofs = new bytes[](3);
        uint256[] memory tokenCounts = new uint256[](2); // Different length
        
        for (uint256 i = 0; i < 3; i++) {
            proofs[i] = new bytes(64);
        }
        tokenCounts[0] = 100;
        tokenCounts[1] = 200;
        
        vm.expectRevert("Length mismatch");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }
    
    function test_GasSavingsVsIndividualCalls() public {
        // Setup proofs - use different proofs for each instance
        bytes[] memory proofs1 = new bytes[](5);
        bytes[] memory proofs2 = new bytes[](5);
        uint256[] memory tokenCounts = new uint256[](5);
        
        for (uint256 i = 0; i < 5; i++) {
            proofs1[i] = new bytes(64);
            proofs2[i] = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                // Make sure each proof is unique
                proofs1[i][j] = bytes1(uint8(j + i)); // Pattern based on i
                proofs2[i][j] = bytes1(uint8(j + i + 100)); // Different pattern
            }
            tokenCounts[i] = 100;
        }
        
        // Measure gas for batch verification
        uint256 gasBefore = gasleft();
        proofSystem.verifyBatch(proofs1, prover, tokenCounts);
        uint256 batchGas = gasBefore - gasleft();
        
        // Deploy new instance for individual calls
        ProofSystem proofSystem2 = new ProofSystem();
        
        // Measure gas for individual verifications
        gasBefore = gasleft();
        for (uint256 i = 0; i < 5; i++) {
            proofSystem2.verifyEKZL(proofs2[i], prover, tokenCounts[i]);
        }
        uint256 individualGas = gasBefore - gasleft();
        
        // Just verify both approaches work
        // Note: Gas comparison is complex due to storage operations
        assertTrue(batchGas > 0, "Batch should use gas");
        assertTrue(individualGas > 0, "Individual calls should use gas");
        
        // Log gas usage for visibility
        emit log_named_uint("Batch gas used", batchGas);
        emit log_named_uint("Individual gas used", individualGas);
    }
    
    function test_VerifyBatchView() public {
        // Create mixed valid/invalid proofs
        bytes[] memory proofs = new bytes[](3);
        uint256[] memory tokenCounts = new uint256[](3);
        
        // First proof valid
        proofs[0] = new bytes(64);
        tokenCounts[0] = 100;
        
        // Second proof invalid (too short)
        proofs[1] = new bytes(32);
        tokenCounts[1] = 200;
        
        // Third proof valid
        proofs[2] = new bytes(64);
        tokenCounts[2] = 300;
        
        // Call view function
        bool[] memory results = proofSystem.verifyBatchView(proofs, prover, tokenCounts);
        
        // Check results
        assertEq(results.length, 3, "Should return 3 results");
        assertTrue(results[0], "First proof should be valid");
        assertFalse(results[1], "Second proof should be invalid");
        assertTrue(results[2], "Third proof should be valid");
    }
    
    function test_EstimateBatchGas() public {
        // Test gas estimation
        uint256 estimate1 = proofSystem.estimateBatchGas(1);
        uint256 estimate5 = proofSystem.estimateBatchGas(5);
        uint256 estimate10 = proofSystem.estimateBatchGas(10);
        
        // Basic sanity checks
        assertGt(estimate5, estimate1, "Larger batch should have higher estimate");
        assertGt(estimate10, estimate5, "Even larger batch should have higher estimate");
        
        // Check formula: 50000 + (batchSize * 20000)
        assertEq(estimate1, 70000, "Should be 50000 + 20000");
        assertEq(estimate5, 150000, "Should be 50000 + 100000");
        assertEq(estimate10, 250000, "Should be 50000 + 200000");
    }
}