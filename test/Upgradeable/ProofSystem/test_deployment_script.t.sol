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

    address public prover = address(0xA11CE);

    function setUp() public {
        // Create deployment script
        deployScript = new DeployProofSystemUpgradeable();
    }

    // Use bytes32(0) for non-model sessions
    bytes32 constant MODEL_ID = bytes32(0);

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

    function test_DeployedContractCanMarkProofsUsed() public {
        (address proxy, ) = deployScript.run();

        ProofSystemUpgradeable proofSystem = ProofSystemUpgradeable(proxy);
        address owner = proofSystem.owner();

        // Authorize caller (owner calls markProofUsed)
        bytes32 proofHash = bytes32(uint256(0x1234));
        uint256 claimedTokens = 100;

        // Owner can mark proof used
        vm.prank(owner);
        bool result = proofSystem.markProofUsed(proofHash, prover, claimedTokens, MODEL_ID);
        assertTrue(result, "First call should succeed");

        // Replay should fail
        vm.prank(owner);
        bool replayResult = proofSystem.markProofUsed(proofHash, prover, claimedTokens, MODEL_ID);
        assertFalse(replayResult, "Replay should fail");
    }

}
