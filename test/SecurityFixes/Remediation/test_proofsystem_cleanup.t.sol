// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";

/// @notice Phase 5: F202615147, F202615149, F202615002, F202615064, F202615065, F202615066
/// Tests for ProofSystem cleanup — dead function removal and storage layout preservation.
contract ProofSystemCleanupTest is Test {
    ProofSystemUpgradeable public proofSystem;
    address public owner = address(this);
    address public marketplace = address(0xCAFE);
    address public host = address(0xBEEF);

    function setUp() public {
        // Deploy via proxy
        ProofSystemUpgradeable impl = new ProofSystemUpgradeable();
        bytes memory initData = abi.encodeWithSelector(ProofSystemUpgradeable.initialize.selector);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        proofSystem = ProofSystemUpgradeable(address(proxy));

        // Authorize marketplace as caller
        proofSystem.setAuthorizedCaller(marketplace, true);
    }

    // ─── markProofUsed tests ────────────────────────────────────────────

    /// @notice markProofUsed works for authorized caller
    function test_MarkProofUsed_AuthorizedCaller() public {
        bytes32 proofHash = keccak256("proof1");
        vm.prank(marketplace);
        bool result = proofSystem.markProofUsed(proofHash, host, 100, bytes32(0));
        assertTrue(result, "First mark should succeed");
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked");
    }

    /// @notice markProofUsed returns false on replay
    function test_MarkProofUsed_ReplayReturnsFalse() public {
        bytes32 proofHash = keccak256("proof1");
        vm.startPrank(marketplace);
        proofSystem.markProofUsed(proofHash, host, 100, bytes32(0));
        bool result = proofSystem.markProofUsed(proofHash, host, 100, bytes32(0));
        vm.stopPrank();
        assertFalse(result, "Replay should return false");
    }

    /// @notice markProofUsed reverts for unauthorized caller
    function test_MarkProofUsed_UnauthorizedReverts() public {
        bytes32 proofHash = keccak256("proof1");
        vm.prank(address(0xDEAD));
        vm.expectRevert("Unauthorized");
        proofSystem.markProofUsed(proofHash, host, 100, bytes32(0));
    }

    // ─── setAuthorizedCaller tests ──────────────────────────────────────

    /// @notice setAuthorizedCaller works for owner
    function test_SetAuthorizedCaller_Owner() public {
        address newCaller = address(0x1234);
        proofSystem.setAuthorizedCaller(newCaller, true);
        assertTrue(proofSystem.authorizedCallers(newCaller));
    }

    /// @notice setAuthorizedCaller reverts for non-owner
    function test_SetAuthorizedCaller_NonOwnerReverts() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        proofSystem.setAuthorizedCaller(address(0x1234), true);
    }

    // ─── Dead function removal tests ────────────────────────────────────

    /// @notice F202615065: registerModelCircuit must not exist
    function test_RegisterModelCircuit_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "registerModelCircuit(address,bytes32)", address(0x1), bytes32(uint256(1))
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "registerModelCircuit should not exist");
    }

    /// @notice F202615065: isCircuitRegistered must not exist
    function test_IsCircuitRegistered_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "isCircuitRegistered(bytes32)", bytes32(uint256(1))
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "isCircuitRegistered should not exist");
    }

    /// @notice F202615065: getModelCircuit must not exist
    function test_GetModelCircuit_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "getModelCircuit(address)", address(0x1)
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "getModelCircuit should not exist");
    }

    /// @notice F202615002: verifyBatch must not exist
    function test_VerifyBatch_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "verifyBatch(bytes[],address,uint256[])"
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "verifyBatch should not exist");
    }

    /// @notice F202615002: verifyBatchView must not exist
    function test_VerifyBatchView_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "verifyBatchView(bytes[],address,uint256[])"
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "verifyBatchView should not exist");
    }

    /// @notice F202615002: estimateBatchGas must not exist
    function test_EstimateBatchGas_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature("estimateBatchGas(uint256)", 5);
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "estimateBatchGas should not exist");
    }

    /// @notice F202615066: verifyAndMarkComplete must not exist
    function test_VerifyAndMarkComplete_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "verifyAndMarkComplete(bytes,address,uint256)"
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "verifyAndMarkComplete should not exist");
    }

    /// @notice F202615147: verifyHostSignature must not exist
    function test_VerifyHostSignature_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "verifyHostSignature(bytes,address,uint256)"
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "verifyHostSignature should not exist");
    }

    /// @notice F202615066: recordVerifiedProof must not exist
    function test_RecordVerifiedProof_DoesNotExist() public {
        bytes memory data = abi.encodeWithSignature(
            "recordVerifiedProof(bytes32)", bytes32(uint256(1))
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "recordVerifiedProof should not exist");
    }

    // ─── Storage layout preservation ────────────────────────────────────

    /// @notice F202615064: authorizedCallers must remain accessible at correct slot
    function test_AuthorizedCallers_AtCorrectSlot() public {
        proofSystem.setAuthorizedCaller(address(0xBEEF), true);
        assertTrue(proofSystem.authorizedCallers(address(0xBEEF)));

        proofSystem.setAuthorizedCaller(address(0xBEEF), false);
        assertFalse(proofSystem.authorizedCallers(address(0xBEEF)));
    }

    /// @notice Verify registeredCircuits mapping is no longer publicly accessible
    function test_RegisteredCircuits_NotPublic() public {
        bytes memory data = abi.encodeWithSignature(
            "registeredCircuits(bytes32)", bytes32(uint256(1))
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "registeredCircuits should not be publicly accessible");
    }

    /// @notice Verify modelCircuits mapping is no longer publicly accessible
    function test_ModelCircuits_NotPublic() public {
        bytes memory data = abi.encodeWithSignature(
            "modelCircuits(address)", address(0x1)
        );
        (bool success,) = address(proofSystem).call(data);
        assertFalse(success, "modelCircuits should not be publicly accessible");
    }
}
