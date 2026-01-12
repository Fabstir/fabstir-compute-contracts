// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title ModelRegistryUpgradeable Initialization Tests
 * @dev Tests initialization, re-initialization protection, and basic proxy functionality
 */
contract ModelRegistryInitializationTest is Test {
    ModelRegistryUpgradeable public implementation;
    ModelRegistryUpgradeable public registry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy implementation
        implementation = new ModelRegistryUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        registry = ModelRegistryUpgradeable(proxyAddr);
    }

    // ============================================================
    // Initialization Tests
    // ============================================================

    function test_InitializeSetsGovernanceToken() public view {
        assertEq(address(registry.governanceToken()), address(fabToken));
    }

    function test_InitializeSetsOwner() public view {
        assertEq(registry.owner(), owner);
    }

    function test_InitializeCanOnlyBeCalledOnce() public {
        // Try to initialize again - should revert
        vm.expectRevert();
        registry.initialize(address(fabToken));
    }

    function test_InitializeRevertsWithZeroAddress() public {
        // Deploy new implementation
        ModelRegistryUpgradeable newImpl = new ModelRegistryUpgradeable();

        // Try to initialize with zero address - should revert
        vm.expectRevert("Invalid token address");
        address(new ERC1967Proxy(
            address(newImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(0)))
        ));
    }

    function test_ImplementationCannotBeInitialized() public {
        // Try to initialize implementation directly - should revert
        vm.expectRevert();
        implementation.initialize(address(fabToken));
    }

    // ============================================================
    // Basic Functionality Through Proxy Tests
    // ============================================================

    function test_GetModelIdWorks() public view {
        bytes32 modelId = registry.getModelId("TheBloke/Llama-2-7B-GGUF", "llama-2-7b.Q4_K_M.gguf");
        bytes32 expected = keccak256(abi.encodePacked("TheBloke/Llama-2-7B-GGUF", "/", "llama-2-7b.Q4_K_M.gguf"));
        assertEq(modelId, expected);
    }

    function test_AddTrustedModelWorks() public {
        string memory repo = "TheBloke/Llama-2-7B-GGUF";
        string memory fileName = "llama-2-7b.Q4_K_M.gguf";
        bytes32 hash = keccak256("model-hash");

        vm.prank(owner);
        registry.addTrustedModel(repo, fileName, hash);

        bytes32 modelId = registry.getModelId(repo, fileName);
        assertTrue(registry.isModelApproved(modelId));
        assertTrue(registry.isTrustedModel(modelId));
        assertEq(registry.getModelHash(modelId), hash);
    }

    function test_AddTrustedModelOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        registry.addTrustedModel("repo", "file", bytes32(0));
    }

    function test_DeactivateModelWorks() public {
        // First add a model
        string memory repo = "Test/Model";
        string memory fileName = "model.gguf";
        bytes32 hash = keccak256("hash");

        vm.prank(owner);
        registry.addTrustedModel(repo, fileName, hash);

        bytes32 modelId = registry.getModelId(repo, fileName);
        assertTrue(registry.isModelApproved(modelId));

        // Deactivate
        vm.prank(owner);
        registry.deactivateModel(modelId);

        assertFalse(registry.isModelApproved(modelId));
    }

    function test_ReactivateModelWorks() public {
        // Add and deactivate a model
        string memory repo = "Test/Model";
        string memory fileName = "model.gguf";
        bytes32 hash = keccak256("hash");

        vm.prank(owner);
        registry.addTrustedModel(repo, fileName, hash);

        bytes32 modelId = registry.getModelId(repo, fileName);

        vm.prank(owner);
        registry.deactivateModel(modelId);

        // Reactivate
        vm.prank(owner);
        registry.reactivateModel(modelId);

        assertTrue(registry.isModelApproved(modelId));
    }

    function test_GetAllModelsWorks() public {
        // Add multiple models
        vm.startPrank(owner);
        registry.addTrustedModel("Repo1", "file1.gguf", bytes32(uint256(1)));
        registry.addTrustedModel("Repo2", "file2.gguf", bytes32(uint256(2)));
        vm.stopPrank();

        bytes32[] memory models = registry.getAllModels();
        assertEq(models.length, 2);
    }

    function test_BatchAddTrustedModelsWorks() public {
        string[] memory repos = new string[](2);
        repos[0] = "Repo1";
        repos[1] = "Repo2";

        string[] memory fileNames = new string[](2);
        fileNames[0] = "file1.gguf";
        fileNames[1] = "file2.gguf";

        bytes32[] memory hashes = new bytes32[](2);
        hashes[0] = bytes32(uint256(1));
        hashes[1] = bytes32(uint256(2));

        vm.prank(owner);
        registry.batchAddTrustedModels(repos, fileNames, hashes);

        bytes32[] memory models = registry.getAllModels();
        assertEq(models.length, 2);

        assertTrue(registry.isModelApproved(registry.getModelId("Repo1", "file1.gguf")));
        assertTrue(registry.isModelApproved(registry.getModelId("Repo2", "file2.gguf")));
    }

    function test_GetModelReturnsCorrectData() public {
        string memory repo = "TheBloke/Llama-2-7B-GGUF";
        string memory fileName = "llama-2-7b.Q4_K_M.gguf";
        bytes32 hash = keccak256("model-hash");

        vm.prank(owner);
        registry.addTrustedModel(repo, fileName, hash);

        bytes32 modelId = registry.getModelId(repo, fileName);
        ModelRegistryUpgradeable.Model memory model = registry.getModel(modelId);

        assertEq(model.huggingfaceRepo, repo);
        assertEq(model.fileName, fileName);
        assertEq(model.sha256Hash, hash);
        assertEq(model.approvalTier, 1);
        assertTrue(model.active);
        assertTrue(model.timestamp > 0);
    }

    // ============================================================
    // Constants Tests
    // ============================================================

    function test_ConstantsAreCorrect() public view {
        assertEq(registry.PROPOSAL_DURATION(), 3 days);
        assertEq(registry.APPROVAL_THRESHOLD(), 100000 * 10**18);
        assertEq(registry.PROPOSAL_FEE(), 100 * 10**18);
    }
}
