// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystem No Signature Tests (AUDIT REMEDIATION)
 * @notice Comprehensive tests for Sub-phase 1.3: Verify ProofSystem works without signature verification
 *
 * AUDIT REMEDIATION: Remove redundant signature verification
 * - Signature was redundant because msg.sender == session.host already authenticates
 * - ProofSystem now provides replay protection only via markProofUsed()
 * - Gas savings: ~3,000+ gas per proof submission (ecrecover removal)
 */
contract ProofSystemNoSignatureTest is Test {
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public authorizedCaller = address(0x2);  // Simulates JobMarketplace
    address public unauthorizedCaller = address(0x3);
    address public prover = address(0x4);

    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy ProofSystem as proxy
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
    // Test: Replay protection works (same proofHash rejected twice)
    // ============================================================

    /**
     * @notice Verify replay protection - first call succeeds, second fails
     */
    function test_ReplayProtection_SameHashRejected() public {
        bytes32 proofHash = keccak256("test proof");
        uint256 tokens = 500;
        bytes32 modelId = bytes32(0);

        vm.startPrank(authorizedCaller);

        // First call should succeed
        bool result1 = proofSystem.markProofUsed(proofHash, prover, tokens, modelId);
        assertTrue(result1, "First call should succeed");

        // Second call with same hash should return false
        bool result2 = proofSystem.markProofUsed(proofHash, prover, tokens, modelId);
        assertFalse(result2, "Replay should return false");

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test replay protection with random hashes
     */
    function testFuzz_ReplayProtection(bytes32 proofHash, uint256 tokens) public {
        vm.assume(tokens > 0);

        vm.startPrank(authorizedCaller);

        bool result1 = proofSystem.markProofUsed(proofHash, prover, tokens, bytes32(0));
        assertTrue(result1, "First call should always succeed");

        bool result2 = proofSystem.markProofUsed(proofHash, prover, tokens, bytes32(0));
        assertFalse(result2, "Replay should always fail");

        vm.stopPrank();
    }

    // ============================================================
    // Test: Different proofHashes accepted
    // ============================================================

    /**
     * @notice Verify different proof hashes are all accepted
     */
    function test_DifferentHashesAccepted() public {
        vm.startPrank(authorizedCaller);

        for (uint256 i = 0; i < 10; i++) {
            bytes32 proofHash = keccak256(abi.encodePacked("proof", i, block.timestamp));
            bool result = proofSystem.markProofUsed(proofHash, prover, 100 * (i + 1), bytes32(i));
            assertTrue(result, "Each unique hash should succeed");
        }

        vm.stopPrank();
    }

    /**
     * @notice Verify same content but different hashing produces different results
     */
    function test_HashCollisionSafe() public {
        bytes32 proofHash1 = keccak256(abi.encodePacked("proof", uint256(1)));
        bytes32 proofHash2 = keccak256(abi.encodePacked("proof1")); // Different encoding

        vm.startPrank(authorizedCaller);

        bool result1 = proofSystem.markProofUsed(proofHash1, prover, 100, bytes32(0));
        assertTrue(result1, "First hash should succeed");

        bool result2 = proofSystem.markProofUsed(proofHash2, prover, 100, bytes32(0));
        assertTrue(result2, "Different hash should also succeed");

        vm.stopPrank();
    }

    // ============================================================
    // Test: Unauthorized caller reverts
    // ============================================================

    /**
     * @notice Verify unauthorized caller cannot mark proofs
     */
    function test_UnauthorizedCaller_Reverts() public {
        bytes32 proofHash = keccak256("unauthorized test");

        vm.prank(unauthorizedCaller);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
    }

    /**
     * @notice Verify random addresses cannot mark proofs
     */
    function testFuzz_RandomAddressCannot_MarkProof(address randomAddr) public {
        vm.assume(randomAddr != owner);
        vm.assume(randomAddr != authorizedCaller);
        vm.assume(randomAddr != address(0));

        bytes32 proofHash = keccak256(abi.encodePacked("random", randomAddr));

        vm.prank(randomAddr);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
    }

    // ============================================================
    // Test: Authorized caller succeeds
    // ============================================================

    /**
     * @notice Verify authorized caller can mark proofs
     */
    function test_AuthorizedCaller_Succeeds() public {
        bytes32 proofHash = keccak256("authorized test");

        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, prover, 500, bytes32(0));

        assertTrue(result, "Authorized caller should succeed");
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked");
    }

    /**
     * @notice Verify multiple authorized callers can coexist
     */
    function test_MultipleAuthorizedCallers() public {
        address anotherCaller = address(0x999);

        // Authorize another caller
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(anotherCaller, true);

        // Both should be able to mark different proofs
        bytes32 hash1 = keccak256("caller1 proof");
        bytes32 hash2 = keccak256("caller2 proof");

        vm.prank(authorizedCaller);
        bool result1 = proofSystem.markProofUsed(hash1, prover, 100, bytes32(0));
        assertTrue(result1, "First caller should succeed");

        vm.prank(anotherCaller);
        bool result2 = proofSystem.markProofUsed(hash2, prover, 200, bytes32(0));
        assertTrue(result2, "Second caller should succeed");
    }

    // ============================================================
    // Test: Owner can mark proofs
    // ============================================================

    /**
     * @notice Verify owner can always mark proofs (regardless of authorizedCallers)
     */
    function test_Owner_CanMarkProofs() public {
        bytes32 proofHash = keccak256("owner test");

        vm.prank(owner);
        bool result = proofSystem.markProofUsed(proofHash, prover, 1000, bytes32(uint256(1)));

        assertTrue(result, "Owner should always be able to mark proofs");
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked");
    }

    /**
     * @notice Verify owner can mark proofs even if not in authorizedCallers
     */
    function test_Owner_CanMarkProofs_NotExplicitlyAuthorized() public {
        // Verify owner is not in authorizedCallers mapping
        assertFalse(proofSystem.authorizedCallers(owner), "Owner should not be in authorizedCallers by default");

        bytes32 proofHash = keccak256("owner implicit test");

        vm.prank(owner);
        bool result = proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        assertTrue(result, "Owner should succeed even without explicit authorization");
    }

    // ============================================================
    // Test: ProofVerified event emitted correctly
    // ============================================================

    /**
     * @notice Verify ProofVerified event emitted with correct parameters
     */
    function test_Event_ProofVerified_EmittedCorrectly() public {
        bytes32 proofHash = keccak256("event test");
        uint256 tokens = 1234;

        vm.prank(authorizedCaller);

        vm.expectEmit(true, true, true, true);
        emit ProofVerified(proofHash, prover, tokens);

        proofSystem.markProofUsed(proofHash, prover, tokens, bytes32(0));
    }

    /**
     * @notice Verify event includes correct prover address
     */
    function testFuzz_Event_ContainsCorrectProver(address testProver) public {
        vm.assume(testProver != address(0));

        bytes32 proofHash = keccak256(abi.encodePacked("prover test", testProver));

        vm.prank(authorizedCaller);

        vm.expectEmit(true, true, true, true);
        emit ProofVerified(proofHash, testProver, 100);

        proofSystem.markProofUsed(proofHash, testProver, 100, bytes32(0));
    }

    /**
     * @notice Verify no event on replay (returns false, no event)
     */
    function test_Event_NotEmitted_OnReplay() public {
        bytes32 proofHash = keccak256("replay event test");

        vm.startPrank(authorizedCaller);

        // First call emits event
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        // Second call should NOT emit event (just return false)
        // We can't easily test "no event emitted" in Foundry, but we can verify return value
        bool result = proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
        assertFalse(result, "Replay should return false without event");

        vm.stopPrank();
    }

    // ============================================================
    // Test: Return value is correct (true for new, false for replay)
    // ============================================================

    /**
     * @notice Comprehensive return value verification
     */
    function test_ReturnValue_Comprehensive() public {
        vm.startPrank(authorizedCaller);

        bytes32[] memory hashes = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            hashes[i] = keccak256(abi.encodePacked("hash", i));
        }

        // All first calls return true
        for (uint256 i = 0; i < 5; i++) {
            bool result = proofSystem.markProofUsed(hashes[i], prover, 100, bytes32(0));
            assertTrue(result, "First call should return true");
        }

        // All second calls return false
        for (uint256 i = 0; i < 5; i++) {
            bool result = proofSystem.markProofUsed(hashes[i], prover, 100, bytes32(0));
            assertFalse(result, "Replay should return false");
        }

        vm.stopPrank();
    }

    /**
     * @notice Verify return value doesn't depend on token count or model
     */
    function test_ReturnValue_IndependentOfParams() public {
        bytes32 proofHash = keccak256("param test");

        vm.startPrank(authorizedCaller);

        // First call with specific params
        bool result1 = proofSystem.markProofUsed(proofHash, prover, 100, bytes32(uint256(1)));
        assertTrue(result1, "First call should succeed");

        // Second call with different params but same hash should still fail
        bool result2 = proofSystem.markProofUsed(proofHash, address(0x999), 99999, bytes32(uint256(2)));
        assertFalse(result2, "Replay should fail regardless of other params");

        vm.stopPrank();
    }

    // ============================================================
    // Test: verifiedProofs mapping updated correctly
    // ============================================================

    /**
     * @notice Verify verifiedProofs mapping is set after markProofUsed
     */
    function test_VerifiedProofs_SetCorrectly() public {
        bytes32 proofHash = keccak256("mapping test");

        assertFalse(proofSystem.verifiedProofs(proofHash), "Should be false initially");

        vm.prank(authorizedCaller);
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        assertTrue(proofSystem.verifiedProofs(proofHash), "Should be true after markProofUsed");
    }

    /**
     * @notice Verify verifiedProofs is permanent (can't be unset)
     */
    function test_VerifiedProofs_Permanent() public {
        bytes32 proofHash = keccak256("permanent test");

        vm.prank(authorizedCaller);
        proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));

        assertTrue(proofSystem.verifiedProofs(proofHash), "Should be marked");

        // Multiple replay attempts don't change state
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(authorizedCaller);
            proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
        }

        assertTrue(proofSystem.verifiedProofs(proofHash), "Should still be marked");
    }

    // ============================================================
    // Test: recordVerifiedProof still works (backwards compat)
    // ============================================================

    /**
     * @notice Verify recordVerifiedProof still works for backwards compatibility
     */
    function test_RecordVerifiedProof_StillWorks() public {
        bytes32 proofHash = keccak256("record test");

        assertFalse(proofSystem.verifiedProofs(proofHash), "Should be false initially");

        vm.prank(owner);
        proofSystem.recordVerifiedProof(proofHash);

        assertTrue(proofSystem.verifiedProofs(proofHash), "Should be true after record");
    }

    /**
     * @notice Verify recordVerifiedProof blocks markProofUsed for same hash
     */
    function test_RecordVerifiedProof_BlocksMarkProofUsed() public {
        bytes32 proofHash = keccak256("cross test");

        // Record via recordVerifiedProof
        vm.prank(owner);
        proofSystem.recordVerifiedProof(proofHash);

        // markProofUsed should return false
        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, prover, 100, bytes32(0));
        assertFalse(result, "markProofUsed should fail after recordVerifiedProof");
    }

    // ============================================================
    // Test: Authorization management
    // ============================================================

    /**
     * @notice Verify setAuthorizedCaller works correctly
     */
    function test_SetAuthorizedCaller() public {
        address newCaller = address(0x888);

        assertFalse(proofSystem.authorizedCallers(newCaller), "Should not be authorized initially");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AuthorizedCallerUpdated(newCaller, true);
        proofSystem.setAuthorizedCaller(newCaller, true);

        assertTrue(proofSystem.authorizedCallers(newCaller), "Should be authorized");
    }

    /**
     * @notice Verify authorization can be revoked
     */
    function test_RevokeAuthorization() public {
        // Verify currently authorized
        assertTrue(proofSystem.authorizedCallers(authorizedCaller), "Should be authorized");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AuthorizedCallerUpdated(authorizedCaller, false);
        proofSystem.setAuthorizedCaller(authorizedCaller, false);

        assertFalse(proofSystem.authorizedCallers(authorizedCaller), "Should no longer be authorized");

        // Should now fail to mark proofs
        vm.prank(authorizedCaller);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(keccak256("revoked test"), prover, 100, bytes32(0));
    }

    /**
     * @notice Verify only owner can set authorized callers
     */
    function test_OnlyOwner_CanSetAuthorizedCaller() public {
        address newCaller = address(0x777);

        vm.prank(authorizedCaller);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(newCaller, true);

        vm.prank(unauthorizedCaller);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(newCaller, true);
    }
}
