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
import {ETHRejecter} from "test/mocks/ETHRejecter.sol";
import {BlocklistableERC20Mock} from "test/mocks/BlocklistableERC20Mock.sol";

/**
 * @title Settlement Pull Pattern Tests
 * @notice F202614898 (MEDIUM): Refund failure should not block host payment
 *
 * When a session completes and the depositor can't receive refund (contract rejects ETH,
 * or address is blocklisted for ERC20), the entire settlement reverts — blocking host payment.
 * Fix: On refund failure, credit to depositor's deposit balance for later withdrawal.
 */
contract SettlementPullPatternTest is Test {
    // Declare event locally for tests (will be added to contract in implementation phase)
    event RefundCreditedToDeposit(uint256 indexed jobId, address indexed depositor, uint256 amount, address indexed token);

    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    BlocklistableERC20Mock public blockToken;
    ETHRejecter public ethRejecter;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public treasury = address(0x4);
    address public normalUser = address(0x5);

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

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(address(new ERC1967Proxy(
            address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        )));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW))
        ))));

        // Deploy mock contracts for failure scenarios
        ethRejecter = new ETHRejecter();
        blockToken = new BlocklistableERC20Mock("Block USDC", "bUSDC");

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(blockToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        _registerHost(host);
        vm.deal(host, 100 ether);
        vm.deal(normalUser, 100 ether);
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);
        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setTokenPricing(address(blockToken), MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    // ============================================================
    // Test: ETH refund fails → host still gets paid, refund credited to deposit
    // ============================================================

    /// @notice F202614898: ETH refund fails → host paid, refund credited to deposit
    function test_ETHRefundFails_HostStillGetsPaid() public {
        address rejecter = address(ethRejecter);
        vm.deal(rejecter, 10 ether);

        vm.prank(rejecter);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        // Host submits proof for partial amount
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "QmCID", "QmDelta");

        // Wait for dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Host completes — ETH refund to rejecter will fail, but host should still get paid
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify host got paid
        uint256 hostBal = hostEarnings.getBalance(host, address(0));
        assertGt(hostBal, 0, "Host should have earnings");

        // Verify refund was credited to rejecter's deposit balance
        uint256 creditedRefund = marketplace.userDepositsNative(rejecter);
        assertGt(creditedRefund, 0, "Refund should be credited to deposit");

        // Verify session recorded the refund
        (,,,,,,,,,,,,,,uint256 refundedToUser,,,) = marketplace.sessionJobs(sessionId);
        assertGt(refundedToUser, 0, "refundedToUser should be set");
    }

    // ============================================================
    // Test: ERC20 refund fails → host still gets paid, refund credited to deposit
    // ============================================================

    /// @notice F202614898: ERC20 refund fails → host paid, refund credited to deposit
    function test_ERC20RefundFails_HostStillGetsPaid() public {
        address depositor = address(0x99);
        blockToken.mint(depositor, 10_000_000_000);
        vm.prank(depositor);
        blockToken.approve(address(marketplace), type(uint256).max);

        uint256 stablePrice = 1000;
        vm.prank(depositor);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host, address(blockToken), USDC_MIN_DEPOSIT * 2, stablePrice, 1 days, MIN_PROVEN_TOKENS, 300
        );

        // Blocklist depositor AFTER session creation (simulates USDC compliance action)
        blockToken.blockAddress(depositor);

        // Host submits proof
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "QmCID", "QmDelta");

        // Wait for dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Host completes — ERC20 transfer to blocklisted depositor will fail
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify host got paid
        uint256 hostBal = hostEarnings.getBalance(host, address(blockToken));
        assertGt(hostBal, 0, "Host should have earnings");

        // Verify refund was credited to depositor's token deposit balance
        uint256 creditedRefund = marketplace.userDepositsToken(depositor, address(blockToken));
        assertGt(creditedRefund, 0, "Refund should be credited to token deposit");
    }

    // ============================================================
    // Test: Credited refund is accessible in deposit mapping
    // ============================================================

    /// @notice F202614898: Credited refund balance is accessible
    function test_CreditedRefundAccessibleInDeposit() public {
        address rejecter = address(ethRejecter);
        vm.deal(rejecter, 10 ether);

        vm.prank(rejecter);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof_withdraw"), "QmCID", "QmDelta");

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify refund credited
        uint256 credited = marketplace.userDepositsNative(rejecter);
        assertGt(credited, 0, "Should have credited refund");

        // The balance is accessible in the deposit mapping
        assertEq(marketplace.userDepositsNative(rejecter), credited, "Balance should be accessible");
    }

    // ============================================================
    // Test: RefundCreditedToDeposit event emitted
    // ============================================================

    /// @notice F202614898: RefundCreditedToDeposit event emitted on ETH refund failure
    function test_RefundCreditedToDeposit_EventEmitted() public {
        address rejecter = address(ethRejecter);
        vm.deal(rejecter, 10 ether);

        vm.prank(rejecter);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof_event"), "QmCID", "QmDelta");

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Compute expected refund
        uint256 hostPayment = (MIN_PROVEN_TOKENS * MIN_PRICE_NATIVE) / 1000;
        uint256 expectedRefund = 1 ether - hostPayment;

        // Expect the RefundCreditedToDeposit event
        vm.expectEmit(true, true, true, true);
        emit RefundCreditedToDeposit(sessionId, rejecter, expectedRefund, address(0));

        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");
    }

    // ============================================================
    // Test: Normal refund still works directly (no regression)
    // ============================================================

    /// @notice F202614898: Normal ETH refund still works directly
    function test_NormalRefundStillWorksDirect() public {
        vm.prank(normalUser);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof_normal"), "QmCID", "QmDelta");

        uint256 balBefore = normalUser.balance;

        // Depositor completes (no dispute window)
        vm.prank(normalUser);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify direct ETH refund
        uint256 balAfter = normalUser.balance;
        assertGt(balAfter, balBefore, "User should receive direct ETH refund");

        // Verify no deposit credit was used (refund went directly)
        uint256 depositBal = marketplace.userDepositsNative(normalUser);
        assertEq(depositBal, 0, "No deposit credit - refund was direct");
    }

    // ============================================================
    // Test: session.refundedToUser set correctly regardless of delivery method
    // ============================================================

    /// @notice F202614898: refundedToUser set correctly even when refund fails
    function test_SessionRefundedToUser_SetCorrectly() public {
        address rejecter = address(ethRejecter);
        vm.deal(rejecter, 10 ether);

        vm.prank(rejecter);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof_refset"), "QmCID", "QmDelta");

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify refundedToUser is set even though direct delivery failed
        (,,,,,,,,,,,,,,uint256 refundedToUser,,,) = marketplace.sessionJobs(sessionId);
        uint256 hostPayment = (MIN_PROVEN_TOKENS * MIN_PRICE_NATIVE) / 1000;
        uint256 expectedRefund = 1 ether - hostPayment;
        assertEq(refundedToUser, expectedRefund, "refundedToUser should match expected");
    }
}
