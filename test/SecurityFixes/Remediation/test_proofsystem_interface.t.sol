// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystem Interface Tests - markProofUsed
 * @notice Tests for Sub-phase 1.1: Update IProofSystem Interface
 *
 * AUDIT REMEDIATION: Remove redundant signature verification
 * The signature is redundant because msg.sender == session.host already authenticates.
 *
 * Changes:
 * - Remove verifyAndMarkComplete() from interface
 * - Add markProofUsed() for replay protection only
 */
contract ProofSystemInterfaceTest is Test {
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public authorizedCaller = address(0x2);
    address public unauthorizedCaller = address(0x3);
    address public prover = address(0x4);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Authorize a caller
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        vm.stopPrank();
    }

    // ============================================================
    // Test: markProofUsed function exists and is callable
    // ============================================================

    /**
     * @notice Verify markProofUsed function exists in the interface
     * @dev This test confirms the function signature is correct
     */
    function test_MarkProofUsed_FunctionExists() public {
        bytes32 proofHash = keccak256("test proof");
        uint256 claimedTokens = 100;
        bytes32 modelId = bytes32(uint256(1));

        // Call from authorized caller - should not revert with "function does not exist"
        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, prover, claimedTokens, modelId);

        // Should return true for new proof
        assertTrue(result, "markProofUsed should return true for new proof");
    }

    // ============================================================
    // Test: markProofUsed returns bool
    // ============================================================

    /**
     * @notice Verify markProofUsed returns boolean indicating success
     */
    function test_MarkProofUsed_ReturnsBool() public {
        bytes32 proofHash1 = keccak256("proof 1");
        bytes32 proofHash2 = keccak256("proof 2");
        uint256 claimedTokens = 100;
        bytes32 modelId = bytes32(0);

        vm.startPrank(authorizedCaller);

        // First call should return true
        bool result1 = proofSystem.markProofUsed(proofHash1, prover, claimedTokens, modelId);
        assertTrue(result1, "First call should return true");

        // Second call with same proofHash should return false (replay protection)
        bool result2 = proofSystem.markProofUsed(proofHash1, prover, claimedTokens, modelId);
        assertFalse(result2, "Replay should return false");

        // Different proofHash should return true
        bool result3 = proofSystem.markProofUsed(proofHash2, prover, claimedTokens, modelId);
        assertTrue(result3, "Different proof should return true");

        vm.stopPrank();
    }

    // ============================================================
    // Test: markProofUsed accepts (bytes32, address, uint256, bytes32) parameters
    // ============================================================

    /**
     * @notice Verify markProofUsed accepts correct parameter types
     * @dev Parameters: proofHash (bytes32), prover (address), claimedTokens (uint256), modelId (bytes32)
     */
    function test_MarkProofUsed_AcceptsCorrectParameters() public {
        // Test with various parameter values
        bytes32 proofHash = keccak256(abi.encodePacked("unique proof", block.timestamp));
        address testProver = address(0x12345);
        uint256 tokens = 1000;
        bytes32 model = keccak256("TinyLlama-1.1B");

        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, testProver, tokens, model);
        assertTrue(result, "Should accept all parameter types correctly");
    }

    /**
     * @notice Verify markProofUsed works with zero modelId (non-model sessions)
     */
    function test_MarkProofUsed_AcceptsZeroModelId() public {
        bytes32 proofHash = keccak256("non-model proof");
        bytes32 zeroModelId = bytes32(0);

        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, prover, 500, zeroModelId);
        assertTrue(result, "Should accept zero modelId for non-model sessions");
    }

    /**
     * @notice Verify markProofUsed works with various token counts
     */
    function test_MarkProofUsed_AcceptsVariousTokenCounts() public {
        vm.startPrank(authorizedCaller);

        // Minimum tokens (100)
        bool result1 = proofSystem.markProofUsed(keccak256("min tokens"), prover, 100, bytes32(0));
        assertTrue(result1, "Should accept minimum token count");

        // Large token count
        bool result2 = proofSystem.markProofUsed(keccak256("large tokens"), prover, 1_000_000, bytes32(0));
        assertTrue(result2, "Should accept large token count");

        vm.stopPrank();
    }

    // ============================================================
    // Test: verifyAndMarkComplete no longer exists (compile-time check)
    // ============================================================

    /**
     * @notice This is a compile-time verification
     * @dev After removing verifyAndMarkComplete from interface, any code calling it will fail to compile.
     *      We verify the new interface is in use by checking markProofUsed works.
     */
    function test_NewInterfaceInUse() public {
        // If this test compiles and passes, the new interface is in use
        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(keccak256("interface test"), prover, 100, bytes32(0));
        assertTrue(result, "New interface should work");
    }
}
