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
 * @dev Tests for Sub-phase 6.2: Integrate ProofSystem Verification Call
 *
 * Issue: ProofSystem.verifyAndMarkComplete() exists but is NEVER CALLED
 * by JobMarketplace.submitProofOfWork(). This phase integrates the verification.
 *
 * After this phase:
 * - Valid signatures from host pass verification
 * - Invalid signatures revert
 * - Replay attacks are prevented
 * - ProofSubmission.verified reflects actual verification status
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

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
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
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
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
            1000 // proof interval
        );

        // Advance time so rate limiting passes
        vm.warp(block.timestamp + 10);
    }

    // ============================================================
    // Sub-phase 6.2 Tests: ProofSystem Integration
    // ============================================================

    /**
     * @notice Test that valid signature from host passes verification
     */
    function test_ValidSignaturePassesVerification() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Generate valid signature from host
        bytes memory signature = _generateHostSignature(proofHash, host, tokensClaimed);

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmTestCID");

        // Verify tokens were credited (proof was accepted)
        (,,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be credited");

        // Verify proof was marked as verified in ProofSystem
        assertTrue(proofSystem.verifiedProofs(proofHash), "Proof should be marked as verified");
    }

    /**
     * @notice Test that invalid signature reverts
     */
    function test_InvalidSignatureReverts() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Create invalid signature (random bytes)
        bytes memory invalidSignature = new bytes(65);
        invalidSignature[0] = 0x12;
        invalidSignature[64] = 0x1b; // v = 27

        vm.prank(host);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, invalidSignature, "QmTestCID");
    }

    /**
     * @notice Test that signature from wrong signer (not host) reverts
     */
    function test_WrongSignerReverts() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Generate signature from attacker (not the session host)
        bytes memory attackerSignature = _generateHostSignature(proofHash, attacker, tokensClaimed);

        // Host submits proof but with attacker's signature
        vm.prank(host);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, attackerSignature, "QmTestCID");
    }

    /**
     * @notice Test that replay attack (same proofHash twice) reverts
     */
    function test_ReplayAttackReverts() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        // Generate valid signature
        bytes memory signature = _generateHostSignature(proofHash, host, tokensClaimed);

        // First submission should succeed
        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmTestCID");

        // Advance time for rate limiting
        vm.warp(block.timestamp + 5);

        // Second submission with same proofHash should fail (replay attack)
        vm.prank(host);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmTestCID2");
    }

    /**
     * @notice Test that ProofSystem not set (address(0)) still works (graceful degradation)
     */
    function test_ProofSystemNotSetStillWorks() public {
        // Deploy a new marketplace without ProofSystem configured
        vm.startPrank(owner);
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
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
            1000
        );

        // Advance time
        vm.warp(block.timestamp + 10);

        bytes32 proofHash = keccak256("test proof");
        uint256 tokensClaimed = 500;

        // Any 65-byte signature should work when ProofSystem not set
        bytes memory dummySignature = new bytes(65);
        dummySignature[64] = 0x1b; // v = 27

        vm.prank(host);
        // Should NOT revert - graceful degradation
        marketplaceNoProof.submitProofOfWork(newSessionId, tokensClaimed, proofHash, dummySignature, "QmTestCID");

        // Verify tokens were credited
        (,,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplaceNoProof.sessionJobs(newSessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be credited even without ProofSystem");
    }

    /**
     * @notice Test that ProofSubmission.verified field is true when verification passes
     */
    function test_ProofSubmissionMarkedAsVerified() public {
        bytes32 proofHash = keccak256("test proof data");
        uint256 tokensClaimed = 500;

        bytes memory signature = _generateHostSignature(proofHash, host, tokensClaimed);

        vm.prank(host);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmTestCID");

        // Get the proof submission and check verified flag
        (
            bytes32 storedHash,
            uint256 storedTokens,
            ,
            bool verified
        ) = marketplace.getProofSubmission(sessionId, 0);

        assertEq(storedHash, proofHash, "Proof hash should match");
        assertEq(storedTokens, tokensClaimed, "Tokens claimed should match");
        assertTrue(verified, "Proof should be marked as verified");
    }

    /**
     * @notice Test that ProofSubmission.verified is false when ProofSystem not configured
     */
    function test_ProofSubmissionNotVerifiedWithoutProofSystem() public {
        // Deploy a new marketplace without ProofSystem configured
        vm.startPrank(owner);
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (
                address(nodeRegistry),
                payable(address(hostEarnings)),
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
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
            1000
        );

        vm.warp(block.timestamp + 10);

        bytes32 proofHash = keccak256("test proof");
        bytes memory dummySignature = new bytes(65);
        dummySignature[64] = 0x1b;

        vm.prank(host);
        marketplaceNoProof.submitProofOfWork(newSessionId, 500, proofHash, dummySignature, "QmTestCID");

        // Get proof and check verified is false
        (,,, bool verified) = marketplaceNoProof.getProofSubmission(newSessionId, 0);
        assertFalse(verified, "Proof should NOT be verified when ProofSystem not configured");
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
        // Must match ProofSystem._verifyEKZL: keccak256(proofHash, prover, claimedTokens)
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
