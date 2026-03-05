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

/**
 * @title Timeout No Early Fee Tests
 * @notice F202615257 (MEDIUM): Early Cancel Fee Applied on Depositor-Triggered Timeouts
 *
 * When depositor calls triggerSessionTimeout() after host inactivity, the early cancel fee
 * should NOT be charged. Only voluntary cancellations via completeSessionJob() should incur
 * the early cancel fee.
 */
contract TimeoutNoEarlyFeeTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdc;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public depositor = address(0x3);
    address public treasury = address(0x4);
    address public thirdParty = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant TOKEN_PRICE = 1000;
    uint256 constant MIN_PROVEN_TOKENS = 100;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;
    uint256 constant MIN_TOKENS_FEE = 500;
    uint256 constant PROOF_TIMEOUT = 300;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdc = new ERC20Mock("USD Coin", "USDC");

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

        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasury(treasury);
        marketplace.addAcceptedToken(address(usdc), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        marketplace.setMinTokensFee(MIN_TOKENS_FEE);
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        _registerHost();
    }

    function _registerHost() internal {
        fabToken.mint(host, MIN_STAKE);
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(usdc), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        vm.stopPrank();
    }

    function _createSession(uint256 deposit) internal returns (uint256) {
        usdc.mint(depositor, deposit);
        vm.prank(depositor);
        usdc.approve(address(marketplace), type(uint256).max);
        vm.prank(depositor);
        return marketplace.createSessionJobForModelWithToken(
            host, modelId, address(usdc), deposit, TOKEN_PRICE, 1 days, MIN_PROVEN_TOKENS, PROOF_TIMEOUT
        );
    }

    // ============================================================
    // Test: Depositor triggers timeout with no proofs → full refund (no early fee)
    // ============================================================

    /// @notice F202615257: Depositor should NOT be charged early fee on timeout
    function test_Timeout_NoEarlyFee_WhenDepositorTriggers() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Advance past proofTimeoutWindow (host never submits proof)
        vm.warp(block.timestamp + PROOF_TIMEOUT + 1);

        // Depositor calls triggerSessionTimeout
        vm.prank(depositor);
        marketplace.triggerSessionTimeout(sessionId);

        // Depositor should get full refund — no early fee
        uint256 depositorBal = usdc.balanceOf(depositor);
        assertEq(depositorBal, deposit, "Depositor should get full refund on timeout (no early fee)");

        // Host should get zero (no proofs)
        uint256 hostBal = hostEarnings.getBalance(host, address(usdc));
        assertEq(hostBal, 0, "Host should get zero when no proofs on timeout");
    }

    // ============================================================
    // Test: Third party triggers timeout with no proofs → no early fee
    // ============================================================

    /// @notice F202615257: Third party triggering timeout should also not charge early fee
    function test_Timeout_NoEarlyFee_WhenThirdPartyTriggers() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Advance past proofTimeoutWindow
        vm.warp(block.timestamp + PROOF_TIMEOUT + 1);

        // Third party triggers timeout
        vm.prank(thirdParty);
        marketplace.triggerSessionTimeout(sessionId);

        // Depositor should get full refund
        uint256 depositorBal = usdc.balanceOf(depositor);
        assertEq(depositorBal, deposit, "Depositor should get full refund when third party triggers timeout");
    }

    // ============================================================
    // Test: Depositor completes voluntarily with no proofs → early fee IS charged (regression)
    // ============================================================

    /// @notice F202615257: Voluntary cancel should still charge early fee (regression test)
    function test_VoluntaryCancel_EarlyFeeCharged() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Advance past dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Depositor voluntarily completes (no proofs)
        vm.prank(depositor);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Early fee should be charged: minTokensFee * pricePerToken / PRICE_PRECISION
        uint256 expectedEarlyFee = (MIN_TOKENS_FEE * TOKEN_PRICE) / 1000;
        uint256 depositorBal = usdc.balanceOf(depositor);
        assertEq(depositorBal, deposit - expectedEarlyFee, "Depositor should be charged early fee on voluntary cancel");

        // Host should receive the early fee (minus treasury cut)
        uint256 hostBal = hostEarnings.getBalance(host, address(usdc));
        assertGt(hostBal, 0, "Host should receive early fee on voluntary cancel");
    }

    // ============================================================
    // Test: Host payment is zero when no proofs exist in both paths
    // ============================================================

    /// @notice F202615257: Host gets zero when no proofs exist (timeout path)
    function test_Timeout_HostPaymentZero_NoProofs() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        vm.warp(block.timestamp + PROOF_TIMEOUT + 1);

        vm.prank(depositor);
        marketplace.triggerSessionTimeout(sessionId);

        // Verify host earnings are zero
        uint256 hostBal = hostEarnings.getBalance(host, address(usdc));
        assertEq(hostBal, 0, "Host payment must be zero on timeout with no proofs");

        // Verify session refund equals full deposit
        (, , , , , , , , , , , , , , uint256 refundedToUser, , , ) = marketplace.sessionJobs(sessionId);
        assertEq(refundedToUser, deposit, "Full deposit should be refunded on timeout");
    }

    // ============================================================
    // Test: ETH timeout also has no early fee
    // ============================================================

    /// @notice F202615257: ETH session timeout should also not charge early fee
    function test_Timeout_NoEarlyFee_ETHSession() public {
        uint256 deposit = 1 ether;

        vm.prank(depositor);
        vm.deal(depositor, deposit);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, PROOF_TIMEOUT
        );

        uint256 balBefore = depositor.balance;

        // Advance past proofTimeoutWindow
        vm.warp(block.timestamp + PROOF_TIMEOUT + 1);

        vm.prank(depositor);
        marketplace.triggerSessionTimeout(sessionId);

        // Depositor should get full refund
        uint256 balAfter = depositor.balance;
        assertEq(balAfter - balBefore, deposit, "ETH depositor should get full refund on timeout");
    }
}
