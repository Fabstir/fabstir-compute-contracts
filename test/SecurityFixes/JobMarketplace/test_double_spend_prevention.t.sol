// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Double-Spend Prevention Security Tests
 * @dev Tests for Sub-phase 3.1: Fix Deposit Tracking Logic
 *
 * CRITICAL VULNERABILITY: When creating inline sessions (with msg.value/deposit),
 * the funds were BOTH stored in the session AND credited to userDepositsNative/Token,
 * allowing users to immediately withdraw while the session still held their deposit.
 *
 * Attack flow (before fix):
 * 1. User calls createSessionJob{value: 1 ETH}()
 * 2. session.deposit = 1 ETH (correct)
 * 3. userDepositsNative[user] += 1 ETH (BUG!)
 * 4. User calls withdrawNative(1 ETH) - succeeds
 * 5. Host completes session and gets paid from contract balance
 * 6. Result: 1 ETH withdrawn twice
 */
contract DoubleSpendPreventionTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x3);
    address public attacker = address(0x666);

    bytes32 public modelId;

    uint256 constant feeBasisPoints = 1000; // 10%
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    // Dummy 65-byte signature for Sub-phase 6.1 (length validation only)
    bytes constant DUMMY_SIG = hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000101";

    function setUp() public {
        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        vm.startPrank(owner);

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                feeBasisPoints,
                disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Add mock USDC to accepted tokens
        marketplace.addAcceptedToken(address(usdcToken), 500000);

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Setup users with funds
        vm.deal(user, 100 ether);
        vm.deal(attacker, 100 ether);
        usdcToken.mint(user, 1000 * 10**6);
        usdcToken.mint(attacker, 1000 * 10**6);
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        vm.prank(attacker);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    function _registerHost(address hostAddr) internal {
        fabToken.mint(hostAddr, 10000 * 10**18);
        vm.prank(hostAddr);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.prank(hostAddr);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host.example.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );
    }

    // ============================================================
    // ETH Double-Spend Prevention Tests
    // ============================================================

    function test_CannotWithdrawAfterInlineSessionCreation_ETH() public {
        uint256 depositAmount = 1 ether;

        // User creates session with ETH
        vm.prank(user);
        marketplace.createSessionJob{value: depositAmount}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // User's pre-deposit balance should be ZERO (not credited)
        assertEq(marketplace.userDepositsNative(user), 0, "Pre-deposit balance should be zero");

        // Attempt to withdraw should fail
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawNative(depositAmount);
    }

    function test_CannotWithdrawAfterInlineSessionCreation_ETH_ForModel() public {
        uint256 depositAmount = 1 ether;

        // User creates model-specific session with ETH
        vm.prank(user);
        marketplace.createSessionJobForModel{value: depositAmount}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // User's pre-deposit balance should be ZERO
        assertEq(marketplace.userDepositsNative(user), 0, "Pre-deposit balance should be zero");

        // Attempt to withdraw should fail
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawNative(depositAmount);
    }

    // ============================================================
    // USDC Double-Spend Prevention Tests
    // ============================================================

    function test_CannotWithdrawAfterInlineSessionCreation_USDC() public {
        uint256 depositAmount = 10 * 10**6; // 10 USDC

        // User creates session with USDC
        vm.prank(user);
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            depositAmount,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        // User's pre-deposit balance should be ZERO
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), 0, "Pre-deposit balance should be zero");

        // Attempt to withdraw should fail
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawToken(address(usdcToken), depositAmount);
    }

    function test_CannotWithdrawAfterInlineSessionCreation_USDC_ForModel() public {
        uint256 depositAmount = 10 * 10**6; // 10 USDC

        // User creates model-specific session with USDC
        vm.prank(user);
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            depositAmount,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        // User's pre-deposit balance should be ZERO
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), 0, "Pre-deposit balance should be zero");

        // Attempt to withdraw should fail
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawToken(address(usdcToken), depositAmount);
    }

    // ============================================================
    // Pre-Deposit Flow Tests (These should still work correctly)
    // ============================================================

    function test_PreDepositThenSessionDeductsCorrectly_ETH() public {
        uint256 preDepositAmount = 2 ether;
        uint256 sessionAmount = 1 ether;

        // User pre-deposits ETH
        vm.prank(user);
        marketplace.depositNative{value: preDepositAmount}();

        // Verify pre-deposit balance
        assertEq(marketplace.userDepositsNative(user), preDepositAmount, "Pre-deposit should be credited");

        // Create session from pre-deposit
        vm.prank(user);
        marketplace.createSessionFromDeposit(
            host,
            address(0), // native
            sessionAmount,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Pre-deposit balance should be reduced
        assertEq(marketplace.userDepositsNative(user), preDepositAmount - sessionAmount, "Balance should be deducted");

        // Can withdraw the unlocked remainder
        vm.prank(user);
        marketplace.withdrawNative(preDepositAmount - sessionAmount);

        // Balance should now be zero
        assertEq(marketplace.userDepositsNative(user), 0, "Balance should be zero after withdrawal");
    }

    function test_PreDepositThenSessionDeductsCorrectly_USDC() public {
        uint256 preDepositAmount = 20 * 10**6; // 20 USDC
        uint256 sessionAmount = 10 * 10**6; // 10 USDC

        // User pre-deposits USDC
        vm.prank(user);
        marketplace.depositToken(address(usdcToken), preDepositAmount);

        // Verify pre-deposit balance
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), preDepositAmount);

        // Create session from pre-deposit
        vm.prank(user);
        marketplace.createSessionFromDeposit(
            host,
            address(usdcToken),
            sessionAmount,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        // Pre-deposit balance should be reduced
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), preDepositAmount - sessionAmount);

        // Can withdraw the unlocked remainder
        vm.prank(user);
        marketplace.withdrawToken(address(usdcToken), preDepositAmount - sessionAmount);

        // Balance should now be zero
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), 0);
    }

    // ============================================================
    // Attack Scenario Tests
    // ============================================================

    function test_DoubleSpendAttackPrevented_ETH() public {
        uint256 attackAmount = 5 ether;
        uint256 attackerBalanceBefore = attacker.balance;
        uint256 contractBalanceBefore = address(marketplace).balance;

        // Attacker creates session
        vm.prank(attacker);
        marketplace.createSessionJob{value: attackAmount}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Contract should have received the ETH
        assertEq(address(marketplace).balance, contractBalanceBefore + attackAmount);

        // Attacker's balance should be reduced
        assertEq(attacker.balance, attackerBalanceBefore - attackAmount);

        // Attacker's pre-deposit balance should be ZERO (attack prevented!)
        assertEq(marketplace.userDepositsNative(attacker), 0);

        // Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawNative(attackAmount);

        // Contract balance unchanged (attack failed)
        assertEq(address(marketplace).balance, contractBalanceBefore + attackAmount);
    }

    function test_DoubleSpendAttackPrevented_USDC() public {
        uint256 attackAmount = 50 * 10**6; // 50 USDC
        uint256 attackerBalanceBefore = usdcToken.balanceOf(attacker);

        // Attacker creates session
        vm.prank(attacker);
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            attackAmount,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        // Attacker's USDC balance should be reduced
        assertEq(usdcToken.balanceOf(attacker), attackerBalanceBefore - attackAmount);

        // Attacker's pre-deposit balance should be ZERO
        assertEq(marketplace.userDepositsToken(attacker, address(usdcToken)), 0);

        // Attacker cannot withdraw
        vm.prank(attacker);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawToken(address(usdcToken), attackAmount);
    }

    // ============================================================
    // Multiple Sessions Test
    // ============================================================

    function test_MultipleInlineSessionsDoNotAccumulateBalance() public {
        // Create multiple sessions
        vm.startPrank(user);

        marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);
        marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);
        marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);

        vm.stopPrank();

        // Pre-deposit balance should still be ZERO (not 3 ETH!)
        assertEq(marketplace.userDepositsNative(user), 0, "Balance should not accumulate from inline sessions");
    }

    // ============================================================
    // Session Completion Tests
    // ============================================================

    function test_SessionCompletionDistributesFundsCorrectly() public {
        uint256 depositAmount = 1 ether;

        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: depositAmount}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Host submits proof
        vm.warp(block.timestamp + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            1000,
            bytes32(uint256(0x1234)),
            DUMMY_SIG,
            "QmProof"
        );

        // Complete session
        vm.warp(block.timestamp + disputeWindow + 1);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Host should have earnings
        uint256 hostBalance = hostEarnings.getBalance(host, address(0));
        assertTrue(hostBalance > 0, "Host should have earnings");

        // User's pre-deposit balance should still be ZERO (refund goes elsewhere or is spent)
        assertEq(marketplace.userDepositsNative(user), 0, "Pre-deposit should remain zero");
    }
}
