// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Production Readiness Tests
 * @dev Tests to verify the contract is production-ready after dead code removal
 *
 * Verifies:
 * - All state-changing functions have proper access control
 * - Contract behaves securely under various conditions
 * - Only markProofUsed and setAuthorizedCaller remain as state-changing functions
 */
contract ProofSystemProductionReadyTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public unauthorizedUser = address(0x2);
    address public authorizedCaller = address(0x3);

    event AuthorizedCallerUpdated(address indexed caller, bool authorized);
    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);

    function setUp() public {
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

    function test_MarkProofUsedRequiresAuthorization() public {
        bytes32 proofHash = bytes32(uint256(0x1234));

        vm.prank(unauthorizedUser);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));
    }

    function test_SetAuthorizedCallerRequiresOwner() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
    }

    function test_UpgradeRequiresOwner() public {
        ProofSystemUpgradeable newImpl = new ProofSystemUpgradeable();

        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.upgradeToAndCall(address(newImpl), "");
    }

    // ============================================================
    // State-Changing Function Security Tests
    // ============================================================

    function test_AllStateChangingFunctionsHaveAccessControl() public {
        // 1. markProofUsed - requires authorizedCallers or owner
        vm.prank(unauthorizedUser);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(bytes32(uint256(1)), address(0xBEEF), 100, bytes32(0));

        // 2. setAuthorizedCaller - requires owner (onlyOwner modifier)
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(address(0x100), true);

        // 3. upgradeToAndCall - requires owner (via _authorizeUpgrade)
        ProofSystemUpgradeable newImpl = new ProofSystemUpgradeable();
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.upgradeToAndCall(address(newImpl), "");
    }

    // ============================================================
    // View Functions (No Access Control Needed)
    // ============================================================

    function test_ViewFunctionsArePermissionless() public view {
        // 1. verifiedProofs - public mapping
        proofSystem.verifiedProofs(bytes32(uint256(1)));

        // 2. authorizedCallers - public mapping
        proofSystem.authorizedCallers(address(0x100));

        // 3. owner - inherited from OwnableUpgradeable
        proofSystem.owner();
    }

    // ============================================================
    // No Backdoors Test
    // ============================================================

    function test_NoUnauthorizedStateModification() public {
        vm.startPrank(unauthorizedUser);

        // Try to mark a proof
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(bytes32(uint256(1)), address(0xBEEF), 100, bytes32(0));

        // Try to authorize a caller
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(unauthorizedUser, true);

        // Try to upgrade
        vm.expectRevert();
        proofSystem.upgradeToAndCall(address(implementation), "");

        vm.stopPrank();

        // Verify no state was modified
        assertFalse(proofSystem.verifiedProofs(bytes32(uint256(1))));
        assertFalse(proofSystem.authorizedCallers(unauthorizedUser));
    }

    // ============================================================
    // Authorized Operations Work Correctly
    // ============================================================

    function test_OwnerCanPerformAllAuthorizedOperations() public {
        vm.startPrank(owner);

        // Owner can authorize callers
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
        assertTrue(proofSystem.authorizedCallers(authorizedCaller));

        // Owner can mark proofs
        proofSystem.markProofUsed(bytes32(uint256(0x1111)), address(0xBEEF), 100, bytes32(0));
        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(0x1111))));

        vm.stopPrank();
    }

    function test_AuthorizedCallerCanMarkProofs() public {
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        vm.prank(authorizedCaller);
        proofSystem.markProofUsed(bytes32(uint256(0x3333)), address(0xBEEF), 100, bytes32(0));

        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(0x3333))));
    }

    // ============================================================
    // Contract Initialization Security
    // ============================================================

    function test_CannotReinitialize() public {
        vm.expectRevert();
        proofSystem.initialize();
    }

    function test_ImplementationCannotBeInitialized() public {
        vm.expectRevert();
        implementation.initialize();
    }

    // ============================================================
    // Event Emission Verification
    // ============================================================

    function test_EventsEmittedCorrectly() public {
        vm.startPrank(owner);

        // AuthorizedCallerUpdated event
        vm.expectEmit(true, false, false, true);
        emit AuthorizedCallerUpdated(authorizedCaller, true);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        // ProofVerified event
        vm.expectEmit(true, true, false, true);
        emit ProofVerified(bytes32(uint256(0x4444)), address(0xBEEF), 100);
        proofSystem.markProofUsed(bytes32(uint256(0x4444)), address(0xBEEF), 100, bytes32(0));

        vm.stopPrank();
    }
}
