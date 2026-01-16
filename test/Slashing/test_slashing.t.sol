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
    uint256 constant COOLDOWN = 24 hours + 1;

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

    // ============================================================
    // Sub-phase 2.1: slashStake() Function Tests
    // ============================================================

    /// @notice Helper to set up slashing (authority + treasury)
    function _setupSlashing() internal {
        vm.startPrank(owner);
        nodeRegistry.setSlashingAuthority(owner);
        nodeRegistry.setTreasury(treasury);
        vm.stopPrank();
    }

    /**
     * @notice Test slashStake reduces host stake correctly
     */
    function test_SlashStake_ReducesHostStake() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        uint256 slashAmount = 100 * 10**18;

        vm.prank(owner);
        nodeRegistry.slashStake(host, slashAmount, "evidenceCID123", "overclaimed tokens");

        (,uint256 stakedAmount,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedAmount, MIN_STAKE - slashAmount);
    }

    /**
     * @notice Test slashStake transfers slashed amount to treasury
     */
    function test_SlashStake_TransfersToTreasury() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        uint256 slashAmount = 100 * 10**18;
        uint256 treasuryBalanceBefore = fabToken.balanceOf(treasury);

        vm.prank(owner);
        nodeRegistry.slashStake(host, slashAmount, "evidenceCID123", "overclaimed tokens");

        assertEq(fabToken.balanceOf(treasury), treasuryBalanceBefore + slashAmount);
    }

    /**
     * @notice Test slashStake emits SlashExecuted event
     */
    function test_SlashStake_EmitsSlashExecutedEvent() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        uint256 slashAmount = 100 * 10**18;

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit NodeRegistryWithModelsUpgradeable.SlashExecuted(
            host,
            slashAmount,
            MIN_STAKE - slashAmount,
            "evidenceCID123",
            "overclaimed tokens",
            owner,
            block.timestamp
        );
        nodeRegistry.slashStake(host, slashAmount, "evidenceCID123", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake updates lastSlashTime
     */
    function test_SlashStake_UpdatesLastSlashTime() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        assertEq(nodeRegistry.lastSlashTime(host), 0);

        vm.prank(owner);
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "overclaimed tokens");

        assertEq(nodeRegistry.lastSlashTime(host), block.timestamp);
    }

    /**
     * @notice Test slashStake reverts if host not registered
     */
    function test_SlashStake_RevertsIfHostNotRegistered() public {
        _setupSlashing();
        // host not registered

        vm.prank(owner);
        vm.expectRevert("Host not registered");
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake reverts if host not active
     */
    function test_SlashStake_RevertsIfHostNotActive() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // Unregister the host to make it inactive
        vm.prank(host);
        nodeRegistry.unregisterNode();

        vm.prank(owner);
        vm.expectRevert("Host not registered");
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake reverts if evidence CID is empty
     */
    function test_SlashStake_RevertsIfNoEvidence() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        vm.prank(owner);
        vm.expectRevert("Evidence CID required");
        nodeRegistry.slashStake(host, 100 * 10**18, "", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake reverts if reason is empty
     */
    function test_SlashStake_RevertsIfNoReason() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        vm.prank(owner);
        vm.expectRevert("Reason required");
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "");
    }

    /**
     * @notice Test slashStake reverts if amount exceeds stake
     */
    function test_SlashStake_RevertsIfAmountExceedsStake() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        vm.prank(owner);
        vm.expectRevert("Amount exceeds stake");
        nodeRegistry.slashStake(host, MIN_STAKE + 1, "evidenceCID123", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake reverts if amount exceeds max percentage (50%)
     */
    function test_SlashStake_RevertsIfExceedsMaxPercentage() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // 51% of 1000 FAB = 510 FAB
        uint256 slashAmount = (MIN_STAKE * 51) / 100;

        vm.prank(owner);
        vm.expectRevert("Exceeds max slash percentage");
        nodeRegistry.slashStake(host, slashAmount, "evidenceCID123", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake reverts if cooldown is active
     */
    function test_SlashStake_RevertsIfCooldownActive() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // First slash
        vm.prank(owner);
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "first offense");

        // Try second slash immediately - should fail
        vm.prank(owner);
        vm.expectRevert("Slash cooldown active");
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID456", "second offense");
    }

    /**
     * @notice Test slashStake works after cooldown expires
     */
    function test_SlashStake_WorksAfterCooldownExpires() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // First slash
        vm.prank(owner);
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "first offense");

        // Warp time past cooldown (24 hours)
        vm.warp(block.timestamp + 24 hours + 1);

        // Second slash should work
        vm.prank(owner);
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID456", "second offense");

        (,uint256 stakedAmount,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedAmount, MIN_STAKE - 200 * 10**18);
    }

    /**
     * @notice Test slashStake reverts if caller is not authority
     */
    function test_SlashStake_RevertsIfNotAuthority() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        vm.prank(nonOwner);
        vm.expectRevert("Not slashing authority");
        nodeRegistry.slashStake(host, 100 * 10**18, "evidenceCID123", "overclaimed tokens");
    }

    /**
     * @notice Test slashStake allows exactly 50% slash
     */
    function test_SlashStake_AllowsExactly50Percent() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // Exactly 50% of 1000 FAB = 500 FAB
        uint256 slashAmount = MIN_STAKE / 2;

        vm.prank(owner);
        nodeRegistry.slashStake(host, slashAmount, "evidenceCID123", "overclaimed tokens");

        (,uint256 stakedAmount,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedAmount, MIN_STAKE - slashAmount);
    }

    // ============================================================
    // Sub-phase 2.2: Auto-Unregister Logic Tests
    // ============================================================

    /**
     * @notice Test auto-unregister triggers when stake falls below 100 FAB
     */
    function test_SlashStake_AutoUnregistersIfBelowMinimum() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // Use explicit cumulative timestamps to avoid block.timestamp evaluation issues
        uint256 time = block.timestamp;

        // Slash 50% (500 FAB) twice with cooldown in between
        // After 1st slash: 1000 - 500 = 500 FAB
        vm.prank(owner);
        nodeRegistry.slashStake(host, 500 * 10**18, "evidenceCID1", "first offense");

        // Warp past cooldown
        time += COOLDOWN;
        vm.warp(time);

        // After 2nd slash (50% of 500 = 250): 500 - 250 = 250 FAB (still above 100)
        vm.prank(owner);
        nodeRegistry.slashStake(host, 250 * 10**18, "evidenceCID2", "second offense");

        // Warp past cooldown again
        time += COOLDOWN;
        vm.warp(time);

        // Slash 50% of 250 = 125, leaving 125 FAB (still above 100)
        vm.prank(owner);
        nodeRegistry.slashStake(host, 125 * 10**18, "evidenceCID3", "third offense");

        // Host should still be active with 125 FAB
        assertTrue(nodeRegistry.isActiveNode(host));

        // Warp past cooldown
        time += COOLDOWN;
        vm.warp(time);

        // Now slash 30 FAB (within 50% of 125 = 62.5), leaving 95 FAB (below 100)
        vm.prank(owner);
        nodeRegistry.slashStake(host, 30 * 10**18, "evidenceCID4", "fourth offense - triggers auto-unregister");

        // Host should be unregistered (inactive)
        assertFalse(nodeRegistry.isActiveNode(host));
    }

    /**
     * @notice Test auto-unregister returns remaining stake to host
     */
    function test_SlashStake_ReturnsRemainingStakeOnAutoUnregister() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // Get host balance before
        uint256 hostBalanceBefore = fabToken.balanceOf(host);
        uint256 time = block.timestamp;

        // Slash down close to minimum
        vm.prank(owner);
        nodeRegistry.slashStake(host, 500 * 10**18, "evidenceCID1", "first offense");

        time += COOLDOWN;
        vm.warp(time);

        vm.prank(owner);
        nodeRegistry.slashStake(host, 250 * 10**18, "evidenceCID2", "second offense");

        time += COOLDOWN;
        vm.warp(time);

        vm.prank(owner);
        nodeRegistry.slashStake(host, 125 * 10**18, "evidenceCID3", "third offense");

        time += COOLDOWN;
        vm.warp(time);

        // Current stake: 125 FAB. Slash 30 to leave 95 (below 100)
        vm.prank(owner);
        nodeRegistry.slashStake(host, 30 * 10**18, "evidenceCID4", "triggers auto-unregister");

        // Host should receive remaining 95 FAB
        uint256 hostBalanceAfter = fabToken.balanceOf(host);
        assertEq(hostBalanceAfter, hostBalanceBefore + 95 * 10**18);
    }

    /**
     * @notice Test auto-unregister removes host from active nodes list
     */
    function test_SlashStake_RemovesFromActiveNodesOnAutoUnregister() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");
        _registerHost(host2, "host2-metadata");

        // Verify both in active list
        address[] memory activeNodes = nodeRegistry.getAllActiveNodes();
        assertEq(activeNodes.length, 2);

        uint256 time = block.timestamp;

        // Slash host down to trigger auto-unregister
        vm.prank(owner);
        nodeRegistry.slashStake(host, 500 * 10**18, "eCID1", "1");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 250 * 10**18, "eCID2", "2");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 125 * 10**18, "eCID3", "3");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 30 * 10**18, "eCID4", "4");

        // Only host2 should remain
        activeNodes = nodeRegistry.getAllActiveNodes();
        assertEq(activeNodes.length, 1);
        assertEq(activeNodes[0], host2);
    }

    /**
     * @notice Test auto-unregister emits HostAutoUnregistered event
     */
    function test_SlashStake_EmitsHostAutoUnregisteredEvent() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        uint256 time = block.timestamp;

        // Slash down to trigger
        vm.prank(owner);
        nodeRegistry.slashStake(host, 500 * 10**18, "eCID1", "1");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 250 * 10**18, "eCID2", "2");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 125 * 10**18, "eCID3", "3");
        time += COOLDOWN;
        vm.warp(time);

        // Expect HostAutoUnregistered event
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit NodeRegistryWithModelsUpgradeable.HostAutoUnregistered(
            host,
            30 * 10**18,  // slashed amount
            95 * 10**18,  // remaining returned
            "4"           // reason
        );
        nodeRegistry.slashStake(host, 30 * 10**18, "eCID4", "4");
    }

    /**
     * @notice Test exact boundary - 100 FAB remaining does NOT trigger auto-unregister
     */
    function test_SlashStake_ExactBoundary_100FAB_NoAutoUnregister() public {
        _setupSlashing();

        // Host stakes extra to have 1100 FAB total
        _registerHost(host, "host-metadata");
        fabToken.mint(host, 100 * 10**18);
        vm.prank(host);
        nodeRegistry.stake(100 * 10**18);

        // Now host has 1100 FAB
        (,uint256 stakedBefore,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedBefore, 1100 * 10**18);

        uint256 time = block.timestamp;

        // Slash 50% = 550, leaving 550
        vm.prank(owner);
        nodeRegistry.slashStake(host, 550 * 10**18, "eCID1", "1");
        time += COOLDOWN;
        vm.warp(time);

        // Slash 50% of 550 = 275, leaving 275
        vm.prank(owner);
        nodeRegistry.slashStake(host, 275 * 10**18, "eCID2", "2");
        time += COOLDOWN;
        vm.warp(time);

        // Slash 50% of 275 = 137.5 (137), leaving 138
        vm.prank(owner);
        nodeRegistry.slashStake(host, 137 * 10**18, "eCID3", "3");
        time += COOLDOWN;
        vm.warp(time);

        // Slash 38 to leave exactly 100
        vm.prank(owner);
        nodeRegistry.slashStake(host, 38 * 10**18, "eCID4", "4");

        // Host should still be active with exactly 100 FAB
        assertTrue(nodeRegistry.isActiveNode(host));
        (,uint256 stakedAfter,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedAfter, 100 * 10**18);
    }

    /**
     * @notice Test boundary - 99 FAB remaining DOES trigger auto-unregister
     */
    function test_SlashStake_Boundary_Below100FAB_AutoUnregisters() public {
        _setupSlashing();

        // Host stakes extra to have 1099 FAB total
        _registerHost(host, "host-metadata");
        fabToken.mint(host, 99 * 10**18);
        vm.prank(host);
        nodeRegistry.stake(99 * 10**18);

        // Now host has 1099 FAB
        (,uint256 stakedBefore,,,,,,) = nodeRegistry.getNodeFullInfo(host);
        assertEq(stakedBefore, 1099 * 10**18);

        uint256 time = block.timestamp;

        // Slash down in multiple steps
        vm.prank(owner);
        nodeRegistry.slashStake(host, 549 * 10**18, "eCID1", "1"); // 550 left
        time += COOLDOWN;
        vm.warp(time);

        vm.prank(owner);
        nodeRegistry.slashStake(host, 275 * 10**18, "eCID2", "2"); // 275 left
        time += COOLDOWN;
        vm.warp(time);

        vm.prank(owner);
        nodeRegistry.slashStake(host, 137 * 10**18, "eCID3", "3"); // 138 left
        time += COOLDOWN;
        vm.warp(time);

        // Slash 39 to leave 99 (below 100)
        vm.prank(owner);
        nodeRegistry.slashStake(host, 39 * 10**18, "eCID4", "4");

        // Host should be unregistered
        assertFalse(nodeRegistry.isActiveNode(host));
    }

    /**
     * @notice Test auto-unregister removes from model mappings
     */
    function test_SlashStake_RemovesFromModelMappingsOnAutoUnregister() public {
        _setupSlashing();
        _registerHost(host, "host-metadata");

        // Verify host is in model mappings
        address[] memory nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 1);
        assertEq(nodesForModel[0], host);

        uint256 time = block.timestamp;

        // Slash down to trigger auto-unregister
        vm.prank(owner);
        nodeRegistry.slashStake(host, 500 * 10**18, "eCID1", "1");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 250 * 10**18, "eCID2", "2");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 125 * 10**18, "eCID3", "3");
        time += COOLDOWN;
        vm.warp(time);
        vm.prank(owner);
        nodeRegistry.slashStake(host, 30 * 10**18, "eCID4", "4");

        // Model mappings should be empty
        nodesForModel = nodeRegistry.getNodesForModel(modelId1);
        assertEq(nodesForModel.length, 0);
    }

    // ============================================================
    // Phase 3: Upgrade Initialization Tests
    // ============================================================

    /**
     * @notice Test initializeSlashing sets slashingAuthority to owner
     */
    function test_InitializeSlashing_SetsSlashingAuthorityToOwner() public {
        // Authority should be zero before initialization
        assertEq(nodeRegistry.slashingAuthority(), address(0));

        // Initialize slashing
        vm.prank(owner);
        nodeRegistry.initializeSlashing(treasury);

        // Authority should now be the owner
        assertEq(nodeRegistry.slashingAuthority(), owner);
    }

    /**
     * @notice Test initializeSlashing sets treasury correctly
     */
    function test_InitializeSlashing_SetsTreasury() public {
        // Treasury should be zero before initialization
        assertEq(nodeRegistry.treasury(), address(0));

        // Initialize slashing
        vm.prank(owner);
        nodeRegistry.initializeSlashing(treasury);

        // Treasury should be set
        assertEq(nodeRegistry.treasury(), treasury);
    }

    /**
     * @notice Test initializeSlashing reverts if already initialized
     */
    function test_InitializeSlashing_RevertsIfAlreadyInitialized() public {
        // Initialize first time
        vm.prank(owner);
        nodeRegistry.initializeSlashing(treasury);

        // Try to initialize again - should fail
        vm.prank(owner);
        vm.expectRevert("Already initialized");
        nodeRegistry.initializeSlashing(treasury);
    }

    /**
     * @notice Test initializeSlashing only callable by owner
     */
    function test_InitializeSlashing_OnlyOwner() public {
        // Non-owner should not be able to initialize
        vm.prank(nonOwner);
        vm.expectRevert();
        nodeRegistry.initializeSlashing(treasury);
    }

    /**
     * @notice Test initializeSlashing reverts if treasury is zero address
     */
    function test_InitializeSlashing_RevertsOnZeroTreasury() public {
        vm.prank(owner);
        vm.expectRevert("Invalid treasury");
        nodeRegistry.initializeSlashing(address(0));
    }
}
