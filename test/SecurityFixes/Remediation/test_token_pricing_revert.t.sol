// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/// @notice F202614977: Require per-token pricing, remove silent fallback
contract TokenPricingRevertTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public daiToken; // second ERC20 to test per-token behavior

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
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");
        daiToken = new ERC20Mock("DAI", "DAI");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("TestModel/Repo", "model.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("TestModel/Repo", "model.gguf");

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(address(new ERC1967Proxy(
            address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        )));

        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW))
        ))));

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdcToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host (no setTokenPricing yet — tests verify revert behavior)
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();

        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);
    }

    // -------------------------------------------------------
    // getNodePricing — revert on missing ERC20 pricing
    // -------------------------------------------------------

    function test_GetNodePricing_RevertsWhenNoTokenPricingSet() public {
        vm.expectRevert("No token pricing");
        nodeRegistry.getNodePricing(host, address(usdcToken));
    }

    function test_GetNodePricing_ReturnsCustomPriceWhenSet() public {
        vm.prank(host);
        nodeRegistry.setTokenPricing(address(usdcToken), MIN_PRICE_STABLE);

        uint256 price = nodeRegistry.getNodePricing(host, address(usdcToken));
        assertEq(price, MIN_PRICE_STABLE);
    }

    function test_GetNodePricing_NativePathUnchanged() public {
        // address(0) path should still return minPricePerTokenNative
        uint256 price = nodeRegistry.getNodePricing(host, address(0));
        assertEq(price, MIN_PRICE_NATIVE);
    }

    function test_GetNodePricing_RevertsForDifferentUnconfiguredToken() public {
        // Set pricing for USDC but not DAI
        vm.prank(host);
        nodeRegistry.setTokenPricing(address(usdcToken), MIN_PRICE_STABLE);

        // USDC works
        uint256 price = nodeRegistry.getNodePricing(host, address(usdcToken));
        assertEq(price, MIN_PRICE_STABLE);

        // DAI reverts
        vm.expectRevert("No token pricing");
        nodeRegistry.getNodePricing(host, address(daiToken));
    }

    function test_GetNodePricing_ClearPricingMakesItRevertAgain() public {
        // Set then clear
        vm.startPrank(host);
        nodeRegistry.setTokenPricing(address(usdcToken), MIN_PRICE_STABLE);
        nodeRegistry.setTokenPricing(address(usdcToken), 0); // clear
        vm.stopPrank();

        vm.expectRevert("No token pricing");
        nodeRegistry.getNodePricing(host, address(usdcToken));
    }

    // -------------------------------------------------------
    // getModelPricing — revert on missing ERC20 pricing
    // -------------------------------------------------------

    function test_GetModelPricing_RevertsWhenNoModelOverrideAndNoCustomPricing() public {
        vm.expectRevert("No token pricing");
        nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
    }

    function test_GetModelPricing_ReturnsModelOverrideWhenSet() public {
        uint256 stableOverride = 50;
        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, MIN_PRICE_NATIVE, stableOverride);

        uint256 price = nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
        assertEq(price, stableOverride);
    }

    function test_GetModelPricing_FallsBackToCustomTokenPricing() public {
        // No model override, but customTokenPricing is set
        vm.prank(host);
        nodeRegistry.setTokenPricing(address(usdcToken), 42);

        uint256 price = nodeRegistry.getModelPricing(host, modelId, address(usdcToken));
        assertEq(price, 42);
    }

    function test_GetModelPricing_NativePathUnchanged() public {
        uint256 price = nodeRegistry.getModelPricing(host, modelId, address(0));
        assertEq(price, MIN_PRICE_NATIVE);
    }

    function test_GetModelPricing_UnregisteredNodeReturnsZero() public {
        address nonRegistered = address(0xDEAD);
        uint256 price = nodeRegistry.getModelPricing(nonRegistered, modelId, address(usdcToken));
        assertEq(price, 0);
    }

    // -------------------------------------------------------
    // Integration: createSessionJobWithToken
    // -------------------------------------------------------

    function test_CreateSessionWithToken_RevertsWhenHostHasNoTokenPricing() public {
        uint256 deposit = 1_000_000;
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), deposit);

        vm.expectRevert("No token pricing");
        marketplace.createSessionJobWithToken(
            host, address(usdcToken), deposit, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
        vm.stopPrank();
    }

    function test_CreateSessionWithToken_SucceedsAfterSetTokenPricing() public {
        // Host sets pricing
        vm.prank(host);
        nodeRegistry.setTokenPricing(address(usdcToken), MIN_PRICE_STABLE);

        uint256 deposit = 1_000_000;
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), deposit);
        marketplace.createSessionJobWithToken(
            host, address(usdcToken), deposit, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
        vm.stopPrank();

        // Session was created — nextJobId should have advanced
        uint256 nextId = marketplace.nextJobId();
        assertGt(nextId, 0);
    }
}
