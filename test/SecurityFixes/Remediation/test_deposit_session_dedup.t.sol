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
 * @title Deposit Session Deduplication Tests (F202614873)
 * @notice Regression tests for Phase 13: Code deduplication in createSessionFromDeposit
 *
 * Finding: F202614873 (INFO)
 * Issue: Code duplication between createSessionFromDeposit() and createSessionFromDepositForModel().
 * Fix: Extract _deductFromDeposit() helper and refactor both functions to use
 *       _validateSessionParams() and _initializeSession().
 *
 * These tests verify existing behavior is preserved through the refactoring.
 */
contract DepositSessionDedupTest is Test {
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
        marketplace.depositNative{value: 10 ether}();
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.depositToken(address(usdcToken), 5_000_000_000);
        vm.stopPrank();
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);
        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        vm.stopPrank();
    }

    // ============================================================
    // createSessionFromDeposit() — ETH success
    // ============================================================

    function test_CreateFromDeposit_ETH_Success() public {
        uint256 depositAmount = 0.1 ether;
        uint256 balanceBefore = marketplace.userDepositsNative(user);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), depositAmount, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        assertGt(sessionId, 0, "Session ID should be > 0");
        uint256 balanceAfter = marketplace.userDepositsNative(user);
        assertEq(balanceAfter, balanceBefore - depositAmount, "Native deposit should be deducted");

        (uint256 id, address depositor, address sessionHost, address paymentToken, uint256 deposit,,,,,,,,,,,,,) =
            marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
        assertEq(paymentToken, address(0));
        assertEq(deposit, depositAmount);
    }

    // ============================================================
    // createSessionFromDeposit() — Token success
    // ============================================================

    function test_CreateFromDeposit_Token_Success() public {
        uint256 depositAmount = 100_000_000; // 100 USDC
        uint256 balanceBefore = marketplace.userDepositsToken(user, address(usdcToken));

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(usdcToken), depositAmount, MIN_PRICE_STABLE, 1 hours, 100, 300
        );

        assertGt(sessionId, 0);
        uint256 balanceAfter = marketplace.userDepositsToken(user, address(usdcToken));
        assertEq(balanceAfter, balanceBefore - depositAmount, "Token deposit should be deducted");
    }

    // ============================================================
    // Zero deposit reverts
    // ============================================================

    function test_CreateFromDeposit_ZeroDeposit_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Zero deposit");
        marketplace.createSessionFromDepositForModel(modelId, host, address(0), 0, MIN_PRICE_NATIVE, 1 hours, 100, 300);
    }

    // ============================================================
    // Insufficient balance reverts (native)
    // ============================================================

    function test_CreateFromDeposit_InsufficientNativeBalance_Reverts() public {
        uint256 tooMuch = 50 ether; // User only deposited 10 ether

        vm.prank(user);
        vm.expectRevert("Low balance");
        marketplace.createSessionFromDepositForModel(modelId, host, address(0), tooMuch, MIN_PRICE_NATIVE, 1 hours, 100, 300);
    }

    // ============================================================
    // Insufficient balance reverts (token)
    // ============================================================

    function test_CreateFromDeposit_InsufficientTokenBalance_Reverts() public {
        uint256 tooMuch = 50_000_000_000; // User only deposited 5B

        vm.prank(user);
        vm.expectRevert("Low balance");
        marketplace.createSessionFromDepositForModel(modelId, host, address(usdcToken), tooMuch, MIN_PRICE_STABLE, 1 hours, 100, 300);
    }

    // ============================================================
    // Invalid host reverts
    // ============================================================

    function test_CreateFromDeposit_InvalidHost_Reverts() public {
        vm.prank(user);
        vm.expectRevert("No host");
        marketplace.createSessionFromDepositForModel(modelId, address(0), address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300);
    }

    // ============================================================
    // Invalid duration reverts
    // ============================================================

    function test_CreateFromDeposit_InvalidDuration_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Bad dur");
        marketplace.createSessionFromDepositForModel(modelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 0, 100, 300);
    }

    // ============================================================
    // Token not accepted reverts
    // ============================================================

    function test_CreateFromDeposit_TokenNotAccepted_Reverts() public {
        ERC20Mock randomToken = new ERC20Mock("Random", "RND");

        vm.prank(user);
        vm.expectRevert("Bad token");
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(randomToken), 100_000_000, MIN_PRICE_STABLE, 1 hours, 100, 300
        );
    }

    // ============================================================
    // createSessionFromDepositForModel() — valid params success
    // ============================================================

    function test_CreateFromDepositForModel_Success() public {
        uint256 depositAmount = 0.1 ether;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), depositAmount, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        assertGt(sessionId, 0, "Session ID should be > 0");

        (uint256 id, address depositor, address sessionHost,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(id, sessionId);
        assertEq(depositor, user);
        assertEq(sessionHost, host);
    }

    // ============================================================
    // createSessionFromDepositForModel() — stores model
    // ============================================================

    function test_CreateFromDepositForModel_StoresModel() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );

        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, modelId, "Model should be stored for session");
    }

    // ============================================================
    // Deactivated model reverts
    // ============================================================

    function test_CreateFromDepositForModel_DeactivatedModel_Reverts() public {
        bytes32 unapprovedModelId = keccak256("unapproved-model");

        vm.prank(user);
        vm.expectRevert("Bad model");
        marketplace.createSessionFromDepositForModel(
            unapprovedModelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
    }
}
