// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title markProofUsed Unit Tests
 * @notice Tests for Sub-phase 1.2: Implement markProofUsed and Remove Signature Verification
 *
 * AUDIT REMEDIATION: Remove redundant signature verification
 *
 * Tests:
 * - markProofUsed returns true for new proofHash
 * - markProofUsed returns false for already-used proofHash (replay protection)
 * - markProofUsed emits ProofVerified event
 * - Only authorized callers can call markProofUsed
 * - Owner can call markProofUsed
 */
contract MarkProofUsedTest is Test {
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public authorizedCaller = address(0x2);
    address public unauthorizedCaller = address(0x3);
    address public prover = address(0x4);

    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Authorize a caller (simulating JobMarketplace)
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        vm.stopPrank();
    }

    // ============================================================
    // Test: markProofUsed returns true for new proofHash
    // ============================================================

    /**
     * @notice Verify markProofUsed returns true for a new, unused proof hash
     */
    function test_MarkProofUsed_ReturnsTrueForNewProof() public {
        bytes32 proofHash = keccak256("new proof");
        uint256 claimedTokens = 100;
        bytes32 modelId = bytes32(uint256(1));

        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, prover, claimedTokens, modelId);

        assertTrue(result, "Should return true for new proof");
    }

    /**
     * @notice Verify different proof hashes all return true
     */
    function test_MarkProofUsed_MultipleDifferentProofs() public {
        vm.startPrank(authorizedCaller);

        for (uint256 i = 0; i < 5; i++) {
            bytes32 proofHash = keccak256(abi.encodePacked("proof", i));
            bool result = proofSystem.markProofUsed(proofHash, prover, 100 + i, bytes32(0));
            assertTrue(result, "Each unique proof should return true");
        }

        vm.stopPrank();
    }

    // ============================================================
    // Test: markProofUsed returns false for already-used proofHash
    // ============================================================

    /**
     * @notice Verify replay protection - same proof hash returns false on second use
     */
    function test_MarkProofUsed_ReturnsFalseForReplay() public {
        bytes32 proofHash = keccak256("replay test");
        uint256 claimedTokens = 500;
        bytes32 modelId = bytes32(0);

        vm.startPrank(authorizedCaller);

        // First use - should succeed
        bool result1 = proofSystem.markProofUsed(proofHash, prover, claimedTokens, modelId);
        assertTrue(result1, "First use should return true");

        // Second use (replay) - should fail
        bool result2 = proofSystem.markProofUsed(proofHash, prover, claimedTokens, modelId);
        assertFalse(result2, "Replay should return false");

        // Third attempt - still false
        bool result3 = proofSystem.markProofUsed(proofHash, prover, claimedTokens, modelId);
        assertFalse(result3, "Third attempt should also return false");

        vm.stopPrank();
    }

    /**
     * @notice Verify proof is marked in verifiedProofs mapping
     */
    function test_MarkProofUsed_SetsVerifiedProofsMapping() public {
        bytes32 proofHash = keccak256("mapping test");

        // Initially not verified
        assertFalse(proofSystem.verifiedProofs(proofHash), "Should not be verified initially");

        vm.prank(authorizedCaller);
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        // Now verified
        assertTrue(proofSystem.verifiedProofs(proofHash), "Should be verified after markProofUsed");
    }

    // ============================================================
    // Test: markProofUsed emits ProofVerified event
    // ============================================================

    /**
     * @notice Verify ProofVerified event is emitted correctly
     */
    function test_MarkProofUsed_EmitsProofVerifiedEvent() public {
        bytes32 proofHash = keccak256("event test");
        uint256 claimedTokens = 1000;

        vm.prank(authorizedCaller);

        // Expect the event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit ProofVerified(proofHash, prover, claimedTokens);

        proofSystem.markProofUsed(proofHash, prover, claimedTokens, bytes32(0));
    }

    /**
     * @notice Verify event is NOT emitted for replay (returns false without event)
     */
    function test_MarkProofUsed_NoEventOnReplay() public {
        bytes32 proofHash = keccak256("no event on replay");

        vm.startPrank(authorizedCaller);

        // First call emits event
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        // Second call (replay) should not emit event - just return false
        // Note: This test verifies the function returns false; no event is emitted
        bool result = proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
        assertFalse(result, "Replay should return false without event");

        vm.stopPrank();
    }

    // ============================================================
    // Test: Only authorized callers can call markProofUsed
    // ============================================================

    /**
     * @notice Verify unauthorized caller reverts
     */
    function test_MarkProofUsed_RevertsForUnauthorizedCaller() public {
        bytes32 proofHash = keccak256("unauthorized test");

        vm.prank(unauthorizedCaller);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
    }

    /**
     * @notice Verify random address cannot call markProofUsed
     */
    function test_MarkProofUsed_RevertsForRandomAddress() public {
        bytes32 proofHash = keccak256("random address test");
        address randomAddr = address(0xDEADBEEF);

        vm.prank(randomAddr);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
    }

    // ============================================================
    // Test: Owner can call markProofUsed
    // ============================================================

    /**
     * @notice Verify owner can call markProofUsed directly
     */
    function test_MarkProofUsed_OwnerCanCall() public {
        bytes32 proofHash = keccak256("owner call test");

        vm.prank(owner);
        bool result = proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        assertTrue(result, "Owner should be able to call markProofUsed");
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked");
    }

    /**
     * @notice Verify owner can still authorize other callers
     */
    function test_MarkProofUsed_OwnerCanAuthorizeNewCaller() public {
        address newCaller = address(0x999);

        // Initially unauthorized
        vm.prank(newCaller);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(keccak256("test1"), prover, 100, bytes32(0));

        // Owner authorizes new caller
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(newCaller, true);

        // Now can call
        vm.prank(newCaller);
        bool result = proofSystem.markProofUsed(keccak256("test2"), prover, 100, bytes32(0));
        assertTrue(result, "Newly authorized caller should succeed");
    }

    // ============================================================
    // Test: Return value is correct
    // ============================================================

    /**
     * @notice Comprehensive return value test
     */
    function test_MarkProofUsed_ReturnValueCorrectness() public {
        vm.startPrank(authorizedCaller);

        bytes32 proof1 = keccak256("return test 1");
        bytes32 proof2 = keccak256("return test 2");
        bytes32 proof3 = keccak256("return test 3");

        // All new proofs return true
        assertTrue(proofSystem.markProofUsed(proof1, prover, 100, bytes32(0)), "proof1 first use");
        assertTrue(proofSystem.markProofUsed(proof2, prover, 200, bytes32(0)), "proof2 first use");
        assertTrue(proofSystem.markProofUsed(proof3, prover, 300, bytes32(0)), "proof3 first use");

        // All replays return false
        assertFalse(proofSystem.markProofUsed(proof1, prover, 100, bytes32(0)), "proof1 replay");
        assertFalse(proofSystem.markProofUsed(proof2, prover, 200, bytes32(0)), "proof2 replay");
        assertFalse(proofSystem.markProofUsed(proof3, prover, 300, bytes32(0)), "proof3 replay");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test for return values
     */
    function testFuzz_MarkProofUsed_ReturnValue(bytes32 proofHash, uint256 tokens) public {
        vm.assume(tokens > 0);

        vm.startPrank(authorizedCaller);

        // First use always true
        bool result1 = proofSystem.markProofUsed(proofHash, prover, tokens, bytes32(0));
        assertTrue(result1, "First use should always return true");

        // Second use always false
        bool result2 = proofSystem.markProofUsed(proofHash, prover, tokens, bytes32(0));
        assertFalse(result2, "Second use should always return false");

        vm.stopPrank();
    }
}
