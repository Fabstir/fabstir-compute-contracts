// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../mocks/MockERC20.sol";

/**
 * @title ReproposalCooldownTest
 * @notice Tests for Phase 15: Re-proposal Cooldown System
 */
contract ReproposalCooldownTest is Test {
    ModelRegistryUpgradeable public modelRegistry;
    MockERC20 public fabToken;

    address public owner = address(0x1);
    address public proposer = address(0x2);
    address public voter1 = address(0x3);
    address public whale = address(0x4);

    bytes32 public testModelId;

    function setUp() public {
        // Deploy FAB token
        fabToken = new MockERC20("FAB", "FAB", 18);

        // Deploy ModelRegistry with proxy
        vm.startPrank(owner);
        ModelRegistryUpgradeable impl = new ModelRegistryUpgradeable();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(ModelRegistryUpgradeable.initialize.selector, address(fabToken))
        );
        modelRegistry = ModelRegistryUpgradeable(address(proxy));
        vm.stopPrank();

        // Mint tokens for test users
        fabToken.mint(proposer, 10000 * 10**18);
        fabToken.mint(voter1, 50000 * 10**18);
        fabToken.mint(whale, 500000 * 10**18);

        // Approve ModelRegistry to spend tokens
        vm.prank(proposer);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        vm.prank(voter1);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        vm.prank(whale);
        fabToken.approve(address(modelRegistry), type(uint256).max);

        // Calculate test model ID
        testModelId = modelRegistry.getModelId("test/model", "model.gguf");
    }

    // ============================================
    // Phase 15.1 Tests: Constants and State Variables
    // ============================================

    function test_ReproposalCooldownConstant() public view {
        assertEq(
            modelRegistry.REPROPOSAL_COOLDOWN(),
            30 days,
            "REPROPOSAL_COOLDOWN should be 30 days"
        );
    }

    function test_LastProposalExecutionTimeMappingAccessible() public view {
        // Should return 0 for any modelId initially
        assertEq(
            modelRegistry.lastProposalExecutionTime(testModelId),
            0,
            "lastProposalExecutionTime should be 0 initially"
        );
    }

    function test_LastProposalExecutionTimeReturnsZeroForNonExistentProposal() public view {
        bytes32 randomModelId = keccak256("random/model");
        assertEq(
            modelRegistry.lastProposalExecutionTime(randomModelId),
            0,
            "lastProposalExecutionTime should be 0 for non-existent proposal"
        );
    }

    // ============================================
    // Phase 15.3 Tests: Re-proposal Logic
    // ============================================

    function _createAndRejectProposal() internal returns (bytes32) {
        // Create proposal
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        // Vote against (not enough to pass threshold)
        vm.prank(voter1);
        modelRegistry.voteOnProposal(testModelId, 10000 * 10**18, false);

        // Warp past endTime
        (,,,,,,,uint256 endTime,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime + 1);

        // Execute (will be rejected)
        modelRegistry.executeProposal(testModelId);

        return testModelId;
    }

    function _createAndApproveProposal() internal returns (bytes32) {
        // Create proposal
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        // Vote for (enough to pass threshold)
        vm.prank(whale);
        modelRegistry.voteOnProposal(testModelId, 100000 * 10**18, true);

        // Warp past endTime
        (,,,,,,,uint256 endTime,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime + 1);

        // Execute (will be approved)
        modelRegistry.executeProposal(testModelId);

        return testModelId;
    }

    function test_ReproposingImmediatelyAfterRejectionReverts() public {
        bytes32 modelId = _createAndRejectProposal();

        // Verify proposal was executed
        (,,,,,bool executed,,,) = modelRegistry.proposals(modelId);
        assertTrue(executed, "Proposal should be executed");

        // Verify lastProposalExecutionTime is set
        assertGt(modelRegistry.lastProposalExecutionTime(modelId), 0, "lastProposalExecutionTime should be set");

        // Try to re-propose immediately - should fail
        vm.prank(proposer);
        vm.expectRevert("Must wait cooldown period");
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
    }

    function test_ReproposingAfterCooldownSucceeds() public {
        bytes32 modelId = _createAndRejectProposal();

        uint256 executionTime = modelRegistry.lastProposalExecutionTime(modelId);

        // Warp past cooldown
        vm.warp(executionTime + modelRegistry.REPROPOSAL_COOLDOWN() + 1);

        // Re-propose should succeed
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));

        // Verify new proposal exists
        (,,,,uint256 proposalTime,,,,) = modelRegistry.proposals(modelId);
        assertGt(proposalTime, executionTime, "New proposal should be created");
    }

    function test_ReproposingApprovedModelStillBlocked() public {
        _createAndApproveProposal();

        // Verify model exists
        assertTrue(modelRegistry.isModelApproved(testModelId), "Model should be approved");

        // Warp past cooldown
        vm.warp(block.timestamp + modelRegistry.REPROPOSAL_COOLDOWN() + 1);

        // Re-propose should still fail (model already exists)
        vm.prank(proposer);
        vm.expectRevert("Model already exists");
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
    }

    function test_OldProposalDataClearedOnReproposal() public {
        bytes32 modelId = _createAndRejectProposal();

        // Verify old proposal has data
        (,address oldProposer,,,,,,, ) = modelRegistry.proposals(modelId);
        assertEq(oldProposer, proposer, "Old proposal should have proposer");

        // Warp past cooldown
        vm.warp(modelRegistry.lastProposalExecutionTime(modelId) + modelRegistry.REPROPOSAL_COOLDOWN() + 1);

        // Re-propose with different proposer
        address newProposer = address(0x5);
        fabToken.mint(newProposer, 1000 * 10**18);
        vm.prank(newProposer);
        fabToken.approve(address(modelRegistry), type(uint256).max);

        vm.prank(newProposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));

        // Verify new proposal has new data
        (,address currentProposer,,,,,,,) = modelRegistry.proposals(modelId);
        assertEq(currentProposer, newProposer, "New proposal should have new proposer");
    }

    function test_CannotProposeWhileActiveProposalExists() public {
        // Create first proposal
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        // Try to create another proposal for same model - should fail
        vm.prank(proposer);
        vm.expectRevert("Active proposal exists");
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
    }
}
