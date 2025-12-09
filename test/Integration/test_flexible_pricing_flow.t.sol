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
 * @title FlexiblePricingFlowTest
 * @notice Integration tests for complete flexible pricing flows
 * @dev Phase 4.2 - Tests end-to-end flows with new pricing features
 */
contract FlexiblePricingFlowTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    HostEarnings public hostEarnings;
    ProofSystem public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public daiToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host1 = address(3);
    address public host2 = address(4);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    bytes32 public modelId1 = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant HOST_MIN_PRICE_NATIVE = 3_000_000_000;
    uint256 constant HOST_MIN_PRICE_STABLE = 5000;
    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant DAI_MIN_DEPOSIT = 1e18; // 1 DAI

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC Token", "USDC");
        daiToken = new ERC20Mock("DAI Token", "DAI");
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

        // Add approved models
        modelRegistry.addTrustedModel(
            "CohereForAI/TinyVicuna-1B-32k-GGUF",
            "tiny-vicuna-1b.q4_k_m.gguf",
            bytes32(0)
        );
        modelRegistry.addTrustedModel(
            "TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF",
            "TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf",
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

        // Fund user with ETH, USDC, and DAI
        vm.deal(user, 100 ether);
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);
        vm.prank(owner);
        daiToken.mint(user, 1000e18);

        vm.startPrank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
        daiToken.approve(address(marketplace), type(uint256).max);
        vm.stopPrank();
    }

    // ============ Helper Functions ============

    function _registerHost(address host, bytes32[] memory models, uint256 nativePrice, uint256 stablePrice) internal {
        vm.startPrank(owner);
        fabToken.mint(host, MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            nativePrice,
            stablePrice
        );
        vm.stopPrank();
    }

    function _registerHost1WithBothModels() internal {
        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;
        _registerHost(host1, models, HOST_MIN_PRICE_NATIVE, HOST_MIN_PRICE_STABLE);
    }

    function _registerHost2WithBothModels() internal {
        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId1;
        models[1] = modelId2;
        _registerHost(host2, models, HOST_MIN_PRICE_NATIVE, HOST_MIN_PRICE_STABLE);
    }

    // ============ Test: Host registers → sets model pricing → client creates model session ============

    /// @notice Test complete flow: host registers, sets model-specific pricing, client creates model-aware session
    function test_HostSetsModelPricingClientCreatesSession() public {
        // Step 1: Host registers with default pricing
        _registerHost1WithBothModels();

        // Step 2: Host sets model-specific pricing for modelId1 (higher than default)
        uint256 modelSpecificNative = HOST_MIN_PRICE_NATIVE * 2;
        uint256 modelSpecificStable = HOST_MIN_PRICE_STABLE * 2;

        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, modelSpecificNative, modelSpecificStable);

        // Step 3: Verify model pricing is set
        uint256 queriedPrice = nodeRegistry.getModelPricing(host1, modelId1, address(0));
        assertEq(queriedPrice, modelSpecificNative, "Model pricing should be set");

        // Step 4: Client creates session with model-specific pricing
        uint256 deposit = 1 ether;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host1,
            modelId1,
            modelSpecificNative, // Must meet model-specific minimum
            3600,
            100
        );

        // Step 5: Verify session was created with correct model
        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, modelId1, "Session model should be stored");

        // Step 6: Verify session details
        (
            uint256 id,
            address depositor,
            ,  // requester
            address sessionHost,
            address paymentToken,
            uint256 sessionDeposit,
            uint256 storedPrice,
            ,  // tokensUsed
            ,  // maxDuration
            ,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Depositor should be user");
        assertEq(sessionHost, host1, "Host should match");
        assertEq(paymentToken, address(0), "Payment token should be native");
        assertEq(sessionDeposit, deposit, "Deposit should match");
        assertEq(storedPrice, modelSpecificNative, "Price should match model-specific price");
    }

    /// @notice Test that client cannot create session with price below model minimum
    function test_HostSetsModelPricingClientCannotUnderpay() public {
        _registerHost1WithBothModels();

        // Host sets higher model-specific pricing
        uint256 modelSpecificNative = HOST_MIN_PRICE_NATIVE * 3;

        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, modelSpecificNative, HOST_MIN_PRICE_STABLE);

        // Client tries to create session with default pricing (too low)
        uint256 deposit = 1 ether;

        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionJobForModel{value: deposit}(
            host1,
            modelId1,
            HOST_MIN_PRICE_NATIVE, // Default price is now too low
            3600,
            100
        );
    }

    // ============ Test: Host registers → sets token pricing → client creates session with token ============

    /// @notice Test complete flow: host sets custom token pricing for a specific stablecoin
    function test_HostSetsTokenPricingClientUsesToken() public {
        _registerHost1WithBothModels();

        // Host sets custom pricing for USDC (higher than default stable)
        uint256 customUsdcPrice = HOST_MIN_PRICE_STABLE * 2;

        vm.prank(host1);
        nodeRegistry.setTokenPricing(address(usdcToken), customUsdcPrice);

        // Verify token pricing is set
        uint256 queriedPrice = nodeRegistry.getNodePricing(host1, address(usdcToken));
        assertEq(queriedPrice, customUsdcPrice, "Custom token pricing should be set");

        // Client creates session with custom token pricing
        uint256 deposit = 10e6; // 10 USDC

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host1,
            address(usdcToken),
            deposit,
            customUsdcPrice, // Must meet custom token minimum
            3600,
            100
        );

        // Verify session was created
        (
            uint256 id,
            ,  // depositor
            ,  // requester
            ,  // host
            address paymentToken,
            uint256 sessionDeposit,
            uint256 storedPrice,
            ,  // tokensUsed
            ,  // maxDuration
            ,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(paymentToken, address(usdcToken), "Payment token should be USDC");
        assertEq(sessionDeposit, deposit, "Deposit should match");
        assertEq(storedPrice, customUsdcPrice, "Price should match custom token price");
    }

    // ============ Test: Treasury adds new token → host sets pricing → client uses new token ============

    /// @notice Test complete flow: treasury adds DAI, host sets pricing, client uses DAI
    function test_TreasuryAddsTokenHostSetsPricingClientUses() public {
        _registerHost1WithBothModels();

        // Step 1: Treasury adds DAI as accepted token
        vm.prank(treasury);
        marketplace.addAcceptedToken(address(daiToken), DAI_MIN_DEPOSIT);

        // Step 2: Verify DAI is accepted
        assertTrue(marketplace.acceptedTokens(address(daiToken)), "DAI should be accepted");

        // Step 3: Host sets custom pricing for DAI
        uint256 customDaiPrice = 15000; // Higher than default stable

        vm.prank(host1);
        nodeRegistry.setTokenPricing(address(daiToken), customDaiPrice);

        // Step 4: Verify DAI pricing is set
        uint256 queriedPrice = nodeRegistry.getNodePricing(host1, address(daiToken));
        assertEq(queriedPrice, customDaiPrice, "Custom DAI pricing should be set");

        // Step 5: Client creates session using DAI
        uint256 deposit = 10e18; // 10 DAI

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host1,
            address(daiToken),
            deposit,
            customDaiPrice,
            3600,
            100
        );

        // Step 6: Verify session was created with DAI
        (
            ,  // id
            ,  // depositor
            ,  // requester
            ,  // host
            address paymentToken,
            uint256 sessionDeposit,
            ,  // pricePerToken
            ,  // tokensUsed
            ,  // maxDuration
            ,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(paymentToken, address(daiToken), "Payment token should be DAI");
        assertEq(sessionDeposit, deposit, "Deposit should match");
    }

    /// @notice Test that client cannot use token before treasury accepts it
    function test_ClientCannotUseUnacceptedToken() public {
        _registerHost1WithBothModels();

        // DAI is not accepted yet
        uint256 deposit = 10e18;

        vm.prank(user);
        vm.expectRevert("Token not accepted");
        marketplace.createSessionJobWithToken(
            host1,
            address(daiToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    // ============ Test: Multiple hosts with different model prices for same model ============

    /// @notice Test that different hosts can have different prices for the same model
    function test_MultipleHostsDifferentModelPrices() public {
        // Register both hosts with same default pricing
        _registerHost1WithBothModels();
        _registerHost2WithBothModels();

        // Host 1 sets premium pricing for modelId1
        uint256 host1ModelPrice = HOST_MIN_PRICE_NATIVE * 3;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, host1ModelPrice, HOST_MIN_PRICE_STABLE);

        // Host 2 sets economy pricing for modelId1
        uint256 host2ModelPrice = HOST_MIN_PRICE_NATIVE * 2;
        vm.prank(host2);
        nodeRegistry.setModelPricing(modelId1, host2ModelPrice, HOST_MIN_PRICE_STABLE);

        // Verify different prices
        uint256 price1 = nodeRegistry.getModelPricing(host1, modelId1, address(0));
        uint256 price2 = nodeRegistry.getModelPricing(host2, modelId1, address(0));

        assertEq(price1, host1ModelPrice, "Host 1 should have premium pricing");
        assertEq(price2, host2ModelPrice, "Host 2 should have economy pricing");
        assertTrue(price1 > price2, "Host 1 should be more expensive");

        // Client can choose cheaper host
        uint256 deposit = 1 ether;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host2, // Choose cheaper host
            modelId1,
            host2ModelPrice,
            3600,
            100
        );

        // Verify session created with host2
        (,, , address sessionHost,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(sessionHost, host2, "Session should be with cheaper host");
    }

    /// @notice Test that client must meet each host's minimum price
    function test_ClientMustMeetEachHostsMinimum() public {
        _registerHost1WithBothModels();
        _registerHost2WithBothModels();

        // Host 1 sets premium pricing
        uint256 host1ModelPrice = HOST_MIN_PRICE_NATIVE * 3;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, host1ModelPrice, HOST_MIN_PRICE_STABLE);

        // Host 2 sets economy pricing
        uint256 host2ModelPrice = HOST_MIN_PRICE_NATIVE * 2;
        vm.prank(host2);
        nodeRegistry.setModelPricing(modelId1, host2ModelPrice, HOST_MIN_PRICE_STABLE);

        // Client tries to use host1 with host2's price (should fail)
        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionJobForModel{value: 1 ether}(
            host1,
            modelId1,
            host2ModelPrice, // Too low for host1
            3600,
            100
        );
    }

    // ============ Test: Price fallback chain works correctly ============

    /// @notice Test the complete price fallback chain
    function test_PriceFallbackChainWorksCorrectly() public {
        _registerHost1WithBothModels();

        // Case 1: No overrides set - should return default
        uint256 defaultNative = nodeRegistry.getModelPricing(host1, modelId1, address(0));
        assertEq(defaultNative, HOST_MIN_PRICE_NATIVE, "Should return default native when no override");

        uint256 defaultStable = nodeRegistry.getModelPricing(host1, modelId1, address(usdcToken));
        assertEq(defaultStable, HOST_MIN_PRICE_STABLE, "Should return default stable when no override");

        // Case 2: Set model-specific native only
        uint256 modelNative = HOST_MIN_PRICE_NATIVE * 2;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, modelNative, 0); // 0 = use default for stable

        uint256 queriedNative = nodeRegistry.getModelPricing(host1, modelId1, address(0));
        assertEq(queriedNative, modelNative, "Should return model-specific native");

        uint256 queriedStable = nodeRegistry.getModelPricing(host1, modelId1, address(usdcToken));
        assertEq(queriedStable, HOST_MIN_PRICE_STABLE, "Should still return default stable");

        // Case 3: Set token-specific pricing (overrides default stable)
        uint256 customTokenPrice = HOST_MIN_PRICE_STABLE * 3;
        vm.prank(host1);
        nodeRegistry.setTokenPricing(address(usdcToken), customTokenPrice);

        // For getNodePricing (token fallback)
        uint256 tokenPrice = nodeRegistry.getNodePricing(host1, address(usdcToken));
        assertEq(tokenPrice, customTokenPrice, "Token pricing should override default");

        // Case 4: Clear model pricing - should fall back to default
        vm.prank(host1);
        nodeRegistry.clearModelPricing(modelId1);

        uint256 clearedNative = nodeRegistry.getModelPricing(host1, modelId1, address(0));
        assertEq(clearedNative, HOST_MIN_PRICE_NATIVE, "Should fall back to default after clearing");
    }

    /// @notice Test that model2 uses different fallbacks than model1
    function test_DifferentModelsDifferentFallbacks() public {
        _registerHost1WithBothModels();

        // Set model-specific pricing ONLY for modelId1
        uint256 model1Price = HOST_MIN_PRICE_NATIVE * 5;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, model1Price, HOST_MIN_PRICE_STABLE);

        // Model 1 should have custom pricing
        uint256 price1 = nodeRegistry.getModelPricing(host1, modelId1, address(0));
        assertEq(price1, model1Price, "Model 1 should have custom pricing");

        // Model 2 should have default pricing (no override set)
        uint256 price2 = nodeRegistry.getModelPricing(host1, modelId2, address(0));
        assertEq(price2, HOST_MIN_PRICE_NATIVE, "Model 2 should have default pricing");
    }

    // ============ Test: Batch query returns correct effective prices ============

    /// @notice Test that getHostModelPrices returns correct effective prices
    function test_BatchQueryReturnsEffectivePrices() public {
        _registerHost1WithBothModels();

        // Get batch prices before any overrides
        (
            bytes32[] memory modelIds,
            uint256[] memory nativePrices,
            uint256[] memory stablePrices
        ) = nodeRegistry.getHostModelPrices(host1);

        assertEq(modelIds.length, 2, "Should return 2 models");
        assertEq(nativePrices.length, 2, "Should return 2 native prices");
        assertEq(stablePrices.length, 2, "Should return 2 stable prices");

        // All prices should be defaults initially
        assertEq(nativePrices[0], HOST_MIN_PRICE_NATIVE, "Native price 0 should be default");
        assertEq(nativePrices[1], HOST_MIN_PRICE_NATIVE, "Native price 1 should be default");
        assertEq(stablePrices[0], HOST_MIN_PRICE_STABLE, "Stable price 0 should be default");
        assertEq(stablePrices[1], HOST_MIN_PRICE_STABLE, "Stable price 1 should be default");

        // Set custom pricing for model 1 only
        uint256 customNative = HOST_MIN_PRICE_NATIVE * 4;
        uint256 customStable = HOST_MIN_PRICE_STABLE * 4;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, customNative, customStable);

        // Get batch prices after override
        (
            bytes32[] memory modelIds2,
            uint256[] memory nativePrices2,
            uint256[] memory stablePrices2
        ) = nodeRegistry.getHostModelPrices(host1);

        // Find which index has modelId1
        uint256 model1Index = modelIds2[0] == modelId1 ? 0 : 1;
        uint256 model2Index = model1Index == 0 ? 1 : 0;

        // Model 1 should have custom pricing
        assertEq(nativePrices2[model1Index], customNative, "Model 1 native should be custom");
        assertEq(stablePrices2[model1Index], customStable, "Model 1 stable should be custom");

        // Model 2 should still have default pricing
        assertEq(nativePrices2[model2Index], HOST_MIN_PRICE_NATIVE, "Model 2 native should be default");
        assertEq(stablePrices2[model2Index], HOST_MIN_PRICE_STABLE, "Model 2 stable should be default");
    }

    /// @notice Test batch query for non-registered operator returns empty arrays
    function test_BatchQueryNonRegisteredReturnsEmpty() public {
        address nonRegistered = address(999);

        (
            bytes32[] memory modelIds,
            uint256[] memory nativePrices,
            uint256[] memory stablePrices
        ) = nodeRegistry.getHostModelPrices(nonRegistered);

        assertEq(modelIds.length, 0, "Should return empty modelIds array");
        assertEq(nativePrices.length, 0, "Should return empty nativePrices array");
        assertEq(stablePrices.length, 0, "Should return empty stablePrices array");
    }

    // ============ Additional Integration Tests ============

    /// @notice Test complete session lifecycle with model-specific pricing
    function test_CompleteSessionLifecycleWithModelPricing() public {
        _registerHost1WithBothModels();

        // Host sets model-specific pricing
        uint256 modelPrice = HOST_MIN_PRICE_NATIVE * 2;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, modelPrice, HOST_MIN_PRICE_STABLE);

        // Client creates session
        uint256 deposit = 1 ether;
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host1,
            modelId1,
            modelPrice,
            3600,
            100
        );

        // Advance time and submit proof
        vm.warp(block.timestamp + 60);
        uint256 tokensToClaim = 100;

        vm.prank(host1);
        marketplace.submitProofOfWork(
            sessionId,
            tokensToClaim,
            bytes32(keccak256("test-proof")),
            "QmTestCID"
        );

        // Verify tokens were claimed
        (,,,,,,, uint256 tokensUsed,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(tokensUsed, tokensToClaim, "Tokens should be claimed");

        // Complete session
        vm.prank(host1);
        marketplace.completeSessionJob(sessionId, "QmConversationCID");

        // Verify session is completed
        (,,,,,,,,,,,, JobMarketplaceWithModels.SessionStatus status,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(uint256(status), uint256(JobMarketplaceWithModels.SessionStatus.Completed), "Session should be completed");
    }

    /// @notice Test model-aware token session with custom pricing
    function test_ModelAwareTokenSessionWithCustomPricing() public {
        _registerHost1WithBothModels();

        // Host sets model-specific stable pricing
        uint256 modelStablePrice = HOST_MIN_PRICE_STABLE * 3;
        vm.prank(host1);
        nodeRegistry.setModelPricing(modelId1, 0, modelStablePrice); // 0 = use default native

        // Client creates token session with model
        uint256 deposit = 10e6; // 10 USDC

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host1,
            modelId1,
            address(usdcToken),
            deposit,
            modelStablePrice,
            3600,
            100
        );

        // Verify session was created correctly
        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, modelId1, "Session model should be stored");

        (
            ,,,
            ,  // host
            address paymentToken,
            ,  // deposit
            uint256 storedPrice,
            ,,,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(paymentToken, address(usdcToken), "Payment token should be USDC");
        assertEq(storedPrice, modelStablePrice, "Price should match model-specific stable price");
    }
}
