// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title ModelRegistryUpgradeable V2 (Mock for testing upgrades)
 * @dev Adds version function and extra state for testing upgrade preservation
 */
contract ModelRegistryUpgradeableV2 is ModelRegistryUpgradeable {
    // New storage variable (appended after existing storage)
    string public registryName;

    function initializeV2(string memory _name) external reinitializer(2) {
        registryName = _name;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }

    function getModelCount() external view returns (uint256) {
        return modelList.length;
    }
}

/**
 * @title ModelRegistryUpgradeable Upgrade Tests
 * @dev Tests upgrade mechanics, state preservation, and authorization
 */
contract ModelRegistryUpgradeTest is Test {
    ModelRegistryUpgradeable public implementation;
    ModelRegistryUpgradeable public registry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    // Test model data
    string constant REPO_1 = "TheBloke/Llama-2-7B-GGUF";
    string constant FILE_1 = "llama-2-7b.Q4_K_M.gguf";
    bytes32 constant HASH_1 = bytes32(uint256(0x1234));

    string constant REPO_2 = "TinyLlama/TinyLlama-1.1B";
    string constant FILE_2 = "tinyllama-1.1b.Q4_K_M.gguf";
    bytes32 constant HASH_2 = bytes32(uint256(0x5678));

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

        // Add some models to test state preservation
        vm.startPrank(owner);
        registry.addTrustedModel(REPO_1, FILE_1, HASH_1);
        registry.addTrustedModel(REPO_2, FILE_2, HASH_2);
        vm.stopPrank();
    }

    // ============================================================
    // Pre-Upgrade State Verification
    // ============================================================

    function test_PreUpgradeStateIsCorrect() public view {
        // Verify models exist before upgrade
        bytes32 modelId1 = registry.getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = registry.getModelId(REPO_2, FILE_2);

        assertTrue(registry.isModelApproved(modelId1));
        assertTrue(registry.isModelApproved(modelId2));
        assertTrue(registry.trustedModels(modelId1));
        assertTrue(registry.trustedModels(modelId2));
        assertEq(registry.getModelHash(modelId1), HASH_1);
        assertEq(registry.getModelHash(modelId2), HASH_2);

        bytes32[] memory allModels = registry.getAllModels();
        assertEq(allModels.length, 2);

        assertEq(registry.owner(), owner);
        assertEq(address(registry.governanceToken()), address(fabToken));
    }

    // ============================================================
    // Upgrade Authorization Tests
    // ============================================================

    function test_OnlyOwnerCanUpgrade() public {
        // Deploy V2 implementation
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        // Try to upgrade as non-owner - should revert
        vm.prank(user1);
        vm.expectRevert();
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");
    }

    function test_OwnerCanUpgrade() public {
        // Deploy V2 implementation
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        // Upgrade as owner - should succeed
        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        // Verify upgrade worked by calling V2 function
        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));
        assertEq(registryV2.version(), "v2");
    }

    // ============================================================
    // State Preservation Tests
    // ============================================================

    function test_UpgradePreservesGovernanceToken() public {
        // Deploy and upgrade to V2
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));
        assertEq(address(registryV2.governanceToken()), address(fabToken));
    }

    function test_UpgradePreservesOwner() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));
        assertEq(registryV2.owner(), owner);
    }

    function test_UpgradePreservesModelData() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        // Verify model data preserved
        bytes32 modelId1 = registryV2.getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = registryV2.getModelId(REPO_2, FILE_2);

        assertTrue(registryV2.isModelApproved(modelId1));
        assertTrue(registryV2.isModelApproved(modelId2));
        assertEq(registryV2.getModelHash(modelId1), HASH_1);
        assertEq(registryV2.getModelHash(modelId2), HASH_2);

        // Verify model details
        ModelRegistryUpgradeable.Model memory model1 = registryV2.getModel(modelId1);
        assertEq(model1.huggingfaceRepo, REPO_1);
        assertEq(model1.fileName, FILE_1);
        assertEq(model1.approvalTier, 1);
        assertTrue(model1.active);
    }

    function test_UpgradePreservesModelList() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        // Verify model list preserved
        bytes32[] memory allModels = registryV2.getAllModels();
        assertEq(allModels.length, 2);
        assertEq(registryV2.getModelCount(), 2);
    }

    function test_UpgradePreservesTrustedModelsMapping() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        bytes32 modelId1 = registryV2.getModelId(REPO_1, FILE_1);
        bytes32 modelId2 = registryV2.getModelId(REPO_2, FILE_2);

        assertTrue(registryV2.trustedModels(modelId1));
        assertTrue(registryV2.trustedModels(modelId2));
    }

    // ============================================================
    // Upgrade With Initialization Tests
    // ============================================================

    function test_UpgradeWithV2Initialization() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        // Upgrade with V2 initialization
        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(ModelRegistryUpgradeableV2.initializeV2, ("My Registry"))
        );

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        // Verify V2 initialization worked
        assertEq(registryV2.registryName(), "My Registry");
        assertEq(registryV2.version(), "v2");

        // Verify V1 state still preserved
        assertEq(registryV2.owner(), owner);
        assertEq(address(registryV2.governanceToken()), address(fabToken));
        assertEq(registryV2.getModelCount(), 2);
    }

    function test_V2InitializationCannotBeCalledTwice() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        // Upgrade with V2 initialization
        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(ModelRegistryUpgradeableV2.initializeV2, ("My Registry"))
        );

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        // Try to call initializeV2 again - should revert
        vm.expectRevert();
        registryV2.initializeV2("Another Name");
    }

    // ============================================================
    // Post-Upgrade Functionality Tests
    // ============================================================

    function test_CanAddModelsAfterUpgrade() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        // Add a new model after upgrade
        string memory newRepo = "NewRepo/Model";
        string memory newFile = "new-model.gguf";
        bytes32 newHash = bytes32(uint256(0xABCD));

        vm.prank(owner);
        registryV2.addTrustedModel(newRepo, newFile, newHash);

        bytes32 newModelId = registryV2.getModelId(newRepo, newFile);
        assertTrue(registryV2.isModelApproved(newModelId));
        assertEq(registryV2.getModelCount(), 3);
    }

    function test_CanDeactivateModelsAfterUpgrade() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        bytes32 modelId1 = registryV2.getModelId(REPO_1, FILE_1);

        vm.prank(owner);
        registryV2.deactivateModel(modelId1);

        assertFalse(registryV2.isModelApproved(modelId1));
    }

    function test_CanTransferOwnershipAfterUpgrade() public {
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        ModelRegistryUpgradeableV2 registryV2 = ModelRegistryUpgradeableV2(address(registry));

        // Transfer ownership
        vm.prank(owner);
        registryV2.transferOwnership(user1);

        assertEq(registryV2.owner(), user1);

        // New owner can add models
        vm.prank(user1);
        registryV2.addTrustedModel("NewOwner/Model", "model.gguf", bytes32(uint256(1)));
    }

    // ============================================================
    // Implementation Slot Verification
    // ============================================================

    function test_ImplementationSlotUpdatedAfterUpgrade() public {
        // Get implementation before upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implBefore = address(uint160(uint256(vm.load(address(registry), slot))));
        assertEq(implBefore, address(implementation));

        // Deploy and upgrade to V2
        ModelRegistryUpgradeableV2 implementationV2 = new ModelRegistryUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(registry)).upgradeToAndCall(address(implementationV2), "");

        // Verify implementation changed
        address implAfter = address(uint160(uint256(vm.load(address(registry), slot))));
        assertEq(implAfter, address(implementationV2));
        assertTrue(implAfter != implBefore);
    }
}
