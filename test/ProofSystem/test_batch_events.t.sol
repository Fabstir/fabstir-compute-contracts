// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ProofSystem.sol";

contract BatchEventsTest is Test {
    ProofSystem public proofSystem;
    
    address public prover = address(0x1234);
    
    function setUp() public {
        proofSystem = new ProofSystem();
    }
    
    function test_BatchProofVerifiedEventEmission() public {
        // Create batch of proofs
        bytes[] memory proofs = new bytes[](3);
        uint256[] memory tokenCounts = new uint256[](3);
        bytes32[] memory expectedHashes = new bytes32[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            proofs[i] = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                proofs[i][j] = bytes1(uint8(i * 64 + j));
            }
            tokenCounts[i] = (i + 1) * 100;
            
            // Calculate expected hash (first 32 bytes)
            bytes memory proof = proofs[i];
            assembly {
                let hash := mload(add(proof, 32))
                mstore(add(add(expectedHashes, 32), mul(32, i)), hash)
            }
        }
        
        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit ProofSystem.BatchProofVerified(expectedHashes, prover, 600);
        
        // Verify batch
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }
    
    function test_EventContainsAllProofHashes() public {
        // Create batch
        bytes[] memory proofs = new bytes[](2);
        uint256[] memory tokenCounts = new uint256[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            proofs[i] = new bytes(64);
            // Set distinct patterns for each proof
            for (uint256 j = 0; j < 64; j++) {
                proofs[i][j] = bytes1(uint8(i == 0 ? j : 255 - j));
            }
            tokenCounts[i] = 100;
        }
        
        // Capture events
        vm.recordLogs();
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Find BatchProofVerified event
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BatchProofVerified(bytes32[],address,uint256)")) {
                eventFound = true;
                
                // Decode event data
                // Note: prover is indexed, so it's in topics, not data
                (bytes32[] memory hashes, uint256 totalTokens) = abi.decode(
                    logs[i].data,
                    (bytes32[], uint256)
                );
                
                assertEq(hashes.length, 2, "Should have 2 proof hashes");
                assertEq(totalTokens, 200, "Total tokens should be 200");
                break;
            }
        }
        
        assertTrue(eventFound, "BatchProofVerified event should be emitted");
    }
    
    function test_TotalTokensCalculation() public {
        // Create batch with different token counts
        bytes[] memory proofs = new bytes[](4);
        uint256[] memory tokenCounts = new uint256[](4);
        uint256 expectedTotal = 0;
        
        for (uint256 i = 0; i < 4; i++) {
            proofs[i] = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                proofs[i][j] = bytes1(uint8(i * 64 + j));
            }
            tokenCounts[i] = (i + 1) * 50; // 50, 100, 150, 200
            expectedTotal += tokenCounts[i];
        }
        
        // Record logs
        vm.recordLogs();
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Check total in event
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BatchProofVerified(bytes32[],address,uint256)")) {
                (, uint256 totalTokens) = abi.decode(
                    logs[i].data,
                    (bytes32[], uint256)
                );
                assertEq(totalTokens, expectedTotal, "Total tokens should match sum");
                assertEq(totalTokens, 500, "Total should be 50+100+150+200=500");
                break;
            }
        }
    }
    
    function test_ProverAddressInEvent() public {
        // Create simple batch
        bytes[] memory proofs = new bytes[](1);
        uint256[] memory tokenCounts = new uint256[](1);
        
        proofs[0] = new bytes(64);
        tokenCounts[0] = 100;
        
        // Test with specific prover address
        address specificProver = address(0x9876);
        
        // Record logs
        vm.recordLogs();
        proofSystem.verifyBatch(proofs, specificProver, tokenCounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Check prover in event
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BatchProofVerified(bytes32[],address,uint256)")) {
                // Prover is indexed, so it's in topics[1]
                address eventProver = address(uint160(uint256(logs[i].topics[1])));
                assertEq(eventProver, specificProver, "Event should contain correct prover");
                break;
            }
        }
    }
    
    function test_EventNotEmittedOnFailure() public {
        // Create batch with invalid proof
        bytes[] memory proofs = new bytes[](2);
        uint256[] memory tokenCounts = new uint256[](2);
        
        proofs[0] = new bytes(64); // Valid
        proofs[1] = new bytes(32); // Invalid (too short)
        tokenCounts[0] = 100;
        tokenCounts[1] = 200;
        
        // Record logs
        vm.recordLogs();
        
        // Should revert
        vm.expectRevert("Invalid proof at index");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        
        // Check no events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BatchProofVerified(bytes32[],address,uint256)")) {
                assertTrue(false, "BatchProofVerified event should not be emitted on failure");
            }
        }
    }
    
    function test_ProofHashesMarkedAsVerified() public {
        // Create batch
        bytes[] memory proofs = new bytes[](2);
        uint256[] memory tokenCounts = new uint256[](2);
        bytes32[] memory hashes = new bytes32[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            proofs[i] = new bytes(64);
            for (uint256 j = 0; j < 64; j++) {
                proofs[i][j] = bytes1(uint8(i * 100 + j));
            }
            tokenCounts[i] = 100;
            
            // Extract hash
            bytes memory proof = proofs[i];
            assembly {
                let hash := mload(add(proof, 32))
                mstore(add(add(hashes, 32), mul(32, i)), hash)
            }
        }
        
        // Verify none are marked as verified initially
        for (uint256 i = 0; i < 2; i++) {
            assertFalse(proofSystem.verifiedProofs(hashes[i]), "Should not be verified initially");
        }
        
        // Verify batch
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        
        // Check all are marked as verified
        for (uint256 i = 0; i < 2; i++) {
            assertTrue(proofSystem.verifiedProofs(hashes[i]), "Should be marked as verified");
        }
    }
}