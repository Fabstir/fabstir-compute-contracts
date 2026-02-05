// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../mocks/MockERC20.sol";

/**
 * @title RejectedFeeHandlingTest
 * @notice Tests for Security Fix: Rejected Proposal Fee Handling
 * @dev Verifies that rejected proposal fees are accumulated and withdrawable by owner
 */
contract RejectedFeeHandlingTest is Test {
    ModelRegistryUpgradeable public modelRegistry;
    MockERC20 public fabToken;

    address public owner = address(0x1);
    address public proposer = address(0x2);
    address public voter1 = address(0x3);
    address public whale = address(0x4);
    address public nonOwner = address(0x5);

    uint256 public constant PROPOSAL_FEE = 100 * 10**18;
    uint256 public constant APPROVAL_THRESHOLD = 100000 * 10**18;

    bytes32 public testModelId;

    event RejectedFeesWithdrawn(address indexed recipient, uint256 amount);

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
    // Helper Functions
    // ============================================

    function _createAndRejectProposal(string memory repo, string memory fileName) internal returns (bytes32) {
        bytes32 modelId = modelRegistry.getModelId(repo, fileName);

        // Create proposal
        vm.prank(proposer);
        modelRegistry.proposeModel(repo, fileName, bytes32(uint256(1)));

        // Vote against (not enough to pass threshold)
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, false);

        // Warp past endTime
        (,,,,,,,uint256 endTime,) = modelRegistry.proposals(modelId);
        vm.warp(endTime + 1);

        // Execute (will be rejected)
        modelRegistry.executeProposal(modelId);

        return modelId;
    }

    function _createAndApproveProposal(string memory repo, string memory fileName) internal returns (bytes32) {
        bytes32 modelId = modelRegistry.getModelId(repo, fileName);

        // Create proposal
        vm.prank(proposer);
        modelRegistry.proposeModel(repo, fileName, bytes32(uint256(1)));

        // Vote for (enough to pass threshold)
        vm.prank(whale);
        modelRegistry.voteOnProposal(modelId, 100000 * 10**18, true);

        // Warp past endTime
        (,,,,,,,uint256 endTime,) = modelRegistry.proposals(modelId);
        vm.warp(endTime + 1);

        // Execute (will be approved)
        modelRegistry.executeProposal(modelId);

        return modelId;
    }

    // ============================================
    // Sub-phase 1.1 Tests: Fee Tracking State
    // ============================================

    function test_AccumulatedRejectedFeesInitiallyZero() public view {
        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            0,
            "accumulatedRejectedFees should be 0 initially"
        );
    }

    function test_RejectedProposalFeeAddedToAccumulated() public {
        uint256 initialAccumulated = modelRegistry.accumulatedRejectedFees();

        // Create and reject a proposal
        _createAndRejectProposal("test/model", "model.gguf");

        // Verify fee was accumulated
        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            initialAccumulated + PROPOSAL_FEE,
            "Rejected proposal fee should be accumulated"
        );
    }

    function test_ApprovedProposalFeeReturnedNotAccumulated() public {
        uint256 proposerBalanceBefore = fabToken.balanceOf(proposer);
        uint256 accumulatedBefore = modelRegistry.accumulatedRejectedFees();

        // Create and approve a proposal
        _createAndApproveProposal("test/model", "model.gguf");

        // Verify fee was returned to proposer
        uint256 proposerBalanceAfter = fabToken.balanceOf(proposer);
        assertEq(
            proposerBalanceAfter,
            proposerBalanceBefore,
            "Approved proposal fee should be returned to proposer"
        );

        // Verify accumulated did not change
        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            accumulatedBefore,
            "Approved proposal should not add to accumulated fees"
        );
    }

    function test_MultipleRejectedProposalsAccumulateFees() public {
        uint256 initialAccumulated = modelRegistry.accumulatedRejectedFees();

        // Create and reject first proposal
        _createAndRejectProposal("test/model1", "model1.gguf");

        // Create and reject second proposal
        _createAndRejectProposal("test/model2", "model2.gguf");

        // Create and reject third proposal
        _createAndRejectProposal("test/model3", "model3.gguf");

        // Verify all fees accumulated
        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            initialAccumulated + (PROPOSAL_FEE * 3),
            "Multiple rejected proposal fees should accumulate"
        );
    }

    // ============================================
    // Sub-phase 1.2 Tests: Fee Withdrawal
    // ============================================

    function test_WithdrawRejectedFeesTransfersTokens() public {
        // Accumulate some rejected fees
        _createAndRejectProposal("test/model", "model.gguf");

        uint256 ownerBalanceBefore = fabToken.balanceOf(owner);
        uint256 accumulated = modelRegistry.accumulatedRejectedFees();

        // Withdraw all fees
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);

        // Verify tokens transferred
        assertEq(
            fabToken.balanceOf(owner),
            ownerBalanceBefore + accumulated,
            "Owner should receive withdrawn fees"
        );

        // Verify accumulated is zero
        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            0,
            "Accumulated fees should be zero after full withdrawal"
        );
    }

    function test_WithdrawAllRejectedFeesWithZeroAmount() public {
        // Accumulate some rejected fees
        _createAndRejectProposal("test/model", "model.gguf");

        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        assertGt(accumulated, 0, "Should have accumulated fees");

        uint256 ownerBalanceBefore = fabToken.balanceOf(owner);

        // Withdraw with 0 means withdraw all
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);

        assertEq(
            fabToken.balanceOf(owner),
            ownerBalanceBefore + accumulated,
            "Zero amount should withdraw all accumulated fees"
        );
    }

    function test_WithdrawPartialRejectedFees() public {
        // Accumulate multiple rejected fees
        _createAndRejectProposal("test/model1", "model1.gguf");
        _createAndRejectProposal("test/model2", "model2.gguf");

        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        uint256 partialAmount = PROPOSAL_FEE;

        uint256 ownerBalanceBefore = fabToken.balanceOf(owner);

        // Withdraw partial amount
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(partialAmount);

        // Verify partial withdrawal
        assertEq(
            fabToken.balanceOf(owner),
            ownerBalanceBefore + partialAmount,
            "Owner should receive partial withdrawal"
        );

        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            accumulated - partialAmount,
            "Remaining accumulated should be correct"
        );
    }

    function test_WithdrawRejectedFeesEmitsEvent() public {
        // Accumulate some rejected fees
        _createAndRejectProposal("test/model", "model.gguf");

        uint256 accumulated = modelRegistry.accumulatedRejectedFees();

        // Expect event emission
        vm.expectEmit(true, false, false, true);
        emit RejectedFeesWithdrawn(owner, accumulated);

        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);
    }

    function test_WithdrawRejectedFeesOnlyOwner() public {
        // Accumulate some rejected fees
        _createAndRejectProposal("test/model", "model.gguf");

        // Non-owner should be rejected
        vm.prank(nonOwner);
        vm.expectRevert();
        modelRegistry.withdrawRejectedFees(0);
    }

    function test_WithdrawRejectedFeesRevertsIfZero() public {
        // No accumulated fees
        assertEq(modelRegistry.accumulatedRejectedFees(), 0, "Should have no accumulated fees");

        // Withdrawal should revert
        vm.prank(owner);
        vm.expectRevert("No fees to withdraw");
        modelRegistry.withdrawRejectedFees(0);
    }

    function test_WithdrawRejectedFeesRevertsIfInsufficientBalance() public {
        // Accumulate some fees
        _createAndRejectProposal("test/model", "model.gguf");

        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        uint256 overAmount = accumulated + 1;

        // Withdrawal should revert due to insufficient balance
        vm.prank(owner);
        vm.expectRevert("Insufficient accumulated fees");
        modelRegistry.withdrawRejectedFees(overAmount);
    }

    // ============================================
    // Sub-phase 1.3 Tests: Integration
    // ============================================

    function test_RejectedFeeFlowEndToEnd() public {
        // Initial state
        assertEq(modelRegistry.accumulatedRejectedFees(), 0, "Initial accumulated should be 0");

        // 1. Create proposal
        uint256 proposerBalanceBefore = fabToken.balanceOf(proposer);
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        // Verify fee was taken
        assertEq(
            fabToken.balanceOf(proposer),
            proposerBalanceBefore - PROPOSAL_FEE,
            "Proposal fee should be taken from proposer"
        );

        // 2. Vote against
        vm.prank(voter1);
        modelRegistry.voteOnProposal(testModelId, 10000 * 10**18, false);

        // 3. Execute (rejected)
        (,,,,,,,uint256 endTime,) = modelRegistry.proposals(testModelId);
        vm.warp(endTime + 1);
        modelRegistry.executeProposal(testModelId);

        // 4. Verify fee accumulated
        assertEq(
            modelRegistry.accumulatedRejectedFees(),
            PROPOSAL_FEE,
            "Fee should be accumulated after rejection"
        );

        // 5. Owner withdraws
        uint256 ownerBalanceBefore = fabToken.balanceOf(owner);
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);

        // 6. Verify owner received fees
        assertEq(
            fabToken.balanceOf(owner),
            ownerBalanceBefore + PROPOSAL_FEE,
            "Owner should receive withdrawn fee"
        );
    }

    function test_MixedApprovedAndRejectedProposals() public {
        // Reject first proposal
        _createAndRejectProposal("test/model1", "model1.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE, "First rejection should accumulate");

        // Approve second proposal
        _createAndApproveProposal("test/model2", "model2.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE, "Approval should not affect accumulated");

        // Reject third proposal
        _createAndRejectProposal("test/model3", "model3.gguf");
        assertEq(modelRegistry.accumulatedRejectedFees(), PROPOSAL_FEE * 2, "Second rejection should add to accumulated");

        // Verify total accumulated is from rejections only
        uint256 expectedTotal = PROPOSAL_FEE * 2;
        assertEq(modelRegistry.accumulatedRejectedFees(), expectedTotal, "Total accumulated should be from 2 rejections");
    }

    function test_WithdrawFeesToTreasury() public {
        // Accumulate fees
        _createAndRejectProposal("test/model", "model.gguf");

        uint256 accumulated = modelRegistry.accumulatedRejectedFees();
        uint256 ownerBalanceBefore = fabToken.balanceOf(owner);

        // Owner withdraws (to themselves as treasury)
        vm.prank(owner);
        modelRegistry.withdrawRejectedFees(0);

        // Owner (as treasury) should have received the fees
        assertEq(
            fabToken.balanceOf(owner),
            ownerBalanceBefore + accumulated,
            "Owner/Treasury should receive withdrawn fees"
        );
    }
}
