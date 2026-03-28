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
 * @title Proof Submission Tests (Post Signature Removal)
 * @dev Tests for F202614998+F202614976: Signature removal from submitProofOfWork.
 *
 * After signature removal:
 * - submitProofOfWork accepts 5 parameters (no signature bytes)
 * - Authentication is via msg.sender == session.host
 * - Replay protection via ProofSystem.markProofUsed()
 * - ProofSubmission.verified reflects proof recording status
 */
contract ProofNoSignatureTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public host = address(0x2);
    address public user = address(0x4);
    address public nonHost = address(0x5);

    bytes32 public modelId;
    uint256 public sessionId;

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");

        vm.startPrank(owner);

        // Deploy ModelRegistry as proxy
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        ));
        modelRegistry = ModelRegistryUpgradeable(modelRegistryProxy);

        // Add approved model
        modelRegistry.addTrustedModel("Model1/Repo", "model1.gguf", bytes32(uint256(1)));
        modelId = modelRegistry.getModelId("Model1/Repo", "model1.gguf");

        // Deploy NodeRegistry as proxy
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        ));
        nodeRegistry = NodeRegistryWithModelsUpgradeable(nodeRegistryProxy);

        // Deploy HostEarnings as proxy
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(new ERC1967Proxy(
            address(hostEarningsImpl),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(hostEarningsProxy));

        // Deploy ProofSystem as proxy
        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        address proofSystemProxy = address(new ERC1967Proxy(
            address(proofSystemImpl),
            abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        ));
        proofSystem = ProofSystemUpgradeable(proofSystemProxy);

        // Deploy JobMarketplace as proxy
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                feeBasisPoints,
                disputeWindow
            ))
        ));
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Configure ProofSystem in marketplace
        marketplace.setProofSystem(address(proofSystem));

        // Authorize marketplace in ProofSystem
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host in NodeRegistry
        fabToken.mint(host, 10000 * 10**18);
        vm.prank(host);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.prank(host);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        vm.prank(host);
        nodeRegistry.setModelTokenPricing(modelId, address(0), MIN_PRICE_NATIVE);

        // Setup user with ETH
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);

        // Create a session for testing proof submission
        vm.prank(user);
        sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days, // maxDuration
            1000, // proof interval
            300 // proofTimeoutWindow
        );

        // Advance time so rate limiting passes
        vm.warp(block.timestamp + 10);
    }

    // ============================================================
    // F202614998+F202614976: Proof Submission Without Signature
    // ============================================================

    /**
     * @notice Test that submitProofOfWork accepts the new 5-parameter format (no signature)
     */
    function test_SubmitProofWithoutSignature_AcceptsNewFormat() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 1000;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID", "");

        // Verify proof was stored
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed);
    }

    /**
     * @notice Test that only host (msg.sender) can submit proofs
     */
    function test_OnlyHostCanSubmitProof() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        vm.prank(nonHost);
        vm.expectRevert("Not host");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID", "");
    }

    /**
     * @notice Test that multiple proofs can be submitted without signatures
     */
    function test_SubmitMultipleProofs_WithoutSignatures() public {
        // Submit first proof (>= proofInterval=1000)
        bytes32 proofHash1 = keccak256("proof 1");
        uint256 tokens1 = 1000;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokens1, proofHash1, "QmCID1", "");

        // Advance time for rate limiting
        vm.warp(block.timestamp + 5);

        // Submit second proof
        bytes32 proofHash2 = keccak256("proof 2");
        uint256 tokens2 = 300;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokens2, proofHash2, "QmCID2", "");

        // Verify total tokens
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokens1 + tokens2);
    }

    /**
     * @notice Test replay attack is still prevented via ProofSystem.markProofUsed
     */
    function test_ReplayAttackStillPrevented() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 1000;

        // First submission succeeds
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmCID1", "");

        // Advance time for rate limiting
        vm.warp(block.timestamp + 5);

        // Second submission with same proofHash reverts
        vm.prank(host);
        vm.expectRevert("Proof already used");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmCID2", "");
    }

    /**
     * @notice Test that proof is marked as verified and recorded in ProofSystem
     */
    function test_ProofMarkedAsVerified() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 1000;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID", "");

        // Verify proof was marked as verified in ProofSystem
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked as verified");

        // Check the proof submission record
        (
            bytes32 storedHash,
            uint256 storedTokens,
            ,
            bool verified,
        ) = marketplace.getProofSubmission(sessionId, 0);

        assertEq(storedHash, proofHash, "Proof hash should match");
        assertEq(storedTokens, tokensClaimed, "Tokens claimed should match");
        assertTrue(verified, "Proof should be marked as verified");
    }
}
