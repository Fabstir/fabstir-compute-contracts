// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title BatchDuplicateHandlingTest
 * @notice Tests for batch duplicate handling consistency
 * @dev Verifies batchAddTrustedModels emits ModelSkipped for duplicates
 */
contract BatchDuplicateHandlingTest is Test {
    ModelRegistryUpgradeable public registry;
    ERC20Mock public fabToken;

    address public owner = address(this);

    string constant REPO_1 = "TheBloke/Model-1-GGUF";
    string constant FILE_1 = "model-1.gguf";
    bytes32 constant HASH_1 = keccak256("hash1");

    string constant REPO_2 = "TheBloke/Model-2-GGUF";
    string constant FILE_2 = "model-2.gguf";
    bytes32 constant HASH_2 = keccak256("hash2");

    string constant REPO_3 = "TheBloke/Model-3-GGUF";
    string constant FILE_3 = "model-3.gguf";
    bytes32 constant HASH_3 = keccak256("hash3");

    // Events - ModelSkipped is expected but doesn't exist yet (RED)
    event ModelSkipped(bytes32 indexed modelId, string reason);
    event ModelAdded(bytes32 indexed modelId, string huggingfaceRepo, string fileName, uint256 tier);

    function setUp() public {
        fabToken = new ERC20Mock("FAB Token", "FAB");
        ModelRegistryUpgradeable implementation = new ModelRegistryUpgradeable();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        registry = ModelRegistryUpgradeable(address(proxy));
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    function _getModelId(string memory repo, string memory file) internal view returns (bytes32) {
        return registry.getModelId(repo, file);
    }

    function _buildArrays(
        uint256 count,
        string[] memory repos,
        string[] memory files,
        bytes32[] memory hashes
    ) internal pure returns (string[] memory, string[] memory, bytes32[] memory) {
        return (repos, files, hashes);
    }

    // ============================================================
    // Test: Duplicate within same batch
    // ============================================================

    function test_BatchAddEmitsSkipEventForDuplicateInSameBatch() public {
        // Prepare arrays with duplicate: [Model1, Model2, Model1]
        string[] memory repos = new string[](3);
        string[] memory files = new string[](3);
        bytes32[] memory hashes = new bytes32[](3);

        repos[0] = REPO_1; files[0] = FILE_1; hashes[0] = HASH_1;
        repos[1] = REPO_2; files[1] = FILE_2; hashes[1] = HASH_2;
        repos[2] = REPO_1; files[2] = FILE_1; hashes[2] = HASH_1; // Duplicate

        bytes32 modelId1 = _getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = _getModelId(REPO_2, FILE_2);

        // Expect: ModelAdded for first two, ModelSkipped for third (duplicate)
        vm.expectEmit(true, false, false, true);
        emit ModelAdded(modelId1, REPO_1, FILE_1, 1);

        vm.expectEmit(true, false, false, true);
        emit ModelAdded(modelId2, REPO_2, FILE_2, 1);

        vm.expectEmit(true, false, false, true);
        emit ModelSkipped(modelId1, "Model already exists");

        registry.batchAddTrustedModels(repos, files, hashes);

        // Verify only 2 models added
        assertEq(registry.getAllModels().length, 2);
    }

    // ============================================================
    // Test: Model exists before batch call
    // ============================================================

    function test_BatchAddEmitsSkipEventForExistingModel() public {
        // Add Model1 first
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        assertEq(registry.getAllModels().length, 1);

        // Prepare batch with existing Model1 and new Model2
        string[] memory repos = new string[](2);
        string[] memory files = new string[](2);
        bytes32[] memory hashes = new bytes32[](2);

        repos[0] = REPO_1; files[0] = FILE_1; hashes[0] = HASH_1; // Already exists
        repos[1] = REPO_2; files[1] = FILE_2; hashes[1] = HASH_2; // New

        bytes32 modelId1 = _getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = _getModelId(REPO_2, FILE_2);

        // Expect: ModelSkipped for Model1, ModelAdded for Model2
        vm.expectEmit(true, false, false, true);
        emit ModelSkipped(modelId1, "Model already exists");

        vm.expectEmit(true, false, false, true);
        emit ModelAdded(modelId2, REPO_2, FILE_2, 1);

        registry.batchAddTrustedModels(repos, files, hashes);

        // Verify only 2 models total (1 existing + 1 new)
        assertEq(registry.getAllModels().length, 2);
    }

    // ============================================================
    // Test: Mixed new and existing models
    // ============================================================

    function test_BatchAddMixedNewAndExisting() public {
        // Pre-add Model2
        registry.addTrustedModel(REPO_2, FILE_2, HASH_2);

        // Batch: [New1, Existing2, New3]
        string[] memory repos = new string[](3);
        string[] memory files = new string[](3);
        bytes32[] memory hashes = new bytes32[](3);

        repos[0] = REPO_1; files[0] = FILE_1; hashes[0] = HASH_1; // New
        repos[1] = REPO_2; files[1] = FILE_2; hashes[1] = HASH_2; // Exists
        repos[2] = REPO_3; files[2] = FILE_3; hashes[2] = HASH_3; // New

        bytes32 modelId1 = _getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = _getModelId(REPO_2, FILE_2);
        bytes32 modelId3 = _getModelId(REPO_3, FILE_3);

        // Expect events in order: Added, Skipped, Added
        vm.expectEmit(true, false, false, true);
        emit ModelAdded(modelId1, REPO_1, FILE_1, 1);

        vm.expectEmit(true, false, false, true);
        emit ModelSkipped(modelId2, "Model already exists");

        vm.expectEmit(true, false, false, true);
        emit ModelAdded(modelId3, REPO_3, FILE_3, 1);

        registry.batchAddTrustedModels(repos, files, hashes);

        // Verify 3 models total
        assertEq(registry.getAllModels().length, 3);
    }

    // ============================================================
    // Test: All new models (regression - no skip events)
    // ============================================================

    function test_BatchAddAllNewEmitsNoSkipEvents() public {
        string[] memory repos = new string[](2);
        string[] memory files = new string[](2);
        bytes32[] memory hashes = new bytes32[](2);

        repos[0] = REPO_1; files[0] = FILE_1; hashes[0] = HASH_1;
        repos[1] = REPO_2; files[1] = FILE_2; hashes[1] = HASH_2;

        bytes32 modelId1 = _getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = _getModelId(REPO_2, FILE_2);

        // Record logs to verify no ModelSkipped events
        vm.recordLogs();

        registry.batchAddTrustedModels(repos, files, hashes);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Count event types
        uint256 addedCount = 0;
        uint256 skippedCount = 0;
        bytes32 modelAddedSig = keccak256("ModelAdded(bytes32,string,string,uint256)");
        bytes32 modelSkippedSig = keccak256("ModelSkipped(bytes32,string)");

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == modelAddedSig) addedCount++;
            if (logs[i].topics[0] == modelSkippedSig) skippedCount++;
        }

        assertEq(addedCount, 2, "Should emit 2 ModelAdded events");
        assertEq(skippedCount, 0, "Should emit 0 ModelSkipped events");
        assertEq(registry.getAllModels().length, 2);
    }
}
