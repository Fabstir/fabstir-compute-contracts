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
 * @title Delegate Deduplication Regression Tests
 * @notice Ensures createSessionForModelAsDelegate produces identical session state
 *         to createSessionJobForModelWithToken (the canonical token-based path).
 *         These tests guard against behavioral drift during refactoring.
 */
contract DelegateDedupTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public hostAddr = address(0x2);
    address public payer = address(0x3);
    address public delegate = address(0x4);
    address public treasury = address(0x5);
    address public directUser = address(0x6);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant SESSION_AMOUNT = 10_000_000; // 10 USDC

    event SessionJobCreated(uint256 indexed jobId, address indexed depositor, address indexed host, uint256 deposit);
    event SessionJobCreatedForModel(
        uint256 indexed jobId, address indexed depositor, address indexed host, bytes32 modelId, uint256 deposit
    );
    event SessionCreatedByDelegate(
        uint256 indexed sessionId,
        address indexed payer,
        address indexed delegate,
        address host,
        bytes32 modelId,
        uint256 amount
    );

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(
            address(
                new ERC1967Proxy(
                    address(modelRegistryImpl),
                    abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
                )
            )
        );
        modelRegistry.addTrustedModel("ModelA/Repo", "modelA.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("ModelA/Repo", "modelA.gguf");

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(
            address(
                new ERC1967Proxy(
                    address(nodeRegistryImpl),
                    abi.encodeCall(
                        NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry))
                    )
                )
            )
        );

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(
            payable(
                address(
                    new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
                )
            )
        );

        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(
            address(new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())))
        );

        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(
            payable(
                address(
                    new ERC1967Proxy(
                        address(marketplaceImpl),
                        abi.encodeCall(
                            JobMarketplaceWithModelsUpgradeable.initialize,
                            (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW)
                        )
                    )
                )
            )
        );

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
        fabToken.mint(hostAddr, MIN_STAKE);
        vm.startPrank(hostAddr);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);
        vm.stopPrank();

        // Fund payer for delegate path
        usdcToken.mint(payer, 1_000_000_000_000);
        vm.prank(payer);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // Fund directUser for direct path
        usdcToken.mint(directUser, 1_000_000_000_000);
        vm.prank(directUser);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // Authorize delegate (unlimited)
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0));
    }

    /// @notice Helper to get core session fields without stack-too-deep
    function _getSessionCore(uint256 sessionId)
        internal
        view
        returns (address depositor, address host, address token, uint256 deposit, uint256 price, uint256 maxDur)
    {
        (, depositor, host, token, deposit, price,, maxDur,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
    }

    function _getSessionTiming(uint256 sessionId)
        internal
        view
        returns (uint256 startTime, uint256 lastProofTime, uint256 interval, uint256 timeout)
    {
        (,,,,,,,, startTime, lastProofTime, interval, timeout,,,,,,) = marketplace.sessionJobs(sessionId);
    }

    /// @notice Delegate and direct sessions produce identical SessionJob fields
    function test_DelegateSession_MatchesDirectSession_Fields() public {
        // Create direct session
        vm.prank(directUser);
        uint256 directId = marketplace.createSessionJobForModelWithToken(
            hostAddr, modelId, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Create delegate session (same block.timestamp)
        vm.prank(delegate);
        uint256 delegateId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Compare core fields
        (address dep1, address host1, address tok1, uint256 depo1, uint256 price1, uint256 dur1) =
            _getSessionCore(directId);
        (address dep2, address host2, address tok2, uint256 depo2, uint256 price2, uint256 dur2) =
            _getSessionCore(delegateId);

        assertEq(host1, host2, "host mismatch");
        assertEq(tok1, tok2, "paymentToken mismatch");
        assertEq(depo1, depo2, "deposit mismatch");
        assertEq(price1, price2, "pricePerToken mismatch");
        assertEq(dur1, dur2, "maxDuration mismatch");

        // Compare timing fields
        (uint256 s1, uint256 lp1, uint256 i1, uint256 t1) = _getSessionTiming(directId);
        (uint256 s2, uint256 lp2, uint256 i2, uint256 t2) = _getSessionTiming(delegateId);

        assertEq(s1, s2, "startTime mismatch");
        assertEq(lp1, lp2, "lastProofTime mismatch");
        assertEq(i1, i2, "proofInterval mismatch");
        assertEq(t1, t2, "proofTimeoutWindow mismatch");

        // Depositor is intentionally different
        assertEq(dep1, directUser, "direct depositor");
        assertEq(dep2, payer, "delegate depositor");
    }

    /// @notice Delegate path tracks sessionModel identically
    function test_DelegateSession_ModelTracking() public {
        vm.prank(directUser);
        uint256 directId = marketplace.createSessionJobForModelWithToken(
            hostAddr, modelId, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        vm.prank(delegate);
        uint256 delegateId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        assertEq(marketplace.sessionModel(directId), marketplace.sessionModel(delegateId), "model mismatch");
        assertEq(marketplace.sessionModel(delegateId), modelId, "model not set");
    }

    /// @notice Delegate path updates userSessions for payer and hostSessions for host
    function test_DelegateSession_UserSessionTracking() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Session tracked under payer (not delegate) — check via userSessions mapping
        assertEq(marketplace.userSessions(payer, 0), sessionId, "payer session id");

        // Delegate has no sessions — accessing index 0 should revert
        vm.expectRevert();
        marketplace.userSessions(delegate, 0);

        // Session tracked for host
        assertEq(marketplace.hostSessions(hostAddr, 0), sessionId, "host session id");
    }

    /// @notice Delegate path emits all three expected events
    function test_DelegateSession_EmitsAllEvents() public {
        uint256 expectedId = marketplace.nextJobId();

        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(expectedId, payer, hostAddr, SESSION_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreatedForModel(expectedId, payer, hostAddr, modelId, SESSION_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDelegate(expectedId, payer, delegate, hostAddr, modelId, SESSION_AMOUNT);

        vm.prank(delegate);
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // Phase 30.1: End-to-end delegate session lifecycle — refund to payer
    // ============================================================

    /// @notice F202615255: Full delegate lifecycle — refund goes to payer, not delegate
    function test_DelegateSession_EndToEnd_RefundToPayer() public {
        // Configure delegate with totalCap
        vm.prank(payer);
        marketplace.configureDelegate(delegate, uint128(SESSION_AMOUNT), uint128(SESSION_AMOUNT * 2), 0, address(0), bytes32(0));

        uint256 payerBalBefore = usdcToken.balanceOf(payer);

        // Delegate creates session
        vm.prank(delegate);
        uint256 sid = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Host submits proof (advance time for rate limit)
        vm.warp(block.timestamp + 10);
        vm.prank(hostAddr);
        marketplace.submitProofOfWork(sid, 1000, keccak256("lifecycle"), "cid", "delta");

        // Complete after dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(hostAddr);
        marketplace.completeSessionJob(sid, "QmConversation");

        // Assert refund went to payer (not delegate)
        (, , , , , , , , , , , , , uint256 withdrawn, uint256 refunded, , , ) = marketplace.sessionJobs(sid);
        assertGt(refunded, 0, "Refund should be > 0");

        uint256 payerBalAfter = usdcToken.balanceOf(payer);
        // Payer received refund (balance went down by deposit, then up by refund)
        assertEq(payerBalAfter, payerBalBefore - SESSION_AMOUNT + refunded, "Refund goes to payer");

        // Delegate balance unchanged (shouldn't receive refund)
        assertEq(usdcToken.balanceOf(delegate), 0, "Delegate balance unchanged");

        // Host received payment via HostEarnings
        uint256 hostBal = hostEarnings.getBalance(hostAddr, address(usdcToken));
        assertEq(hostBal, withdrawn, "Host received net payment");

        // Delegate spent counter reflects session amount
        (, , uint128 spent, , , , ) = marketplace.delegateConfigs(payer, delegate);
        assertEq(spent, SESSION_AMOUNT, "Spent counter reflects session amount");
    }

    // ============================================================
    // Phase 30.2: Delegate session timeout — refund to payer, no early fee
    // ============================================================

    /// @notice F202615255+F202615257: Delegate timeout refunds payer, no early fee
    function test_DelegateSession_Timeout_RefundToPayer() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0));

        uint256 payerBalBefore = usdcToken.balanceOf(payer);

        // Delegate creates session
        vm.prank(delegate);
        uint256 sid = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // Host goes inactive — advance past proofTimeoutWindow
        vm.warp(block.timestamp + 301);

        // Payer triggers timeout
        vm.prank(payer);
        marketplace.triggerSessionTimeout(sid);

        // Payer gets full refund (no early fee on TimedOut status)
        uint256 payerBalAfter = usdcToken.balanceOf(payer);
        assertEq(payerBalAfter, payerBalBefore, "Payer gets full refund on timeout");

        // Host gets $0
        uint256 hostBal = hostEarnings.getBalance(hostAddr, address(usdcToken));
        assertEq(hostBal, 0, "Host gets zero on timeout");

        // Delegate spent counter still reflects original amount (not decremented)
        (, , uint128 spent, , , , ) = marketplace.delegateConfigs(payer, delegate);
        assertEq(spent, SESSION_AMOUNT, "Spent counter not decremented on timeout");
    }

    // ============================================================
    // Phase 30.3: Delegate session reverts when marketplace is paused
    // ============================================================

    /// @notice Delegate session creation should revert when marketplace is paused
    function test_DelegateSession_RevertsWhenPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(delegate);
        vm.expectRevert();
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // Existing tests
    // ============================================================

    /// @notice Delegate path rejects same invalid params as direct path
    function test_DelegateSession_ValidationParity() public {
        // pricePerToken=0 → "Bad price"
        vm.prank(delegate);
        vm.expectRevert("Bad price");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, 0, 1 days, 1000, 300
        );

        // maxDuration=0 → "Bad dur"
        vm.prank(delegate);
        vm.expectRevert("Bad dur");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 0, 1000, 300
        );

        // proofInterval=0 → "Bad interval"
        vm.prank(delegate);
        vm.expectRevert("Bad interval");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 0, 300
        );

        // host=address(0) → "No host"
        vm.prank(delegate);
        vm.expectRevert("No host");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, address(0), address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );

        // amount below min → "Below min"
        vm.prank(delegate);
        vm.expectRevert("Below min");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), 1, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }
}
