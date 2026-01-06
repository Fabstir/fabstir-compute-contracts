// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";

/**
 * @title ProofSystemUpgradeable Gas Estimation Tests
 * @dev Tests for estimateBatchGas accuracy (Sub-phase 1.3)
 *
 * Issue: Magic numbers in estimateBatchGas (50000, 20000) have no documentation
 * or basis in actual implementation measurements.
 */
contract ProofSystemGasEstimationTest is Test {
    ProofSystemUpgradeable public implementation;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);

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
    // Helper Functions
    // ============================================================

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

    function createBatchProofs(uint256 batchSize) internal view returns (
        bytes[] memory proofs,
        uint256[] memory tokenCounts
    ) {
        proofs = new bytes[](batchSize);
        tokenCounts = new uint256[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            tokenCounts[i] = 100 + i;
            proofs[i] = createSignedProof(bytes32(uint256(i + 1)), tokenCounts[i]);
        }
    }

    // ============================================================
    // Gas Measurement Tests
    // ============================================================

    function test_MeasureActualGasForBatchOf1() public {
        (bytes[] memory proofs, uint256[] memory tokenCounts) = createBatchProofs(1);

        uint256 gasBefore = gasleft();
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Actual gas for batch of 1:", gasUsed);
        console.log("Estimated gas for batch of 1:", proofSystem.estimateBatchGas(1));

        // Gas should be reasonable (not zero, not excessive)
        assertTrue(gasUsed > 0, "Gas used should be positive");
        assertTrue(gasUsed < 500000, "Gas used should be reasonable");
    }

    function test_MeasureActualGasForBatchOf5() public {
        (bytes[] memory proofs, uint256[] memory tokenCounts) = createBatchProofs(5);

        uint256 gasBefore = gasleft();
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Actual gas for batch of 5:", gasUsed);
        console.log("Estimated gas for batch of 5:", proofSystem.estimateBatchGas(5));

        assertTrue(gasUsed > 0, "Gas used should be positive");
    }

    function test_MeasureActualGasForBatchOf10() public {
        (bytes[] memory proofs, uint256[] memory tokenCounts) = createBatchProofs(10);

        uint256 gasBefore = gasleft();
        proofSystem.verifyBatch(proofs, prover, tokenCounts);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Actual gas for batch of 10:", gasUsed);
        console.log("Estimated gas for batch of 10:", proofSystem.estimateBatchGas(10));

        assertTrue(gasUsed > 0, "Gas used should be positive");
    }

    // ============================================================
    // Estimation Accuracy Tests
    // ============================================================

    function test_GasEstimateIncreasesLinearly() public view {
        uint256 estimate1 = proofSystem.estimateBatchGas(1);
        uint256 estimate2 = proofSystem.estimateBatchGas(2);
        uint256 estimate5 = proofSystem.estimateBatchGas(5);
        uint256 estimate10 = proofSystem.estimateBatchGas(10);

        // Check linear increase
        uint256 perProofCost = estimate2 - estimate1;

        assertEq(estimate5, estimate1 + (4 * perProofCost), "Should increase linearly");
        assertEq(estimate10, estimate1 + (9 * perProofCost), "Should increase linearly");
    }

    function test_GasEstimateForBatchOf1() public view {
        uint256 estimate = proofSystem.estimateBatchGas(1);

        // New constants: 15000 + 1*27000 = 42000
        assertEq(estimate, 42000, "Batch of 1 should be 42000");

        // Log for reference
        console.log("Estimate for batch of 1:", estimate);
    }

    function test_GasEstimateForBatchOf10() public view {
        uint256 estimate = proofSystem.estimateBatchGas(10);

        // New constants: 15000 + 10*27000 = 285000
        assertEq(estimate, 285000, "Batch of 10 should be 285000");

        // Should be significantly higher than batch of 1
        uint256 estimate1 = proofSystem.estimateBatchGas(1);
        assertTrue(estimate > estimate1, "Batch of 10 should cost more than batch of 1");

        // Log for reference
        console.log("Estimate for batch of 10:", estimate);
    }

    // ============================================================
    // Edge Case Tests
    // ============================================================

    function test_GasEstimateRejectsZeroBatchSize() public {
        vm.expectRevert("Invalid batch size");
        proofSystem.estimateBatchGas(0);
    }

    function test_GasEstimateRejectsTooLargeBatchSize() public {
        vm.expectRevert("Invalid batch size");
        proofSystem.estimateBatchGas(11);
    }

    function test_GasEstimateAcceptsBoundaryValues() public view {
        // Should accept 1 (minimum)
        uint256 min = proofSystem.estimateBatchGas(1);
        assertTrue(min > 0, "Should accept batch size 1");

        // Should accept 10 (maximum)
        uint256 max = proofSystem.estimateBatchGas(10);
        assertTrue(max > min, "Should accept batch size 10");
    }

    // ============================================================
    // Comprehensive Gas Analysis
    // ============================================================

    function test_AnalyzeGasConsumption() public {
        console.log("=== Gas Consumption Analysis ===");
        console.log("");

        uint256[] memory actualGas = new uint256[](10);
        uint256[] memory estimates = new uint256[](10);

        for (uint256 i = 1; i <= 10; i++) {
            // Create fresh proofs for each batch (different hashes to avoid replay)
            bytes[] memory proofs = new bytes[](i);
            uint256[] memory tokenCounts = new uint256[](i);

            for (uint256 j = 0; j < i; j++) {
                tokenCounts[j] = 100 + j;
                // Use unique proof hash for each measurement
                proofs[j] = createSignedProof(bytes32(uint256(i * 100 + j + 1)), tokenCounts[j]);
            }

            uint256 gasBefore = gasleft();
            proofSystem.verifyBatch(proofs, prover, tokenCounts);
            actualGas[i - 1] = gasBefore - gasleft();
            estimates[i - 1] = proofSystem.estimateBatchGas(i);
        }

        console.log("Batch | Actual Gas | Estimated");
        console.log("------|------------|----------");

        for (uint256 i = 0; i < 10; i++) {
            console.log("Batch", i + 1);
            console.log("  Actual:", actualGas[i]);
            console.log("  Estimated:", estimates[i]);
        }

        // Calculate recommended constants
        // Base cost = actual(1) - perProof
        // Per proof = (actual(10) - actual(1)) / 9
        uint256 perProofCost = (actualGas[9] - actualGas[0]) / 9;
        uint256 baseCost = actualGas[0] - perProofCost;

        console.log("");
        console.log("=== Recommended Constants ===");
        console.log("BASE_VERIFICATION_GAS:", baseCost);
        console.log("PER_PROOF_GAS:", perProofCost);
    }
}
