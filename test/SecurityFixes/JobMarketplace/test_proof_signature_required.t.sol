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
 * @title Proof Signature Required Tests
 * @dev Tests for Sub-phase 6.1: Modify submitProofOfWork Signature
 *
 * Issue: submitProofOfWork currently accepts proofHash without signature.
 * This phase adds a required `bytes calldata signature` parameter (65 bytes).
 *
 * The NEW signature will be:
 * submitProofOfWork(uint256 jobId, uint256 tokensClaimed, bytes32 proofHash, bytes calldata signature, string calldata proofCID)
 */
contract ProofSignatureRequiredTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public user = address(0x4);

    // Use a proper private key for host so we can sign messages
    uint256 public hostPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host;

    bytes32 public modelId;
    uint256 public sessionId;

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;
    uint256 constant PRICE_PRECISION = 1e18;

    function setUp() public {
        // Derive host address from private key
        host = vm.addr(hostPrivateKey);

        // Deploy mock tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");

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
            1000 // proof interval
        );

        // Advance time so rate limiting passes
        vm.warp(block.timestamp + 10);
    }

    // ============================================================
    // Sub-phase 6.1 Tests: Signature Parameter Required
    // ============================================================

    /**
     * @notice Test that submitProofOfWork now requires 5 parameters including signature
     * @dev The new signature is: (jobId, tokensClaimed, proofHash, signature, proofCID)
     *      This test verifies the function accepts the new 5-parameter format
     */
    function test_SubmitProofWithSignature_AcceptsNewFormat() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Generate valid signature from host
        bytes memory signature = _generateHostSignature(proofHash, tokensClaimed);

        vm.prank(host);
        // NEW 5-parameter call
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmTestCID");

        // Verify proof was stored - use tuple unpacking for all 18 fields
        // SessionJob: id, depositor, requester, host, paymentToken, deposit, pricePerToken, tokensUsed,
        //             maxDuration, startTime, lastProofTime, proofInterval, status, withdrawnByHost,
        //             refundedToUser, conversationCID, lastProofHash, lastProofCID
        (,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed);
    }

    /**
     * @notice Test that signature must be exactly 65 bytes
     * @dev ECDSA signatures are exactly 65 bytes: r (32) + s (32) + v (1)
     */
    function test_SubmitProofWithSignature_RevertsOnInvalidLength() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Create invalid signature (64 bytes instead of 65)
        bytes memory invalidSignature = new bytes(64);

        vm.prank(host);
        vm.expectRevert("Invalid signature length");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, invalidSignature, "QmTestCID");
    }

    /**
     * @notice Test that empty signature reverts
     */
    function test_SubmitProofWithSignature_RevertsOnEmptySignature() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        bytes memory emptySignature = "";

        vm.prank(host);
        vm.expectRevert("Invalid signature length");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, emptySignature, "QmTestCID");
    }

    /**
     * @notice Test that signature with 66 bytes reverts
     */
    function test_SubmitProofWithSignature_RevertsOnTooLongSignature() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Create invalid signature (66 bytes instead of 65)
        bytes memory tooLongSignature = new bytes(66);

        vm.prank(host);
        vm.expectRevert("Invalid signature length");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, tooLongSignature, "QmTestCID");
    }

    /**
     * @notice Test that valid 65-byte signature is accepted
     */
    function test_SubmitProofWithSignature_Accepts65Bytes() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Generate valid 65-byte signature
        bytes memory signature = _generateHostSignature(proofHash, tokensClaimed);
        assertEq(signature.length, 65, "Signature should be 65 bytes");

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmTestCID");

        // Success - no revert
    }

    /**
     * @notice Test that multiple proofs can be submitted with valid signatures
     */
    function test_SubmitMultipleProofs_WithSignatures() public {
        // Submit first proof
        bytes32 proofHash1 = keccak256("proof 1");
        uint256 tokens1 = 200;
        bytes memory sig1 = _generateHostSignature(proofHash1, tokens1);

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokens1, proofHash1, sig1, "QmCID1");

        // Advance time for rate limiting
        vm.warp(block.timestamp + 5);

        // Submit second proof
        bytes32 proofHash2 = keccak256("proof 2");
        uint256 tokens2 = 300;
        bytes memory sig2 = _generateHostSignature(proofHash2, tokens2);

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokens2, proofHash2, sig2, "QmCID2");

        // Verify total tokens
        (,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokens1 + tokens2);
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /**
     * @dev Generate a valid ECDSA signature from the host for the given proof
     */
    function _generateHostSignature(bytes32 proofHash, uint256 tokensClaimed) internal view returns (bytes memory) {
        // Create the message hash that will be signed
        // Format: keccak256(proofHash, host, tokensClaimed)
        bytes32 messageHash = keccak256(abi.encodePacked(proofHash, host, tokensClaimed));

        // Create Ethereum signed message hash (EIP-191)
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));

        // Sign with host's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPrivateKey, ethSignedMessageHash);

        // Return 65-byte signature
        return abi.encodePacked(r, s, v);
    }
}
