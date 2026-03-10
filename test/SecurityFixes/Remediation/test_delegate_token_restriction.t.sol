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
 * @title Delegate Token Restriction Tests (Phase 32)
 * @notice Tests that DelegateConfig.allowedToken restricts which payment token a delegate can use
 */
contract DelegateTokenRestrictionTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public otherToken;

    address public owner = address(0x1);
    address public hostAddr = address(0x2);
    address public payer = address(0x3);
    address public delegate = address(0x4);
    address public treasury = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant SESSION_AMOUNT = 10_000_000; // 10 USDC

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");
        otherToken = new ERC20Mock("OTHER", "OTH");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(
                address(modelRegistryImpl),
                abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
            )
        );
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);
        modelRegistry.addTrustedModel("ModelA/Repo", "modelA.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("ModelA/Repo", "modelA.gguf");

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

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(
            new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
        );
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()))
        );
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

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
        marketplace.addAcceptedToken(address(otherToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host with model and pricing for both tokens
        fabToken.mint(hostAddr, MIN_STAKE);
        vm.startPrank(hostAddr);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(otherToken), MIN_PRICE_STABLE);
        vm.stopPrank();

        // Fund payer and approve both tokens
        usdcToken.mint(payer, 1_000_000_000_000);
        otherToken.mint(payer, 1_000_000_000_000);
        vm.startPrank(payer);
        usdcToken.approve(address(marketplace), type(uint256).max);
        otherToken.approve(address(marketplace), type(uint256).max);
        vm.stopPrank();
    }

    // ============================================================
    // Test 1: Delegate restricted to USDC succeeds with USDC
    // ============================================================

    /// @notice Delegate restricted to USDC can create session with USDC
    function test_DelegateTokenRestriction_CorrectToken_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0), address(usdcToken));

        vm.prank(delegate);
        uint256 sid = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertGt(sid, 0);
    }

    // ============================================================
    // Test 2: Delegate restricted to USDC reverts with other token
    // ============================================================

    /// @notice Delegate restricted to USDC cannot use a different token
    function test_DelegateTokenRestriction_WrongToken_Reverts() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0), address(usdcToken));

        vm.prank(delegate);
        vm.expectRevert("Wrong token");
        marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(otherToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
    }

    // ============================================================
    // Test 3: Delegate with allowedToken = address(0) can use any
    // ============================================================

    /// @notice Unrestricted delegate (allowedToken = 0) can use any accepted token
    function test_DelegateTokenRestriction_AnyToken_Succeeds() public {
        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0), address(0));

        // USDC works
        vm.prank(delegate);
        uint256 sid1 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(usdcToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertGt(sid1, 0);

        // otherToken also works
        vm.prank(delegate);
        uint256 sid2 = marketplace.createSessionForModelAsDelegate(
            payer, modelId, hostAddr, address(otherToken), SESSION_AMOUNT, MIN_PRICE_STABLE, 1 days, 1000, 300
        );
        assertGt(sid2, 0);
    }

    // ============================================================
    // Test 4: DelegateConfigured event includes allowedToken field
    // ============================================================

    /// @notice DelegateConfigured event emits allowedToken
    function test_DelegateConfigured_Event_IncludesAllowedToken() public {
        vm.expectEmit(true, true, false, true);
        emit JobMarketplaceWithModelsUpgradeable.DelegateConfigured(
            payer, delegate, 0, 0, 0, address(0), bytes32(0), address(usdcToken)
        );

        vm.prank(payer);
        marketplace.configureDelegate(delegate, 0, 0, 0, address(0), bytes32(0), address(usdcToken));
    }
}
