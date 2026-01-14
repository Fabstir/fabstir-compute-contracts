// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "../../src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title Proof Verification End-to-End Integration Tests
 * @dev Tests for Sub-phase 6.3: Integration Tests for Proof Verification
 *
 * These tests verify the complete flow of:
 * - Host generating valid signatures off-chain
 * - Submitting signed proofs on-chain
 * - Proof verification and marking as verified
 * - Multiple proofs in sessions
 * - Non-transferability of signatures between hosts
 */
contract ProofVerificationE2ETest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    NodeRegistryWithModelsUpgradeable public nodeRegistry;
    ModelRegistryUpgradeable public modelRegistry;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;

    address public owner = address(0x1);
    address public user = address(0x4);
    address public treasury = address(0x5);

    // Host 1 with proper private key
    uint256 public host1PrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host1;

    // Host 2 with different private key
    uint256 public host2PrivateKey = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
    address public host2;

    bytes32 public modelId;

    uint256 constant feeBasisPoints = 1000;
    uint256 constant disputeWindow = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    function setUp() public {
        // Derive addresses from private keys
        host1 = vm.addr(host1PrivateKey);
        host2 = vm.addr(host2PrivateKey);

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
        marketplace.setTreasury(treasury);

        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Authorize marketplace in ProofSystem
        proofSystem.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Register host1 in NodeRegistry
        fabToken.mint(host1, 10000 * 10**18);
        vm.prank(host1);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        vm.prank(host1);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host1.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        // Register host2 in NodeRegistry
        fabToken.mint(host2, 10000 * 10**18);
        vm.prank(host2);
        fabToken.approve(address(nodeRegistry), type(uint256).max);

        vm.prank(host2);
        nodeRegistry.registerNode(
            '{"hardware": "GPU"}',
            "https://api.host2.com",
            models,
            MIN_PRICE_NATIVE,
            MIN_PRICE_STABLE
        );

        // Setup user with ETH
        vm.deal(user, 100 ether);
        vm.deal(host1, 100 ether);
        vm.deal(host2, 100 ether);
    }

    // ============================================================
    // Full Flow Tests
    // ============================================================

    /**
     * @notice Test complete flow: create session, submit signed proof, complete session
     */
    function test_FullFlowWithSignedProof() public {
        // Step 1: User creates session with host1
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host1,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Step 2: Advance time for rate limiting
        vm.warp(block.timestamp + 10);

        // Step 3: Host generates proof and signs it
        bytes32 proofHash = keccak256("AI inference output batch 1");
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignature(host1PrivateKey, proofHash, host1, tokensClaimed);

        // Step 4: Host submits signed proof
        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProofCID1", "");

        // Step 5: Verify proof was accepted and marked as verified
        (bytes32 storedHash, uint256 storedTokens, , bool verified, ) = marketplace.getProofSubmission(sessionId, 0);
        assertEq(storedHash, proofHash, "Proof hash should match");
        assertEq(storedTokens, tokensClaimed, "Tokens claimed should match");
        assertTrue(verified, "Proof should be verified");

        // Step 6: Verify tokens were credited to session
        (,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensClaimed, "Tokens should be credited");

        // Step 7: Complete the session
        vm.warp(block.timestamp + disputeWindow + 1);
        vm.prank(user);
        marketplace.completeSessionJob(sessionId, "QmConversationCID");

        // Step 8: Verify host received earnings
        uint256 hostEarningsBalance = hostEarnings.getBalance(host1, address(0));
        assertTrue(hostEarningsBalance > 0, "Host should have earnings");
    }

    /**
     * @notice Test host generates valid signature off-chain and submits on-chain
     */
    function test_HostSignsProofOffChain() public {
        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.5 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.warp(block.timestamp + 5);

        // Simulate off-chain signing process
        // 1. Host computes hash of work done
        bytes memory workData = abi.encodePacked("User prompt", "AI response with 500 tokens");
        bytes32 proofHash = keccak256(workData);

        // 2. Host determines tokens claimed
        uint256 tokensClaimed = 500;

        // 3. Host signs: keccak256(proofHash, hostAddress, tokensClaimed)
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, host1, tokensClaimed));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", dataHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(host1PrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 4. Host submits on-chain
        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProofCID", "");

        // Verify proof accepted
        (,,, bool verified, ) = marketplace.getProofSubmission(sessionId, 0);
        assertTrue(verified, "Off-chain signed proof should be verified");
    }

    /**
     * @notice Test multiple proofs in same session are all verified
     */
    function test_MultipleProofsAllVerified() public {
        // Create session with larger deposit
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 5 ether}(
            host1,
            modelId,
            MIN_PRICE_NATIVE,
            2 days,
            1000
        );

        // Use explicit base timestamp to avoid vm.warp issues in loops
        uint256 baseTime = 1000;
        vm.warp(baseTime);

        // Submit 5 proofs with different proof hashes
        // Rate limiting: tokensClaimable = timeSinceLastProof * 1000, and allows up to 2x
        // Using 100 tokens with 1 second gap is well within limits (100 <= 2000)
        uint256 tokensPerProof = 100;
        for (uint256 i = 0; i < 5; i++) {
            bytes32 proofHash = keccak256(abi.encodePacked("proof batch ", i));
            bytes memory signature = _generateSignature(host1PrivateKey, proofHash, host1, tokensPerProof);

            vm.prank(host1);
            marketplace.submitProofOfWork(sessionId, tokensPerProof, proofHash, signature, "QmProofCID", "");

            // Advance time between proofs using explicit value
            baseTime += 1;
            vm.warp(baseTime);
        }

        // Verify all 5 proofs are marked as verified
        for (uint256 i = 0; i < 5; i++) {
            (,,, bool verified, ) = marketplace.getProofSubmission(sessionId, i);
            assertTrue(verified, "All proofs should be verified");
        }

        // Verify total tokens credited
        (,,,,,, uint256 tokensUsed,,,,,,,,,, ) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensPerProof * 5, "All tokens should be credited");
    }

    /**
     * @notice Test signatures are non-transferable between hosts
     */
    function test_ProofNotTransferableBetweenHosts() public {
        // Create session with host1
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJobForModel{value: 1 ether}(
            host1,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Create session with host2
        vm.prank(user);
        uint256 sessionId2 = marketplace.createSessionJobForModel{value: 1 ether}(
            host2,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.warp(block.timestamp + 10);

        // Host1 creates a valid signature for their proof
        bytes32 proofHash = keccak256("work done by host1");
        uint256 tokensClaimed = 500;
        bytes memory host1Signature = _generateSignature(host1PrivateKey, proofHash, host1, tokensClaimed);

        // Host1 can use their own signature - should succeed
        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId1, tokensClaimed, proofHash, host1Signature, "QmProofCID", "");

        // Verify proof was accepted for host1's session
        (,,, bool verified, ) = marketplace.getProofSubmission(sessionId1, 0);
        assertTrue(verified, "Host1's signature should work for host1's session");

        // Generate different proofHash for host2 (cannot reuse same proofHash)
        bytes32 proofHash2 = keccak256("attempted replay by host2");

        // Host2 tries to use host1's signature format but for host2's session
        // This should fail because the signature was made for host1's address
        bytes memory host1SignatureForHost2 = _generateSignature(host1PrivateKey, proofHash2, host1, tokensClaimed);

        vm.prank(host2);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId2, tokensClaimed, proofHash2, host1SignatureForHost2, "QmProofCID", "");
    }

    /**
     * @notice Test that different hosts have completely independent signature spaces
     * @dev Each host signs their own unique proof data (representing their work output)
     */
    function test_DifferentHostsIndependentSignatures() public {
        // Create sessions for both hosts
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 1 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.prank(user);
        uint256 sessionId2 = marketplace.createSessionJob{value: 1 ether}(
            host2,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.warp(block.timestamp + 10);

        // Each host signs their own unique proofHash (representing their work)
        // In practice, each host's AI output would be different, thus different proofHashes
        bytes32 proofHash1 = keccak256("host1 work output");
        bytes32 proofHash2 = keccak256("host2 work output");
        uint256 tokensClaimed = 500;

        bytes memory sig1 = _generateSignature(host1PrivateKey, proofHash1, host1, tokensClaimed);
        bytes memory sig2 = _generateSignature(host2PrivateKey, proofHash2, host2, tokensClaimed);

        // Host1 uses their signature on their session
        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId1, tokensClaimed, proofHash1, sig1, "QmCID1", "");

        // Host2 uses their signature on their session
        vm.prank(host2);
        marketplace.submitProofOfWork(sessionId2, tokensClaimed, proofHash2, sig2, "QmCID2", "");

        // Both proofs should be verified
        (,,, bool verified1, ) = marketplace.getProofSubmission(sessionId1, 0);
        (,,, bool verified2, ) = marketplace.getProofSubmission(sessionId2, 0);

        assertTrue(verified1, "Host1's proof should be verified");
        assertTrue(verified2, "Host2's proof should be verified");
    }

    /**
     * @notice Test tampered signature is rejected
     */
    function test_TamperedSignatureRejected() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.warp(block.timestamp + 10);

        bytes32 proofHash = keccak256("valid work");
        uint256 tokensClaimed = 500;
        bytes memory validSignature = _generateSignature(host1PrivateKey, proofHash, host1, tokensClaimed);

        // Tamper with the signature by modifying one byte
        bytes memory tamperedSignature = validSignature;
        tamperedSignature[0] = bytes1(uint8(tamperedSignature[0]) ^ 0xFF);

        vm.prank(host1);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, tamperedSignature, "QmProofCID", "");
    }

    /**
     * @notice Test claiming different token amount than signed fails
     */
    function test_DifferentTokenAmountFails() public {
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 1 ether}(
            host1,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        vm.warp(block.timestamp + 10);

        bytes32 proofHash = keccak256("work done");
        uint256 signedTokens = 500;
        uint256 claimedTokens = 600; // Different from signed amount

        // Sign for 500 tokens
        bytes memory signature = _generateSignature(host1PrivateKey, proofHash, host1, signedTokens);

        // Try to claim 600 tokens - should fail because signature was for 500
        vm.prank(host1);
        vm.expectRevert("Invalid proof signature");
        marketplace.submitProofOfWork(sessionId, claimedTokens, proofHash, signature, "QmProofCID", "");
    }

    /**
     * @notice Test complete session flow with USDC payment
     */
    function test_FullFlowWithUSDC() public {
        // Setup USDC
        usdcToken.mint(user, 1000 * 10**6); // 1000 USDC

        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);

        // Owner sets USDC address
        vm.prank(owner);
        marketplace.setUsdcAddress(address(usdcToken));

        // Create session with USDC
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host1,
            modelId,
            address(usdcToken),
            100 * 10**6, // 100 USDC deposit
            MIN_PRICE_STABLE,
            1 days,
            1000
        );

        vm.warp(block.timestamp + 10);

        // Submit signed proof
        bytes32 proofHash = keccak256("USDC payment work");
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignature(host1PrivateKey, proofHash, host1, tokensClaimed);

        vm.prank(host1);
        marketplace.submitProofOfWork(sessionId, tokensClaimed, proofHash, signature, "QmProofCID", "");

        // Verify proof is verified
        (,,, bool verified, ) = marketplace.getProofSubmission(sessionId, 0);
        assertTrue(verified, "USDC session proof should be verified");
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /**
     * @dev Generate a valid ECDSA signature for the given proof
     */
    function _generateSignature(
        uint256 privateKey,
        bytes32 proofHash,
        address signer,
        uint256 tokensClaimed
    ) internal view returns (bytes memory) {
        // Create the message hash that will be signed
        // Must match ProofSystem._verifyHostSignature: keccak256(proofHash, prover, claimedTokens)
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, signer, tokensClaimed));

        // Create Ethereum signed message hash (EIP-191)
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            dataHash
        ));

        // Sign with private key using Foundry's vm.sign cheatcode
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);

        // Return 65-byte signature (r, s, v)
        return abi.encodePacked(r, s, v);
    }
}
