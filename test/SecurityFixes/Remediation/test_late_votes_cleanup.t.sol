// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../mocks/MockERC20.sol";

/// @title LateVotesCleanupTest
/// @notice F202614965: lateVotes Not Cleared on Proposal Execution
contract LateVotesCleanupTest is Test {
    ModelRegistryUpgradeable public modelRegistry;
    MockERC20 public fabToken;
    address public owner = address(0x1);
    address public proposer = address(0x2);
    address public voter1 = address(0x3);
    address public voter2 = address(0x4);
    uint256 public constant PROPOSAL_FEE = 100 * 10 ** 18;
    uint256 public constant EXTENSION_WINDOW = 4 hours;
    uint256 public constant REPROPOSAL_COOLDOWN = 30 days;
    bytes32 public testModelId;

    function setUp() public {
        fabToken = new MockERC20("FAB", "FAB", 18);
        vm.startPrank(owner);
        ModelRegistryUpgradeable impl = new ModelRegistryUpgradeable();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeWithSelector(ModelRegistryUpgradeable.initialize.selector, address(fabToken))
        );
        modelRegistry = ModelRegistryUpgradeable(address(proxy));
        vm.stopPrank();
        fabToken.mint(proposer, 10000 * 10 ** 18);
        fabToken.mint(voter1, 50000 * 10 ** 18);
        fabToken.mint(voter2, 50000 * 10 ** 18);
        vm.prank(proposer);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        vm.prank(voter1);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        vm.prank(voter2);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        testModelId = modelRegistry.getModelId("test/model", "model.gguf");
    }

    function _createProposalWithLateVotes(uint256 lateVoteAmount) internal {
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));
        (,,,,,,, uint256 endTime,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime - EXTENSION_WINDOW + 1);
        if (lateVoteAmount > 0) {
            vm.prank(voter1);
            modelRegistry.voteOnProposal(testModelId, lateVoteAmount, false);
        }
    }

    function _executeAsRejected() internal {
        (,,,,,,, uint256 endTime,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime + 1);
        modelRegistry.executeProposal(testModelId);
    }

    function test_LateVotesInitiallyZero() public view {
        assertEq(modelRegistry.lateVotes(testModelId), 0);
    }

    function test_LateVotesAccumulatedDuringExtensionWindow() public {
        uint256 voteAmount = 5000 * 10 ** 18;
        _createProposalWithLateVotes(voteAmount);
        assertEq(modelRegistry.lateVotes(testModelId), voteAmount);
    }

    function test_LateVotesClearedOnReproposal() public {
        _createProposalWithLateVotes(9000 * 10 ** 18);
        assertEq(modelRegistry.lateVotes(testModelId), 9000 * 10 ** 18);
        _executeAsRejected();
        vm.warp(block.timestamp + REPROPOSAL_COOLDOWN + 1);
        fabToken.mint(proposer, PROPOSAL_FEE);
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
        assertEq(modelRegistry.lateVotes(testModelId), 0);
    }

    function test_ExtensionRequiresFull10kOnReproposal() public {
        _createProposalWithLateVotes(9000 * 10 ** 18);
        _executeAsRejected();
        vm.warp(block.timestamp + REPROPOSAL_COOLDOWN + 1);
        fabToken.mint(proposer, PROPOSAL_FEE);
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
        (,,,,,,, uint256 newEndTime, uint8 extCount) = modelRegistry.proposals(testModelId);
        assertEq(extCount, 0);
        vm.warp(newEndTime - EXTENSION_WINDOW + 1);
        vm.prank(voter2);
        modelRegistry.voteOnProposal(testModelId, 5000 * 10 ** 18, true);
        (,,,,,,, uint256 endAfter, uint8 extAfter) = modelRegistry.proposals(testModelId);
        assertEq(endAfter, newEndTime);
        assertEq(extAfter, 0);
    }

    function test_PartialLateVotesNotCarriedOver() public {
        _createProposalWithLateVotes(8000 * 10 ** 18);
        _executeAsRejected();
        vm.warp(block.timestamp + REPROPOSAL_COOLDOWN + 1);
        fabToken.mint(proposer, PROPOSAL_FEE);
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
        (,,,,,,, uint256 newEndTime,) = modelRegistry.proposals(testModelId);
        vm.warp(newEndTime - EXTENSION_WINDOW + 1);
        vm.prank(voter2);
        modelRegistry.voteOnProposal(testModelId, 3000 * 10 ** 18, true);
        assertEq(modelRegistry.lateVotes(testModelId), 3000 * 10 ** 18);
        (,,,,,,,, uint8 extCount) = modelRegistry.proposals(testModelId);
        assertEq(extCount, 0);
    }

    function test_MultipleCyclesClearLateVotes() public {
        _createProposalWithLateVotes(7000 * 10 ** 18);
        _executeAsRejected();
        uint256 exec1 = modelRegistry.lastProposalExecutionTime(testModelId);
        vm.warp(exec1 + REPROPOSAL_COOLDOWN + 1);
        fabToken.mint(proposer, PROPOSAL_FEE);
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(2)));
        assertEq(modelRegistry.lateVotes(testModelId), 0);
        (,,,,,,, uint256 endTime2,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime2 - EXTENSION_WINDOW + 1);
        vm.prank(voter2);
        modelRegistry.voteOnProposal(testModelId, 6000 * 10 ** 18, false);
        vm.warp(endTime2 + 1);
        modelRegistry.executeProposal(testModelId);
        uint256 exec2 = modelRegistry.lastProposalExecutionTime(testModelId);
        vm.warp(exec2 + REPROPOSAL_COOLDOWN + 1);
        fabToken.mint(proposer, PROPOSAL_FEE);
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(3)));
        assertEq(modelRegistry.lateVotes(testModelId), 0);
    }
}
