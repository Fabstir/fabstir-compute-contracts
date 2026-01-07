// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {DeployProofSystemUpgradeable} from "../../../script/DeployProofSystemUpgradeable.s.sol";

/**
 * @title ProofSystem Deployment Script Tests
 * @dev Tests the deployment script for ProofSystemUpgradeable
 */
contract ProofSystemDeploymentScriptTest is Test {
    DeployProofSystemUpgradeable public deployScript;

    // Use actual private key for signing tests
    uint256 constant PROVER_PRIVATE_KEY = 0xA11CE;
    address public prover;

    function setUp() public {
        prover = vm.addr(PROVER_PRIVATE_KEY);
        // Create deployment script
        deployScript = new DeployProofSystemUpgradeable();
    }

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

    function test_DeploymentScriptWorks() public {
        // Run the deployment script
        (address proxy, address implementation) = deployScript.run();

        // Verify deployment
        assertTrue(proxy != address(0), "Proxy should be deployed");
        assertTrue(implementation != address(0), "Implementation should be deployed");
        assertTrue(proxy != implementation, "Proxy and implementation should be different");
    }

    function test_DeploymentInitializesCorrectly() public {
        (address proxy, ) = deployScript.run();

        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);

        // Verify initialization
        assertTrue(proofSystem.owner() != address(0), "Owner should be set");
    }

    function test_DeploymentStoresCorrectImplementation() public {
        (address proxy, address implementation) = deployScript.run();

        // Get implementation address from ERC1967 storage slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, implementation, "Implementation addresses should match");
    }

    function test_DeployedContractIsUpgradeable() public {
        (address proxy, ) = deployScript.run();

        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);
        address originalOwner = proofSystem.owner();

        // Deploy new implementation
        ProofSystemUpgradeable newImpl = new ProofSystemUpgradeable();

        // Upgrade should work (as owner)
        vm.prank(originalOwner);
        proofSystem.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, address(newImpl));
    }

    function test_DeployedContractCanVerifyProofs() public {
        (address proxy, ) = deployScript.run();

        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);

        // Verify a signed proof
        bytes32 proofHash = bytes32(uint256(0x1234));
        uint256 claimedTokens = 100;
        bytes memory proof = createSignedProof(proofHash, claimedTokens);

        bool result = proofSystem.verifyEKZL(proof, prover, claimedTokens);
        assertTrue(result);
    }

    function test_DeployedContractCanRegisterCircuits() public {
        (address proxy, ) = deployScript.run();

        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);
        address owner = proofSystem.owner();

        // Register a circuit
        address model = address(0x200);
        bytes32 circuitHash = bytes32(uint256(0x3456));

        vm.prank(owner);
        proofSystem.registerModelCircuit(model, circuitHash);

        // Verify
        assertTrue(proofSystem.isCircuitRegistered(circuitHash));
        assertEq(proofSystem.getModelCircuit(model), circuitHash);
    }
}
