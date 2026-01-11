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
}
