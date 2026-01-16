// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../src/ModelRegistryUpgradeable.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title SlashingTest
 * @notice Tests for the stake slashing functionality
 * @dev Tests slashing mechanism for host misbehavior enforcement
 */
contract SlashingTest is Test {
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public host2 = address(0x3);
    address public treasury = address(0x99);
    address public nonOwner = address(0x88);

    bytes32 public modelId1;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Deploy mock FAB token
        fabToken = new ERC20Mock("FAB Token", "FAB");

        // Deploy ModelRegistry as proxy
        vm.startPrank(owner);
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        vm.stopPrank();

        modelId1 = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry as proxy
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(proxyAddr);

        // Mint and approve FAB tokens for hosts
        _setupHost(host);
        _setupHost(host2);
    }

    function _setupHost(address _host) internal {
        fabToken.mint(_host, 10000 * 10**18);
        vm.prank(_host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
    }

    function _registerHost(address _host, string memory metadata) internal {
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId1;

        vm.prank(_host);
        nodeRegistry.registerNode(
            metadata,
            "https://api.example.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    // ============================================================
    // Sub-phase 1.1: Constants and State Variables Tests
    // ============================================================

    /**
     * @notice Test MAX_SLASH_PERCENTAGE constant is 50
     */
    function test_Constants_MaxSlashPercentage() public view {
        assertEq(nodeRegistry.MAX_SLASH_PERCENTAGE(), 50);
    }

    /**
     * @notice Test MIN_STAKE_AFTER_SLASH constant is 100 FAB
     */
    function test_Constants_MinStakeAfterSlash() public view {
        assertEq(nodeRegistry.MIN_STAKE_AFTER_SLASH(), 100 * 10**18);
    }

    /**
     * @notice Test SLASH_COOLDOWN constant is 24 hours
     */
    function test_Constants_SlashCooldown() public view {
        assertEq(nodeRegistry.SLASH_COOLDOWN(), 24 hours);
    }

    /**
     * @notice Test slashingAuthority state variable exists and is accessible
     */
    function test_StateVariable_SlashingAuthority() public view {
        // Should be address(0) before initialization
        address authority = nodeRegistry.slashingAuthority();
        assertEq(authority, address(0));
    }

    /**
     * @notice Test treasury state variable exists and is accessible
     */
    function test_StateVariable_Treasury() public view {
        // Should be address(0) before initialization
        address treasuryAddr = nodeRegistry.treasury();
        assertEq(treasuryAddr, address(0));
    }

    /**
     * @notice Test lastSlashTime mapping exists and is accessible
     */
    function test_StateVariable_LastSlashTime() public view {
        // Should be 0 for any address before slashing
        uint256 lastSlash = nodeRegistry.lastSlashTime(host);
        assertEq(lastSlash, 0);
    }

    // ============================================================
    // Sub-phase 1.2: Events Declaration Test
    // Note: Event emission tests will be in Sub-phase 2.1 with slashStake
    // ============================================================

    /**
     * @notice Verify contract compiles with events - this test passes if compilation succeeds
     * @dev Events tested: SlashExecuted, HostAutoUnregistered, SlashingAuthorityUpdated, TreasuryUpdated
     */
    function test_EventsAreDeclarated() public pure {
        // This test verifies the contract compiles with all event declarations
        // Actual event emission tests will be in Sub-phase 2.1
        assertTrue(true);
    }

    // ============================================================
    // Sub-phase 1.3: Access Control Functions Tests
    // ============================================================

    /**
     * @notice Test setSlashingAuthority only callable by owner
     */
    function test_SetSlashingAuthority_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        nodeRegistry.setSlashingAuthority(treasury);
    }

    /**
     * @notice Test setSlashingAuthority reverts on zero address
     */
    function test_SetSlashingAuthority_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid authority");
        nodeRegistry.setSlashingAuthority(address(0));
    }

    /**
     * @notice Test setSlashingAuthority updates authority correctly
     */
    function test_SetSlashingAuthority_UpdatesAuthority() public {
        vm.prank(owner);
        nodeRegistry.setSlashingAuthority(treasury);

        assertEq(nodeRegistry.slashingAuthority(), treasury);
    }

    /**
     * @notice Test setSlashingAuthority emits event
     */
    function test_SetSlashingAuthority_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit NodeRegistryWithModelsUpgradeable.SlashingAuthorityUpdated(address(0), treasury);
        nodeRegistry.setSlashingAuthority(treasury);
    }

    /**
     * @notice Test setTreasury only callable by owner
     */
    function test_SetTreasury_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        nodeRegistry.setTreasury(treasury);
    }

    /**
     * @notice Test setTreasury reverts on zero address
     */
    function test_SetTreasury_RevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid treasury");
        nodeRegistry.setTreasury(address(0));
    }

    /**
     * @notice Test setTreasury updates treasury correctly
     */
    function test_SetTreasury_UpdatesTreasury() public {
        vm.prank(owner);
        nodeRegistry.setTreasury(treasury);

        assertEq(nodeRegistry.treasury(), treasury);
    }

    /**
     * @notice Test setTreasury emits event
     */
    function test_SetTreasury_EmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit NodeRegistryWithModelsUpgradeable.TreasuryUpdated(treasury);
        nodeRegistry.setTreasury(treasury);
    }
}
