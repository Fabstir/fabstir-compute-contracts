// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title O1ProposalRemovalTest
 * @notice Tests for Phase 7: O(1) activeProposals array removal
 * @dev Verifies that _removeFromActiveProposals uses O(1) indexed removal
 */
contract O1ProposalRemovalTest is Test {
    ModelRegistryUpgradeable public registry;
    ERC20Mock public fabToken;

    address public owner = address(this);
    address public user1 = address(0x1001);
    address public user2 = address(0x1002);
    address public user3 = address(0x1003);

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
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    function _setupUserWithTokens(address user, uint256 amount) internal {
        fabToken.mint(user, amount);
        vm.prank(user);
        fabToken.approve(address(registry), type(uint256).max);
    }

    function _proposeModel(address proposer, string memory repo, string memory file) internal returns (bytes32) {
        vm.prank(proposer);
        registry.proposeModel(repo, file, keccak256(bytes(repo)));
        return registry.getModelId(repo, file);
    }

    function _executeProposal(bytes32 modelId) internal {
        uint256 proposalDuration = registry.PROPOSAL_DURATION();
        vm.warp(block.timestamp + proposalDuration + 1);
        registry.executeProposal(modelId);
    }

    // ============================================================
    // Basic Functionality Tests
    // ============================================================

    function test_ActiveProposals_AddedOnPropose() public {
        _setupUserWithTokens(user1, 1000 * 10**18);

        bytes32 modelId = _proposeModel(user1, "repo1", "file1.gguf");

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 1);
        assertEq(active[0], modelId);
    }

    function test_ActiveProposals_RemovedOnExecute() public {
        _setupUserWithTokens(user1, 1000 * 10**18);

        bytes32 modelId = _proposeModel(user1, "repo1", "file1.gguf");

        // Execute proposal (will fail due to no votes, but still removes from active)
        _executeProposal(modelId);

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 0);
    }

    function test_ActiveProposals_MultipleProposalsTracked() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        _setupUserWithTokens(user2, 1000 * 10**18);
        _setupUserWithTokens(user3, 1000 * 10**18);

        bytes32 modelId1 = _proposeModel(user1, "repo1", "file1.gguf");
        bytes32 modelId2 = _proposeModel(user2, "repo2", "file2.gguf");
        bytes32 modelId3 = _proposeModel(user3, "repo3", "file3.gguf");

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 3);
    }

    function test_ActiveProposals_MiddleRemovalPreservesOthers() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        _setupUserWithTokens(user2, 1000 * 10**18);
        _setupUserWithTokens(user3, 1000 * 10**18);

        bytes32 modelId1 = _proposeModel(user1, "repo1", "file1.gguf");
        bytes32 modelId2 = _proposeModel(user2, "repo2", "file2.gguf");
        bytes32 modelId3 = _proposeModel(user3, "repo3", "file3.gguf");

        // Remove middle proposal
        _executeProposal(modelId2);

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 2);

        // Verify remaining proposals (order may change due to swap-remove)
        bool found1 = false;
        bool found3 = false;
        for (uint i = 0; i < active.length; i++) {
            if (active[i] == modelId1) found1 = true;
            if (active[i] == modelId3) found3 = true;
        }
        assertTrue(found1, "Model 1 should still be in active list");
        assertTrue(found3, "Model 3 should still be in active list");
    }

    function test_ActiveProposals_FirstRemovalPreservesOthers() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        _setupUserWithTokens(user2, 1000 * 10**18);
        _setupUserWithTokens(user3, 1000 * 10**18);

        bytes32 modelId1 = _proposeModel(user1, "repo1", "file1.gguf");
        bytes32 modelId2 = _proposeModel(user2, "repo2", "file2.gguf");
        bytes32 modelId3 = _proposeModel(user3, "repo3", "file3.gguf");

        // Remove first proposal
        _executeProposal(modelId1);

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 2);

        // Verify remaining proposals
        bool found2 = false;
        bool found3 = false;
        for (uint i = 0; i < active.length; i++) {
            if (active[i] == modelId2) found2 = true;
            if (active[i] == modelId3) found3 = true;
        }
        assertTrue(found2, "Model 2 should still be in active list");
        assertTrue(found3, "Model 3 should still be in active list");
    }

    function test_ActiveProposals_LastRemovalPreservesOthers() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        _setupUserWithTokens(user2, 1000 * 10**18);
        _setupUserWithTokens(user3, 1000 * 10**18);

        bytes32 modelId1 = _proposeModel(user1, "repo1", "file1.gguf");
        bytes32 modelId2 = _proposeModel(user2, "repo2", "file2.gguf");
        bytes32 modelId3 = _proposeModel(user3, "repo3", "file3.gguf");

        // Remove last proposal
        _executeProposal(modelId3);

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 2);

        // Verify remaining proposals
        bool found1 = false;
        bool found2 = false;
        for (uint i = 0; i < active.length; i++) {
            if (active[i] == modelId1) found1 = true;
            if (active[i] == modelId2) found2 = true;
        }
        assertTrue(found1, "Model 1 should still be in active list");
        assertTrue(found2, "Model 2 should still be in active list");
    }

    function test_ActiveProposals_AllRemovedSequentially() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        _setupUserWithTokens(user2, 1000 * 10**18);
        _setupUserWithTokens(user3, 1000 * 10**18);

        bytes32 modelId1 = _proposeModel(user1, "repo1", "file1.gguf");
        bytes32 modelId2 = _proposeModel(user2, "repo2", "file2.gguf");
        bytes32 modelId3 = _proposeModel(user3, "repo3", "file3.gguf");

        // Remove all sequentially
        _executeProposal(modelId1);
        assertEq(registry.getActiveProposals().length, 2);

        _executeProposal(modelId2);
        assertEq(registry.getActiveProposals().length, 1);

        _executeProposal(modelId3);
        assertEq(registry.getActiveProposals().length, 0);
    }

    // ============================================================
    // Gas Efficiency Tests
    // ============================================================

    function test_GasUsage_ExecuteProposal_SingleProposal() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        bytes32 modelId = _proposeModel(user1, "repo1", "file1.gguf");

        vm.warp(block.timestamp + registry.PROPOSAL_DURATION() + 1);

        uint256 gasBefore = gasleft();
        registry.executeProposal(modelId);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("executeProposal (1 proposal) gas", gasUsed);
        // Should be under 100k for a single proposal
        assertLt(gasUsed, 100000, "Gas should be reasonable for single proposal");
    }

    function test_GasUsage_ExecuteProposal_TenProposals() public {
        // Create 10 proposals
        address[] memory users = new address[](10);
        bytes32[] memory modelIds = new bytes32[](10);

        for (uint i = 0; i < 10; i++) {
            users[i] = address(uint160(0x2000 + i));
            _setupUserWithTokens(users[i], 1000 * 10**18);
            modelIds[i] = _proposeModel(users[i], string(abi.encodePacked("repo", vm.toString(i))), "file.gguf");
        }

        vm.warp(block.timestamp + registry.PROPOSAL_DURATION() + 1);

        // Execute middle proposal and measure gas
        uint256 gasBefore = gasleft();
        registry.executeProposal(modelIds[5]);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("executeProposal (10 proposals, middle) gas", gasUsed);
        // With O(1) removal, gas should be similar to single proposal case
        assertLt(gasUsed, 150000, "Gas should be reasonable with O(1) removal");
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    function test_ActiveProposals_EmptyInitially() public {
        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active.length, 0);
    }

    function test_ActiveProposals_SingleAddRemove() public {
        _setupUserWithTokens(user1, 1000 * 10**18);
        bytes32 modelId = _proposeModel(user1, "repo1", "file1.gguf");

        assertEq(registry.getActiveProposals().length, 1);

        _executeProposal(modelId);

        assertEq(registry.getActiveProposals().length, 0);
    }

    function test_ActiveProposals_ReAddAfterRemove() public {
        _setupUserWithTokens(user1, 2000 * 10**18);

        // First proposal
        bytes32 modelId1 = _proposeModel(user1, "repo1", "file1.gguf");
        assertEq(registry.getActiveProposals().length, 1);

        _executeProposal(modelId1);
        assertEq(registry.getActiveProposals().length, 0);

        // Second proposal (different model)
        bytes32 modelId2 = _proposeModel(user1, "repo2", "file2.gguf");
        assertEq(registry.getActiveProposals().length, 1);

        bytes32[] memory active = registry.getActiveProposals();
        assertEq(active[0], modelId2);
    }
}
