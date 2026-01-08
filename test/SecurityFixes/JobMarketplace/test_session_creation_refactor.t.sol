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
 * @title Session Creation Refactor Tests
 * @dev Tests for Phase 5: Session Creation Code Deduplication
 *
 * These tests verify that after refactoring:
 * 1. All 4 session creation functions behave identically
 * 2. All validations still occur in the correct order
 * 3. Events are emitted correctly
 * 4. Gas costs are acceptable
 */
contract SessionCreationRefactorTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x3);

    bytes32 public modelId;

    uint256 constant feeBasisPoints = 1000; // 10%
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    // Session parameters
    uint256 constant DEPOSIT_ETH = 1 ether;
    uint256 constant DEPOSIT_USDC = 1000000; // 1 USDC
    uint256 constant PRICE_PER_TOKEN = MIN_PRICE_NATIVE; // Must meet host minimum
    uint256 constant PRICE_PER_TOKEN_STABLE = MIN_PRICE_STABLE; // For stable token sessions
    uint256 constant MAX_DURATION = 1 hours;
    uint256 constant PROOF_INTERVAL = 100;

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
                feeBasisPoints,
                disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Configure
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        marketplace.addAcceptedToken(address(usdcToken), 500000); // 0.5 USDC minimum
        vm.stopPrank();

        // Register host
        fabToken.mint(host, 10000 * 10**18);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("Test Host", "http://test.local", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();

        // Fund user
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 1000000 * 10**6);
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    // Helper to extract key session fields (struct has 17 returned fields, skipping dynamic array)
    function _getSessionBasics(uint256 jobId) internal view returns (
        uint256 id,
        address depositor,
        address sessionHost,
        address paymentToken,
        uint256 deposit,
        JobMarketplaceWithModelsUpgradeable.SessionStatus status
    ) {
        (id, depositor, sessionHost, paymentToken, deposit,,,,,,, status,,,,,) = marketplace.sessionJobs(jobId);
    }

    // ============================================================
    // Behavioral Equivalence Tests
    // ============================================================

    function test_CreateSessionJob_CreatesValidSession() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT_ETH}(
            host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL
        );

        (uint256 id, address depositor, address sessionHost, address paymentToken, uint256 deposit,
         JobMarketplaceWithModelsUpgradeable.SessionStatus status) = _getSessionBasics(jobId);

        assertEq(id, jobId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
        assertEq(paymentToken, address(0));
        assertEq(deposit, DEPOSIT_ETH);
        assertEq(uint256(status), uint256(JobMarketplaceWithModelsUpgradeable.SessionStatus.Active));
    }

    function test_CreateSessionJobForModel_CreatesValidSession() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(
            host, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL
        );

        (uint256 id, address depositor, address sessionHost, address paymentToken, uint256 deposit,
         JobMarketplaceWithModelsUpgradeable.SessionStatus status) = _getSessionBasics(jobId);

        assertEq(id, jobId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
        assertEq(paymentToken, address(0));
        assertEq(deposit, DEPOSIT_ETH);
        assertEq(marketplace.sessionModel(jobId), modelId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModelsUpgradeable.SessionStatus.Active));
    }

    function test_CreateSessionJobWithToken_CreatesValidSession() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL
        );

        (uint256 id, address depositor, address sessionHost, address paymentToken, uint256 deposit,
         JobMarketplaceWithModelsUpgradeable.SessionStatus status) = _getSessionBasics(jobId);

        assertEq(id, jobId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
        assertEq(paymentToken, address(usdcToken));
        assertEq(deposit, DEPOSIT_USDC);
        assertEq(uint256(status), uint256(JobMarketplaceWithModelsUpgradeable.SessionStatus.Active));
    }

    function test_CreateSessionJobForModelWithToken_CreatesValidSession() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL
        );

        (uint256 id, address depositor, address sessionHost, address paymentToken, uint256 deposit,
         JobMarketplaceWithModelsUpgradeable.SessionStatus status) = _getSessionBasics(jobId);

        assertEq(id, jobId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
        assertEq(paymentToken, address(usdcToken));
        assertEq(deposit, DEPOSIT_USDC);
        assertEq(marketplace.sessionModel(jobId), modelId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModelsUpgradeable.SessionStatus.Active));
    }

    // ============================================================
    // Validation Order Tests (Host validation MUST come before model)
    // ============================================================

    function test_CreateSessionJobForModel_ValidatesHostBeforeModel() public {
        address unregisteredHost = address(0x999);

        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(
            unregisteredHost, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL
        );
    }

    function test_CreateSessionJobForModelWithToken_ValidatesHostBeforeModel() public {
        address unregisteredHost = address(0x999);

        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJobForModelWithToken(
            unregisteredHost, modelId, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL
        );
    }

    // ============================================================
    // Validation Tests (ensure all validations still work)
    // ============================================================

    function test_CreateSessionJob_RejectsZeroPrice() public {
        vm.prank(user);
        vm.expectRevert("Invalid price");
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, 0, MAX_DURATION, PROOF_INTERVAL);
    }

    function test_CreateSessionJob_RejectsZeroDuration() public {
        vm.prank(user);
        vm.expectRevert("Invalid duration");
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, 0, PROOF_INTERVAL);
    }

    function test_CreateSessionJob_RejectsExcessiveDuration() public {
        vm.prank(user);
        vm.expectRevert("Invalid duration");
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, 366 days, PROOF_INTERVAL);
    }

    function test_CreateSessionJob_RejectsZeroProofInterval() public {
        vm.prank(user);
        vm.expectRevert("Invalid proof interval");
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, 0);
    }

    function test_CreateSessionJob_RejectsZeroHost() public {
        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionJob{value: DEPOSIT_ETH}(address(0), PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
    }

    function test_CreateSessionJob_RejectsUnregisteredHost() public {
        vm.prank(user);
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: DEPOSIT_ETH}(address(0x999), PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
    }

    function test_CreateSessionJob_RejectsInsufficientDeposit() public {
        vm.prank(user);
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJob{value: 0.00001 ether}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
    }

    function test_CreateSessionJobWithToken_RejectsUnapprovedToken() public {
        address badToken = address(0x123);
        vm.prank(user);
        vm.expectRevert("Token not accepted");
        marketplace.createSessionJobWithToken(host, badToken, DEPOSIT_USDC, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
    }

    function test_CreateSessionJobForModel_RejectsUnsupportedModel() public {
        bytes32 unsupportedModel = bytes32(uint256(999));

        vm.prank(user);
        vm.expectRevert("Host does not support model");
        marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(
            host, unsupportedModel, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL
        );
    }

    // ============================================================
    // Tracking Tests (userSessions and hostSessions)
    // ============================================================

    function test_AllMethods_IncrementNextJobId() public {
        uint256 initialJobId = marketplace.nextJobId();

        vm.startPrank(user);
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(host, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        marketplace.createSessionJobWithToken(host, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);
        marketplace.createSessionJobForModelWithToken(host, modelId, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);
        vm.stopPrank();

        assertEq(marketplace.nextJobId(), initialJobId + 4);
    }

    function test_AllMethods_TrackUserSessions() public {
        vm.startPrank(user);

        uint256 jobId1 = marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        uint256 jobId2 = marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(host, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        uint256 jobId3 = marketplace.createSessionJobWithToken(host, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);
        uint256 jobId4 = marketplace.createSessionJobForModelWithToken(host, modelId, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);

        vm.stopPrank();

        // Access individual elements from the public mapping
        assertEq(marketplace.userSessions(user, 0), jobId1);
        assertEq(marketplace.userSessions(user, 1), jobId2);
        assertEq(marketplace.userSessions(user, 2), jobId3);
        assertEq(marketplace.userSessions(user, 3), jobId4);
    }

    function test_AllMethods_TrackHostSessions() public {
        vm.startPrank(user);

        uint256 jobId1 = marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        uint256 jobId2 = marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(host, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        uint256 jobId3 = marketplace.createSessionJobWithToken(host, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);
        uint256 jobId4 = marketplace.createSessionJobForModelWithToken(host, modelId, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);

        vm.stopPrank();

        // Access individual elements from the public mapping
        assertEq(marketplace.hostSessions(host, 0), jobId1);
        assertEq(marketplace.hostSessions(host, 1), jobId2);
        assertEq(marketplace.hostSessions(host, 2), jobId3);
        assertEq(marketplace.hostSessions(host, 3), jobId4);
    }

    // ============================================================
    // Event Tests
    // ============================================================

    function test_CreateSessionJob_EmitsEvents() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit JobMarketplaceWithModelsUpgradeable.SessionJobCreated(1, user, host, DEPOSIT_ETH);

        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
    }

    function test_CreateSessionJobForModel_EmitsModelEvent() public {
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit JobMarketplaceWithModelsUpgradeable.SessionJobCreatedForModel(1, user, host, modelId, DEPOSIT_ETH);

        marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(host, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
    }

    // ============================================================
    // Gas Comparison Tests (capture baseline before refactoring)
    // ============================================================

    function test_GasUsage_CreateSessionJob() public {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        uint256 gasUsed = gasBefore - gasleft();

        // Log gas for comparison - should be similar before and after refactoring
        // Acceptable increase is ~500 gas for internal function calls
        emit log_named_uint("createSessionJob gas", gasUsed);
        assertTrue(gasUsed < 400000, "Gas usage too high");
    }

    function test_GasUsage_CreateSessionJobForModel() public {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        marketplace.createSessionJobForModel{value: DEPOSIT_ETH}(host, modelId, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("createSessionJobForModel gas", gasUsed);
        assertTrue(gasUsed < 430000, "Gas usage too high");
    }

    function test_GasUsage_CreateSessionJobWithToken() public {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        marketplace.createSessionJobWithToken(host, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("createSessionJobWithToken gas", gasUsed);
        // Token sessions cost more due to ERC20 transferFrom
        assertTrue(gasUsed < 500000, "Gas usage too high");
    }

    function test_GasUsage_CreateSessionJobForModelWithToken() public {
        vm.prank(user);
        uint256 gasBefore = gasleft();
        marketplace.createSessionJobForModelWithToken(host, modelId, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("createSessionJobForModelWithToken gas", gasUsed);
        // Token sessions with model cost more due to ERC20 transferFrom + model checks
        assertTrue(gasUsed < 520000, "Gas usage too high");
    }

    // ============================================================
    // Security Tests (Double-spend prevention still works)
    // ============================================================

    function test_InlineDeposit_NotWithdrawable_Native() public {
        vm.prank(user);
        marketplace.createSessionJob{value: DEPOSIT_ETH}(host, PRICE_PER_TOKEN, MAX_DURATION, PROOF_INTERVAL);

        // User should NOT be able to withdraw the deposit (it's locked in session)
        uint256 withdrawable = marketplace.userDepositsNative(user);
        assertEq(withdrawable, 0, "Inline deposit should not be withdrawable");
    }

    function test_InlineDeposit_NotWithdrawable_Token() public {
        vm.prank(user);
        marketplace.createSessionJobWithToken(host, address(usdcToken), DEPOSIT_USDC, PRICE_PER_TOKEN_STABLE, MAX_DURATION, PROOF_INTERVAL);

        // User should NOT be able to withdraw the deposit (it's locked in session)
        uint256 withdrawable = marketplace.userDepositsToken(user, address(usdcToken));
        assertEq(withdrawable, 0, "Inline deposit should not be withdrawable");
    }
}
