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
 * @title Model Approved Check Tests (F202615162)
 * @notice Tests for Phase 11: isModelApproved check at session creation
 *
 * Finding: F202615162 (MEDIUM)
 * Issue: Deactivated Model Still Usable for Sessions. Model-specific session
 *        functions only checked nodeSupportsModel() but not isModelApproved().
 *        A deactivated model could still be used if a host had it registered.
 * Fix: Add explicit isModelApproved() check in all 4 model session functions.
 */
contract ModelApprovedCheckTest is Test {
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
    address public delegate = address(0x6);

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

        // User pre-deposits funds for deposit-based tests
        vm.startPrank(user);
        marketplace.depositNative{value: 10 ether}();
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.depositToken(address(usdcToken), 1_000_000_000);
        vm.stopPrank();

        // Authorize delegate for delegate tests
        vm.prank(user);
        marketplace.authorizeDelegate(delegate, true);

        // Fund delegate's payer (user) with USDC allowance for delegate
        usdcToken.mint(user, 10_000_000_000);
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
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
    // Test: createSessionJobForModel reverts with deactivated model
    // ============================================================

    /// @notice F202615162: Deactivated model rejected at session creation (ETH)
    function test_CreateSessionJobForModel_DeactivatedModel_Reverts() public {
        vm.prank(owner);
        modelRegistry.deactivateModel(modelId);

        vm.prank(user);
        vm.expectRevert("Bad model");
        marketplace.createSessionJobForModel{value: 1 ether}(host, modelId, MIN_PRICE_NATIVE, 1 days, 100, 300);
    }

    /// @notice F202615162: Active model still works for createSessionJobForModel
    function test_CreateSessionJobForModel_ActiveModel_Succeeds() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, 100, 300
        );
        assertGt(sessionId, 0, "Session should be created");
    }

    // ============================================================
    // Test: createSessionJobForModelWithToken reverts with deactivated model
    // ============================================================

    /// @notice F202615162: Deactivated model rejected at session creation (Token)
    function test_CreateSessionJobForModelWithToken_DeactivatedModel_Reverts() public {
        vm.prank(owner);
        modelRegistry.deactivateModel(modelId);

        usdcToken.mint(user, 10_000_000_000);
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        vm.expectRevert("Bad model");
        marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, 100, 300
        );
        vm.stopPrank();
    }

    /// @notice F202615162: Active model still works for createSessionJobForModelWithToken
    function test_CreateSessionJobForModelWithToken_ActiveModel_Succeeds() public {
        usdcToken.mint(user, 10_000_000_000);
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, 100, 300
        );
        vm.stopPrank();
        assertGt(sessionId, 0, "Session should be created");
    }

    // ============================================================
    // Test: createSessionFromDepositForModel reverts with deactivated model
    // ============================================================

    /// @notice F202615162: Deactivated model rejected for deposit-based session
    function test_CreateSessionFromDepositForModel_DeactivatedModel_Reverts() public {
        vm.prank(owner);
        modelRegistry.deactivateModel(modelId);

        vm.prank(user);
        vm.expectRevert("Bad model");
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
    }

    /// @notice F202615162: Active model still works for createSessionFromDepositForModel
    function test_CreateSessionFromDepositForModel_ActiveModel_Succeeds() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.1 ether, MIN_PRICE_NATIVE, 1 hours, 100, 300
        );
        assertGt(sessionId, 0, "Session should be created");
    }

    // ============================================================
    // Test: createSessionForModelAsDelegate reverts with deactivated model
    // ============================================================

    /// @notice F202615162: Deactivated model rejected for delegate session
    function test_CreateSessionForModelAsDelegate_DeactivatedModel_Reverts() public {
        vm.prank(owner);
        modelRegistry.deactivateModel(modelId);

        vm.prank(delegate);
        vm.expectRevert("Bad model");
        marketplace.createSessionForModelAsDelegate(
            user, modelId, host, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, 100, 300
        );
    }

    /// @notice F202615162: Active model still works for createSessionForModelAsDelegate
    function test_CreateSessionForModelAsDelegate_ActiveModel_Succeeds() public {
        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            user, modelId, host, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, 100, 300
        );
        assertGt(sessionId, 0, "Session should be created");
    }
}
