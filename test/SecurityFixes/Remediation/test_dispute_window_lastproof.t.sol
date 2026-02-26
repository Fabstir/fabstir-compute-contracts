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
 * @title Dispute Window LastProofTime Tests (F202615144)
 * @notice Tests for Phase 10: Dispute window uses lastProofTime instead of startTime
 *
 * Finding: F202615144 (MEDIUM)
 * Issue: Dispute Window Calculated From Session Start Time Instead of Last Proof Submission.
 *        The dispute window in completeSessionJob() was calculated from session.startTime,
 *        allowing the host to complete immediately after proof submission once the initial
 *        window passed.
 * Fix: Change to session.lastProofTime so the dispute window resets after each proof.
 */
contract DisputeWindowLastProofTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x3);
    address public treasury = address(0x4);
    address public thirdParty = address(0x5);

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");

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

        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        _registerHost(host);
        vm.deal(user, 100 ether);
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);
        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, 1);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);
        vm.stopPrank();
    }

    function _createSession() internal returns (uint256) {
        vm.prank(user);
        return marketplace.createSessionJobForModel{value: 1 ether}(
            host, modelId, MIN_PRICE_NATIVE, 1 days, 100, 300
        );
    }

    function _submitProof(uint256 sessionId, uint256 tokens, bytes32 proofHash) internal {
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokens, proofHash, "cid", "delta");
    }

    // ============================================================
    // Test: Host cannot complete within disputeWindow from lastProofTime
    // ============================================================

    /// @notice F202615144: Host must wait disputeWindow from lastProofTime, not startTime
    function test_DisputeWindow_FromLastProofTime() public {
        uint256 sessionId = _createSession();

        // Submit proof at t=startTime+100
        vm.warp(block.timestamp + 100);
        _submitProof(sessionId, 100, keccak256("proof1"));

        // Try to complete 15s after proof (less than disputeWindow=30)
        vm.warp(block.timestamp + 15);
        vm.prank(host);
        vm.expectRevert("Wait dispute window");
        marketplace.completeSessionJob(sessionId, "QmCID");
    }

    // ============================================================
    // Test: Host can complete after disputeWindow from lastProofTime
    // ============================================================

    /// @notice F202615144: Host completes after disputeWindow from lastProofTime
    function test_DisputeWindow_HostCompletesAfterWindow() public {
        uint256 sessionId = _createSession();

        // Submit proof at t=startTime+100
        vm.warp(block.timestamp + 100);
        _submitProof(sessionId, 100, keccak256("proof2"));

        // Complete after disputeWindow from lastProofTime (100+31 > 100+30)
        vm.warp(block.timestamp + 31);
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmCID");
    }

    // ============================================================
    // Test: Depositor can complete immediately (no dispute window)
    // ============================================================

    /// @notice F202615144: Depositor bypasses dispute window
    function test_DisputeWindow_DepositorBypassesWindow() public {
        uint256 sessionId = _createSession();

        // Submit proof
        vm.warp(block.timestamp + 100);
        _submitProof(sessionId, 100, keccak256("proof3"));

        // Depositor completes immediately (0s after proof)
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmCID");
    }

    // ============================================================
    // Test: Multiple proofs — window resets after each
    // ============================================================

    /// @notice F202615144: Dispute window resets after each proof submission
    function test_DisputeWindow_ResetsAfterEachProof() public {
        uint256 sessionId = _createSession();

        // First proof at t+100
        vm.warp(block.timestamp + 100);
        _submitProof(sessionId, 100, keccak256("proof4a"));

        // Wait past disputeWindow from first proof
        vm.warp(block.timestamp + 31);

        // Submit second proof — resets window
        _submitProof(sessionId, 100, keccak256("proof4b"));

        // Try to complete 10s after second proof (within new window)
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        vm.expectRevert("Wait dispute window");
        marketplace.completeSessionJob(sessionId, "QmCID");

        // Complete after disputeWindow from second proof
        vm.warp(block.timestamp + 21);
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmCID");
    }

    // ============================================================
    // Test: Host cannot complete immediately even if startTime window passed
    // ============================================================

    /// @notice F202615144: Even if startTime+disputeWindow passed, must wait from lastProofTime
    function test_DisputeWindow_StartTimeWindowPassedButProofRecent() public {
        uint256 sessionId = _createSession();

        // Advance well past startTime + disputeWindow
        vm.warp(block.timestamp + 500);

        // Submit proof at t+500
        _submitProof(sessionId, 100, keccak256("proof5"));

        // Try to complete 5s after proof — startTime+30 long passed, but lastProofTime+30 not
        vm.warp(block.timestamp + 5);
        vm.prank(host);
        vm.expectRevert("Wait dispute window");
        marketplace.completeSessionJob(sessionId, "QmCID");
    }
}
