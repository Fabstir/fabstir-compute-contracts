// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable V2 (Mock for testing upgrades)
 * @dev Adds version function and extra state for testing upgrade preservation
 */
contract ProofSystemUpgradeableV2 is ProofSystemUpgradeable {
    // New storage variable (appended after existing storage)
    string public systemName;

    function initializeV2(string memory _name) external reinitializer(2) {
        systemName = _name;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }

    function getVerifiedProofCount() external view returns (uint256) {
        // This is just for testing - returns 0 since we can't enumerate mapping
        return 0;
    }
}

/**
 * @title ProofSystemUpgradeable Upgrade Tests
 * @dev Tests upgrade mechanics, state preservation, and authorization
 */
contract ProofSystemUpgradeTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public prover = address(0x3);
    address public modelAddress = address(0x100);

    bytes32 constant CIRCUIT_HASH = bytes32(uint256(0x1234));
    bytes32 constant PROOF_HASH_1 = bytes32(uint256(0xABCD));
    bytes32 constant PROOF_HASH_2 = bytes32(uint256(0xEF01));

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

        // Set up some state to test preservation
        vm.startPrank(owner);
        proofSystem.registerModelCircuit(modelAddress, CIRCUIT_HASH);
        // Record verified proofs (requires owner authorization after security fix)
        proofSystem.recordVerifiedProof(PROOF_HASH_1);
        proofSystem.recordVerifiedProof(PROOF_HASH_2);
        vm.stopPrank();
    }

    // ============================================================
    // Pre-Upgrade State Verification
    // ============================================================

    function test_PreUpgradeStateIsCorrect() public view {
        // Verify circuits registered
        assertTrue(proofSystem.isCircuitRegistered(CIRCUIT_HASH));
        assertEq(proofSystem.getModelCircuit(modelAddress), CIRCUIT_HASH);

        // Verify proofs recorded
        assertTrue(proofSystem.verifiedProofs(PROOF_HASH_1));
        assertTrue(proofSystem.verifiedProofs(PROOF_HASH_2));

        // Verify owner
        assertEq(proofSystem.owner(), owner);
    }

    // ============================================================
    // Upgrade Authorization Tests
    // ============================================================

    function test_OnlyOwnerCanUpgrade() public {
        // Deploy V2 implementation
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        // Try to upgrade as non-owner - should revert
        vm.prank(user1);
        vm.expectRevert();
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");
    }

    function test_OwnerCanUpgrade() public {
        // Deploy V2 implementation
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        // Upgrade as owner - should succeed
        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        // Verify upgrade worked by calling V2 function
        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));
        assertEq(proofSystemV2.version(), "v2");
    }

    // ============================================================
    // State Preservation Tests
    // ============================================================

    function test_UpgradePreservesOwner() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));
        assertEq(proofSystemV2.owner(), owner);
    }

    function test_UpgradePreservesVerifiedProofs() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Verify proofs still marked as verified
        assertTrue(proofSystemV2.verifiedProofs(PROOF_HASH_1));
        assertTrue(proofSystemV2.verifiedProofs(PROOF_HASH_2));
    }

    function test_UpgradePreservesRegisteredCircuits() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Verify circuit still registered
        assertTrue(proofSystemV2.isCircuitRegistered(CIRCUIT_HASH));
    }

    function test_UpgradePreservesModelCircuits() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Verify model-to-circuit mapping preserved
        assertEq(proofSystemV2.getModelCircuit(modelAddress), CIRCUIT_HASH);
    }

    // ============================================================
    // Upgrade With Initialization Tests
    // ============================================================

    function test_UpgradeWithV2Initialization() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        // Upgrade with V2 initialization
        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(ProofSystemUpgradeableV2.initializeV2, ("EZKL Verifier"))
        );

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Verify V2 initialization worked
        assertEq(proofSystemV2.systemName(), "EZKL Verifier");
        assertEq(proofSystemV2.version(), "v2");

        // Verify V1 state still preserved
        assertEq(proofSystemV2.owner(), owner);
        assertTrue(proofSystemV2.verifiedProofs(PROOF_HASH_1));
        assertTrue(proofSystemV2.isCircuitRegistered(CIRCUIT_HASH));
    }

    function test_V2InitializationCannotBeCalledTwice() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        // Upgrade with V2 initialization
        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(ProofSystemUpgradeableV2.initializeV2, ("EZKL Verifier"))
        );

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Try to call initializeV2 again - should revert
        vm.expectRevert();
        proofSystemV2.initializeV2("Another Name");
    }

    // ============================================================
    // Post-Upgrade Functionality Tests
    // ============================================================

    function test_CanVerifyProofsAfterUpgrade() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Verify new proofs work
        bytes memory newProof = abi.encodePacked(
            bytes32(uint256(0x9999)),
            bytes32(uint256(0x8888))
        );

        bool result = proofSystemV2.verifyEKZL(newProof, prover, 100);
        assertTrue(result);
    }

    function test_CanRecordProofsAfterUpgrade() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Record a new proof (requires owner authorization after security fix)
        bytes32 newProofHash = bytes32(uint256(0x7777));
        vm.prank(owner);
        proofSystemV2.recordVerifiedProof(newProofHash);

        assertTrue(proofSystemV2.verifiedProofs(newProofHash));
    }

    function test_CanRegisterCircuitsAfterUpgrade() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Register a new circuit
        address newModel = address(0x200);
        bytes32 newCircuitHash = bytes32(uint256(0x6666));

        vm.prank(owner);
        proofSystemV2.registerModelCircuit(newModel, newCircuitHash);

        assertTrue(proofSystemV2.isCircuitRegistered(newCircuitHash));
        assertEq(proofSystemV2.getModelCircuit(newModel), newCircuitHash);
    }

    function test_CanTransferOwnershipAfterUpgrade() public {
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        ProofSystemUpgradeableV2 proofSystemV2 = ProofSystemUpgradeableV2(address(proofSystem));

        // Transfer ownership
        vm.prank(owner);
        proofSystemV2.transferOwnership(user1);

        assertEq(proofSystemV2.owner(), user1);

        // New owner can register circuits
        vm.prank(user1);
        proofSystemV2.registerModelCircuit(address(0x300), bytes32(uint256(0x5555)));
    }

    // ============================================================
    // Implementation Slot Verification
    // ============================================================

    function test_ImplementationSlotUpdatedAfterUpgrade() public {
        // Get implementation before upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implBefore = address(uint160(uint256(vm.load(address(proofSystem), slot))));
        assertEq(implBefore, address(implementation));

        // Deploy and upgrade to V2
        ProofSystemUpgradeableV2 implementationV2 = new ProofSystemUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(proofSystem)).upgradeToAndCall(address(implementationV2), "");

        // Verify implementation changed
        address implAfter = address(uint160(uint256(vm.load(address(proofSystem), slot))));
        assertEq(implAfter, address(implementationV2));
        assertTrue(implAfter != implBefore);
    }
}
