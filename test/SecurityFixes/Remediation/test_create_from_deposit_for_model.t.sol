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
 * @title CreateFromDepositForModel Tests (AUDIT-F5)
 * @notice Tests for Phase 5: Add createSessionFromDepositForModel function
 *
 * Finding: AUDIT-F5
 * Slack Ref: slack-C0A61FZC8SH-p1769608000786449
 *
 * Issue: Users with pre-deposits cannot create model-specific sessions.
 * The existing createSessionFromDeposit() doesn't support modelId parameter.
 *
 * Fix: Add createSessionFromDepositForModel() function that:
 * - Validates model is approved
 * - Uses model-specific pricing
 * - Stores modelId in sessionModel mapping
 */
contract CreateFromDepositForModelTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x3);
    address public treasury = address(0x4);

    bytes32 public modelId;
    bytes32 public unapprovedModelId = keccak256("unapproved-model");

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_DEPOSIT = 0.001 ether;
    uint256 constant USDC_MIN_DEPOSIT = 500_000; // 0.5 USDC (6 decimals)
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000; // 1M USDC

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(
                address(modelRegistryImpl),
                abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
            )
        );
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(
            new ERC1967Proxy(
                address(nodeRegistryImpl),
                abi.encodeCall(
                    NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry))
                )
            )
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
            new ERC1967Proxy(
                address(marketplaceImpl),
                abi.encodeCall(
                    JobMarketplaceWithModelsUpgradeable.initialize,
                    (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW)
                )
            )
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Configure marketplace
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        // Authorize marketplace in HostEarnings and ProofSystem
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
        _registerHost(host);

        // Fund user and set up deposits
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000); // 10k USDC

        // User pre-deposits funds
        vm.startPrank(user);
        marketplace.depositNative{value: 1 ether}();
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.depositToken(address(usdcToken), 1_000_000_000); // 1000 USDC
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
    // Test: Successfully creates model session from pre-deposited ETH
    // ============================================================

    /**
     * @notice Verify createSessionFromDepositForModel works with ETH deposits
     * @dev Should create session, store modelId, and emit events
     */
    function test_CreateFromDepositForModel_Success_ETH() public {
        uint256 depositAmount = 0.1 ether;
        uint256 balanceBefore = marketplace.userDepositsNative(user);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId,
            host,
            address(0), // ETH
            depositAmount,
            MIN_PRICE_NATIVE,
            1 hours,
            100, // proofInterval
            300 // proofTimeoutWindow
        );

        // Verify session created
        assertGt(sessionId, 0, "Session ID should be > 0");

        // Verify deposit deducted from pre-deposit balance
        uint256 balanceAfter = marketplace.userDepositsNative(user);
        assertEq(balanceAfter, balanceBefore - depositAmount, "Deposit should be deducted");

        // Verify session details
        (
            uint256 id,
            address depositor,
            address sessionHost,
            address paymentToken,
            uint256 deposit,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(sessionHost, host, "Host should match");
        assertEq(paymentToken, address(0), "Payment token should be ETH (address(0))");
        assertEq(deposit, depositAmount, "Deposit should match");
    }

    // ============================================================
    // Test: Successfully creates model session from pre-deposited USDC
    // ============================================================

    /**
     * @notice Verify createSessionFromDepositForModel works with USDC deposits
     */
    function test_CreateFromDepositForModel_Success_USDC() public {
        uint256 depositAmount = 100_000_000; // 100 USDC
        uint256 balanceBefore = marketplace.userDepositsToken(user, address(usdcToken));

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId,
            host,
            address(usdcToken),
            depositAmount,
            MIN_PRICE_STABLE,
            1 hours,
            100,
            300
        );

        // Verify session created
        assertGt(sessionId, 0, "Session ID should be > 0");

        // Verify deposit deducted from pre-deposit balance
        uint256 balanceAfter = marketplace.userDepositsToken(user, address(usdcToken));
        assertEq(balanceAfter, balanceBefore - depositAmount, "Token deposit should be deducted");

        // Verify session uses correct token
        (,, , address paymentToken, uint256 deposit,,,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(paymentToken, address(usdcToken), "Payment token should be USDC");
        assertEq(deposit, depositAmount, "Deposit should match");
    }

    // ============================================================
    // Test: Reverts for unapproved model
    // ============================================================

    /**
     * @notice Verify function reverts when model is not supported by host
     * @dev Since hosts can only register with approved models, an unapproved model
     *      will never be supported by any host, resulting in "Host does not support model"
     */
    function test_CreateFromDepositForModel_UnapprovedModel_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Host does not support model");
        marketplace.createSessionFromDepositForModel(
            unapprovedModelId, // Not supported by host
            host,
            address(0),
            0.1 ether,
            MIN_PRICE_NATIVE,
            1 hours,
            100,
            300
        );
    }

    // ============================================================
    // Test: Reverts for insufficient deposit
    // ============================================================

    /**
     * @notice Verify function reverts when user has insufficient pre-deposit
     */
    function test_CreateFromDepositForModel_InsufficientDeposit_Reverts() public {
        // Try to use more than deposited
        uint256 excessiveAmount = 2 ether; // User only deposited 1 ETH

        vm.prank(user);
        vm.expectRevert("Insufficient native balance");
        marketplace.createSessionFromDepositForModel(
            modelId,
            host,
            address(0),
            excessiveAmount,
            MIN_PRICE_NATIVE,
            1 hours,
            100,
            300
        );
    }

    // ============================================================
    // Test: Stores modelId in sessionModel mapping
    // ============================================================

    /**
     * @notice Verify modelId is stored in sessionModel mapping
     */
    function test_CreateFromDepositForModel_StoresModelId() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId,
            host,
            address(0),
            0.1 ether,
            MIN_PRICE_NATIVE,
            1 hours,
            100,
            300
        );

        // Verify modelId stored
        bytes32 storedModelId = marketplace.sessionModel(sessionId);
        assertEq(storedModelId, modelId, "Model ID should be stored");
    }

    // ============================================================
    // Test: Uses model-specific pricing from NodeRegistry
    // ============================================================

    /**
     * @notice Verify function validates price against model-specific pricing
     */
    function test_CreateFromDepositForModel_UsesModelPricing() public {
        // Set model-specific pricing higher than default (nativePrice, stablePrice)
        uint256 higherModelPrice = MIN_PRICE_NATIVE * 2;
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, higherModelPrice, MIN_PRICE_STABLE);

        // Try to create session with default price (lower than model price)
        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionFromDepositForModel(
            modelId,
            host,
            address(0),
            0.1 ether,
            MIN_PRICE_NATIVE, // Below model-specific price
            1 hours,
            100,
            300
        );

        // Now create with correct model-specific price - should succeed
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId,
            host,
            address(0),
            0.1 ether,
            higherModelPrice,
            1 hours,
            100,
            300
        );

        assertGt(sessionId, 0, "Session should be created with correct model price");
    }

    // ============================================================
    // Test: Reverts for zero modelId
    // ============================================================

    /**
     * @notice Verify function reverts when modelId is bytes32(0)
     */
    function test_CreateFromDepositForModel_ZeroModelId_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid model ID");
        marketplace.createSessionFromDepositForModel(
            bytes32(0), // Invalid
            host,
            address(0),
            0.1 ether,
            MIN_PRICE_NATIVE,
            1 hours,
            100,
            300
        );
    }

    // ============================================================
    // Test: Validates host supports model
    // ============================================================

    /**
     * @notice Verify function checks that host supports the model
     */
    function test_CreateFromDepositForModel_HostDoesNotSupportModel_Reverts() public {
        // Add a new model that host doesn't support
        vm.prank(owner);
        modelRegistry.addTrustedModel("Model2/Repo", "model2.gguf", bytes32(uint256(2)));
        bytes32 unsupportedModelId = modelRegistry.getModelId("Model2/Repo", "model2.gguf");

        vm.prank(user);
        vm.expectRevert("Host does not support model");
        marketplace.createSessionFromDepositForModel(
            unsupportedModelId,
            host,
            address(0),
            0.1 ether,
            MIN_PRICE_NATIVE,
            1 hours,
            100,
            300
        );
    }
}
