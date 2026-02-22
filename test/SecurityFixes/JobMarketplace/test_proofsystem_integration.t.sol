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
 * @title ProofSystem Integration Tests
 * @dev Tests for ProofSystem integration with JobMarketplace.
 *
 * After signature removal (F202614998+F202614976):
 * - Authentication is via msg.sender == session.host
 * - ProofSystem.markProofUsed() provides replay protection
 * - ProofSubmission.verified reflects proof recording status
 */
contract ProofSystemIntegrationTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public user = address(0x4);

    // Use proper private keys so we can sign messages
    uint256 public hostPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host;

    uint256 public attackerPrivateKey = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
    address public attacker;

    bytes32 public modelId;
    uint256 public sessionId;

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;
    uint256 constant MIN_PROVEN_TOKENS = 100;

    function setUp() public {
        // Derive addresses from private keys
        host = vm.addr(hostPrivateKey);
        attacker = vm.addr(attackerPrivateKey);

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

        // Configure ProofSystem in marketplace
        marketplace.setProofSystem(address(proofSystem));

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Authorize marketplace in ProofSystem (for recording verified proofs)
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
        vm.deal(attacker, 100 ether);

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
    // Sub-phase 6.2 Tests: ProofSystem Integration
    // ============================================================

    /**
     * @notice Test that valid proof from host passes verification
     */
    function test_ValidProofPassesVerification() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID", "");

        // Verify tokens were credited (proof was accepted)
        (,,,,,, uint256 tokensUsed,,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be credited");

        // Verify proof was marked as verified in ProofSystem
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked as verified");
    }

    /**
     * @notice Test that replay attack (same proofHash twice) reverts
     */
    function test_ReplayAttackReverts() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // First submission should succeed
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID", "");

        // Advance time for rate limiting
        vm.warp(block.timestamp + 5);

        // Second submission with same proofHash should fail (replay attack)
        vm.prank(host);
        vm.expectRevert("Proof already used");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID2", "");
    }

    /**
     * @notice Test that ProofSystem not set (address(0)) reverts (F202614909)
     */
    function test_ProofSystemNotSetReverts() public {
        // Deploy a new marketplace without ProofSystem configured
        vm.startPrank(owner);
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
        JobMarketplaceWithModelsUpgradeable marketplaceNoProof = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));

        // Authorize in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplaceNoProof), true);
        vm.stopPrank();

        // Create session on marketplace without ProofSystem
        vm.prank(user);
        uint256 newSessionId = marketplaceNoProof.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        // Advance time
        vm.warp(block.timestamp + 10);

        bytes32 proofHash = keccak256("test proof");
        uint256 tokensClaimed = 500;

        // Should revert when ProofSystem not set (F202614909)
        vm.prank(host);
        vm.expectRevert("ProofSystem not set");
        marketplaceNoProof.submitProofOfWork(newSessionId, tokensClaimed, proofHash, "QmTestCID", "");
    }

    /**
     * @notice Test that ProofSubmission.verified field is true when verification passes
     */
    function test_ProofSubmissionMarkedAsVerified() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, "QmTestCID", "");

        // Get the proof submission and check verified flag
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

    /**
     * @notice Test that proof submission reverts when ProofSystem not configured (F202614909)
     */
    function test_ProofSubmissionRevertsWithoutProofSystem() public {
        // Deploy a new marketplace without ProofSystem configured
        vm.startPrank(owner);
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
        JobMarketplaceWithModelsUpgradeable marketplaceNoProof = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));
        hostEarnings.setAuthorizedCaller(address(marketplaceNoProof), true);
        vm.stopPrank();

        // Create session
        vm.prank(user);
        uint256 newSessionId = marketplaceNoProof.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000,
            300
        );

        vm.warp(block.timestamp + 10);

        bytes32 proofHash = keccak256("test proof");

        // Should revert when ProofSystem not set (F202614909)
        vm.prank(host);
        vm.expectRevert("ProofSystem not set");
        marketplaceNoProof.submitProofOfWork(newSessionId, 500, proofHash, "QmTestCID", "");
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /**
     * @dev Generate a valid ECDSA signature for the given proof
     * @param proofHash The hash of the proof data
     * @param signer The address that should sign (for deriving private key)
     * @param tokensClaimed Number of tokens being claimed
     */
    function _generateHostSignature(bytes32 proofHash, address signer, uint256 tokensClaimed) internal view returns (bytes memory) {
        // Determine which private key to use
        uint256 privateKey;
        if (signer == host) {
            privateKey = hostPrivateKey;
        } else if (signer == attacker) {
            privateKey = attackerPrivateKey;
        } else {
            revert("Unknown signer");
        }

        // Create the message hash that will be signed
        // Must match ProofSystem._verifyHostSignature: keccak256(proofHash, prover, claimedTokens)
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, signer, tokensClaimed));

        // Create Ethereum signed message hash (EIP-191)
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            dataHash
        ));

        // Sign with private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);

        // Return 65-byte signature (r, s, v)
        return abi.encodePacked(r, s, v);
    }
}
