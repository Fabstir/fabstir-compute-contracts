// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../../src/ModelRegistryUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../mocks/MockERC20.sol";

/**
 * @title VoteExtensionTest
 * @notice Tests for Phase 14: Vote Extension (Anti-Sniping)
 */
contract VoteExtensionTest is Test {
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
        fabToken.mint(proposer, 1000 * 10**18);
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
    // Phase 14.1 Tests: Constants and State Variables
    // ============================================

    function test_ExtensionThresholdConstant() public view {
        assertEq(
            modelRegistry.EXTENSION_THRESHOLD(),
            10000 * 10**18,
            "EXTENSION_THRESHOLD should be 10,000 FAB"
        );
    }

    function test_ExtensionWindowConstant() public view {
        assertEq(
            modelRegistry.EXTENSION_WINDOW(),
            4 hours,
            "EXTENSION_WINDOW should be 4 hours"
        );
    }

    function test_ExtensionDurationConstant() public view {
        assertEq(
            modelRegistry.EXTENSION_DURATION(),
            1 days,
            "EXTENSION_DURATION should be 1 day"
        );
    }

    function test_MaxExtensionsConstant() public view {
        assertEq(
            modelRegistry.MAX_EXTENSIONS(),
            3,
            "MAX_EXTENSIONS should be 3"
        );
    }

    function test_ProposalHasEndTimeField() public {
        // Create a proposal
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        // Get proposal and verify endTime field exists and is set correctly
        (
            ,  // modelId
            ,  // proposer
            ,  // votesFor
            ,  // votesAgainst
            uint256 proposalTime,
            ,  // executed
            ,  // modelData
            uint256 endTime,
            // extensionCount
        ) = modelRegistry.proposals(testModelId);

        assertEq(
            endTime,
            proposalTime + modelRegistry.PROPOSAL_DURATION(),
            "endTime should be proposalTime + PROPOSAL_DURATION"
        );
    }

    function test_ProposalHasExtensionCountField() public {
        // Create a proposal
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        // Get proposal and verify extensionCount field exists and is 0
        (
            ,  // modelId
            ,  // proposer
            ,  // votesFor
            ,  // votesAgainst
            ,  // proposalTime
            ,  // executed
            ,  // modelData
            ,  // endTime
            uint8 extensionCount
        ) = modelRegistry.proposals(testModelId);

        assertEq(extensionCount, 0, "extensionCount should be 0 for new proposal");
    }

    function test_NewProposalEndTimeInitialized() public {
        uint256 expectedEndTime = block.timestamp + modelRegistry.PROPOSAL_DURATION();

        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        (
            ,,,,,,,
            uint256 endTime,
        ) = modelRegistry.proposals(testModelId);

        assertEq(endTime, expectedEndTime, "endTime should be initialized on proposal creation");
    }

    function test_NewProposalExtensionCountIsZero() public {
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));

        (
            ,,,,,,,,
            uint8 extensionCount
        ) = modelRegistry.proposals(testModelId);

        assertEq(extensionCount, 0, "extensionCount should be 0 on proposal creation");
    }

    // ============================================
    // Phase 14.3 Tests: Late Vote Tracking
    // ============================================

    function test_LateVotesMappingAccessible() public view {
        // lateVotes should be 0 for any modelId initially
        assertEq(
            modelRegistry.lateVotes(testModelId),
            0,
            "lateVotes should be 0 initially"
        );
    }

    function test_LateVotesMappingReturnsZeroForNonExistentProposal() public view {
        bytes32 randomModelId = keccak256("random/model");
        assertEq(
            modelRegistry.lateVotes(randomModelId),
            0,
            "lateVotes should be 0 for non-existent proposal"
        );
    }

    // ============================================
    // Phase 14.4 Tests: Vote Extension Logic
    // ============================================

    function _createProposal() internal returns (bytes32) {
        vm.prank(proposer);
        modelRegistry.proposeModel("test/model", "model.gguf", bytes32(uint256(1)));
        return testModelId;
    }

    function test_VoteOutsideExtensionWindowDoesNotTriggerExtension() public {
        bytes32 modelId = _createProposal();

        // Get initial endTime
        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        // Vote early (outside extension window)
        // Extension window is last 4 hours, so voting at day 1 should not trigger
        vm.warp(block.timestamp + 1 days);

        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 15000 * 10**18, true);

        // endTime should NOT have changed
        (,,,,,,,uint256 newEndTime,) = modelRegistry.proposals(modelId);
        assertEq(newEndTime, initialEndTime, "endTime should not change for early votes");
    }

    function test_SmallVoteInExtensionWindowDoesNotTriggerExtension() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        // Warp to extension window (last 4 hours)
        vm.warp(initialEndTime - 2 hours);

        // Vote with small amount (below threshold of 10k FAB)
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 5000 * 10**18, true);

        // endTime should NOT have changed
        (,,,,,,,uint256 newEndTime,) = modelRegistry.proposals(modelId);
        assertEq(newEndTime, initialEndTime, "endTime should not change for small votes");

        // But lateVotes should be tracked
        assertEq(modelRegistry.lateVotes(modelId), 5000 * 10**18, "lateVotes should track small votes");
    }

    function test_LargeVoteInExtensionWindowTriggersExtension() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        // Warp to extension window
        vm.warp(initialEndTime - 2 hours);

        // Vote with large amount (>= threshold of 10k FAB)
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        // endTime SHOULD have changed
        (,,,,,,,uint256 newEndTime,) = modelRegistry.proposals(modelId);
        assertEq(
            newEndTime,
            initialEndTime + modelRegistry.EXTENSION_DURATION(),
            "endTime should increase by EXTENSION_DURATION"
        );
    }

    function test_ExtensionIncreasesEndTimeByExtensionDuration() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        vm.warp(initialEndTime - 2 hours);

        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        (,,,,,,,uint256 newEndTime,) = modelRegistry.proposals(modelId);
        assertEq(newEndTime - initialEndTime, 1 days, "Extension should add exactly 1 day");
    }

    function test_ExtensionIncrementsExtensionCount() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime, uint8 initialCount) = modelRegistry.proposals(modelId);
        assertEq(initialCount, 0, "Initial extensionCount should be 0");

        vm.warp(initialEndTime - 2 hours);

        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        (,,,,,,,,uint8 newCount) = modelRegistry.proposals(modelId);
        assertEq(newCount, 1, "extensionCount should be 1 after first extension");
    }

    function test_ExtensionResetsLateVotesToZero() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        vm.warp(initialEndTime - 2 hours);

        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        // lateVotes should be reset to 0 after extension
        assertEq(modelRegistry.lateVotes(modelId), 0, "lateVotes should reset after extension");
    }

    function test_CumulativeSmallVotesReachingThresholdTriggerExtension() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        vm.warp(initialEndTime - 2 hours);

        // First small vote (5k)
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 5000 * 10**18, true);

        // endTime should not change yet
        (,,,,,,,uint256 midEndTime,) = modelRegistry.proposals(modelId);
        assertEq(midEndTime, initialEndTime, "endTime should not change after first small vote");

        // Second small vote (5k) - cumulative reaches threshold
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 5000 * 10**18, true);

        // NOW endTime should have changed
        (,,,,,,,uint256 newEndTime,) = modelRegistry.proposals(modelId);
        assertEq(
            newEndTime,
            initialEndTime + 1 days,
            "endTime should extend after cumulative votes reach threshold"
        );
    }

    function test_CannotExtendBeyondMaxExtensions() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 endTime,) = modelRegistry.proposals(modelId);

        // Trigger MAX_EXTENSIONS (3) extensions
        for (uint8 i = 0; i < 3; i++) {
            vm.warp(endTime - 2 hours);
            vm.prank(whale);
            modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);
            (,,,,,,,endTime,) = modelRegistry.proposals(modelId);
        }

        // Verify we hit max extensions
        (,,,,,,,,uint8 count) = modelRegistry.proposals(modelId);
        assertEq(count, 3, "Should have 3 extensions");

        uint256 endTimeAfterMax = endTime;

        // Try to trigger another extension
        vm.warp(endTime - 2 hours);
        vm.prank(whale);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        // endTime should NOT have changed
        (,,,,,,,uint256 finalEndTime,) = modelRegistry.proposals(modelId);
        assertEq(finalEndTime, endTimeAfterMax, "endTime should not change beyond MAX_EXTENSIONS");
    }

    function test_VotingAfterOriginalEndTimeButBeforeExtendedEndTimeSucceeds() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 originalEndTime,) = modelRegistry.proposals(modelId);

        // Trigger an extension
        vm.warp(originalEndTime - 2 hours);
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        (,,,,,,,uint256 extendedEndTime,) = modelRegistry.proposals(modelId);

        // Warp past original end time but before extended end time
        vm.warp(originalEndTime + 12 hours);
        assertTrue(block.timestamp > originalEndTime, "Should be past original end time");
        assertTrue(block.timestamp < extendedEndTime, "Should be before extended end time");

        // This vote should succeed
        vm.prank(whale);
        modelRegistry.voteOnProposal(modelId, 1000 * 10**18, true);

        // Verify vote was counted
        (,,uint256 votesFor,,,,,,) = modelRegistry.proposals(modelId);
        assertEq(votesFor, 11000 * 10**18, "Vote should be counted");
    }

    function test_VotingExtendedEventEmitted() public {
        bytes32 modelId = _createProposal();

        (,,,,,,,uint256 initialEndTime,) = modelRegistry.proposals(modelId);

        vm.warp(initialEndTime - 2 hours);

        uint256 expectedNewEndTime = initialEndTime + 1 days;

        vm.expectEmit(true, false, false, true);
        emit ModelRegistryUpgradeable.VotingExtended(modelId, expectedNewEndTime, 1);

        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);
    }

    function test_VotingUsesEndTimeNotCalculatedTime() public {
        bytes32 modelId = _createProposal();

        (,,,,uint256 proposalTime,,,uint256 endTime,) = modelRegistry.proposals(modelId);

        // Trigger an extension
        vm.warp(endTime - 2 hours);
        vm.prank(voter1);
        modelRegistry.voteOnProposal(modelId, 10000 * 10**18, true);

        // Warp past proposalTime + PROPOSAL_DURATION (original calculated end)
        vm.warp(proposalTime + modelRegistry.PROPOSAL_DURATION() + 1 hours);

        // This should still work because we're using endTime (which was extended)
        vm.prank(whale);
        modelRegistry.voteOnProposal(modelId, 1000 * 10**18, true);

        (,,uint256 votesFor,,,,,,) = modelRegistry.proposals(modelId);
        assertEq(votesFor, 11000 * 10**18, "Vote should succeed using endTime");
    }
}
