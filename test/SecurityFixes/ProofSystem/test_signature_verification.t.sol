// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Signature Verification Tests
 * @dev Tests for signature-based proof verification (Sub-phase 1.2)
 *
 * Security Fix: _verifyHostSignature (formerly _verifyEKZL) was returning true for any proof >= 64 bytes
 * without actual verification. Now requires valid ECDSA signature from prover.
 *
 * Proof format: [32 bytes proofHash][32 bytes r][32 bytes s][1 byte v] = 97 bytes
 */
contract ProofSystemSignatureVerificationTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);

    // Use actual private keys for signing tests
    uint256 constant HOST_PRIVATE_KEY = 0xA11CE;
    uint256 constant ATTACKER_PRIVATE_KEY = 0xBAD;

    address public host;
    address public attacker;

    function setUp() public {
        // Derive addresses from private keys
        host = vm.addr(HOST_PRIVATE_KEY);
        attacker = vm.addr(ATTACKER_PRIVATE_KEY);

        // Deploy implementation
        implementation = new ProofSystemUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proxyAddr);
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /**
     * @dev Create a signed proof that the contract can verify
     * @param privateKey The private key to sign with
     * @param proofHash The proof hash (first 32 bytes of proof)
     * @param prover The address that should be recovered (host)
     * @param claimedTokens Number of tokens being claimed
     * @return proof The complete proof bytes: [proofHash][r][s][v]
     */
    function createSignedProof(
        uint256 privateKey,
        bytes32 proofHash,
        address prover,
        uint256 claimedTokens
    ) internal pure returns (bytes memory) {
        // Create the message hash that was signed
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, prover, claimedTokens));
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            dataHash
        ));

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);

        // Pack into proof format: [proofHash][r][s][v]
        return abi.encodePacked(proofHash, r, s, v);
    }

    // ============================================================
    // Valid Signature Tests
    // ============================================================

    function test_ValidSignaturePassesVerification() public view {
        bytes32 proofHash = bytes32(uint256(0x1234));
        uint256 claimedTokens = 100;

        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            host,
            claimedTokens
        );

        bool result = proofSystem.verifyHostSignature(proof, host, claimedTokens);
        assertTrue(result, "Valid signature should pass verification");
    }

    function test_ValidSignatureWithDifferentTokenCounts() public view {
        // Test with various token counts
        uint256[] memory tokenCounts = new uint256[](4);
        tokenCounts[0] = 1;
        tokenCounts[1] = 100;
        tokenCounts[2] = 10000;
        tokenCounts[3] = type(uint128).max;

        for (uint256 i = 0; i < tokenCounts.length; i++) {
            bytes memory proof = createSignedProof(
                HOST_PRIVATE_KEY,
                bytes32(uint256(0x5678 + i)), // Different proof hash each time
                host,
                tokenCounts[i]
            );

            bool result = proofSystem.verifyHostSignature(proof, host, tokenCounts[i]);
            assertTrue(result, "Valid signature should pass for any token count");
        }
    }

    // ============================================================
    // Invalid Signature Tests
    // ============================================================

    function test_InvalidSignatureFails() public view {
        bytes32 proofHash = bytes32(uint256(0xABCD));
        uint256 claimedTokens = 100;

        // Create proof with garbage signature data
        bytes memory invalidProof = abi.encodePacked(
            proofHash,
            bytes32(uint256(0x1111)), // invalid r
            bytes32(uint256(0x2222)), // invalid s
            uint8(27)                  // v
        );

        bool result = proofSystem.verifyHostSignature(invalidProof, host, claimedTokens);
        assertFalse(result, "Invalid signature should fail verification");
    }

    function test_WrongSignerFails() public view {
        bytes32 proofHash = bytes32(uint256(0xDEAD));
        uint256 claimedTokens = 100;

        // Sign with attacker's key but try to verify for host
        bytes memory proof = createSignedProof(
            ATTACKER_PRIVATE_KEY,
            proofHash,
            host,  // Claiming this is from host
            claimedTokens
        );

        // Should fail because signature is from attacker, not host
        bool result = proofSystem.verifyHostSignature(proof, host, claimedTokens);
        assertFalse(result, "Signature from wrong address should fail");
    }

    function test_TamperedProofHashFails() public view {
        bytes32 originalProofHash = bytes32(uint256(0xBEEF));
        bytes32 tamperedProofHash = bytes32(uint256(0xDEAD));
        uint256 claimedTokens = 100;

        // Create valid signature for original proof hash
        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            originalProofHash,
            host,
            claimedTokens
        );

        // Tamper with the proof hash in the proof bytes
        // Replace first 32 bytes with tampered hash
        assembly {
            mstore(add(proof, 32), tamperedProofHash)
        }

        // Should fail because proof hash doesn't match signature
        bool result = proofSystem.verifyHostSignature(proof, host, claimedTokens);
        assertFalse(result, "Tampered proof hash should fail verification");
    }

    function test_TamperedTokenCountFails() public view {
        bytes32 proofHash = bytes32(uint256(0xCAFE));
        uint256 originalTokens = 100;
        uint256 tamperedTokens = 1000; // Attacker tries to claim more

        // Create valid signature for original token count
        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            host,
            originalTokens
        );

        // Try to verify with different token count
        bool result = proofSystem.verifyHostSignature(proof, host, tamperedTokens);
        assertFalse(result, "Tampered token count should fail verification");
    }

    // ============================================================
    // Replay Attack Prevention Tests
    // ============================================================

    function test_ReplayAttackFails() public {
        bytes32 proofHash = bytes32(uint256(0xF00D));
        uint256 claimedTokens = 100;

        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            host,
            claimedTokens
        );

        // First verification should pass
        bool firstResult = proofSystem.verifyAndMarkComplete(proof, host, claimedTokens);
        assertTrue(firstResult, "First verification should pass");

        // Second verification (replay) should fail
        bool replayResult = proofSystem.verifyHostSignature(proof, host, claimedTokens);
        assertFalse(replayResult, "Replay attack should fail");
    }

    function test_SameSignatureDifferentSessionFails() public view {
        bytes32 proofHash = bytes32(uint256(0xBABE));
        uint256 claimedTokens = 100;

        // Create signature for host address
        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            host,
            claimedTokens
        );

        // Try to use the same signature for a different prover address
        address differentProver = address(0x9999);
        bool result = proofSystem.verifyHostSignature(proof, differentProver, claimedTokens);
        assertFalse(result, "Signature for different prover should fail");
    }

    // ============================================================
    // Edge Case Tests
    // ============================================================

    function test_TooShortProofFails() public view {
        // Proof needs to be at least 97 bytes: 32 (hash) + 32 (r) + 32 (s) + 1 (v)
        bytes memory shortProof = abi.encodePacked(
            bytes32(uint256(0x1234)),
            bytes32(uint256(0x5678))
        ); // Only 64 bytes

        bool result = proofSystem.verifyHostSignature(shortProof, host, 100);
        assertFalse(result, "Too short proof should fail");
    }

    function test_ZeroTokensFails() public view {
        bytes32 proofHash = bytes32(uint256(0x1111));

        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            host,
            0  // Zero tokens
        );

        bool result = proofSystem.verifyHostSignature(proof, host, 0);
        assertFalse(result, "Zero tokens should fail");
    }

    function test_ZeroProverFails() public view {
        bytes32 proofHash = bytes32(uint256(0x2222));

        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            address(0),
            100
        );

        bool result = proofSystem.verifyHostSignature(proof, address(0), 100);
        assertFalse(result, "Zero prover address should fail");
    }

    function test_InvalidVValueHandled() public view {
        bytes32 proofHash = bytes32(uint256(0x3333));
        uint256 claimedTokens = 100;

        // Create proof with invalid v value (not 27 or 28)
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, host, claimedTokens));
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            dataHash
        ));

        (, bytes32 r, bytes32 s) = vm.sign(HOST_PRIVATE_KEY, messageHash);

        // Corrupt v value
        uint8 invalidV = 99;
        bytes memory invalidProof = abi.encodePacked(proofHash, r, s, invalidV);

        bool result = proofSystem.verifyHostSignature(invalidProof, host, claimedTokens);
        assertFalse(result, "Invalid v value should fail or return zero address");
    }

    // ============================================================
    // Fuzz Tests
    // ============================================================

    function testFuzz_ValidSignatureAlwaysPasses(
        bytes32 proofHash,
        uint256 claimedTokens
    ) public view {
        // Bound inputs to valid ranges
        vm.assume(claimedTokens > 0);
        vm.assume(proofHash != bytes32(0));

        bytes memory proof = createSignedProof(
            HOST_PRIVATE_KEY,
            proofHash,
            host,
            claimedTokens
        );

        bool result = proofSystem.verifyHostSignature(proof, host, claimedTokens);
        assertTrue(result, "Valid signature should always pass");
    }

    function testFuzz_WrongSignerAlwaysFails(
        bytes32 proofHash,
        uint256 claimedTokens
    ) public view {
        vm.assume(claimedTokens > 0);
        vm.assume(proofHash != bytes32(0));

        // Sign with attacker key
        bytes memory proof = createSignedProof(
            ATTACKER_PRIVATE_KEY,
            proofHash,
            host,
            claimedTokens
        );

        // Verify for host - should fail
        bool result = proofSystem.verifyHostSignature(proof, host, claimedTokens);
        assertFalse(result, "Wrong signer should always fail");
    }
}
