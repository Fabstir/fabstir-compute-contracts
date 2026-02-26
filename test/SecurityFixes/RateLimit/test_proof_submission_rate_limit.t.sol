// test/SecurityFixes/RateLimit/test_proof_submission_rate_limit.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/// @notice F202614913: Rate limit enforcement in submitProofOfWork
contract ProofSubmissionRateLimitTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    MockERC20 public fabToken;

    address public owner;
    address public host;
    address public user;

    bytes32 public TINY_LLAMA_MODEL_ID;
    bytes32 public TINY_VICUNA_MODEL_ID;

    uint256 constant MIN_STAKE = 1000 * 10 ** 18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant DEFAULT_RATE_LIMIT = 2000;

    function setUp() public {
        owner = address(this);
        host = makeAddr("host");
        user = makeAddr("user");

        fabToken = new MockERC20("FAB", "FAB", 18);

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelImpl = new ModelRegistryUpgradeable();
        ERC1967Proxy modelProxy = new ERC1967Proxy(
            address(modelImpl), abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        );
        modelRegistry = ModelRegistryUpgradeable(address(modelProxy));

        // Add models
        modelRegistry.addTrustedModel("TinyLlama", "1.1B", bytes32(uint256(1)));
        modelRegistry.addTrustedModel("TinyVicuna", "1B", bytes32(uint256(2)));
        TINY_LLAMA_MODEL_ID = modelRegistry.getModelId("TinyLlama", "1.1B");
        TINY_VICUNA_MODEL_ID = modelRegistry.getModelId("TinyVicuna", "1B");

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeImpl = new NodeRegistryWithModelsUpgradeable();
        ERC1967Proxy nodeProxy = new ERC1967Proxy(
            address(nodeImpl),
            abi.encodeCall(
                NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry))
            )
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(nodeProxy));

        // Deploy HostEarnings
        HostEarningsUpgradeable earningsImpl = new HostEarningsUpgradeable();
        ERC1967Proxy earningsProxy =
            new ERC1967Proxy(address(earningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()));
        hostEarnings = HostEarningsUpgradeable(payable(address(earningsProxy)));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(
                JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW)
            )
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(marketplaceProxy)));

        // Deploy ProofSystem
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        ERC1967Proxy proofSystemProxy =
            new ERC1967Proxy(address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ()));
        proofSystem = ProofSystemUpgradeable(address(proofSystemProxy));

        // Configure
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        proofSystem.setAuthorizedCaller(address(marketplace), true);
        marketplace.setProofSystem(address(proofSystem));

        // Fund and register host
        fabToken.mint(host, MIN_STAKE * 10);
        vm.deal(user, 100 ether);

        bytes32[] memory models = new bytes32[](2);
        models[0] = TINY_LLAMA_MODEL_ID;
        models[1] = TINY_VICUNA_MODEL_ID;

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        nodeRegistry.registerNode("Test Host", "http://test.api", models, MIN_PRICE_NATIVE, 10);
        nodeRegistry.setModelTokenPricing(TINY_LLAMA_MODEL_ID, address(0), MIN_PRICE_NATIVE);
        nodeRegistry.setModelTokenPricing(TINY_VICUNA_MODEL_ID, address(0), MIN_PRICE_NATIVE);
        vm.stopPrank();
    }

    /// @notice Model with custom rate limit allows more tokens than old hardcoded limit
    function test_ProofSubmission_UsesModelRateLimit() public {
        // Configure TinyLlama with 3000 tokens/sec rate limit
        modelRegistry.setModelRateLimit(TINY_LLAMA_MODEL_ID, 3000);

        uint256 sessionId = _createModelSession(TINY_LLAMA_MODEL_ID, 1 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Should allow up to 3000 tokens (would fail with old hardcoded 2000 limit)
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 2500, keccak256("proof1"), "cid1", "delta1");

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 2500);
    }

    /// @notice Non-model session uses default rate (2000 tokens/sec)
    function test_ProofSubmission_NonModelSession_UsesDefaultRate() public {
        uint256 sessionId = _createNonModelSession(1 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Default rate is 2000 tokens/sec - claiming 2000 should succeed
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 2000, keccak256("proof1"), "cid1", "delta1");

        // Claiming 2001 should fail after another second
        vm.warp(block.timestamp + 1);
        vm.prank(host);
        vm.expectRevert("Excessive tokens claimed");
        marketplace.submitProofOfWork(sessionId, 2001, keccak256("proof2"), "cid2", "delta2");
    }

    /// @notice Higher rate limit allows proportionally more tokens
    function test_ProofSubmission_HigherRateAllowsMoreTokens() public {
        modelRegistry.setModelRateLimit(TINY_VICUNA_MODEL_ID, 5000);

        uint256 sessionId = _createModelSession(TINY_VICUNA_MODEL_ID, 10 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Should allow 5000 tokens (would fail with default 2000 limit)
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 5000, keccak256("proof1"), "cid1", "delta1");

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 5000);
    }

    /// @notice Exceeding model rate limit reverts
    function test_ProofSubmission_ExceedsModelRateLimit_Reverts() public {
        modelRegistry.setModelRateLimit(TINY_LLAMA_MODEL_ID, 1000);

        uint256 sessionId = _createModelSession(TINY_LLAMA_MODEL_ID, 1 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Try to claim 1500 tokens (exceeds 1000 limit)
        vm.prank(host);
        vm.expectRevert("Excessive tokens claimed");
        marketplace.submitProofOfWork(sessionId, 1500, keccak256("proof1"), "cid1", "delta1");
    }

    /// @notice Unconfigured model uses default rate (2000 tokens/sec)
    function test_ProofSubmission_ModelNotConfigured_UsesDefault() public {
        // Don't configure rate limit — uses default 2000
        uint256 sessionId = _createModelSession(TINY_LLAMA_MODEL_ID, 1 ether);

        vm.warp(block.timestamp + 1);

        // Should allow up to 2000 (default)
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 2000, keccak256("proof1"), "cid1", "delta1");

        // Should not allow more than default after another second
        vm.warp(block.timestamp + 1);
        vm.prank(host);
        vm.expectRevert("Excessive tokens claimed");
        marketplace.submitProofOfWork(sessionId, 2001, keccak256("proof2"), "cid2", "delta2");
    }

    // ============================================================
    // Helper functions
    // ============================================================

    function _createModelSession(bytes32 modelId, uint256 deposit) internal returns (uint256) {
        vm.deal(user, deposit);
        vm.prank(user);
        return marketplace.createSessionJobForModel{value: deposit}(host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300);
    }

    function _createNonModelSession(uint256 deposit) internal returns (uint256) {
        vm.deal(user, deposit);
        vm.prank(user);
        return marketplace.createSessionJobForModel{value: deposit}(host, TINY_LLAMA_MODEL_ID, MIN_PRICE_NATIVE, 3600, 100, 300);
    }
}
