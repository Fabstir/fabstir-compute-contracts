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
 * @title Cancellation Integration Tests
 */
contract CancellationIntegrationTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    uint256 public hostPrivateKey = 0xA11CE;
    address public host;
    address public user = address(0x3);
    address public delegate = address(0x6);
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
        host = vm.addr(hostPrivateKey);
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

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
        marketplace.setMinTokensFee(1000);

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();

        vm.deal(user, 100 ether);
    }

    function test_BotAbuse_MultipleQuickCancels() public {
        uint256 hostEarningsBefore = hostEarnings.getBalance(host, address(0));

        for (uint256 i = 0; i < 3; i++) {
            vm.deal(user, 1 ether);
            vm.prank(user);
            uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
                host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
            );
            vm.prank(user);
            marketplace.completeSessionJob(sessionId, "bot-cancel");
        }

        uint256 hostEarningsAfter = hostEarnings.getBalance(host, address(0));
        uint256 singleFee = (1000 * MIN_PRICE_NATIVE) / 1000;
        assertEq(hostEarningsAfter - hostEarningsBefore, singleFee * 3, "Host receives 3x fees");
    }

    function test_DelegatedSession_DepositorCancel() public {
        usdcToken.mint(user, 1_000_000_000);
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        marketplace.authorizeDelegate(delegate, true);
        vm.stopPrank();

        vm.prank(delegate);
        uint256 sessionId = marketplace.createSessionForModelAsDelegate(
            user, modelId, host, address(usdcToken), 100_000_000, MIN_PRICE_STABLE, 3600, 100, 300
        );

        uint256 hostEarningsBefore = hostEarnings.getBalance(host, address(usdcToken));
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "depositor-cancel");

        uint256 hostEarningsAfter = hostEarnings.getBalance(host, address(usdcToken));
        uint256 expectedFee = (1000 * MIN_PRICE_STABLE) / 1000;
        assertEq(hostEarningsAfter - hostEarningsBefore, expectedFee, "Fee charged");
    }

    function test_FeeCalculation_Precision() public {
        uint256 expectedFee = (1000 * MIN_PRICE_NATIVE) / 1000;

        vm.deal(user, 1 ether);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        uint256 hostEarningsBefore = hostEarnings.getBalance(host, address(0));
        uint256 userBalanceBefore = user.balance;

        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancel");

        uint256 hostEarningsAfter = hostEarnings.getBalance(host, address(0));
        uint256 userBalanceAfter = user.balance;

        assertEq(hostEarningsAfter - hostEarningsBefore, expectedFee, "Host fee matches");
        assertEq(userBalanceAfter - userBalanceBefore, 1 ether - expectedFee, "Refund matches");
    }
}
