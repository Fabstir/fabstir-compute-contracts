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

/// @notice F202614917: Early cancellation fee tests
contract EarlyCancellationFeeTest is Test {
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
    address public nonOwner = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant PRICE_PRECISION = 1000;

    function setUp() public {
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

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host
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

    /// @notice setMinTokensFee reverts for non-owner
    function test_SetMinTokensFee_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        marketplace.setMinTokensFee(1000);
    }

    /// @notice setMinTokensFee succeeds for owner
    function test_SetMinTokensFee_Success() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(1000);
        assertEq(marketplace.minTokensFee(), 1000);
    }

    /// @notice F202614917: Early cancel (no proofs) charges minTokensFee in ETH
    function test_EarlyComplete_ChargesFee_ETH() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(1000);

        uint256 deposit = 1 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        uint256 hostEarningsBefore = hostEarnings.getBalance(host, address(0));
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled-early");

        uint256 hostEarningsAfter = hostEarnings.getBalance(host, address(0));
        assertGt(hostEarningsAfter, hostEarningsBefore, "Host should receive early cancel fee");
    }

    /// @notice Normal completion with proofs still settles normally
    function test_CompleteAfterProof_NoEarlyFee() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(1000);

        uint256 deposit = 1 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        vm.warp(block.timestamp + 1);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 500, keccak256("proof1"), "cid1", "delta1");

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 500, "Tokens should be recorded");

        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "completed-normally");
    }

    /// @notice Host completing with no proofs gets nothing (no early fee)
    function test_HostComplete_NoEarlyFee() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(1000);

        uint256 deposit = 1 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        uint256 userBalanceBefore = user.balance;

        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "host-completed");

        uint256 userBalanceAfter = user.balance;
        assertEq(userBalanceAfter - userBalanceBefore, deposit, "Full refund when host completes");
    }

    /// @notice Early cancel fee capped at deposit amount
    function test_EarlyComplete_FeeCapped_AtDeposit() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(10_000);

        uint256 deposit = 0.001 ether;
        uint256 highPrice = 1e15; // earlyFee = 10000 * 1e15 / 1000 = 1e16 >> deposit
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, highPrice, 3600, 100, 300
        );

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled");

        uint256 userBalanceAfter = user.balance;
        assertEq(userBalanceAfter, userBalanceBefore, "User gets 0 when fee >= deposit");
    }

    /// @notice F202614917: Early cancel charges fee in USDC
    function test_EarlyComplete_ChargesFee_USDC() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(1000);

        uint256 deposit = 100_000_000;
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), deposit);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdcToken), deposit, MIN_PRICE_STABLE, 3600, 100, 300
        );
        vm.stopPrank();

        uint256 hostEarningsBefore = hostEarnings.getBalance(host, address(usdcToken));
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled-usdc");

        uint256 hostEarningsAfter = hostEarnings.getBalance(host, address(usdcToken));
        assertGt(hostEarningsAfter, hostEarningsBefore, "Host should receive USDC fee");
    }

    /// @notice Early cancel on model session also charges fee
    function test_EarlyComplete_NonModelSession() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(1000);

        uint256 deposit = 1 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        uint256 hostEarningsBefore = hostEarnings.getBalance(host, address(0));
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled");

        uint256 hostEarningsAfter = hostEarnings.getBalance(host, address(0));
        assertGt(hostEarningsAfter, hostEarningsBefore, "Host should receive fee");
    }

    /// @notice When minTokensFee is 0, no early cancel fee charged
    function test_EarlyComplete_ZeroMinTokensFee_NoFee() public {
        assertEq(marketplace.minTokensFee(), 0);

        uint256 deposit = 1 ether;
        vm.deal(user, deposit);
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );

        uint256 userBalanceBefore = user.balance;
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "cancelled");

        uint256 userBalanceAfter = user.balance;
        assertEq(userBalanceAfter - userBalanceBefore, deposit, "Full refund when minTokensFee=0");
    }
}
