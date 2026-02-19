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
 * @title Deposit Session Deduplication Regression Tests
 * @notice GAP 5 / Finding #18 (LOW): Regression tests for createSessionFromDeposit refactoring
 *
 * These tests verify existing behavior is preserved after extracting shared helpers.
 * All tests should pass BEFORE and AFTER the refactoring.
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
    uint256 constant MIN_PROVEN_TOKENS = 100;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant MIN_DEPOSIT = 0.0001 ether;

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

        // Fund user
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);

        // User deposits both native and token
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
        vm.stopPrank();
    }

    // ============================================================
    // createSessionFromDeposit — ETH success
    // ============================================================

    function test_CreateSessionFromDeposit_ETH_Succeeds() public {
        uint256 balBefore = marketplace.userDepositsNative(user);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host, address(0), 0.5 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        assertGt(sessionId, 0, "Session ID > 0");
        uint256 balAfter = marketplace.userDepositsNative(user);
        assertEq(balAfter, balBefore - 0.5 ether, "Deposit deducted");
    }

    // ============================================================
    // createSessionFromDeposit — USDC success
    // ============================================================

    function test_CreateSessionFromDeposit_Token_Succeeds() public {
        uint256 balBefore = marketplace.userDepositsToken(user, address(usdcToken));

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        assertGt(sessionId, 0, "Session ID > 0");
        uint256 balAfter = marketplace.userDepositsToken(user, address(usdcToken));
        assertEq(balAfter, balBefore - USDC_MIN_DEPOSIT, "Token deposit deducted");
    }

    // ============================================================
    // Zero deposit reverts
    // ============================================================

    function test_CreateSessionFromDeposit_ZeroDeposit_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Zero deposit");
        marketplace.createSessionFromDeposit(
            host, address(0), 0, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Insufficient balance reverts
    // ============================================================

    function test_CreateSessionFromDeposit_InsufficientBalance_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Insufficient balance");
        marketplace.createSessionFromDeposit(
            host, address(0), 50 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Invalid host reverts
    // ============================================================

    function test_CreateSessionFromDeposit_InvalidHost_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionFromDeposit(
            address(0), address(0), 0.5 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Invalid duration reverts
    // ============================================================

    function test_CreateSessionFromDeposit_InvalidDuration_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Invalid duration");
        marketplace.createSessionFromDeposit(
            host, address(0), 0.5 ether, MIN_PRICE_NATIVE, 0, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Token not accepted reverts
    // ============================================================

    function test_CreateSessionFromDeposit_TokenNotAccepted_Reverts() public {
        address badToken = address(0xBAD);
        vm.prank(user);
        vm.expectRevert("Token not accepted");
        marketplace.createSessionFromDeposit(
            host, badToken, 1000, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // createSessionFromDepositForModel — success
    // ============================================================

    function test_CreateSessionFromDepositForModel_ValidParams_Succeeds() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.5 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        assertGt(sessionId, 0, "Session ID > 0");
    }

    // ============================================================
    // createSessionFromDepositForModel — stores model
    // ============================================================

    function test_CreateSessionFromDepositForModel_StoresModel() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.5 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, modelId, "Model should be stored");
    }

    // ============================================================
    // Deactivated model reverts (preserves GAP 3 check after refactor)
    // ============================================================

    function test_CreateSessionFromDepositForModel_DeactivatedModel_Reverts() public {
        vm.prank(owner);
        modelRegistry.deactivateModel(modelId);

        vm.prank(user);
        vm.expectRevert("Model not approved");
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.5 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }
}
