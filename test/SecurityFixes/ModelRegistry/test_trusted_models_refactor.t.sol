// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title TrustedModelsRefactorTest
 * @notice Tests for Phase 6: trustedModels mapping removal and isTrustedModel() replacement
 * @dev Verifies that isTrustedModel() correctly identifies tier 1 models
 */
contract TrustedModelsRefactorTest is Test {
    ModelRegistryUpgradeable public registry;
    ERC20Mock public fabToken;

    address public owner = address(this);
    address public user1 = address(0x1001);

    // Test model data
    string constant REPO_1 = "TheBloke/TinyVicuna-1B-GGUF";
    string constant FILE_1 = "tinyvicuna-1b.Q4_K_M.gguf";
    bytes32 constant HASH_1 = keccak256("hash1");

    string constant REPO_2 = "TheBloke/TinyLlama-1.1B-GGUF";
    string constant FILE_2 = "tinyllama-1.1b.Q4_K_M.gguf";
    bytes32 constant HASH_2 = keccak256("hash2");

    string constant REPO_3 = "Community/Model-3";
    string constant FILE_3 = "model3.gguf";
    bytes32 constant HASH_3 = keccak256("hash3");

    function setUp() public {
        // Deploy FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry with proxy
        ModelRegistryUpgradeable implementation = new ModelRegistryUpgradeable();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        registry = ModelRegistryUpgradeable(address(proxy));

        // Give user1 some FAB tokens for proposals
        fabToken.mint(user1, 1000000 * 10**18);
        vm.prank(user1);
        fabToken.approve(address(registry), type(uint256).max);
    }

    // ============================================================
    // isTrustedModel() Basic Functionality
    // ============================================================

    function test_IsTrustedModel_ReturnsTrueForTier1Model() public {
        // Add a trusted model (tier 1)
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId = registry.getModelId(REPO_1, FILE_1);

        // isTrustedModel should return true
        assertTrue(registry.isTrustedModel(modelId), "Tier 1 model should be trusted");
    }

    function test_IsTrustedModel_ReturnsFalseForNonexistentModel() public {
        bytes32 fakeModelId = keccak256("nonexistent");

        // isTrustedModel should return false for non-existent model
        assertFalse(registry.isTrustedModel(fakeModelId), "Non-existent model should not be trusted");
    }

    function test_IsTrustedModel_ReturnsFalseForDeactivatedTier1Model() public {
        // Add a trusted model
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId = registry.getModelId(REPO_1, FILE_1);

        // Deactivate the model
        registry.deactivateModel(modelId);

        // isTrustedModel should return false (not active)
        assertFalse(registry.isTrustedModel(modelId), "Deactivated model should not be trusted");
    }

    function test_IsTrustedModel_ReturnsTrueAfterReactivation() public {
        // Add, deactivate, then reactivate
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId = registry.getModelId(REPO_1, FILE_1);

        registry.deactivateModel(modelId);
        assertFalse(registry.isTrustedModel(modelId));

        registry.reactivateModel(modelId);
        assertTrue(registry.isTrustedModel(modelId), "Reactivated model should be trusted");
    }

    // ============================================================
    // Tier 2 (Community) Models Should Not Be Trusted
    // ============================================================

    function test_IsTrustedModel_ReturnsFalseForTier2Model() public {
        // Cache values before prank to avoid consuming prank with view calls
        uint256 proposalFee = registry.PROPOSAL_FEE();
        uint256 approvalThreshold = registry.APPROVAL_THRESHOLD();

        // Ensure user1 has enough tokens for proposal fee + votes
        uint256 totalNeeded = proposalFee + approvalThreshold;
        fabToken.mint(user1, totalNeeded);
        vm.prank(user1);
        fabToken.approve(address(registry), type(uint256).max);

        // Propose a community model (tier 2)
        vm.prank(user1);
        registry.proposeModel(REPO_3, FILE_3, HASH_3);

        bytes32 modelId = registry.getModelId(REPO_3, FILE_3);

        // Vote on proposal
        vm.prank(user1);
        registry.voteOnProposal(modelId, approvalThreshold, true);

        // Fast forward past proposal duration
        vm.warp(block.timestamp + registry.PROPOSAL_DURATION() + 1);

        // Execute the proposal
        registry.executeProposal(modelId);

        // Model should be approved but NOT trusted (tier 2)
        assertTrue(registry.isModelApproved(modelId), "Model should be approved");
        assertFalse(registry.isTrustedModel(modelId), "Tier 2 model should not be trusted");

        // Verify it's tier 2
        ModelRegistryUpgradeable.Model memory model = registry.getModel(modelId);
        assertEq(model.approvalTier, 2, "Should be tier 2");
    }

    // ============================================================
    // Batch Add Trusted Models
    // ============================================================

    function test_IsTrustedModel_WorksWithBatchAdd() public {
        string[] memory repos = new string[](2);
        string[] memory files = new string[](2);
        bytes32[] memory hashes = new bytes32[](2);

        repos[0] = REPO_1;
        files[0] = FILE_1;
        hashes[0] = HASH_1;

        repos[1] = REPO_2;
        files[1] = FILE_2;
        hashes[1] = HASH_2;

        registry.batchAddTrustedModels(repos, files, hashes);

        bytes32 modelId1 = registry.getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = registry.getModelId(REPO_2, FILE_2);

        assertTrue(registry.isTrustedModel(modelId1), "Batch model 1 should be trusted");
        assertTrue(registry.isTrustedModel(modelId2), "Batch model 2 should be trusted");
    }

    // ============================================================
    // Consistency with approvalTier
    // ============================================================

    function test_IsTrustedModel_ConsistentWithApprovalTier() public {
        // Add trusted model
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId = registry.getModelId(REPO_1, FILE_1);

        // Get model data
        ModelRegistryUpgradeable.Model memory model = registry.getModel(modelId);

        // Verify consistency: isTrustedModel == (approvalTier == 1 && active)
        bool expected = model.approvalTier == 1 && model.active;
        assertEq(registry.isTrustedModel(modelId), expected, "isTrustedModel should match approvalTier logic");
    }

    function test_IsTrustedModel_MultipleModels_MixedTiers() public {
        // Add tier 1 model
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId1 = registry.getModelId(REPO_1, FILE_1);

        // Cache values before prank to avoid consuming prank with view calls
        uint256 proposalFee = registry.PROPOSAL_FEE();
        uint256 approvalThreshold = registry.APPROVAL_THRESHOLD();
        uint256 proposalDuration = registry.PROPOSAL_DURATION();

        // Ensure user1 has enough tokens for proposal fee + votes
        uint256 totalNeeded = proposalFee + approvalThreshold;
        fabToken.mint(user1, totalNeeded);
        vm.prank(user1);
        fabToken.approve(address(registry), type(uint256).max);

        // Add tier 2 model via proposal
        vm.prank(user1);
        registry.proposeModel(REPO_3, FILE_3, HASH_3);
        bytes32 modelId3 = registry.getModelId(REPO_3, FILE_3);

        vm.prank(user1);
        registry.voteOnProposal(modelId3, approvalThreshold, true);
        vm.warp(block.timestamp + proposalDuration + 1);
        registry.executeProposal(modelId3);

        // Tier 1 should be trusted, tier 2 should not
        assertTrue(registry.isTrustedModel(modelId1), "Tier 1 should be trusted");
        assertFalse(registry.isTrustedModel(modelId3), "Tier 2 should not be trusted");

        // Both should be approved
        assertTrue(registry.isModelApproved(modelId1), "Tier 1 should be approved");
        assertTrue(registry.isModelApproved(modelId3), "Tier 2 should be approved");
    }

    // ============================================================
    // Gas Usage Tests
    // ============================================================

    function test_GasUsage_IsTrustedModel() public {
        // Add a model first
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId = registry.getModelId(REPO_1, FILE_1);

        // Measure gas for isTrustedModel call
        uint256 gasBefore = gasleft();
        registry.isTrustedModel(modelId);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("isTrustedModel gas", gasUsed);

        // Should be under 5000 gas for a simple view function
        assertLt(gasUsed, 5000, "isTrustedModel should be gas efficient");
    }

    function test_GasUsage_AddTrustedModel() public {
        // Measure gas for addTrustedModel
        uint256 gasBefore = gasleft();
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("addTrustedModel gas", gasUsed);

        // Should be under 250k gas (storage writes are expensive)
        assertLt(gasUsed, 250000, "addTrustedModel should be gas efficient");
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    function test_IsTrustedModel_ZeroModelId() public {
        // bytes32(0) should return false
        assertFalse(registry.isTrustedModel(bytes32(0)), "Zero model ID should not be trusted");
    }

    function test_IsTrustedModel_AfterMultipleStateChanges() public {
        // Add model
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        bytes32 modelId = registry.getModelId(REPO_1, FILE_1);

        // Multiple state changes
        assertTrue(registry.isTrustedModel(modelId)); // Active tier 1

        registry.deactivateModel(modelId);
        assertFalse(registry.isTrustedModel(modelId)); // Inactive

        registry.reactivateModel(modelId);
        assertTrue(registry.isTrustedModel(modelId)); // Active again

        registry.deactivateModel(modelId);
        assertFalse(registry.isTrustedModel(modelId)); // Inactive again
    }
}
