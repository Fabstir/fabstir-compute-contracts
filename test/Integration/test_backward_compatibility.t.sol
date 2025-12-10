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
 * @title BackwardCompatibilityTest
 * @notice Integration tests verifying all existing functionality works unchanged
 * @dev Phase 4.1 - Ensures backward compatibility after flexible pricing additions
 */
contract BackwardCompatibilityTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    HostEarnings public hostEarnings;
    ProofSystem public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    // With PRICE_PRECISION=1000: prices are 1000x for sub-cent granularity
    uint256 constant HOST_MIN_PRICE_NATIVE = 3_000_000; // ~$0.013/million @ $4400 ETH
    uint256 constant HOST_MIN_PRICE_STABLE = 5000; // $5/million
    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC Token", "USDC");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

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

        // Fund user
        vm.deal(user, 100 ether);
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    // ============ Helper Functions ============

    function _registerHost() internal {
        vm.startPrank(owner);
        fabToken.mint(host, MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            HOST_MIN_PRICE_NATIVE,
            HOST_MIN_PRICE_STABLE
        );
        vm.stopPrank();
    }

    // ============ Backward Compatibility Tests ============

    /// @notice Test that node registration with default pricing still works unchanged
    function test_RegisterNodeWithDefaultPricingWorks() public {
        vm.startPrank(owner);
        fabToken.mint(host, MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        // Register with default pricing (same as before flexible pricing)
        nodeRegistry.registerNode(
            "test-metadata",
            "https://api.test.com",
            models,
            HOST_MIN_PRICE_NATIVE,
            HOST_MIN_PRICE_STABLE
        );
        vm.stopPrank();

        // Verify node data is correct (public getter returns 7 fields, excludes bytes32[] array)
        (
            address operator,
            uint256 stakedAmount,
            bool active,
            string memory metadata,
            string memory apiUrl,
            uint256 minPriceNative,
            uint256 minPriceStable
        ) = nodeRegistry.nodes(host);

        assertEq(operator, host, "Operator should be host");
        assertEq(stakedAmount, MIN_STAKE, "Staked amount should match");
        assertTrue(active, "Node should be active");
        assertEq(metadata, "test-metadata", "Metadata should match");
        assertEq(apiUrl, "https://api.test.com", "API URL should match");
        assertEq(minPriceNative, HOST_MIN_PRICE_NATIVE, "Native price should match");
        assertEq(minPriceStable, HOST_MIN_PRICE_STABLE, "Stable price should match");

        // Verify model is associated
        assertTrue(nodeRegistry.nodeSupportsModel(host, modelId), "Host should support model");
    }

    /// @notice Test that createSessionJob() without model parameter still works
    function test_CreateSessionJobWithoutModelWorks() public {
        _registerHost();

        uint256 deposit = 1 ether;
        uint256 pricePerToken = HOST_MIN_PRICE_NATIVE;
        uint256 maxDuration = 3600;
        uint256 proofInterval = 100;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host,
            pricePerToken,
            maxDuration,
            proofInterval
        );

        // Verify session was created correctly
        (
            uint256 id,
            address depositor,
            ,  // requester
            address sessionHost,
            address paymentToken,
            uint256 sessionDeposit,
            uint256 storedPrice,
            ,  // tokensUsed
            uint256 storedMaxDuration,
            ,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(sessionHost, host, "Host should match");
        assertEq(paymentToken, address(0), "Payment token should be native");
        assertEq(sessionDeposit, deposit, "Deposit should match");
        assertEq(storedPrice, pricePerToken, "Price should match");
        assertEq(storedMaxDuration, maxDuration, "Max duration should match");

        // Verify sessionModel defaults to bytes32(0) for legacy sessions
        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, bytes32(0), "sessionModel should default to bytes32(0)");
    }

    /// @notice Test that createSessionJobWithToken() without model parameter still works
    function test_CreateSessionJobWithTokenWithoutModelWorks() public {
        _registerHost();

        uint256 deposit = 10e6; // 10 USDC
        uint256 pricePerToken = HOST_MIN_PRICE_STABLE;
        uint256 maxDuration = 3600;
        uint256 proofInterval = 100;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            deposit,
            pricePerToken,
            maxDuration,
            proofInterval
        );

        // Verify session was created correctly
        (
            uint256 id,
            address depositor,
            ,  // requester
            address sessionHost,
            address paymentToken,
            uint256 sessionDeposit,
            uint256 storedPrice,
            ,  // tokensUsed
            uint256 storedMaxDuration,
            ,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(sessionHost, host, "Host should match");
        assertEq(paymentToken, address(usdcToken), "Payment token should be USDC");
        assertEq(sessionDeposit, deposit, "Deposit should match");
        assertEq(storedPrice, pricePerToken, "Price should match");
        assertEq(storedMaxDuration, maxDuration, "Max duration should match");

        // Verify sessionModel defaults to bytes32(0) for legacy sessions
        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, bytes32(0), "sessionModel should default to bytes32(0)");
    }

    /// @notice Test that getNodePricing() returns correct default values
    function test_GetNodePricingReturnsCorrectDefaults() public {
        _registerHost();

        // Query native pricing (address(0))
        uint256 nativePrice = nodeRegistry.getNodePricing(host, address(0));
        assertEq(nativePrice, HOST_MIN_PRICE_NATIVE, "Native price should return default");

        // Query stable pricing (USDC address)
        uint256 stablePrice = nodeRegistry.getNodePricing(host, address(usdcToken));
        assertEq(stablePrice, HOST_MIN_PRICE_STABLE, "Stable price should return default");

        // Query with any other token address should return stable price
        address randomToken = address(0x1234);
        uint256 otherPrice = nodeRegistry.getNodePricing(host, randomToken);
        assertEq(otherPrice, HOST_MIN_PRICE_STABLE, "Other token price should return stable default");
    }

    /// @notice Test that the existing session flow works unchanged (full lifecycle)
    function test_ExistingSessionFlowUnchanged() public {
        _registerHost();

        // Step 1: Create session using legacy function
        uint256 deposit = 1 ether;
        uint256 pricePerToken = HOST_MIN_PRICE_NATIVE;
        uint256 proofInterval = 100;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: deposit}(
            host,
            pricePerToken,
            3600,
            proofInterval
        );

        // Step 2: Submit proof of work (as host)
        // submitProofOfWork(jobId, tokensClaimed, proofHash, proofCID)
        // Warp time forward to allow proof submission (avoids "Excessive tokens claimed")
        vm.warp(block.timestamp + 60);

        uint256 tokensToProve = 100;

        vm.prank(host);
        marketplace.submitProofOfWork(
            sessionId,
            tokensToProve,
            bytes32(keccak256("test-proof")),
            "QmTestCID"
        );

        // Verify tokens used increased
        (,,,,,,, uint256 tokensUsed,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensToProve, "Tokens used should be updated");

        // Step 3: Complete session (anyone can call)
        // completeSessionJob(jobId, conversationCID)
        vm.prank(host);
        marketplace.completeSessionJob(sessionId, "QmConversationCID");

        // Verify session is completed (status is field 13, index 12)
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Completed), "Session should be completed");
    }

    /// @notice Test that sessionModel mapping defaults to bytes32(0) for legacy sessions
    function test_SessionModelDefaultsToZeroForLegacySessions() public {
        _registerHost();

        // Create multiple sessions using legacy functions
        vm.startPrank(user);

        // Native session
        uint256 sessionId1 = marketplace.createSessionJob{value: 1 ether}(
            host,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        // Token session
        uint256 sessionId2 = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        vm.stopPrank();

        // Verify both sessions have sessionModel = bytes32(0)
        assertEq(marketplace.sessionModel(sessionId1), bytes32(0), "Native session model should be bytes32(0)");
        assertEq(marketplace.sessionModel(sessionId2), bytes32(0), "Token session model should be bytes32(0)");

        // Verify non-existent sessions also return bytes32(0)
        assertEq(marketplace.sessionModel(999), bytes32(0), "Non-existent session model should be bytes32(0)");
    }

    /// @notice Test that existing pricing update functions still work
    function test_ExistingPricingUpdateFunctionsWork() public {
        _registerHost();

        uint256 newNativePrice = HOST_MIN_PRICE_NATIVE * 2;
        uint256 newStablePrice = HOST_MIN_PRICE_STABLE * 2;

        // Update native pricing
        vm.prank(host);
        nodeRegistry.updatePricingNative(newNativePrice);

        // Update stable pricing
        vm.prank(host);
        nodeRegistry.updatePricingStable(newStablePrice);

        // Verify prices updated
        uint256 updatedNative = nodeRegistry.getNodePricing(host, address(0));
        uint256 updatedStable = nodeRegistry.getNodePricing(host, address(usdcToken));

        assertEq(updatedNative, newNativePrice, "Native price should be updated");
        assertEq(updatedStable, newStablePrice, "Stable price should be updated");
    }

    /// @notice Test that new and legacy session creation can coexist
    function test_NewAndLegacySessionsCoexist() public {
        _registerHost();

        vm.startPrank(user);

        // Create legacy native session
        uint256 legacyNativeId = marketplace.createSessionJob{value: 1 ether}(
            host,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        // Create legacy token session
        uint256 legacyTokenId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        // Create new model-aware native session
        uint256 modelNativeId = marketplace.createSessionJobForModel{value: 1 ether}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        // Create new model-aware token session
        uint256 modelTokenId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        vm.stopPrank();

        // Verify all sessions exist with correct IDs (nextJobId starts at 1)
        assertEq(legacyNativeId, 1, "Legacy native should be session 1");
        assertEq(legacyTokenId, 2, "Legacy token should be session 2");
        assertEq(modelNativeId, 3, "Model native should be session 3");
        assertEq(modelTokenId, 4, "Model token should be session 4");

        // Verify sessionModel mapping is correct
        assertEq(marketplace.sessionModel(legacyNativeId), bytes32(0), "Legacy native should have no model");
        assertEq(marketplace.sessionModel(legacyTokenId), bytes32(0), "Legacy token should have no model");
        assertEq(marketplace.sessionModel(modelNativeId), modelId, "Model native should have modelId");
        assertEq(marketplace.sessionModel(modelTokenId), modelId, "Model token should have modelId");
    }
}
