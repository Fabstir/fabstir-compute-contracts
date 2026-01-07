// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title Fund Safety Integration Tests
 * @dev Tests for Sub-phase 3.3: Integration Tests for Fund Safety
 *
 * Critical invariant: Total funds in system = user withdrawable + locked in sessions + host earnings + treasury
 * No funds should be lost, duplicated, or become inaccessible.
 */
contract FundSafetyTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public host2 = address(0x22);
    address public user = address(0x3);
    address public user2 = address(0x33);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant PRICE_PRECISION = 1000;

    // Dummy 65-byte signature for Sub-phase 6.1 (length validation only)
    bytes constant DUMMY_SIG = hex"0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000101";

    function setUp() public {
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
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        marketplace.addAcceptedToken(address(usdcToken), 500000);

        vm.stopPrank();

        // Register hosts
        _registerHost(host);
        _registerHost(host2);

        // Setup users with funds
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);
        usdcToken.mint(user, 10000 * 10**6);
        usdcToken.mint(user2, 10000 * 10**6);
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        vm.prank(user2);
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
    // Full Session Lifecycle - No Funds Lost or Duplicated
    // ============================================================

    function test_FullSessionLifecycle_NoFundsLostOrDuplicated_ETH() public {
        uint256 deposit = 1 ether;
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Track initial balances
        uint256 userInitialBalance = user.balance;
        uint256 contractInitialBalance = address(marketplace).balance;

        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Verify: user paid, contract received
        assertEq(user.balance, userInitialBalance - deposit, "User should have paid deposit");
        assertEq(address(marketplace).balance, contractInitialBalance + deposit, "Contract should hold deposit");

        // Host submits proof (claims some tokens)
        uint256 tokensUsed = 500;
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensUsed, bytes32(uint256(0x1234)), DUMMY_SIG, "QmProof");

        // Complete session
        vm.warp(startTime + DISPUTE_WINDOW + 2);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Calculate expected distributions
        uint256 hostPaymentGross = (tokensUsed * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (hostPaymentGross * FEE_BASIS_POINTS) / 10000;
        uint256 hostPaymentNet = hostPaymentGross - treasuryFee;
        uint256 userRefund = deposit - hostPaymentGross;

        // Verify host earnings in HostEarnings contract
        uint256 hostEarningsBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostEarningsBalance, hostPaymentNet, "Host should receive net payment");

        // Verify treasury accumulated
        assertEq(marketplace.accumulatedTreasuryNative(), treasuryFee, "Treasury should receive fee");

        // Verify user's locked balance is 0
        assertEq(marketplace.getLockedBalanceNative(user), 0, "No locked balance after completion");

        // Verify total funds in system = deposit
        uint256 totalInSystem = hostEarningsBalance + marketplace.accumulatedTreasuryNative() + userRefund;
        assertEq(totalInSystem, deposit, "Total funds should equal original deposit");
    }

    function test_FullSessionLifecycle_NoFundsLostOrDuplicated_USDC() public {
        uint256 deposit = 100 * 10**6; // 100 USDC
        uint256 startTime = 1000;
        vm.warp(startTime);

        uint256 userInitialBalance = usdcToken.balanceOf(user);

        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            deposit,
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        assertEq(usdcToken.balanceOf(user), userInitialBalance - deposit, "User should have paid deposit");

        // Host submits proof
        uint256 tokensUsed = 1000;
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensUsed, bytes32(uint256(0x1234)), DUMMY_SIG, "QmProof");

        // Complete session
        vm.warp(startTime + DISPUTE_WINDOW + 2);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Calculate expected
        uint256 hostPaymentGross = (tokensUsed * MIN_PRICE_STABLE) / PRICE_PRECISION;
        uint256 treasuryFee = (hostPaymentGross * FEE_BASIS_POINTS) / 10000;
        uint256 hostPaymentNet = hostPaymentGross - treasuryFee;

        // Verify host earnings
        uint256 hostEarningsBalance = hostEarnings.getBalance(host, address(usdcToken));
        assertEq(hostEarningsBalance, hostPaymentNet, "Host should receive net payment in USDC");

        // Verify locked balance is 0
        assertEq(marketplace.getLockedBalanceToken(user, address(usdcToken)), 0, "No locked USDC after completion");
    }

    // ============================================================
    // Multiple Concurrent Sessions - Balances Correct
    // ============================================================

    function test_MultipleConcurrentSessions_BalancesCorrect() public {
        uint256 startTime = 1000;
        vm.warp(startTime);

        // User creates 3 sessions with different amounts
        vm.startPrank(user);
        uint256 s1 = marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);
        uint256 s2 = marketplace.createSessionJob{value: 2 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);
        uint256 s3 = marketplace.createSessionJob{value: 3 ether}(host2, MIN_PRICE_NATIVE, 1 days, 1000);
        vm.stopPrank();

        // Verify locked balance = 6 ETH
        assertEq(marketplace.getLockedBalanceNative(user), 6 ether, "Locked should be 6 ETH");

        // Host submits proofs to session 1
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(s1, 100, bytes32(uint256(0x1)), DUMMY_SIG, "QmProof1");

        // Complete session 1
        vm.warp(startTime + DISPUTE_WINDOW + 2);
        vm.prank(user);
        marketplace.completeSessionJob(s1, "QmConvo1");

        // Verify locked balance decreased
        assertEq(marketplace.getLockedBalanceNative(user), 5 ether, "Locked should be 5 ETH after s1 complete");

        // Complete remaining sessions (MIN_PROVEN_TOKENS = 100)
        vm.warp(startTime + DISPUTE_WINDOW + 3);
        vm.prank(host);
        marketplace.submitProofOfWork(s2, 150, bytes32(uint256(0x2)), DUMMY_SIG, "QmProof2");
        vm.warp(startTime + 2*DISPUTE_WINDOW + 4);
        vm.prank(user);
        marketplace.completeSessionJob(s2, "QmConvo2");

        vm.warp(startTime + 2*DISPUTE_WINDOW + 5);
        vm.prank(host2);
        marketplace.submitProofOfWork(s3, 200, bytes32(uint256(0x3)), DUMMY_SIG, "QmProof3");
        vm.warp(startTime + 3*DISPUTE_WINDOW + 6);
        vm.prank(user);
        marketplace.completeSessionJob(s3, "QmConvo3");

        // All sessions complete - locked should be 0
        assertEq(marketplace.getLockedBalanceNative(user), 0, "Locked should be 0 after all complete");

        // Verify hosts have earnings
        assertTrue(hostEarnings.getBalance(host, address(0)) > 0, "Host should have earnings");
        assertTrue(hostEarnings.getBalance(host2, address(0)) > 0, "Host2 should have earnings");
    }

    function test_MultipleUsers_ConcurrentSessions_IndependentBalances() public {
        uint256 startTime = 1000;
        vm.warp(startTime);

        // User1 creates session
        vm.prank(user);
        marketplace.createSessionJob{value: 2 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);

        // User2 creates session
        vm.prank(user2);
        marketplace.createSessionJob{value: 3 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);

        // Verify independent locked balances
        assertEq(marketplace.getLockedBalanceNative(user), 2 ether, "User1 locked should be 2 ETH");
        assertEq(marketplace.getLockedBalanceNative(user2), 3 ether, "User2 locked should be 3 ETH");

        // Verify total balance calculations are independent
        assertEq(marketplace.getTotalBalanceNative(user), 2 ether, "User1 total should be 2 ETH");
        assertEq(marketplace.getTotalBalanceNative(user2), 3 ether, "User2 total should be 3 ETH");
    }

    // ============================================================
    // Session Timeout - Correct Fund Distribution
    // ============================================================

    function test_SessionTimeout_CorrectDistribution() public {
        uint256 deposit = 1 ether;
        uint256 maxDuration = 1 hours;
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create session with 1 hour max duration
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host,
            MIN_PRICE_NATIVE,
            maxDuration,
            1000
        );

        // Host submits some proofs
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 200, bytes32(uint256(0x1234)), DUMMY_SIG, "QmProof");

        // Session times out
        vm.warp(startTime + maxDuration + 1);

        // Anyone can trigger session timeout
        vm.prank(address(0x999)); // Random address
        marketplace.triggerSessionTimeout(sessionId);

        // Calculate expected distributions
        uint256 hostPaymentGross = (200 * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (hostPaymentGross * FEE_BASIS_POINTS) / 10000;
        uint256 hostPaymentNet = hostPaymentGross - treasuryFee;
        uint256 userRefund = deposit - hostPaymentGross;

        // Verify host earnings
        uint256 hostEarningsBalance = hostEarnings.getBalance(host, address(0));
        assertEq(hostEarningsBalance, hostPaymentNet, "Host should receive earned amount");

        // Verify locked is 0
        assertEq(marketplace.getLockedBalanceNative(user), 0, "Locked should be 0 after timeout");

        // Verify funds accounting
        uint256 totalDistributed = hostEarningsBalance + marketplace.accumulatedTreasuryNative() + userRefund;
        assertEq(totalDistributed, deposit, "Total distributed should equal deposit");
    }

    // ============================================================
    // Session Early Completion - Host Gets Paid For Work Done
    // ============================================================

    function test_SessionEarlyCompletion_NoWork_FullRefund() public {
        uint256 deposit = 1 ether;
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Host never submits any proofs
        // User completes session immediately (no work done = full refund)
        vm.warp(startTime + DISPUTE_WINDOW + 1);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify full refund goes to user (no host earnings, no treasury fee)
        assertEq(marketplace.getLockedBalanceNative(user), 0, "Locked should be 0 after completion");
        assertEq(hostEarnings.getBalance(host, address(0)), 0, "Host should have no earnings when no work done");
        assertEq(marketplace.accumulatedTreasuryNative(), 0, "Treasury should be 0 when no work done");
    }

    function test_SessionEarlyCompletion_PartialWork_HostPaid() public {
        uint256 deposit = 1 ether;
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Host submits some proofs
        vm.warp(startTime + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 300, bytes32(uint256(0x1234)), DUMMY_SIG, "QmProof");

        // User completes session after some work done
        vm.warp(startTime + DISPUTE_WINDOW + 2);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify host got paid for work done
        uint256 hostPaymentGross = (300 * MIN_PRICE_NATIVE) / PRICE_PRECISION;
        uint256 treasuryFee = (hostPaymentGross * FEE_BASIS_POINTS) / 10000;
        uint256 hostPaymentNet = hostPaymentGross - treasuryFee;

        assertEq(hostEarnings.getBalance(host, address(0)), hostPaymentNet, "Host should receive payment for work done");
        assertEq(marketplace.getLockedBalanceNative(user), 0, "Locked should be 0 after completion");
    }

    // ============================================================
    // Pre-Deposit and Session Balance Consistency
    // ============================================================

    function test_PreDepositAndSession_BalanceConsistency() public {
        uint256 preDeposit = 5 ether;
        uint256 sessionAmount = 2 ether;

        // Pre-deposit
        vm.prank(user);
        marketplace.depositNative{value: preDeposit}();

        // Verify pre-deposit credited
        assertEq(marketplace.userDepositsNative(user), preDeposit, "Pre-deposit should be credited");
        assertEq(marketplace.getLockedBalanceNative(user), 0, "No locked balance yet");
        assertEq(marketplace.getTotalBalanceNative(user), preDeposit, "Total = pre-deposit");

        // Create session from pre-deposit
        vm.prank(user);
        marketplace.createSessionFromDeposit(host, address(0), sessionAmount, MIN_PRICE_NATIVE, 1 days, 1000);

        // Verify balance deducted from pre-deposit, added to locked
        assertEq(marketplace.userDepositsNative(user), preDeposit - sessionAmount, "Pre-deposit should be reduced");
        assertEq(marketplace.getLockedBalanceNative(user), sessionAmount, "Locked should equal session amount");
        assertEq(marketplace.getTotalBalanceNative(user), preDeposit, "Total should still be pre-deposit amount");

        // Withdraw remaining pre-deposit
        uint256 userBalanceBefore = user.balance;
        vm.prank(user);
        marketplace.withdrawNative(preDeposit - sessionAmount);

        assertEq(user.balance, userBalanceBefore + (preDeposit - sessionAmount), "User should receive withdrawn amount");
        assertEq(marketplace.userDepositsNative(user), 0, "Pre-deposit should be 0");
        assertEq(marketplace.getLockedBalanceNative(user), sessionAmount, "Locked should still be session amount");
    }

    // ============================================================
    // Fuzz Tests
    // ============================================================

    function testFuzz_DepositWithdraw_NoFundsLost(uint256 depositAmount) public {
        // Bound to reasonable values
        depositAmount = bound(depositAmount, 0.01 ether, 50 ether);

        uint256 userInitialBalance = user.balance;

        // Deposit
        vm.prank(user);
        marketplace.depositNative{value: depositAmount}();

        assertEq(marketplace.userDepositsNative(user), depositAmount, "Deposit should be credited");
        assertEq(user.balance, userInitialBalance - depositAmount, "User balance should decrease");

        // Withdraw
        vm.prank(user);
        marketplace.withdrawNative(depositAmount);

        assertEq(marketplace.userDepositsNative(user), 0, "Deposit should be 0 after withdrawal");
        assertEq(user.balance, userInitialBalance, "User should have original balance back");
    }

    function testFuzz_SessionDeposit_NoDoubleSpend(uint256 sessionDeposit) public {
        // Bound to reasonable values
        sessionDeposit = bound(sessionDeposit, 0.1 ether, 10 ether);

        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create inline session
        vm.prank(user);
        marketplace.createSessionJob{value: sessionDeposit}(host, MIN_PRICE_NATIVE, 1 days, 1000);

        // Pre-deposit balance should be 0 (not credited)
        assertEq(marketplace.userDepositsNative(user), 0, "Pre-deposit should NOT be credited for inline session");

        // Cannot withdraw
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.withdrawNative(sessionDeposit);

        // Locked should equal deposit
        assertEq(marketplace.getLockedBalanceNative(user), sessionDeposit, "Locked should equal session deposit");
    }

    function testFuzz_MultipleRandomSessions(uint256 seed) public {
        uint256 numSessions = (seed % 5) + 1; // 1-5 sessions
        uint256 startTime = 1000;
        vm.warp(startTime);

        uint256 totalDeposited = 0;
        uint256[] memory sessionIds = new uint256[](numSessions);
        uint256[] memory deposits = new uint256[](numSessions);

        // Create random sessions
        vm.startPrank(user);
        for (uint256 i = 0; i < numSessions; i++) {
            uint256 deposit = ((seed / (i + 1)) % 3 + 1) * 0.5 ether; // 0.5-1.5 ETH
            deposits[i] = deposit;
            totalDeposited += deposit;
            sessionIds[i] = marketplace.createSessionJob{value: deposit}(host, MIN_PRICE_NATIVE, 1 days, 1000);
        }
        vm.stopPrank();

        // Verify total locked
        assertEq(marketplace.getLockedBalanceNative(user), totalDeposited, "Total locked should match deposited");

        // Pre-deposit should be 0
        assertEq(marketplace.userDepositsNative(user), 0, "Pre-deposit should be 0");

        // Total should be locked
        assertEq(marketplace.getTotalBalanceNative(user), totalDeposited, "Total should equal locked");
    }

    // ============================================================
    // Contract Balance Invariant
    // ============================================================

    function test_ContractBalance_Invariant() public {
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Multiple users deposit and create sessions
        vm.prank(user);
        marketplace.depositNative{value: 3 ether}();
        vm.prank(user);
        marketplace.createSessionJob{value: 2 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000);

        vm.prank(user2);
        marketplace.createSessionJob{value: 4 ether}(host2, MIN_PRICE_NATIVE, 1 days, 1000);

        // Contract balance should equal sum of all deposits and sessions
        uint256 expectedBalance = 3 ether + 2 ether + 4 ether; // 9 ETH total
        assertEq(address(marketplace).balance, expectedBalance, "Contract balance should match all deposits");

        // Verify: user1 withdrawable + user1 locked + user2 locked = contract balance - treasury
        uint256 user1Withdrawable = marketplace.userDepositsNative(user);
        uint256 user1Locked = marketplace.getLockedBalanceNative(user);
        uint256 user2Locked = marketplace.getLockedBalanceNative(user2);
        uint256 treasury = marketplace.accumulatedTreasuryNative();

        uint256 accountedFunds = user1Withdrawable + user1Locked + user2Locked + treasury;
        assertEq(accountedFunds, expectedBalance, "All funds should be accounted for");
    }
}
