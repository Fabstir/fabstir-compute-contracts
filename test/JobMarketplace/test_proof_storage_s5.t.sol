// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../src/ModelRegistry.sol";
import {HostEarnings} from "../../src/HostEarnings.sol";
import {ProofSystem} from "../../src/ProofSystem.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
 * @title JobMarketplaceS5ProofStorageTest
 * @notice Tests S5 off-chain proof storage with hash + CID on-chain
 * @dev Validates submitProofOfWork accepts proofHash and proofCID instead of full proof bytes
 */
contract JobMarketplaceS5ProofStorageTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    HostEarnings public hostEarnings;
    ProofSystem public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public host = address(2);
    address public renter = address(3);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30;

    // Test data
    bytes32 constant MOCK_PROOF_HASH = bytes32(uint256(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef));
    string constant MOCK_PROOF_CID = "u8pDTQHOOYtest123abcdef1234567890abcdef1234567890";

    uint256 public testJobId;

    event ProofSubmitted(
        uint256 indexed jobId,
        address indexed host,
        uint256 tokensClaimed,
        bytes32 proofHash,
        string proofCID
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC", "USDC");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        // Deploy contracts
        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));
        proofSystem = new ProofSystem();
        hostEarnings = new HostEarnings();
        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            DISPUTE_WINDOW
        );

        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        // Add approved model
        modelRegistry.addTrustedModel(
            "CohereForAI/TinyVicuna-1B-32k-GGUF",
            "tiny-vicuna-1b.q4_k_m.gguf",
            bytes32(0)
        );

        vm.stopPrank();

        // Set proof system
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));

        // Place mock USDC at actual Base Sepolia USDC address
        address actualUsdcAddress = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        vm.etch(actualUsdcAddress, address(usdcToken).code);
        usdcToken = ERC20Mock(actualUsdcAddress);

        // Setup host
        vm.startPrank(host);
        fabToken.mint(host, MIN_STAKE);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            3_000_000_000, // Native price
            5000           // Stable price
        );

        vm.stopPrank();

        // Fund renter
        vm.deal(renter, 100 ether);

        // Create test session
        vm.prank(renter);
        testJobId = marketplace.createSessionJob{value: 0.01 ether}(
            host,
            3_000_000_000, // Price per token
            3600,          // 1 hour
            100            // Proof interval
        );
    }

    /// @notice Test submitProofOfWork accepts proofHash and proofCID
    function test_SubmitProofOfWork_WithHashAndCID() public {
        uint256 tokensClaimed = 100;

        // Advance time to allow enough tokens (100 tokens / 10 tokens per second = 10 seconds minimum)
        vm.warp(block.timestamp + 10);

        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Verify storage (will add getter or read from sessionJobs)
        // This test verifies function signature is correct
    }

    /// @notice Test proof hash is stored correctly
    function test_SubmitProofOfWork_StoresProofHash() public {
        uint256 tokensClaimed = 100;

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Read storage to verify hash stored
        (, , , , , , , uint256 tokensUsed, , , uint256 lastProofTime, , , , , , bytes32 storedHash, string memory storedCID)
            = marketplace.sessionJobs(testJobId);

        assertEq(storedHash, MOCK_PROOF_HASH, "Proof hash not stored correctly");
    }

    /// @notice Test proof CID is stored correctly
    function test_SubmitProofOfWork_StoresProofCID() public {
        uint256 tokensClaimed = 100;

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Read storage to verify CID stored
        (, , , , , , , , , , , , , , , , , string memory storedCID)
            = marketplace.sessionJobs(testJobId);

        assertEq(storedCID, MOCK_PROOF_CID, "Proof CID not stored correctly");
    }

    /// @notice Test event is emitted with hash and CID
    function test_SubmitProofOfWork_EmitsEventWithCID() public {
        uint256 tokensClaimed = 100;

        vm.warp(block.timestamp + 10);
        vm.expectEmit(true, true, false, true);
        emit ProofSubmitted(testJobId, host, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);
    }

    /// @notice Test transaction size is small (<1KB vs 221KB full proof)
    function test_SubmitProofOfWork_TransactionSize() public {
        uint256 tokensClaimed = 100;

        // Encode transaction data
        bytes memory txData = abi.encodeWithSignature(
            "submitProofOfWork(uint256,uint256,bytes32,string)",
            testJobId,
            tokensClaimed,
            MOCK_PROOF_HASH,
            MOCK_PROOF_CID
        );

        // Verify transaction size is well under 128KB RPC limit
        // Should be ~300 bytes vs 221KB for full proof
        assertLt(txData.length, 1024, "Transaction too large");

        // Also verify it's significantly smaller than old approach
        assertLt(txData.length, 500, "Transaction should be ~300 bytes");
    }

    /// @notice Test lastProofTime is updated
    function test_SubmitProofOfWork_UpdatesLastProofTime() public {
        uint256 tokensClaimed = 100;

        // Advance time
        vm.warp(block.timestamp + 10);
        // Get time before submission
        uint256 beforeTime = block.timestamp;

        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Read lastProofTime from storage
        (, , , , , , , , , , uint256 lastProofTime, , , , , , , )
            = marketplace.sessionJobs(testJobId);

        assertEq(lastProofTime, beforeTime, "Last proof time not updated");
    }

    /// @notice Test tokensUsed is incremented correctly
    function test_SubmitProofOfWork_IncrementsTokensUsed() public {
        uint256 tokensClaimed = 100;

        // Get tokens used before
        (, , , , , , , uint256 tokensUsedBefore, , , , , , , , , , )
            = marketplace.sessionJobs(testJobId);

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, tokensClaimed, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Get tokens used after
        (, , , , , , , uint256 tokensUsedAfter, , , , , , , , , , )
            = marketplace.sessionJobs(testJobId);

        assertEq(tokensUsedAfter, tokensUsedBefore + tokensClaimed, "Tokens used not incremented");
    }

    /// @notice Test multiple proof submissions update hash and CID
    function test_SubmitProofOfWork_MultipleSubmissions() public {
        // First submission
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, 100, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Second submission with different hash and CID - advance time from last proof time
        bytes32 secondHash = bytes32(uint256(0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890));
        string memory secondCID = "u8pDTQHOOY_second_proof_cid_test";

        vm.warp(block.timestamp + 20); // Advance more time for second proof
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, 100, secondHash, secondCID);

        // Verify latest proof hash and CID are stored
        (, , , , , , , , , , , , , , , , bytes32 storedHash, string memory storedCID)
            = marketplace.sessionJobs(testJobId);

        assertEq(storedHash, secondHash, "Second proof hash not stored");
        assertEq(storedCID, secondCID, "Second proof CID not stored");
    }

    /// @notice Test only host can submit proof
    function test_SubmitProofOfWork_OnlyHostCanSubmit() public {
        vm.prank(renter);
        vm.expectRevert("Only host can submit proof");
        marketplace.submitProofOfWork(testJobId, 100, MOCK_PROOF_HASH, MOCK_PROOF_CID);
    }

    /// @notice Test cannot submit proof for inactive session
    function test_SubmitProofOfWork_RequiresActiveSession() public {
        // Complete the session first
        vm.prank(renter);
        marketplace.completeSessionJob(testJobId, "conversationCID");

        // Try to submit proof
        vm.prank(host);
        vm.expectRevert("Session not active");
        marketplace.submitProofOfWork(testJobId, 100, MOCK_PROOF_HASH, MOCK_PROOF_CID);
    }

    /// @notice Test minimum tokens requirement still enforced
    function test_SubmitProofOfWork_MinimumTokensRequired() public {
        vm.prank(host);
        vm.expectRevert("Must claim minimum tokens");
        marketplace.submitProofOfWork(testJobId, 50, MOCK_PROOF_HASH, MOCK_PROOF_CID); // Below MIN_PROVEN_TOKENS (100)
    }

    /// @notice Test cannot exceed deposit
    function test_SubmitProofOfWork_CannotExceedDeposit() public {
        // Try to claim more tokens than deposit allows
        uint256 excessiveTokens = 100000000; // Way more than deposit allows

        // Warp enough time to pass time validation (100000000 tokens / 10 tokens per second / 2 for buffer = 5000000 seconds)
        vm.warp(block.timestamp + 10000000);

        vm.prank(host);
        vm.expectRevert("Exceeds deposit");
        marketplace.submitProofOfWork(testJobId, excessiveTokens, MOCK_PROOF_HASH, MOCK_PROOF_CID);
    }

    /// @notice Test proof submission with realistic CID length
    function test_SubmitProofOfWork_RealisticCIDLength() public {
        // S5 CIDs are typically 50-100 characters
        string memory realisticCID = "u8pDTQHOOYabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, 100, MOCK_PROOF_HASH, realisticCID);

        // Verify CID stored correctly even with long string
        (, , , , , , , , , , , , , , , , , string memory storedCID)
            = marketplace.sessionJobs(testJobId);

        assertEq(storedCID, realisticCID, "Long CID not stored correctly");
    }

    /// @notice Test empty CID is allowed (for testing/debugging)
    function test_SubmitProofOfWork_AllowsEmptyCID() public {
        string memory emptyCID = "";

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, 100, MOCK_PROOF_HASH, emptyCID);

        // Verify empty CID stored
        (, , , , , , , , , , , , , , , , , string memory storedCID)
            = marketplace.sessionJobs(testJobId);

        assertEq(storedCID, emptyCID, "Empty CID should be allowed");
    }

    /// @notice Test zero hash is allowed (edge case)
    function test_SubmitProofOfWork_AllowsZeroHash() public {
        bytes32 zeroHash = bytes32(0);

        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, 100, zeroHash, MOCK_PROOF_CID);

        // Verify zero hash stored
        (, , , , , , , , , , , , , , , , bytes32 storedHash, )
            = marketplace.sessionJobs(testJobId);

        assertEq(storedHash, zeroHash, "Zero hash should be allowed");
    }

    /// @notice Test integration: Create session, submit proof, complete session
    function test_Integration_SessionWithS5Proof() public {
        // Submit proof
        vm.warp(block.timestamp + 10);
        vm.prank(host);
        marketplace.submitProofOfWork(testJobId, 100, MOCK_PROOF_HASH, MOCK_PROOF_CID);

        // Verify tokens used
        (, , , , , , , uint256 tokensUsed, , , , , , , , , , )
            = marketplace.sessionJobs(testJobId);
        assertEq(tokensUsed, 100, "Tokens not tracked");

        // Complete session
        vm.prank(renter);
        marketplace.completeSessionJob(testJobId, "finalConversationCID");

        // Verify session completed
        (, , , , , , , , , , , , JobMarketplaceWithModels.SessionStatus status, , , , , )
            = marketplace.sessionJobs(testJobId);
        assertEq(uint256(status), 1, "Session should be completed"); // SessionStatus.Completed = 1
    }
}
