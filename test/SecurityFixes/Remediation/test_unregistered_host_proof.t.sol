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
 * @title Unregistered Host Proof Submission Tests
 * @notice F202615278 (LOW): Host Can Unregister During Active Sessions and Withdraw
 *         Stake While Continuing to Earn
 *
 * After unregisterNode(), host should NOT be able to submit proofs for active sessions.
 */
contract UnregisteredHostProofTest is Test {
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
    // Test: Host submits proof after unregisterNode() → reverts
    // ============================================================

    /// @notice F202615278: Unregistered host cannot submit proofs
    function test_SubmitProof_RevertsWhenHostUnregistered() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Host unregisters (withdraws stake)
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Advance time for rate limit
        vm.warp(block.timestamp + 10);

        // Host tries to submit proof — should revert
        vm.prank(host);
        vm.expectRevert("Host not active");
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");
    }

    // ============================================================
    // Test: Host submits proof while registered → succeeds (regression)
    // ============================================================

    /// @notice F202615278: Registered host can still submit proofs (regression test)
    function test_SubmitProof_SucceedsWhenHostRegistered() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Advance time for rate limit
        vm.warp(block.timestamp + 10);

        // Host submits proof while registered — should succeed
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"), "cid1", "delta1");

        // Verify tokens were recorded
        (, , , , , , uint256 tokensUsed, , , , , , , , , , , ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, MIN_PROVEN_TOKENS, "Tokens should be recorded after valid proof");
    }

    // ============================================================
    // Test: Session can still be completed after host unregisters
    // ============================================================

    /// @notice F202615278: Depositor can still complete session after host unregisters
    function test_CompleteSession_AfterHostUnregisters() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Host unregisters
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Advance past dispute window
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Depositor can still complete session and get refund
        vm.prank(depositor);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        uint256 depositorBal = usdc.balanceOf(depositor);
        assertGt(depositorBal, 0, "Depositor should get refund after host unregisters");
    }

    // ============================================================
    // Test: Session can still be timed out after host unregisters
    // ============================================================

    /// @notice F202615278: Session timeout still works after host unregisters
    function test_Timeout_AfterHostUnregisters() public {
        uint256 deposit = USDC_MIN_DEPOSIT * 2;
        uint256 sessionId = _createSession(deposit);

        // Host unregisters
        vm.prank(host);
        nodeRegistry.unregisterNode();

        // Advance past proof timeout
        vm.warp(block.timestamp + PROOF_TIMEOUT + 1);

        // Depositor can trigger timeout
        vm.prank(depositor);
        marketplace.triggerSessionTimeout(sessionId);

        uint256 depositorBal = usdc.balanceOf(depositor);
        assertEq(depositorBal, deposit, "Depositor should get full refund on timeout after host unregisters");
    }
}
