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
 * @title Dispute Window LastProofTime Tests
 * @notice GAP 2 / Finding #9 (MEDIUM): Dispute window should use lastProofTime, not startTime
 *
 * The dispute window ensures depositors have time to review proofs before host settles.
 * Using startTime means the window never resets, allowing host to settle immediately
 * after submitting a late proof. Using lastProofTime resets the window on each proof.
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

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;

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
        vm.deal(host, 100 ether);
    }

    function _registerHost(address _host) internal {
        fabToken.mint(_host, MIN_STAKE);
        vm.startPrank(_host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;
        nodeRegistry.registerNode("http://host.example.com", "metadata", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    /// @notice Helper: create a session and return session ID
    function _createSession() internal returns (uint256) {
        vm.prank(user);
        return marketplace.createSessionJob{value: 1 ether}(
            host, MIN_PRICE_NATIVE, 1 days, MIN_PROVEN_TOKENS, 300
        );
    }

    /// @notice Helper: host submits proof for a session
    function _submitProof(uint256 sessionId, uint256 tokens, bytes32 proofHash) internal {
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokens, proofHash, "QmCID", "QmDelta");
    }

    // ============================================================
    // Test: Host cannot complete immediately after proof
    // ============================================================

    function test_HostCannotCompleteImmediatelyAfterProof() public {
        uint256 sessionId = _createSession();

        // Advance enough for rate limit to allow tokens
        vm.warp(block.timestamp + 10);
        _submitProof(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"));

        // Host tries to complete immediately after proof — should revert
        vm.prank(host);
        vm.expectRevert("Wait dispute window");
        marketplace.completeSessionJob(sessionId, "QmConversation");
    }

    // ============================================================
    // Test: Host can complete after dispute window from last proof
    // ============================================================

    function test_HostCanCompleteAfterDisputeWindowFromLastProof() public {
        uint256 sessionId = _createSession();

        // Advance time, submit proof
        vm.warp(block.timestamp + 10);
        _submitProof(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"));

        // Advance past dispute window from proof time
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Host completes — should succeed
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        // Verify session is completed
        (,,,,,,,,,,,, JobMarketplaceWithModelsUpgradeable.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint8(status), uint8(1), "Session should be Completed");
    }

    // ============================================================
    // Test: Dispute window resets on each proof
    // ============================================================

    function test_DisputeWindowResetsOnEachProof() public {
        uint256 sessionId = _createSession();

        // Submit first proof
        vm.warp(block.timestamp + 10);
        _submitProof(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"));

        // Wait almost past dispute window from first proof
        vm.warp(block.timestamp + DISPUTE_WINDOW - 1);

        // Submit second proof — resets the window
        _submitProof(sessionId, MIN_PROVEN_TOKENS, keccak256("proof2"));

        // Immediately try to complete — should fail because window just reset
        vm.prank(host);
        vm.expectRevert("Wait dispute window");
        marketplace.completeSessionJob(sessionId, "QmConversation");
    }

    // ============================================================
    // Test: Depositor can complete anytime (no dispute window)
    // ============================================================

    function test_DepositorCanCompleteAnytime() public {
        uint256 sessionId = _createSession();

        // Submit proof
        vm.warp(block.timestamp + 10);
        _submitProof(sessionId, MIN_PROVEN_TOKENS, keccak256("proof1"));

        // Depositor completes immediately — no dispute window required
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        (,,,,,,,,,,,, JobMarketplaceWithModelsUpgradeable.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint8(status), uint8(1), "Session should be Completed");
    }

    // ============================================================
    // Test: Zero proofs — host waits dispute window from start
    // ============================================================

    function test_ZeroProofsDisputeWindowStillWorks() public {
        uint256 sessionId = _createSession();

        // No proofs submitted. lastProofTime == startTime.
        // Host waits past dispute window from start
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversation");

        (,,,,,,,,,,,, JobMarketplaceWithModelsUpgradeable.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint8(status), uint8(1), "Session should be Completed");
    }
}
