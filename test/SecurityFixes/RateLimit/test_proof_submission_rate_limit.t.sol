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

contract ProofSubmissionRateLimitTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    MockERC20 public fabToken;

    address public owner;
    uint256 public hostPrivateKey = 0xA11CE;
    address public host;
    address public user;

    bytes32 public TINY_LLAMA_MODEL_ID;
    bytes32 public TINY_VICUNA_MODEL_ID;

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant DEFAULT_RATE_LIMIT = 2000;

    function setUp() public {
        owner = address(this);
        host = vm.addr(hostPrivateKey);
        user = makeAddr("user");

        fabToken = new MockERC20("FAB", "FAB", 18);

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelImpl = new ModelRegistryUpgradeable();
        ERC1967Proxy modelProxy = new ERC1967Proxy(
            address(modelImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
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
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        );
        nodeRegistry = NodeRegistryWithModelsUpgradeable(address(nodeProxy));

        // Deploy HostEarnings
        HostEarningsUpgradeable earningsImpl = new HostEarningsUpgradeable();
        ERC1967Proxy earningsProxy = new ERC1967Proxy(
            address(earningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        );
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
        ERC1967Proxy proofSystemProxy = new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        );
        proofSystem = ProofSystemUpgradeable(address(proofSystemProxy));

        // Configure
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        marketplace.setProofSystem(address(proofSystem));

        // Fund and register host
        fabToken.mint(host, MIN_STAKE * 10);
        vm.deal(user, 100 ether);

        bytes32[] memory models = new bytes32[](2);
        models[0] = TINY_LLAMA_MODEL_ID;
        models[1] = TINY_VICUNA_MODEL_ID;

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);
        nodeRegistry.registerNode("Test Host", "http://test.api", models, MIN_PRICE_NATIVE, MIN_PRICE_STABLE);
        vm.stopPrank();
    }

    function _generateSignature(bytes32 proofHash, uint256 tokensClaimed, bytes32 modelIdForSig)
        internal view returns (bytes memory)
    {
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, host, tokensClaimed, modelIdForSig));
        bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, messageHash);
        return abi.encodePacked(r, s, v);
    }

    function test_ProofSubmission_UsesModelRateLimit() public {
        // Configure TinyLlama with 3000 tokens/sec rate limit
        modelRegistry.setModelRateLimit(TINY_LLAMA_MODEL_ID, 3000);

        // Create session for TinyLlama model
        uint256 sessionId = _createModelSession(TINY_LLAMA_MODEL_ID, 1 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Should be able to claim up to 3000 tokens (model rate)
        // Would fail with old hardcoded 2000 limit
        bytes memory sig = _generateSignature(keccak256("proof1"), 2500, TINY_LLAMA_MODEL_ID);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 2500, keccak256("proof1"), sig, "cid1", "delta1");

        // Verify tokens were credited
        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 2500);
    }

    function test_ProofSubmission_NonModelSession_UsesDefaultRate() public {
        // Create non-model session (no modelId)
        uint256 sessionId = _createNonModelSession(1 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Default rate is 2000 tokens/sec - claiming 2000 should succeed
        bytes memory sig = _generateSignature(keccak256("proof1"), 2000, bytes32(0));
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 2000, keccak256("proof1"), sig, "cid1", "delta1");

        // Claiming 2001 should fail
        vm.warp(block.timestamp + 1);
        bytes memory sig2 = _generateSignature(keccak256("proof2"), 2001, bytes32(0));
        vm.prank(host);
        vm.expectRevert("Excessive tokens claimed");
        marketplace.submitProofOfWork(sessionId, 2001, keccak256("proof2"), sig2, "cid2", "delta2");
    }

    function test_ProofSubmission_HigherRateAllowsMoreTokens() public {
        // Set high rate limit for test model
        modelRegistry.setModelRateLimit(TINY_VICUNA_MODEL_ID, 5000);

        uint256 sessionId = _createModelSession(TINY_VICUNA_MODEL_ID, 10 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Should allow 5000 tokens (would fail with 2000 limit)
        bytes memory sig = _generateSignature(keccak256("proof1"), 5000, TINY_VICUNA_MODEL_ID);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 5000, keccak256("proof1"), sig, "cid1", "delta1");

        (,,,,,, uint256 tokensUsed,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, 5000);
    }

    function test_ProofSubmission_ExceedsModelRateLimit_Reverts() public {
        // Set lower rate limit for model
        modelRegistry.setModelRateLimit(TINY_LLAMA_MODEL_ID, 1000);

        uint256 sessionId = _createModelSession(TINY_LLAMA_MODEL_ID, 1 ether);

        // Wait 1 second
        vm.warp(block.timestamp + 1);

        // Try to claim 1500 tokens (exceeds 1000 limit)
        bytes memory sig = _generateSignature(keccak256("proof1"), 1500, TINY_LLAMA_MODEL_ID);
        vm.prank(host);
        vm.expectRevert("Excessive tokens claimed");
        marketplace.submitProofOfWork(sessionId, 1500, keccak256("proof1"), sig, "cid1", "delta1");
    }

    function test_ProofSubmission_ModelNotConfigured_UsesDefault() public {
        // Don't configure rate limit for model (uses default 2000)
        uint256 sessionId = _createModelSession(TINY_LLAMA_MODEL_ID, 1 ether);

        vm.warp(block.timestamp + 1);

        // Should allow up to 2000 (default)
        bytes memory sig = _generateSignature(keccak256("proof1"), 2000, TINY_LLAMA_MODEL_ID);
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, 2000, keccak256("proof1"), sig, "cid1", "delta1");

        // Should not allow more than default
        vm.warp(block.timestamp + 1);
        bytes memory sig2 = _generateSignature(keccak256("proof2"), 2001, TINY_LLAMA_MODEL_ID);
        vm.prank(host);
        vm.expectRevert("Excessive tokens claimed");
        marketplace.submitProofOfWork(sessionId, 2001, keccak256("proof2"), sig2, "cid2", "delta2");
    }

    // Helper functions
    function _createModelSession(bytes32 modelId, uint256 deposit) internal returns (uint256) {
        vm.deal(user, deposit);
        vm.prank(user);
        return marketplace.createSessionJobForModel{value: deposit}(
            host, modelId, MIN_PRICE_NATIVE, 3600, 100, 300
        );
    }

    function _createNonModelSession(uint256 deposit) internal returns (uint256) {
        vm.deal(user, deposit);
        vm.prank(user);
        return marketplace.createSessionJob{value: deposit}(
            host, MIN_PRICE_NATIVE, 3600, 100, 300
        );
    }
}
