// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystem Cleanup Tests
 * @dev Verifies the cleaned ProofSystem works correctly with ONLY active functions.
 *      Tests that dead circuit/verification code has been removed.
 */
contract ProofSystemCleanupTest is Test {
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public authorizedCaller = address(0x2);
    address public unauthorized = address(0x3);
    address public prover = address(0xA11CE);

    bytes32 constant PROOF_HASH_1 = bytes32(uint256(0xABCD));
    bytes32 constant PROOF_HASH_2 = bytes32(uint256(0xEF01));
    bytes32 constant MODEL_ID = bytes32(0);

    function setUp() public {
        ProofSystemUpgradeable implementation = new ProofSystemUpgradeable();

        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proxyAddr);

        // Authorize a caller
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
    }

    // ============================================================
    // markProofUsed — Active Function Tests
    // ============================================================

    function test_MarkProofUsed_AuthorizedCaller() public {
        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(PROOF_HASH_1, prover, 100, MODEL_ID);
        assertTrue(result, "Should succeed for authorized caller");
        assertTrue(proofSystem.verifiedProofs(PROOF_HASH_1));
    }

    function test_MarkProofUsed_RevertsUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(PROOF_HASH_1, prover, 100, MODEL_ID);
    }

    function test_MarkProofUsed_ReturnsFalseOnReplay() public {
        vm.prank(authorizedCaller);
        proofSystem.markProofUsed(PROOF_HASH_1, prover, 100, MODEL_ID);

        vm.prank(authorizedCaller);
        bool replay = proofSystem.markProofUsed(PROOF_HASH_1, prover, 100, MODEL_ID);
        assertFalse(replay, "Replay should return false");
    }

    // ============================================================
    // setAuthorizedCaller — Active Function Tests
    // ============================================================

    function test_SetAuthorizedCaller_WorksForOwner() public {
        address newCaller = address(0x99);
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(newCaller, true);
        assertTrue(proofSystem.authorizedCallers(newCaller));
    }

    function test_SetAuthorizedCaller_RevertsForNonOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(address(0x99), true);
    }

    // ============================================================
    // Dead Function Removal — Negative Tests
    // ============================================================

    function test_NoRegisterModelCircuit() public {
        // registerModelCircuit(address,bytes32) should not exist
        bytes memory callData = abi.encodeWithSignature(
            "registerModelCircuit(address,bytes32)",
            address(0x100),
            bytes32(uint256(0x1234))
        );
        (bool success, ) = address(proofSystem).call(callData);
        assertFalse(success, "registerModelCircuit should not exist");
    }

    function test_NoIsCircuitRegistered() public {
        bytes memory callData = abi.encodeWithSignature(
            "isCircuitRegistered(bytes32)",
            bytes32(uint256(0x1234))
        );
        (bool success, ) = address(proofSystem).call(callData);
        assertFalse(success, "isCircuitRegistered should not exist");
    }

    function test_NoGetModelCircuit() public {
        bytes memory callData = abi.encodeWithSignature(
            "getModelCircuit(address)",
            address(0x100)
        );
        (bool success, ) = address(proofSystem).call(callData);
        assertFalse(success, "getModelCircuit should not exist");
    }

    function test_NoRecordVerifiedProof() public {
        bytes memory callData = abi.encodeWithSignature(
            "recordVerifiedProof(bytes32)",
            bytes32(uint256(0x1234))
        );
        vm.prank(owner);
        (bool success, ) = address(proofSystem).call(callData);
        assertFalse(success, "recordVerifiedProof should not exist");
    }
}
