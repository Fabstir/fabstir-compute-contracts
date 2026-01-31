// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Balance Separation Security Tests
 * @dev Tests for Sub-phase 3.2: Add Explicit Deposit vs Session Balance Separation
 *
 * Purpose: Defense in depth - provide clear visibility into:
 * - Withdrawable funds (pre-deposited, not in sessions)
 * - Locked funds (committed to active sessions)
 * - Total balance (sum of both)
 */
contract BalanceSeparationTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    uint256 public hostPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host;
    address public user = address(0x3);

    bytes32 public modelId;

    uint256 constant feeBasisPoints = 1000; // 10%
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Derive host from private key
        host = vm.addr(hostPrivateKey);

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

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

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

        // Configure ProofSystem in marketplace
        marketplace.setProofSystem(address(proofSystem));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Add mock USDC to accepted tokens
        marketplace.addAcceptedToken(address(usdcToken), 500000, 1_000_000 * 10**6);

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Setup users with funds
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 1000 * 10**6);
        vm.prank(user);
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

    function _generateSignature(bytes32 proofHash, uint256 tokensClaimed)
        internal
        view
        returns (bytes memory)
    {
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, host, tokensClaimed));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    // ============================================================
    // Native Token Balance Tests
    // ============================================================

    function test_GetDepositBalanceReturnsOnlyWithdrawable_ETH() public {
        // Pre-deposit 5 ETH
        vm.prank(user);
        marketplace.depositNative{value: 5 ether}();

        // userDepositsNative should be 5 ETH
        assertEq(marketplace.userDepositsNative(user), 5 ether, "Withdrawable should be 5 ETH");

        // Locked should be 0 (no sessions)
        assertEq(marketplace.getLockedBalanceNative(user), 0, "Locked should be 0");

        // Total should be 5 ETH
        assertEq(marketplace.getTotalBalanceNative(user), 5 ether, "Total should be 5 ETH");
    }

    function test_GetLockedBalanceReturnsSessionFunds_ETH() public {
        // Create inline session with 2 ETH
        vm.prank(user);
        marketplace.createSessionJob{value: 2 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // userDepositsNative should be 0 (inline session doesn't credit it)
        assertEq(marketplace.userDepositsNative(user), 0, "Withdrawable should be 0");

        // Locked should be 2 ETH (in session)
        assertEq(marketplace.getLockedBalanceNative(user), 2 ether, "Locked should be 2 ETH");

        // Total should be 2 ETH
        assertEq(marketplace.getTotalBalanceNative(user), 2 ether, "Total should be 2 ETH");
    }

    function test_TotalBalanceEqualsWithdrawablePlusLocked_ETH() public {
        // Pre-deposit 3 ETH
        vm.prank(user);
        marketplace.depositNative{value: 3 ether}();

        // Create session from pre-deposit with 1 ETH
        vm.prank(user);
        marketplace.createSessionFromDeposit(
            host,
            address(0), // native
            1 ether,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Create inline session with 2 ETH
        vm.prank(user);
        marketplace.createSessionJob{value: 2 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Withdrawable should be 2 ETH (3 - 1 used for session)
        assertEq(marketplace.userDepositsNative(user), 2 ether, "Withdrawable should be 2 ETH");

        // Locked should be 3 ETH (1 from pre-deposit session + 2 from inline session)
        assertEq(marketplace.getLockedBalanceNative(user), 3 ether, "Locked should be 3 ETH");

        // Total should be 5 ETH (2 withdrawable + 3 locked)
        assertEq(marketplace.getTotalBalanceNative(user), 5 ether, "Total should be 5 ETH");
    }

    function test_LockedBalanceDecreasesAfterProofs_ETH() public {
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create session with 1 ETH at very high price
        uint256 pricePerToken = 1e12; // 1e12 wei per token = 1e6 tokens per ETH
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host,
            pricePerToken,
            1 days,
            1000,
            300
        );

        // Initial locked = 1 ETH
        assertEq(marketplace.getLockedBalanceNative(user), 1 ether, "Initial locked should be 1 ETH");

        // Host submits proof for some tokens
        vm.warp(startTime + 1);
        bytes32 proofHash = bytes32(uint256(0x1234));
        bytes memory signature = _generateSignature(proofHash, 1000);
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            1000, // tokens used
            proofHash,
            signature,
            "QmProof",
            ""
        );

        // Locked should decrease by amount used
        // Contract formula: used = (tokensUsed * pricePerToken) / PRICE_PRECISION
        // PRICE_PRECISION = 1000, so: used = (1000 * 1e12) / 1000 = 1e12
        uint256 PRICE_PRECISION = 1000;
        uint256 expectedUsed = (1000 * pricePerToken) / PRICE_PRECISION;
        uint256 expectedLocked = 1 ether - expectedUsed;
        assertEq(marketplace.getLockedBalanceNative(user), expectedLocked, "Locked should decrease after proofs");
    }

    function test_LockedBalanceZeroAfterSessionComplete_ETH() public {
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create session with 1 ETH
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Locked = 1 ETH initially
        assertEq(marketplace.getLockedBalanceNative(user), 1 ether, "Initial locked should be 1 ETH");

        // Host submits proof
        vm.warp(startTime + 1);
        bytes32 proofHash = bytes32(uint256(0x1234));
        bytes memory signature = _generateSignature(proofHash, 500);
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            500,
            proofHash,
            signature,
            "QmProof",
            ""
        );

        // Complete session
        vm.warp(startTime + disputeWindow + 2);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Locked should be 0 after completion
        assertEq(marketplace.getLockedBalanceNative(user), 0, "Locked should be 0 after completion");
    }

    // ============================================================
    // ERC20 Token Balance Tests
    // ============================================================

    function test_GetDepositBalanceReturnsOnlyWithdrawable_USDC() public {
        uint256 depositAmount = 50 * 10**6; // 50 USDC

        // Pre-deposit USDC
        vm.prank(user);
        marketplace.depositToken(address(usdcToken), depositAmount);

        // userDepositsToken should be 50 USDC
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), depositAmount, "Withdrawable should be 50 USDC");

        // Locked should be 0 (no sessions)
        assertEq(marketplace.getLockedBalanceToken(user, address(usdcToken)), 0, "Locked should be 0");

        // Total should be 50 USDC
        assertEq(marketplace.getTotalBalanceToken(user, address(usdcToken)), depositAmount, "Total should be 50 USDC");
    }

    function test_GetLockedBalanceReturnsSessionFunds_USDC() public {
        uint256 sessionDeposit = 20 * 10**6; // 20 USDC

        // Create inline session with USDC
        vm.prank(user);
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            sessionDeposit,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );

        // userDepositsToken should be 0 (inline session doesn't credit it)
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), 0, "Withdrawable should be 0");

        // Locked should be 20 USDC
        assertEq(marketplace.getLockedBalanceToken(user, address(usdcToken)), sessionDeposit, "Locked should be 20 USDC");

        // Total should be 20 USDC
        assertEq(marketplace.getTotalBalanceToken(user, address(usdcToken)), sessionDeposit, "Total should be 20 USDC");
    }

    function test_TotalBalanceEqualsWithdrawablePlusLocked_USDC() public {
        uint256 preDeposit = 30 * 10**6; // 30 USDC
        uint256 sessionFromDeposit = 10 * 10**6; // 10 USDC
        uint256 inlineSession = 15 * 10**6; // 15 USDC

        // Pre-deposit 30 USDC
        vm.prank(user);
        marketplace.depositToken(address(usdcToken), preDeposit);

        // Create session from pre-deposit with 10 USDC
        vm.prank(user);
        marketplace.createSessionFromDeposit(
            host,
            address(usdcToken),
            sessionFromDeposit,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );

        // Create inline session with 15 USDC
        vm.prank(user);
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            inlineSession,
            MIN_PRICE_STABLE,
            1 days,
            1000,
            300
        );

        // Withdrawable should be 20 USDC (30 - 10)
        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), preDeposit - sessionFromDeposit, "Withdrawable should be 20 USDC");

        // Locked should be 25 USDC (10 + 15)
        assertEq(marketplace.getLockedBalanceToken(user, address(usdcToken)), sessionFromDeposit + inlineSession, "Locked should be 25 USDC");

        // Total should be 45 USDC (20 + 25)
        assertEq(marketplace.getTotalBalanceToken(user, address(usdcToken)), preDeposit + inlineSession, "Total should be 45 USDC");
    }

    // ============================================================
    // Multiple Sessions Tests
    // ============================================================

    function test_LockedBalanceAcrossMultipleSessions_ETH() public {
        // Create 3 sessions with different amounts
        vm.startPrank(user);
        marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);
        marketplace.createSessionJob{value: 2 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);
        marketplace.createSessionJob{value: 3 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);
        vm.stopPrank();

        // Total locked should be 6 ETH
        assertEq(marketplace.getLockedBalanceNative(user), 6 ether, "Locked should be 6 ETH across all sessions");

        // Withdrawable should be 0
        assertEq(marketplace.userDepositsNative(user), 0, "Withdrawable should be 0");

        // Total should be 6 ETH
        assertEq(marketplace.getTotalBalanceNative(user), 6 ether, "Total should be 6 ETH");
    }

    function test_MixedDepositAndSessionBalance() public {
        // Pre-deposit 10 ETH
        vm.prank(user);
        marketplace.depositNative{value: 10 ether}();

        // Create session from deposit (5 ETH)
        vm.prank(user);
        marketplace.createSessionFromDeposit(host, address(0), 5 ether, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Create inline session (3 ETH)
        vm.prank(user);
        marketplace.createSessionJob{value: 3 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Pre-deposit more (2 ETH)
        vm.prank(user);
        marketplace.depositNative{value: 2 ether}();

        // Withdrawable: 10 - 5 + 2 = 7 ETH
        assertEq(marketplace.userDepositsNative(user), 7 ether, "Withdrawable should be 7 ETH");

        // Locked: 5 + 3 = 8 ETH
        assertEq(marketplace.getLockedBalanceNative(user), 8 ether, "Locked should be 8 ETH");

        // Total: 7 + 8 = 15 ETH
        assertEq(marketplace.getTotalBalanceNative(user), 15 ether, "Total should be 15 ETH");
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    function test_ZeroBalanceForNewUser() public view {
        address newUser = address(0x999);

        assertEq(marketplace.userDepositsNative(newUser), 0, "New user withdrawable should be 0");
        assertEq(marketplace.getLockedBalanceNative(newUser), 0, "New user locked should be 0");
        assertEq(marketplace.getTotalBalanceNative(newUser), 0, "New user total should be 0");
        assertEq(marketplace.getLockedBalanceToken(newUser, address(usdcToken)), 0, "New user USDC locked should be 0");
        assertEq(marketplace.getTotalBalanceToken(newUser, address(usdcToken)), 0, "New user USDC total should be 0");
    }

    function test_LockedBalanceIgnoresCompletedSessions_ETH() public {
        uint256 startTime = 1000;
        vm.warp(startTime);

        // Create 2 sessions
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 1 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);
        vm.prank(user);
        marketplace.createSessionJob{value: 2 ether}(host, MIN_PRICE_NATIVE, 1 days, 1000, 300);

        // Locked should be 3 ETH
        assertEq(marketplace.getLockedBalanceNative(user), 3 ether, "Locked should be 3 ETH");

        // Complete first session
        vm.warp(startTime + 1);
        bytes32 proofHash = bytes32(uint256(0x1234));
        bytes memory signature = _generateSignature(proofHash, 100);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId1, 100, proofHash, signature, "QmProof", "");
        vm.warp(startTime + disputeWindow + 2);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId1, "QmConversation");

        // Locked should now only count second session (2 ETH)
        assertEq(marketplace.getLockedBalanceNative(user), 2 ether, "Locked should be 2 ETH after first session complete");
    }
}
