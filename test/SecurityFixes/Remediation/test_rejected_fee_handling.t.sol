// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../mocks/MockERC20.sol";

/// @title RejectedFeeHandlingTest
/// @notice F202614964: Proposal Fee Permanently Locked on Rejection
contract RejectedFeeHandlingTest is Test {
    ModelRegistryUpgradeable public modelRegistry;
    MockERC20 public fabToken;
    address public owner = address(0x1);
    address public proposer = address(0x2);
    address public voter1 = address(0x3);
    address public whale = address(0x4);
    address public nonOwner = address(0x5);
    uint256 public constant PROPOSAL_FEE = 100 * 10 ** 18;
    bytes32 public testModelId;
    event RejectedFeesWithdrawn(address indexed recipient, uint256 amount);

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
        fabToken.mint(whale, 500000 * 10 ** 18);
        vm.prank(proposer);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        vm.prank(voter1);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        vm.prank(whale);
        fabToken.approve(address(modelRegistry), type(uint256).max);
        testModelId = modelRegistry.getModelId("test/model", "model.gguf");
    }

    function _createAndRejectProposal(string memory repo, string memory fileName) internal returns (bytes32) {
        bytes32 modelId = modelRegistry.getModelId(repo, fileName);
        vm.prank(proposer);
        modelRegistry.proposeModel(repo, fileName, bytes32(uint256(1)));
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10 ** 18, false);
        (,,,,,,, uint256 endTime,) = modelRegistry.proposals(modelId);
        vm.warp(endTime + 1);
        modelRegistry.executeProposal(modelId);
        return modelId;
    }

    function _createAndApproveProposal(string memory repo, string memory fileName) internal returns (bytes32) {
        bytes32 modelId = modelRegistry.getModelId(repo, fileName);
        vm.prank(proposer);
        modelRegistry.proposeModel(repo, fileName, bytes32(uint256(1)));
        vm.prank(whale);
        modelRegistry.voteOnProposal(modelId, 100000 * 10 ** 18, true);
        (,,,,,,, uint256 endTime,) = modelRegistry.proposals(modelId);
        vm.warp(endTime + 1);
        modelRegistry.executeProposal(modelId);
        return modelId;
    }

    function test_AccumulatedRejectedFeesInitiallyZero() public view {
        assertEq(modelRegistry.accumulatedRejectedFees(), 0);
    }

    function test_RejectedProposalFeeAddedToAccumulated() public {
        _createAndRejectProposal("test/model", "model.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE);
    }

    function test_ApprovedProposalFeeReturnedNotAccumulated() public {
        uint256 proposerBal = fabToken.balanceOf(proposer);
        _createAndApproveProposal("test/model", "model.gguf");
        assertEq(fabToken.balanceOf(proposer), proposerBal);
        assertEq(modelRegistry.accumulatedRejectedFees(), 0);
    }

    function test_MultipleRejectedProposalsAccumulateFees() public {
        _createAndRejectProposal("test/model1", "m1.gguf");
        _createAndRejectProposal("test/model2", "m2.gguf");
        _createAndRejectProposal("test/model3", "m3.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE * 3);
    }

    function test_WithdrawRejectedFeesTransfersTokens() public {
        _createAndRejectProposal("test/model", "model.gguf");
        uint256 ownerBal = fabToken.balanceOf(owner);
        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);
        assertEq(fabToken.balanceOf(owner), ownerBal + accumulated);
        assertEq(modelRegistry.accumulatedRejectedFees(), 0);
    }

    function test_WithdrawPartialRejectedFees() public {
        _createAndRejectProposal("test/model1", "m1.gguf");
        _createAndRejectProposal("test/model2", "m2.gguf");
        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        uint256 ownerBal = fabToken.balanceOf(owner);
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(PROPOSAL_FEE);
        assertEq(fabToken.balanceOf(owner), ownerBal + PROPOSAL_FEE);
        assertEq(modelRegistry.accumulatedRejectedFees(), accumulated - PROPOSAL_FEE);
    }

    function test_WithdrawRejectedFeesEmitsEvent() public {
        _createAndRejectProposal("test/model", "model.gguf");
        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        vm.expectEmit(true, false, false, true);
        emit RejectedFeesWithdrawn(owner, accumulated);
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);
    }

    function test_WithdrawRejectedFeesOnlyOwner() public {
        _createAndRejectProposal("test/model", "model.gguf");
        vm.prank(nonOwner);
        vm.expectRevert();
        modelRegistry.withdrawRejectedFees(0);
    }

    function test_WithdrawRejectedFeesRevertsIfZero() public {
        vm.prank(owner);
        vm.expectRevert("No fees to withdraw");
        modelRegistry.withdrawRejectedFees(0);
    }

    function test_WithdrawRejectedFeesRevertsIfInsufficient() public {
        _createAndRejectProposal("test/model", "model.gguf");
        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        vm.prank(owner);
        vm.expectRevert("Insufficient accumulated fees");
        modelRegistry.withdrawRejectedFees(accumulated + 1);
    }

    function test_RejectedFeeFlowEndToEnd() public {
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));
        vm.prank(voter1);
        modelRegistry.voteOnProposal(testModelId, 10000 * 10 ** 18, false);
        (,,,,,,, uint256 endTime,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime + 1);
        modelRegistry.executeProposal(testModelId);
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE);
        uint256 ownerBal = fabToken.balanceOf(owner);
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);
        assertEq(fabToken.balanceOf(owner), ownerBal + PROPOSAL_FEE);
    }

    function test_MixedApprovedAndRejectedProposals() public {
        _createAndRejectProposal("test/model1", "m1.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE);
        _createAndApproveProposal("test/model2", "m2.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE);
        _createAndRejectProposal("test/model3", "m3.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE * 2);
    }
}
