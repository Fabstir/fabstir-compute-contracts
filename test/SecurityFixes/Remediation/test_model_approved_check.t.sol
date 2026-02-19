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
 * @title Model Approved Check Tests
 * @notice GAP 3 / Finding #11 (LOW): Model session functions must check isModelApproved
 *
 * Currently, model session functions only check nodeSupportsModel (host registered with model).
 * But if a model is deactivated AFTER host registered, the host still "supports" it.
 * We need an explicit isModelApproved() check to prevent sessions with deactivated models.
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
    address public delegate = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;
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

        // Register host with the model (while model is still active)
        _registerHost(host);

        // Fund user
        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);

        // User deposits for deposit-based tests
        vm.startPrank(user);
        marketplace.depositNative{value: 10 ether}();
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.depositToken(address(usdcToken), 5_000_000_000);
        vm.stopPrank();

        // Authorize delegate for user
        vm.prank(user);
        marketplace.authorizeDelegate(delegate, true);

        // Fund delegate's payer (user) with USDC approval for delegate tests
        // The delegate pulls from user's wallet via transferFrom
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // NOW deactivate the model (host still "supports" it from registration)
        vm.prank(owner);
        modelRegistry.deactivateModel(modelId);
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
    // Test: createSessionJobForModel with deactivated model reverts
    // ============================================================

    function test_CreateSessionJobForModel_DeactivatedModel_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Model not approved");
        marketplace.createSessionJobForModel{value: 1 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Test: createSessionJobForModelWithToken with deactivated model reverts
    // ============================================================

    function test_CreateSessionJobForModelWithToken_DeactivatedModel_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Model not approved");
        marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Test: createSessionFromDepositForModel with deactivated model reverts
    // ============================================================

    function test_CreateSessionFromDepositForModel_DeactivatedModel_Reverts() public {
        vm.prank(user);
        vm.expectRevert("Model not approved");
        marketplace.createSessionFromDepositForModel(
            modelId, host, address(0), 0.5 ether, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Test: createSessionForModelAsDelegate with deactivated model reverts
    // ============================================================

    function test_CreateSessionForModelAsDelegate_DeactivatedModel_Reverts() public {
        vm.prank(delegate);
        vm.expectRevert(JobMarketplaceWithModelsUpgradeable.BadDelegateParams.selector);
        marketplace.createSessionForModelAsDelegate(
            user, modelId, host, address(usdcToken), USDC_MIN_DEPOSIT, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    // ============================================================
    // Sanity: active model succeeds (reactivate then create)
    // ============================================================

    function test_CreateSessionJobForModel_ActiveModel_Succeeds() public {
        // Reactivate the model
        vm.prank(owner);
        modelRegistry.reactivateModel(modelId);

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
        assertGt(sessionId, 0, "Session should be created");
    }
}
