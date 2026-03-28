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
import {NoReturnToken} from "test/mocks/NoReturnToken.sol";
import {FalseReturnToken} from "test/mocks/FalseReturnToken.sol";
import {RevertingTransferToken} from "test/mocks/RevertingTransferToken.sol";

/**
 * @title Safe Refund Transfer Tests
 * @notice F202615254 (HIGH): Use of IERC20.transfer() Instead of SafeERC20.safeTransfer()
 *
 * The try/catch in _settleSessionPayments() uses raw IERC20.transfer(). Tokens that don't
 * return a bool (USDT-like) cause ABI decoding failure that bypasses the catch block.
 * Settlement reverts, permanently locking funds.
 */
contract SafeRefundTransferTest is Test {
    event RefundCreditedToDeposit(uint256 indexed jobId, address indexed depositor, uint256 amount, address indexed token);

    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public normalToken;
    NoReturnToken public noReturnToken;
    FalseReturnToken public falseReturnToken;
    RevertingTransferToken public revertingToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public depositor = address(0x3);
    address public treasury = address(0x4);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant TOKEN_PRICE = 1000; // Higher price so host actually earns (1000/1000 = 1 per token)
    uint256 constant MIN_PROVEN_TOKENS = 100;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        normalToken = new ERC20Mock("Normal Token", "NORM");
        noReturnToken = new NoReturnToken("NoReturn Token", "NRT");
        falseReturnToken = new FalseReturnToken("FalseReturn Token", "FRT");
        revertingToken = new RevertingTransferToken("Reverting Token", "RVT");

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
        marketplace.addAcceptedToken(address(normalToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        marketplace.addAcceptedToken(address(noReturnToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        marketplace.addAcceptedToken(address(falseReturnToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
        marketplace.addAcceptedToken(address(revertingToken), USDC_MIN_DEPOSIT, USDC_MAX_DEPOSIT);
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
        nodeRegistry.setModelTokenPricing(modelId, address(normalToken), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(noReturnToken), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(falseReturnToken), MIN_PRICE_STABLE);
        nodeRegistry.setModelTokenPricing(modelId, address(revertingToken), MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    function _createTokenSession(address token, uint256 deposit) internal returns (uint256) {
        vm.prank(depositor);
        return marketplace.createSessionJobForModelWithToken(
            host, modelId, token, deposit, TOKEN_PRICE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    function _submitProofAndComplete(uint256 sessionId, bytes32 proofHash) internal {
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, proofHash, "QmCID", "QmDelta");

        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");
    }

    // ============================================================
    // Test: NoReturnToken — settlement succeeds, direct transfer works
    // ============================================================

    /// @notice F202615254: Settlement with non-returning token succeeds via direct transfer
    function test_Settlement_NoReturnToken_DirectTransfer() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        noReturnToken.mint(depositor, deposit);
        vm.prank(depositor);
        noReturnToken.approve(address(marketplace), type(uint256).max);

        uint256 balBefore = noReturnToken.balanceOf(depositor);
        uint256 sessionId = _createTokenSession(address(noReturnToken), deposit);
        _submitProofAndComplete(sessionId, keccak256("proof_noreturn"));

        // Host should have earnings
        uint256 hostBal = hostEarnings.getBalance(host, address(noReturnToken));
        assertGt(hostBal, 0, "Host should have earnings");

        // Low-level call treats ret.length==0 as success → direct transfer works for USDT-like tokens
        uint256 balAfter = noReturnToken.balanceOf(depositor);
        assertGt(balAfter, balBefore - deposit, "Depositor should receive direct refund for NoReturnToken");

        // No deposit credit needed — direct transfer succeeded
        uint256 creditedRefund = marketplace.userDepositsToken(depositor, address(noReturnToken));
        assertEq(creditedRefund, 0, "No deposit credit needed for NoReturnToken");
    }

    // ============================================================
    // Test: FalseReturnToken — settlement succeeds, refund credited to deposit
    // ============================================================

    /// @notice F202615254: Settlement with false-returning token succeeds
    function test_Settlement_FalseReturnToken_CreditsDeposit() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        falseReturnToken.mint(depositor, deposit);
        vm.prank(depositor);
        falseReturnToken.approve(address(marketplace), type(uint256).max);

        uint256 sessionId = _createTokenSession(address(falseReturnToken), deposit);

        // Set depositor as fail target AFTER session creation (refund to depositor returns false)
        falseReturnToken.setFailTarget(depositor);
        _submitProofAndComplete(sessionId, keccak256("proof_falsereturn"));

        // Host should have earnings
        uint256 hostBal = hostEarnings.getBalance(host, address(falseReturnToken));
        assertGt(hostBal, 0, "Host should have earnings");

        // Refund credited to deposit (transfer returned false)
        uint256 creditedRefund = marketplace.userDepositsToken(depositor, address(falseReturnToken));
        assertGt(creditedRefund, 0, "Refund should be credited to deposit for FalseReturnToken");
    }

    // ============================================================
    // Test: RevertingToken — settlement succeeds, refund credited to deposit
    // ============================================================

    /// @notice F202615254: Settlement with reverting token succeeds
    function test_Settlement_RevertingToken_CreditsDeposit() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        revertingToken.mint(depositor, deposit);
        vm.prank(depositor);
        revertingToken.approve(address(marketplace), type(uint256).max);

        uint256 sessionId = _createTokenSession(address(revertingToken), deposit);

        // Set depositor as fail target AFTER session creation (refund to depositor reverts)
        revertingToken.setFailTarget(depositor);
        _submitProofAndComplete(sessionId, keccak256("proof_reverting"));

        // Host should have earnings
        uint256 hostBal = hostEarnings.getBalance(host, address(revertingToken));
        assertGt(hostBal, 0, "Host should have earnings");

        // Refund credited to deposit (transfer reverted)
        uint256 creditedRefund = marketplace.userDepositsToken(depositor, address(revertingToken));
        assertGt(creditedRefund, 0, "Refund should be credited to deposit for RevertingToken");
    }

    // ============================================================
    // Test: Normal ERC20 — direct transfer succeeds, no deposit credit
    // ============================================================

    /// @notice F202615254: Normal ERC20 token refund still works directly (regression)
    function test_Settlement_NormalToken_DirectTransfer() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        normalToken.mint(depositor, deposit);
        vm.prank(depositor);
        normalToken.approve(address(marketplace), type(uint256).max);

        uint256 sessionId = _createTokenSession(address(normalToken), deposit);

        uint256 balBefore = normalToken.balanceOf(depositor);
        _submitProofAndComplete(sessionId, keccak256("proof_normal"));
        uint256 balAfter = normalToken.balanceOf(depositor);

        // Direct transfer succeeded — balance increased
        assertGt(balAfter, balBefore, "Depositor should receive direct token refund");

        // No deposit credit used
        uint256 creditedRefund = marketplace.userDepositsToken(depositor, address(normalToken));
        assertEq(creditedRefund, 0, "No deposit credit - refund was direct for normal token");
    }

    // ============================================================
    // Test: Host payment unaffected in all failure cases
    // ============================================================

    /// @notice F202615254: Host payment is unaffected when refund transfer fails
    function test_HostPayment_UnaffectedByRefundFailure() public {
        // Create two sessions: one with normal token, one with NoReturnToken
        uint256 deposit = USDC_MIN_DEPOSIT * 2;

        normalToken.mint(depositor, deposit);
        vm.prank(depositor);
        normalToken.approve(address(marketplace), type(uint256).max);
        uint256 normalSessionId = _createTokenSession(address(normalToken), deposit);

        noReturnToken.mint(depositor, deposit);
        vm.prank(depositor);
        noReturnToken.approve(address(marketplace), type(uint256).max);
        uint256 noReturnSessionId = _createTokenSession(address(noReturnToken), deposit);

        // Complete both sessions
        _submitProofAndComplete(normalSessionId, keccak256("proof_normal2"));

        // Reset timestamp for second session proof
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(noReturnSessionId, MIN_PROVEN_TOKENS, keccak256("proof_noreturn2"), "QmCID", "QmDelta");
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        vm.prank(host);
        marketplace.completeSessionJob(noReturnSessionId, "QmConversation");

        // Both should have host earnings
        uint256 hostBalNormal = hostEarnings.getBalance(host, address(normalToken));
        uint256 hostBalNoReturn = hostEarnings.getBalance(host, address(noReturnToken));
        assertGt(hostBalNormal, 0, "Host should have normal token earnings");
        assertGt(hostBalNoReturn, 0, "Host should have NoReturnToken earnings");

        // Earnings should be equal (same deposit, same tokens used)
        assertEq(hostBalNormal, hostBalNoReturn, "Host earnings should be equal regardless of refund behavior");
    }
}
