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
 * @title DeltaCID Tests
 * @dev Tests for deltaCID parameter in submitProofOfWork and ProofSubmitted event
 *
 * Phase 1 TDD: These tests are written BEFORE implementation.
 * They should fail to compile until the contract is updated.
 */
contract DeltaCIDTest is Test {
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

    // Host with proper private key for signing
    uint256 public hostPrivateKey = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address public host;

    bytes32 public modelId;

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant MIN_PRICE_NATIVE = 227_273;
    uint256 constant MIN_PRICE_STABLE = 1;

    // Event declaration matching the NEW signature with deltaCID
    event ProofSubmitted(
        uint256 indexed jobId,
        address indexed host,
        uint256 tokensClaimed,
        bytes32 proofHash,
        string proofCID,
        string deltaCID  // NEW field
    );

    function setUp() public {
        // Derive address from private key
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
                FEE_BASIS_POINTS,
                DISPUTE_WINDOW
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

        // Setup user and host with ETH
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);
    }

    // ============================================================
    // deltaCID Tests
    // ============================================================

    /**
     * @notice Test that ProofSubmitted event includes deltaCID
     * @dev Verifies the event emission contains the new deltaCID field
     */
    function test_ProofSubmittedEventIncludesDeltaCID() public {
        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Advance time for rate limiting
        vm.warp(block.timestamp + 10);

        // Generate proof and signature
        bytes32 proofHash = keccak256("AI inference output batch 1");
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignature(hostPrivateKey, proofHash, host, tokensClaimed);

        // Expect event with deltaCID
        vm.expectEmit(true, true, false, true);
        emit ProofSubmitted(sessionId, host, tokensClaimed, proofHash, "QmProofCID", "QmDeltaCID123");

        // Submit proof with deltaCID (6 parameters)
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            tokensClaimed,
            proofHash,
            signature,
            "QmProofCID",
            "QmDeltaCID123"  // NEW: deltaCID parameter
        );
    }

    /**
     * @notice Test that deltaCID is stored in ProofSubmission struct
     * @dev Verifies getProofSubmission returns the correct deltaCID
     */
    function test_DeltaCIDStoredInProofSubmission() public {
        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Advance time
        vm.warp(block.timestamp + 10);

        // Generate and submit proof with deltaCID
        bytes32 proofHash = keccak256("AI inference output");
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignature(hostPrivateKey, proofHash, host, tokensClaimed);

        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            tokensClaimed,
            proofHash,
            signature,
            "QmProofCID",
            "QmDeltaCID_Stored"  // deltaCID to store
        );

        // Retrieve proof and verify deltaCID (5 return values)
        (
            bytes32 storedHash,
            uint256 storedTokens,
            ,
            bool verified,
            string memory deltaCID
        ) = marketplace.getProofSubmission(sessionId, 0);

        assertEq(storedHash, proofHash, "Proof hash should match");
        assertEq(storedTokens, tokensClaimed, "Tokens should match");
        assertTrue(verified, "Proof should be verified");
        assertEq(deltaCID, "QmDeltaCID_Stored", "deltaCID should match");
    }

    /**
     * @notice Test multiple proofs with different deltaCIDs
     * @dev Verifies each proof stores its own unique deltaCID
     */
    function test_MultipleProofsWithDifferentDeltaCIDs() public {
        // Create session with larger deposit
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 5 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            2 days,
            1000
        );

        uint256 baseTime = 1000;
        vm.warp(baseTime);

        // Submit 3 proofs with different deltaCIDs
        string[3] memory deltaCIDs = ["QmDelta1", "QmDelta2", "QmDelta3"];

        for (uint256 i = 0; i < 3; i++) {
            bytes32 proofHash = keccak256(abi.encodePacked("proof batch ", i));
            uint256 tokensClaimed = 100;
            bytes memory signature = _generateSignature(hostPrivateKey, proofHash, host, tokensClaimed);

            vm.prank(host);
            marketplace.submitProofOfWork(
                sessionId,
                tokensClaimed,
                proofHash,
                signature,
                "QmProofCID",
                deltaCIDs[i]  // Different deltaCID for each
            );

            baseTime += 1;
            vm.warp(baseTime);
        }

        // Verify each proof has correct deltaCID
        for (uint256 i = 0; i < 3; i++) {
            (, , , , string memory storedDeltaCID) = marketplace.getProofSubmission(sessionId, i);
            assertEq(storedDeltaCID, deltaCIDs[i], string(abi.encodePacked("deltaCID ", i, " should match")));
        }
    }

    /**
     * @notice Test that empty deltaCID is allowed
     * @dev Verifies submitting proof with empty string deltaCID does not revert
     */
    function test_EmptyDeltaCIDAllowed() public {
        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Advance time
        vm.warp(block.timestamp + 10);

        // Generate proof
        bytes32 proofHash = keccak256("AI inference output");
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignature(hostPrivateKey, proofHash, host, tokensClaimed);

        // Submit with empty deltaCID - should not revert
        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            tokensClaimed,
            proofHash,
            signature,
            "QmProofCID",
            ""  // Empty deltaCID
        );

        // Verify proof was stored with empty deltaCID
        (, , , , string memory storedDeltaCID) = marketplace.getProofSubmission(sessionId, 0);
        assertEq(storedDeltaCID, "", "Empty deltaCID should be stored");
    }

    /**
     * @notice Test getProofSubmission returns deltaCID correctly
     * @dev Verifies the getter function returns all 5 values including deltaCID
     */
    function test_GetProofSubmissionReturnsDeltaCID() public {
        // Create session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            MIN_PRICE_NATIVE,
            1 days,
            1000
        );

        // Advance time
        vm.warp(block.timestamp + 10);

        // Submit proof with specific deltaCID
        bytes32 proofHash = keccak256("test proof");
        uint256 tokensClaimed = 500;
        bytes memory signature = _generateSignature(hostPrivateKey, proofHash, host, tokensClaimed);

        string memory expectedDeltaCID = "QmDeltaCID_GetterTest_12345";

        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            tokensClaimed,
            proofHash,
            signature,
            "QmProofCID",
            expectedDeltaCID
        );

        // Call getter and verify all 5 return values
        (
            bytes32 returnedHash,
            uint256 returnedTokens,
            uint256 returnedTimestamp,
            bool returnedVerified,
            string memory returnedDeltaCID
        ) = marketplace.getProofSubmission(sessionId, 0);

        assertEq(returnedHash, proofHash, "Hash should match");
        assertEq(returnedTokens, tokensClaimed, "Tokens should match");
        assertGt(returnedTimestamp, 0, "Timestamp should be set");
        assertTrue(returnedVerified, "Should be verified");
        assertEq(returnedDeltaCID, expectedDeltaCID, "deltaCID should match expected");
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
