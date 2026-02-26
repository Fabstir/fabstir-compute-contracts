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

/// @notice Phase 18B: Verify modelless JM functions removed + model-based functions still work
contract ModellessRemovalTest is Test {
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
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

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

        // Register host and set model-token pricing
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdcToken), MIN_PRICE_STABLE);
        vm.stopPrank();

        vm.deal(user, 100 ether);
        usdcToken.mint(user, 10_000_000_000);
    }

    // -------------------------------------------------------
    // Regression: model-based functions still work
    // -------------------------------------------------------

    function test_CreateSessionJobForModel_StillWorks() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJobForModel{value: 1 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
        assertGt(jobId, 0);
    }

    function test_CreateSessionJobForModelWithToken_StillWorks() public {
        uint256 deposit = 1_000_000;
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), deposit, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
        vm.stopPrank();
        assertGt(jobId, 0);
    }

    function test_CreateSessionFromDepositForModel_StillWorks() public {
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), 2_000_000);
        marketplace.depositToken(address(usdcToken), 2_000_000);
        uint256 jobId = marketplace.createSessionFromDepositForModel(
            modelId, host, address(usdcToken), 1_000_000, MIN_PRICE_STABLE, 1 days, MIN_PROVEN_TOKENS, 300
        );
        vm.stopPrank();
        assertGt(jobId, 0);
    }

    // -------------------------------------------------------
    // Removed JM functions — low-level call returns false
    // -------------------------------------------------------

    function test_CreateSessionJob_FunctionRemoved() public {
        (bool success,) = address(marketplace).call{value: 1 ether}(
            abi.encodeWithSignature(
                "createSessionJob(address,uint256,uint256,uint256,uint256)",
                host, MIN_PRICE_NATIVE, uint256(1 days), MIN_PROVEN_TOKENS, uint256(300)
            )
        );
        assertFalse(success, "createSessionJob should not exist");
    }

    function test_CreateSessionJobWithToken_FunctionRemoved() public {
        (bool success,) = address(marketplace).call(
            abi.encodeWithSignature(
                "createSessionJobWithToken(address,address,uint256,uint256,uint256,uint256,uint256)",
                host, address(usdcToken), uint256(1_000_000), MIN_PRICE_STABLE, uint256(1 days), MIN_PROVEN_TOKENS, uint256(300)
            )
        );
        assertFalse(success, "createSessionJobWithToken should not exist");
    }

    function test_CreateSessionFromDeposit_FunctionRemoved() public {
        (bool success,) = address(marketplace).call(
            abi.encodeWithSignature(
                "createSessionFromDeposit(address,address,uint256,uint256,uint256,uint256,uint256)",
                host, address(usdcToken), uint256(1_000_000), MIN_PRICE_STABLE, uint256(1 days), MIN_PROVEN_TOKENS, uint256(300)
            )
        );
        assertFalse(success, "createSessionFromDeposit should not exist");
    }
}
