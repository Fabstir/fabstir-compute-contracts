// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Access Control Tests
 * @dev Tests for markProofUsed access control (Sub-phase 1.1)
 *
 * Security Fix: proof recording was callable by anyone, enabling front-running
 * attacks where malicious actors could mark proof hashes as used before legitimate
 * hosts submit their proofs.
 */
contract ProofSystemAccessControlTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public authorizedCaller = address(0x2);  // e.g., JobMarketplace
    address public unauthorizedUser = address(0x3);
    address public anotherUser = address(0x4);

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
    // setAuthorizedCaller Tests
    // ============================================================

    function test_OwnerCanAuthorizeCallers() public {
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        assertTrue(proofSystem.authorizedCallers(authorizedCaller));
    }

    function test_OwnerCanRevokeAuthorization() public {
        // First authorize
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
        assertTrue(proofSystem.authorizedCallers(authorizedCaller));

        // Then revoke
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, false);
        assertFalse(proofSystem.authorizedCallers(authorizedCaller));
    }

    function test_NonOwnerCannotAuthorizeCallers() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
    }

    function test_CannotAuthorizeZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid caller");
        proofSystem.setAuthorizedCaller(address(0), true);
    }

    function test_SetAuthorizedCallerEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit AuthorizedCallerUpdated(authorizedCaller, true);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
    }

    // ============================================================
    // markProofUsed Access Control Tests
    // ============================================================

    function test_AuthorizedCallerCanMarkProof() public {
        // Authorize the caller
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        // Authorized caller should be able to mark proof
        bytes32 proofHash = bytes32(uint256(0x1234));
        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, authorizedCaller, 100, bytes32(0));

        assertTrue(result);
        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_OwnerCanMarkProofDirectly() public {
        // Owner should be able to mark proof without being in authorizedCallers
        bytes32 proofHash = bytes32(uint256(0x5678));
        vm.prank(owner);
        bool result = proofSystem.markProofUsed(proofHash, owner, 100, bytes32(0));

        assertTrue(result);
        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_UnauthorizedCallerCannotMarkProof() public {
        bytes32 proofHash = bytes32(uint256(0xABCD));

        vm.prank(unauthorizedUser);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, unauthorizedUser, 100, bytes32(0));

        // Proof should not be recorded
        assertFalse(proofSystem.verifiedProofs(proofHash));
    }

    function test_RevokedCallerCannotMarkProof() public {
        // First authorize
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        // Then revoke
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, false);

        // Revoked caller should not be able to mark proof
        bytes32 proofHash = bytes32(uint256(0xDEAD));
        vm.prank(authorizedCaller);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, authorizedCaller, 100, bytes32(0));
    }

    function test_MarkProofUsedEmitsEvent() public {
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        bytes32 proofHash = bytes32(uint256(0xBEEF));

        vm.prank(authorizedCaller);
        vm.expectEmit(true, true, false, true);
        emit ProofVerified(proofHash, authorizedCaller, 100);
        proofSystem.markProofUsed(proofHash, authorizedCaller, 100, bytes32(0));
    }

    // ============================================================
    // Front-Running Prevention Tests
    // ============================================================

    function test_FrontRunningAttackPrevented() public {
        // This test demonstrates the attack vector that is now prevented
        //
        // Attack scenario:
        // 1. Legitimate host prepares proof with hash H
        // 2. Attacker sees pending tx in mempool
        // 3. Attacker tries to front-run with markProofUsed(H)
        // 4. Attack should fail because attacker is not authorized

        bytes32 proofHash = bytes32(uint256(0xCAFE));
        address attacker = address(0x666);

        // Attacker tries to front-run
        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, attacker, 100, bytes32(0));

        // Proof should not be marked as verified
        assertFalse(proofSystem.verifiedProofs(proofHash));

        // Legitimate caller (authorized) can still mark the proof
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, authorizedCaller, 100, bytes32(0));

        assertTrue(result);
        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_MultipleAuthorizedCallers() public {
        address caller1 = address(0x100);
        address caller2 = address(0x200);

        // Authorize multiple callers
        vm.startPrank(owner);
        proofSystem.setAuthorizedCaller(caller1, true);
        proofSystem.setAuthorizedCaller(caller2, true);
        vm.stopPrank();

        // Both should be able to mark proofs
        vm.prank(caller1);
        proofSystem.markProofUsed(bytes32(uint256(1)), caller1, 100, bytes32(0));

        vm.prank(caller2);
        proofSystem.markProofUsed(bytes32(uint256(2)), caller2, 100, bytes32(0));

        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(1))));
        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(2))));
    }
}
