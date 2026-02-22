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
 * @title CreateFromDepositForModel Tests (F202614916)
 * @notice Tests for Phase 9: Add createSessionFromDepositForModel function
 *
 * Finding: F202614916 (INFO)
 * Issue: Pre-deposited users cannot create model-specific sessions.
 * Fix: Add createSessionFromDepositForModel() that validates model,
 *       uses model-specific pricing, and stores modelId.
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
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;

    function setUp() public {
        vm.startPrank(owner);

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

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        _registerHost(host);

        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);

        // User pre-deposits funds
        vm.startPrank(user);
        marketplace.depositNative{value: 1 ether}();
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.depositToken(address(usdcToken), 1_000_000_000);
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

    function test_CreateFromDepositForModel_Success_ETH() public {
        uint256 depositAmount = 0.1 ether;
        uint256 balanceBefore = marketplace.userDepositsNative(user);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), depositAmount, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        assertGt(sessionId, 0, "Session ID should be > 0");

        uint256 balanceAfter = marketplace.userDepositsNative(user);
        assertEq(balanceAfter, balanceBefore - depositAmount, "Deposit should be deducted");

        (uint256 id, address depositor, address sessionHost, address paymentToken, uint256 deposit,,,,,,,,,,,,,) =
            marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
        assertEq(paymentToken, address(0));
        assertEq(deposit, depositAmount);
    }

    // ============================================================
    // Test: Successfully creates model session from pre-deposited USDC
    // ============================================================

    function test_CreateFromDepositForModel_Success_USDC() public {
        uint256 depositAmount = 100_000_000; // 100 USDC
        uint256 balanceBefore = marketplace.userDepositsToken(user, address(usdcToken));

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(usdcToken), depositAmount, MIN_PRICE_STABLE, 1 hours, 100, 300
        );

        assertGt(sessionId, 0);
        uint256 balanceAfter = marketplace.userDepositsToken(user, address(usdcToken));
        assertEq(balanceAfter, balanceBefore - depositAmount);

        (,,, address paymentToken, uint256 deposit,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(paymentToken, address(usdcToken));
        assertEq(deposit, depositAmount);
    }

    // ============================================================
    // Test: Stores modelId in sessionModel mapping
    // ============================================================

    function test_CreateFromDepositForModel_StoresModelId() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        assertEq(marketplace.sessionModel(sessionId), modelId, "Model ID should be stored");
    }

    // ============================================================
    // Test: Deducts from deposit balance
    // ============================================================

    function test_CreateFromDepositForModel_DeductsBalance() public {
        uint256 nativeBefore = marketplace.userDepositsNative(user);
        uint256 depositAmount = 0.1 ether;

        vm.prank(user);
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), depositAmount, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        assertEq(marketplace.userDepositsNative(user), nativeBefore - depositAmount);
    }

    // ============================================================
    // Test: Host must support model
    // ============================================================

    function test_CreateFromDepositForModel_HostDoesNotSupportModel_Reverts() public {
        vm.prank(owner);
        modelRegistry.addTrustedModel("Model2/Repo", "model2.gguf", bytes32(uint256(2)));
        bytes32 unsupportedModelId = modelRegistry.getModelId("Model2/Repo", "model2.gguf");

        vm.prank(user);
        vm.expectRevert("Model not supported");
        marketplace.createSessionFromDepositForModel(
            unsupportedModelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
    }

    // ============================================================
    // Test: Zero deposit reverts
    // ============================================================

    function test_CreateFromDepositForModel_ZeroModelId_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid model ID");
        marketplace.createSessionFromDepositForModel(
            bytes32(0), host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
    }

    // ============================================================
    // Test: Insufficient balance reverts
    // ============================================================

    function test_CreateFromDepositForModel_InsufficientDeposit_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 2 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
    }

    // ============================================================
    // Test: Uses model-specific pricing
    // ============================================================

    function test_CreateFromDepositForModel_UsesModelPricing() public {
        uint256 higherModelPrice = MIN_PRICE_NATIVE * 2;
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, higherModelPrice, MIN_PRICE_STABLE);

        // Below model price should revert
        vm.prank(user);
        vm.expectRevert("Price below host min");
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        // At model price should succeed
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.1 ether, higherModelPrice, 1 hours, 100, 300
        );
        assertGt(sessionId, 0);
    }
}
