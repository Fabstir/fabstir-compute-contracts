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
 * @title Delegated Session Creation Tests
 * @notice Tests for createSessionFromDepositAsDelegate and createSessionFromDepositForModelAsDelegate
 */
contract DelegatedSessionCreationTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public treasury = address(0x4);
    address public depositor;
    address public delegate;

    bytes32 public modelId;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;

    uint256 public depositAmount = 0.1 ether;
    uint256 public pricePerToken = MIN_PRICE_NATIVE;
    uint256 public maxDuration = 1 hours;
    uint256 public proofInterval = 100;
    uint256 public proofTimeoutWindow = 300;

    event SessionCreatedByDelegate(
        uint256 indexed sessionId,
        address indexed depositor,
        address indexed delegate,
        address host,
        bytes32 modelId,
        uint256 deposit
    );

    function setUp() public {
        depositor = makeAddr("depositor");
        delegate = makeAddr("delegate");

        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(address(modelRegistryImpl), abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken))))
        );
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(
            new ERC1967Proxy(address(nodeRegistryImpl), abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), modelRegistryProxy)))
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(
            new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
        );
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(
            new ERC1967Proxy(address(marketplaceImpl), abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (nodeRegistryProxy, payable(hostEarningsProxy), 1000, 30)))
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Configure marketplace
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        // Authorize marketplace
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Setup depositor with funds and deposits
        vm.deal(depositor, 10 ether);
        usdcToken.mint(depositor, 10_000_000_000);

        vm.startPrank(depositor);
        marketplace.depositNative{value: 5 ether}();
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.depositToken(address(usdcToken), 1_000_000_000);
        marketplace.authorizeDelegate(delegate, true);
        vm.stopPrank();
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);
        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // ============================================================
    // Non-Model Delegated Session Tests
    // ============================================================

    function test_CreateSessionAsDelegate_ETH_Success() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        assertGt(sessionId, 0);
    }

    function test_CreateSessionAsDelegate_SessionOwnerIsDepositor() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        (, address sessionDepositor,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(sessionDepositor, depositor, "Session owner should be depositor, not delegate");
    }

    function test_CreateSessionAsDelegate_DeductsFundsFromDepositor() public {
        uint256 balanceBefore = marketplace.userDepositsNative(depositor);
        vm.prank(delegate);
        marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        uint256 balanceAfter = marketplace.userDepositsNative(depositor);
        assertEq(balanceAfter, balanceBefore - depositAmount);
    }

    function test_CreateSessionAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_CreateSessionAsDelegate_EmitsSessionCreatedByDelegate() public {
        vm.prank(delegate);
        vm.expectEmit(true, true, true, true);
        emit SessionCreatedByDelegate(1, depositor, delegate, host, bytes32(0), depositAmount);
        marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_CreateSessionAsDelegate_ZeroDepositor_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Invalid depositor");
        marketplace.createSessionFromDepositAsDelegate(
            address(0), host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_CreateSessionAsDelegate_InsufficientBalance_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert("Insufficient native balance");
        marketplace.createSessionFromDepositAsDelegate(
            depositor, host, address(0), 100 ether, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    // ============================================================
    // Model-Specific Delegated Session Tests
    // ============================================================

    function test_CreateSessionForModelAsDelegate_ETH_Success() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositForModelAsDelegate(
            depositor, modelId, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        assertGt(sessionId, 0);
        assertEq(marketplace.sessionModel(sessionId), modelId);
    }

    function test_CreateSessionForModelAsDelegate_USDC_Success() public {
        uint256 usdcDeposit = 100_000_000; // 100 USDC
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositForModelAsDelegate(
            depositor, modelId, host, address(usdcToken), usdcDeposit, MIN_PRICE_STABLE, maxDuration, proofInterval, proofTimeoutWindow
        );
        assertGt(sessionId, 0);
    }

    function test_CreateSessionForModelAsDelegate_SessionOwnerIsDepositor() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionFromDepositForModelAsDelegate(
            depositor, modelId, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        (, address sessionDepositor,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(sessionDepositor, depositor);
    }

    function test_CreateSessionForModelAsDelegate_UnauthorizedDelegate_Reverts() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionFromDepositForModelAsDelegate(
            depositor, modelId, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_CreateSessionForModelAsDelegate_RevokedDelegate_Reverts() public {
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, false);

        vm.prank(delegate);
        vm.expectRevert("Not authorized delegate");
        marketplace.createSessionFromDepositForModelAsDelegate(
            depositor, modelId, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
    }

    function test_CreateSessionForModelAsDelegate_DepositorCanCreateDirectly() public {
        // Depositor should still be able to create sessions for themselves
        vm.prank(depositor);
        uint256 sessionId = marketplace.createSessionFromDepositForModelAsDelegate(
            depositor, modelId, host, address(0), depositAmount, pricePerToken, maxDuration, proofInterval, proofTimeoutWindow
        );
        assertGt(sessionId, 0);
    }
}
