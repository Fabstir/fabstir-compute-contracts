// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Production Readiness Tests
 * @dev Tests to verify the contract is production-ready (Sub-phase 1.4)
 *
 * Verifies:
 * - No unsafe testing functions remain
 * - All state-changing functions have proper access control
 * - Contract behaves securely under various conditions
 */
contract ProofSystemProductionReadyTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public unauthorizedUser = address(0x2);
    address public authorizedCaller = address(0x3);

    // Use actual private key for signing tests
    uint256 constant PROVER_PRIVATE_KEY = 0xA11CE;
    address public prover;

    function setUp() public {
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
    // Access Control Verification Tests
    // ============================================================

    function test_RecordVerifiedProofRequiresAuthorization() public {
        bytes32 proofHash = bytes32(uint256(0x1234));

        // Unauthorized user should fail
        vm.prank(unauthorizedUser);
        vm.expectRevert("Unauthorized");
        proofSystem.recordVerifiedProof(proofHash);
    }

    function test_SetAuthorizedCallerRequiresOwner() public {
        // Non-owner should fail
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
    }

    function test_RegisterModelCircuitRequiresOwner() public {
        // Non-owner should fail
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.registerModelCircuit(address(0x100), bytes32(uint256(1)));
    }

    function test_UpgradeRequiresOwner() public {
        ProofSystemUpgradeable newImpl = new ProofSystemUpgradeable();

        // Non-owner should fail
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.upgradeToAndCall(address(newImpl), "");
    }

    // ============================================================
    // State-Changing Function Security Tests
    // ============================================================

    function test_AllStateChangingFunctionsHaveAccessControl() public {
        // This test documents all state-changing functions and their access control

        // 1. recordVerifiedProof - requires authorizedCallers or owner
        vm.prank(unauthorizedUser);
        vm.expectRevert("Unauthorized");
        proofSystem.recordVerifiedProof(bytes32(uint256(1)));

        // 2. setAuthorizedCaller - requires owner (onlyOwner modifier)
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(address(0x100), true);

        // 3. registerModelCircuit - requires owner (onlyOwner modifier)
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.registerModelCircuit(address(0x100), bytes32(uint256(1)));

        // 4. verifyAndMarkComplete - no access control needed (anyone can verify)
        // This is intentional - verification is permissionless but records proof hash

        // 5. verifyBatch - no access control needed (anyone can verify batch)
        // This is intentional - batch verification is permissionless but records proof hashes

        // 6. upgradeToAndCall - requires owner (via _authorizeUpgrade)
        ProofSystemUpgradeable newImpl = new ProofSystemUpgradeable();
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.upgradeToAndCall(address(newImpl), "");
    }

    // ============================================================
    // View Functions (No Access Control Needed)
    // ============================================================

    function test_ViewFunctionsArePermissionless() public view {
        // These functions are intentionally permissionless

        // 1. verifyEKZL - read-only verification
        bytes memory proof = new bytes(97);
        proofSystem.verifyEKZL(proof, prover, 100);

        // 2. verifiedProofs - public mapping
        proofSystem.verifiedProofs(bytes32(uint256(1)));

        // 3. authorizedCallers - public mapping
        proofSystem.authorizedCallers(address(0x100));

        // 4. registeredCircuits - public mapping
        proofSystem.registeredCircuits(bytes32(uint256(1)));

        // 5. modelCircuits - public mapping
        proofSystem.modelCircuits(address(0x100));

        // 6. isCircuitRegistered - view function
        proofSystem.isCircuitRegistered(bytes32(uint256(1)));

        // 7. getModelCircuit - view function
        proofSystem.getModelCircuit(address(0x100));

        // 8. verifyBatchView - view function
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = new bytes(97);
        uint256[] memory tokenCounts = new uint256[](1);
        tokenCounts[0] = 100;
        proofSystem.verifyBatchView(proofs, prover, tokenCounts);

        // 9. estimateBatchGas - pure function
        proofSystem.estimateBatchGas(1);

        // 10. owner - inherited from OwnableUpgradeable
        proofSystem.owner();
    }

    // ============================================================
    // No Backdoors Test
    // ============================================================

    function test_NoUnauthorizedStateModification() public {
        // Attempt all possible state modifications as unauthorized user
        vm.startPrank(unauthorizedUser);

        // Try to record a proof
        vm.expectRevert("Unauthorized");
        proofSystem.recordVerifiedProof(bytes32(uint256(1)));

        // Try to authorize a caller
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(unauthorizedUser, true);

        // Try to register a circuit
        vm.expectRevert();
        proofSystem.registerModelCircuit(unauthorizedUser, bytes32(uint256(1)));

        // Try to upgrade
        vm.expectRevert();
        proofSystem.upgradeToAndCall(address(implementation), "");

        vm.stopPrank();

        // Verify no state was modified
        assertFalse(proofSystem.verifiedProofs(bytes32(uint256(1))));
        assertFalse(proofSystem.authorizedCallers(unauthorizedUser));
        assertFalse(proofSystem.registeredCircuits(bytes32(uint256(1))));
    }

    // ============================================================
    // Authorized Operations Work Correctly
    // ============================================================

    function test_OwnerCanPerformAllAuthorizedOperations() public {
        vm.startPrank(owner);

        // Owner can authorize callers
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
        assertTrue(proofSystem.authorizedCallers(authorizedCaller));

        // Owner can record proofs
        proofSystem.recordVerifiedProof(bytes32(uint256(0x1111)));
        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(0x1111))));

        // Owner can register circuits
        proofSystem.registerModelCircuit(address(0x100), bytes32(uint256(0x2222)));
        assertTrue(proofSystem.isCircuitRegistered(bytes32(uint256(0x2222))));

        vm.stopPrank();
    }

    function test_AuthorizedCallerCanRecordProofs() public {
        // First authorize the caller
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        // Authorized caller can record proofs
        vm.prank(authorizedCaller);
        proofSystem.recordVerifiedProof(bytes32(uint256(0x3333)));

        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(0x3333))));
    }

    // ============================================================
    // Contract Initialization Security
    // ============================================================

    function test_CannotReinitialize() public {
        // Contract cannot be reinitialized
        vm.expectRevert();
        proofSystem.initialize();
    }

    function test_ImplementationCannotBeInitialized() public {
        // Implementation contract cannot be initialized
        vm.expectRevert();
        implementation.initialize();
    }

    // ============================================================
    // Event Emission Verification
    // ============================================================

    event AuthorizedCallerUpdated(address indexed caller, bool authorized);
    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);
    event CircuitRegistered(bytes32 indexed circuitHash, address indexed model);

    function test_EventsEmittedCorrectly() public {
        vm.startPrank(owner);

        // AuthorizedCallerUpdated event
        vm.expectEmit(true, false, false, true);
        emit AuthorizedCallerUpdated(authorizedCaller, true);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        // ProofVerified event
        vm.expectEmit(true, true, false, true);
        emit ProofVerified(bytes32(uint256(0x4444)), owner, 0);
        proofSystem.recordVerifiedProof(bytes32(uint256(0x4444)));

        // CircuitRegistered event
        vm.expectEmit(true, true, false, false);
        emit CircuitRegistered(bytes32(uint256(0x5555)), address(0x100));
        proofSystem.registerModelCircuit(address(0x100), bytes32(uint256(0x5555)));

        vm.stopPrank();
    }
}
