// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Initialization Tests
 * @dev Tests initialization, re-initialization protection, and basic proxy functionality
 */
contract ProofSystemInitializationTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public user1 = address(0x2);

    // Use actual private key for signing tests (prover derived from this)
    uint256 constant PROVER_PRIVATE_KEY = 0xA11CE;
    address public prover;

    function setUp() public {
        // Derive prover address from private key
        prover = vm.addr(PROVER_PRIVATE_KEY);
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
     * @dev Create a signed proof for testing
     * @param proofHash The proof hash (first 32 bytes)
     * @param claimedTokens Number of tokens being claimed
     * @return proof The complete signed proof bytes
     */
    function createSignedProof(
        bytes32 proofHash,
        uint256 claimedTokens
    ) internal view returns (bytes memory) {
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, prover, claimedTokens));
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            dataHash
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PROVER_PRIVATE_KEY, messageHash);
        return abi.encodePacked(proofHash, r, s, v);
    }

    // ============================================================
    // Initialization Tests
    // ============================================================

    function test_InitializeSetsOwner() public view {
        assertEq(proofSystem.owner(), owner);
    }

    function test_InitializeCanOnlyBeCalledOnce() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        proofSystem.initialize();
    }

    function test_ImplementationCannotBeInitialized() public {
        // Try to initialize implementation directly - should revert
        vm.expectRevert();
        implementation.initialize();
    }

    // ============================================================
    // Basic Functionality Through Proxy Tests
    // ============================================================

    function test_VerifyEKZLWithValidProof() public view {
        bytes32 proofHash = bytes32(uint256(1));
        uint256 claimedTokens = 100;

        bytes memory proof = createSignedProof(proofHash, claimedTokens);

        bool result = proofSystem.verifyEKZL(proof, prover, claimedTokens);
        assertTrue(result);
    }

    function test_VerifyEKZLRejectsShortProof() public view {
        bytes memory shortProof = abi.encodePacked(bytes32(uint256(1))); // Only 32 bytes

        bool result = proofSystem.verifyEKZL(shortProof, prover, 100);
        assertFalse(result);
    }

    function test_VerifyEKZLRejectsZeroTokens() public view {
        bytes memory proof = abi.encodePacked(
            bytes32(uint256(1)),
            bytes32(uint256(2))
        );

        bool result = proofSystem.verifyEKZL(proof, prover, 0);
        assertFalse(result);
    }

    function test_VerifyEKZLRejectsZeroProver() public view {
        bytes memory proof = abi.encodePacked(
            bytes32(uint256(1)),
            bytes32(uint256(2))
        );

        bool result = proofSystem.verifyEKZL(proof, address(0), 100);
        assertFalse(result);
    }

    function test_VerifyAndMarkCompleteWorks() public {
        bytes32 proofHash = bytes32(uint256(0x1234));
        uint256 claimedTokens = 100;

        bytes memory proof = createSignedProof(proofHash, claimedTokens);

        bool result = proofSystem.verifyAndMarkComplete(proof, prover, claimedTokens);
        assertTrue(result);

        // Verify proof is now marked as verified (replay should fail)
        bool replayResult = proofSystem.verifyEKZL(proof, prover, claimedTokens);
        assertFalse(replayResult);
    }

    function test_RecordVerifiedProofWorks() public {
        bytes32 proofHash = bytes32(uint256(0xABCD));

        vm.prank(owner);  // Owner authorization required after security fix
        proofSystem.recordVerifiedProof(proofHash);

        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_RegisterModelCircuitOnlyOwner() public {
        address model = address(0x100);
        bytes32 circuitHash = bytes32(uint256(0x200));

        // Non-owner should fail
        vm.prank(user1);
        vm.expectRevert();
        proofSystem.registerModelCircuit(model, circuitHash);

        // Owner should succeed
        vm.prank(owner);
        proofSystem.registerModelCircuit(model, circuitHash);

        assertTrue(proofSystem.isCircuitRegistered(circuitHash));
        assertEq(proofSystem.getModelCircuit(model), circuitHash);
    }

    function test_RegisterModelCircuitValidation() public {
        vm.startPrank(owner);

        // Invalid model address
        vm.expectRevert("Invalid model");
        proofSystem.registerModelCircuit(address(0), bytes32(uint256(1)));

        // Invalid circuit hash
        vm.expectRevert("Invalid circuit");
        proofSystem.registerModelCircuit(address(0x100), bytes32(0));

        vm.stopPrank();
    }

    function test_BatchVerificationWorks() public {
        uint256[] memory tokenCounts = new uint256[](2);
        tokenCounts[0] = 100;
        tokenCounts[1] = 200;

        bytes[] memory proofs = new bytes[](2);
        proofs[0] = createSignedProof(bytes32(uint256(1)), tokenCounts[0]);
        proofs[1] = createSignedProof(bytes32(uint256(3)), tokenCounts[1]);

        bool result = proofSystem.verifyBatch(proofs, prover, tokenCounts);
        assertTrue(result);
    }

    function test_BatchVerificationLengthMismatch() public {
        bytes[] memory proofs = new bytes[](2);
        proofs[0] = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)));
        proofs[1] = abi.encodePacked(bytes32(uint256(3)), bytes32(uint256(4)));

        uint256[] memory tokenCounts = new uint256[](1);
        tokenCounts[0] = 100;

        vm.expectRevert("Length mismatch");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }

    function test_BatchVerificationEmptyBatch() public {
        bytes[] memory proofs = new bytes[](0);
        uint256[] memory tokenCounts = new uint256[](0);

        vm.expectRevert("Empty batch");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }

    function test_BatchVerificationTooLarge() public {
        bytes[] memory proofs = new bytes[](11);
        uint256[] memory tokenCounts = new uint256[](11);

        for (uint i = 0; i < 11; i++) {
            proofs[i] = abi.encodePacked(bytes32(uint256(i + 1)), bytes32(uint256(i + 100)));
            tokenCounts[i] = 100;
        }

        vm.expectRevert("Batch too large");
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
    }

    function test_VerifyBatchViewWorks() public view {
        uint256[] memory tokenCounts = new uint256[](2);
        tokenCounts[0] = 100;
        tokenCounts[1] = 200;

        bytes[] memory proofs = new bytes[](2);
        proofs[0] = createSignedProof(bytes32(uint256(0x100)), tokenCounts[0]);
        proofs[1] = createSignedProof(bytes32(uint256(0x200)), tokenCounts[1]);

        bool[] memory results = proofSystem.verifyBatchView(proofs, prover, tokenCounts);
        assertEq(results.length, 2);
        assertTrue(results[0]);
        assertTrue(results[1]);
    }

    function test_EstimateBatchGas() public view {
        // New constants: BASE = 15000, PER_PROOF = 27000
        // Based on actual gas measurements from verifyBatch()
        assertEq(proofSystem.estimateBatchGas(1), 42000);   // 15000 + 1*27000
        assertEq(proofSystem.estimateBatchGas(5), 150000);  // 15000 + 5*27000
        assertEq(proofSystem.estimateBatchGas(10), 285000); // 15000 + 10*27000
    }
}
