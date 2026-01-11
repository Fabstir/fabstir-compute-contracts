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
}
