// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Access Control Tests
 * @dev Tests for markProofUsed and setAuthorizedCaller access control
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
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);
        assertTrue(proofSystem.authorizedCallers(authorizedCaller));

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
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        bytes32 proofHash = bytes32(uint256(0x1234));
        vm.prank(authorizedCaller);
        bool result = proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));

        assertTrue(result);
        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_OwnerCanMarkProofDirectly() public {
        bytes32 proofHash = bytes32(uint256(0x5678));
        vm.prank(owner);
        bool result = proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));

        assertTrue(result);
        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_UnauthorizedCallerCannotMarkProof() public {
        bytes32 proofHash = bytes32(uint256(0xABCD));

        vm.prank(unauthorizedUser);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));

        assertFalse(proofSystem.verifiedProofs(proofHash));
    }

    function test_RevokedCallerCannotMarkProof() public {
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, false);

        bytes32 proofHash = bytes32(uint256(0xDEAD));
        vm.prank(authorizedCaller);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));
    }

    function test_MarkProofUsedEmitsEvent() public {
        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        bytes32 proofHash = bytes32(uint256(0xBEEF));

        vm.prank(authorizedCaller);
        vm.expectEmit(true, true, false, true);
        emit ProofVerified(proofHash, address(0xBEEF), 100);
        proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));
    }

    // ============================================================
    // Front-Running Prevention Tests
    // ============================================================

    function test_FrontRunningAttackPrevented() public {
        bytes32 proofHash = bytes32(uint256(0xCAFE));
        address attacker = address(0x666);

        vm.prank(attacker);
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));

        assertFalse(proofSystem.verifiedProofs(proofHash));

        vm.prank(owner);
        proofSystem.setAuthorizedCaller(authorizedCaller, true);

        vm.prank(authorizedCaller);
        proofSystem.markProofUsed(proofHash, address(0xBEEF), 100, bytes32(0));

        assertTrue(proofSystem.verifiedProofs(proofHash));
    }

    function test_MultipleAuthorizedCallers() public {
        address caller1 = address(0x100);
        address caller2 = address(0x200);

        vm.startPrank(owner);
        proofSystem.setAuthorizedCaller(caller1, true);
        proofSystem.setAuthorizedCaller(caller2, true);
        vm.stopPrank();

        vm.prank(caller1);
        proofSystem.markProofUsed(bytes32(uint256(1)), address(0xBEEF), 100, bytes32(0));

        vm.prank(caller2);
        proofSystem.markProofUsed(bytes32(uint256(2)), address(0xBEEF), 200, bytes32(0));

        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(1))));
        assertTrue(proofSystem.verifiedProofs(bytes32(uint256(2))));
    }
}
