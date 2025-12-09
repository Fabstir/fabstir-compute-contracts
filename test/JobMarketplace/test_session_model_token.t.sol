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
 * @title SessionModelTokenTest
 * @notice Tests for createSessionJobForModelWithToken() function (Phase 3.3)
 * @dev Verifies model-aware session creation with token payment and per-model pricing
 */
contract SessionModelTokenTest is Test {
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
    bytes32 public modelId2 = keccak256(abi.encodePacked("TinyLlama/TinyLlama-1.1B-Chat-v1.0-GGUF", "/", "TinyLlama-1.1B-Chat-v1.0.Q4_K_M.gguf"));
    bytes32 public unsupportedModelId = keccak256(abi.encodePacked("Unsupported/Model", "/", "model.gguf"));

    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant HOST_MIN_PRICE_NATIVE = 3_000_000_000;
    uint256 constant HOST_MIN_PRICE_STABLE = 5000;
    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant USDC_MIN_DEPOSIT = 800000; // 0.80 USDC

    // Events to test
    event SessionJobCreated(uint256 indexed jobId, address indexed requester, address indexed host, uint256 deposit);
    event SessionJobCreatedForModel(uint256 indexed jobId, address indexed requester, address indexed host, bytes32 modelId, uint256 deposit);

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

        // Register host with minimum price and supported models
        vm.startPrank(owner);
        fabToken.mint(host, MIN_STAKE);
        vm.stopPrank();

        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](2);
        models[0] = modelId;
        models[1] = modelId2;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            HOST_MIN_PRICE_NATIVE,
            HOST_MIN_PRICE_STABLE
        );
        vm.stopPrank();

        // Fund user with USDC tokens
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        // Approve marketplace to spend user's USDC
        vm.prank(user);
        usdcToken.approve(address(marketplace), type(uint256).max);
    }

    // ============ Basic Functionality Tests ============

    /// @notice Test successful model-aware session creation with token payment
    function test_CreateSessionJobForModelWithToken_Success() public {
        uint256 deposit = 10e6; // 10 USDC
        uint256 pricePerToken = HOST_MIN_PRICE_STABLE;
        uint256 maxDuration = 3600;
        uint256 proofInterval = 100;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            pricePerToken,
            maxDuration,
            proofInterval
        );

        // Verify session was created
        (
            uint256 id,
            address depositor,
            ,  // requester (deprecated)
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
        assertEq(storedPrice, pricePerToken, "Price per token should match");
        assertEq(storedMaxDuration, maxDuration, "Max duration should match");
    }

    /// @notice Test that model ID is stored in sessionModel mapping
    function test_CreateSessionJobForModelWithToken_StoresModelId() public {
        uint256 deposit = 10e6;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, modelId, "Model ID should be stored in sessionModel mapping");
    }

    /// @notice Test that creation fails if host does not support the model
    function test_CreateSessionJobForModelWithToken_FailsIfHostDoesNotSupportModel() public {
        uint256 deposit = 10e6;

        vm.prank(user);
        vm.expectRevert("Host does not support model");
        marketplace.createSessionJobForModelWithToken(
            host,
            unsupportedModelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    /// @notice Test that creation fails if price is below host's model minimum for stable
    function test_CreateSessionJobForModelWithToken_FailsIfPriceBelowModelMinimum() public {
        // Set a higher minimum stable price for the specific model
        uint256 modelMinStablePrice = HOST_MIN_PRICE_STABLE * 2;

        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, HOST_MIN_PRICE_NATIVE, modelMinStablePrice);

        uint256 deposit = 10e6;
        uint256 lowPrice = HOST_MIN_PRICE_STABLE; // Below model minimum

        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            lowPrice,
            3600,
            100
        );
    }

    /// @notice Test that model-specific stable pricing is used when set
    function test_CreateSessionJobForModelWithToken_UsesModelOverridePricing() public {
        // Set model-specific stable pricing higher than default
        uint256 modelMinStablePrice = HOST_MIN_PRICE_STABLE * 3;

        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, HOST_MIN_PRICE_NATIVE, modelMinStablePrice);

        uint256 deposit = 10e6;

        // Should fail with default stable price
        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        // Should succeed with model-specific stable price
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            modelMinStablePrice,
            3600,
            100
        );

        assertGt(sessionId, 0, "Session should be created with model-specific stable price");
    }

    /// @notice Test that default stable pricing is used when no model override exists
    function test_CreateSessionJobForModelWithToken_FallsBackToDefaultPricing() public {
        // No model-specific pricing set, should use default stable
        uint256 deposit = 10e6;

        // Get default stable pricing
        uint256 defaultStable = nodeRegistry.getNodePricing(host, address(usdcToken));

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            defaultStable,
            3600,
            100
        );

        assertGt(sessionId, 0, "Session should be created with default stable pricing");
    }

    /// @notice Test that both SessionJobCreated and SessionJobCreatedForModel events are emitted
    function test_CreateSessionJobForModelWithToken_EmitsEvents() public {
        uint256 deposit = 10e6;
        uint256 expectedJobId = marketplace.nextJobId();

        vm.prank(user);

        // Expect SessionJobCreated event
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(expectedJobId, user, host, deposit);

        // Expect SessionJobCreatedForModel event
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreatedForModel(expectedJobId, user, host, modelId, deposit);

        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    /// @notice Test that token not accepted fails
    function test_CreateSessionJobForModelWithToken_FailsIfTokenNotAccepted() public {
        ERC20Mock unknownToken = new ERC20Mock("Unknown Token", "UNK");
        vm.prank(owner);
        unknownToken.mint(user, 1000e6);

        vm.prank(user);
        unknownToken.approve(address(marketplace), type(uint256).max);

        vm.prank(user);
        vm.expectRevert("Token not accepted");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(unknownToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    /// @notice Test that deposit below minimum fails
    function test_CreateSessionJobForModelWithToken_ValidatesMinDeposit() public {
        uint256 lowDeposit = USDC_MIN_DEPOSIT / 2; // Below minimum

        vm.prank(user);
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            lowDeposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    /// @notice Test that zero deposit fails
    function test_CreateSessionJobForModelWithToken_ValidatesZeroDeposit() public {
        vm.prank(user);
        // Zero deposit triggers "Insufficient deposit" first since it's below min
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            0,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    /// @notice Test that invalid price fails
    function test_CreateSessionJobForModelWithToken_ValidatesPrice() public {
        vm.prank(user);
        vm.expectRevert("Invalid price");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            10e6,
            0, // Invalid price
            3600,
            100
        );
    }

    /// @notice Test that invalid duration fails
    function test_CreateSessionJobForModelWithToken_ValidatesDuration() public {
        vm.prank(user);
        vm.expectRevert("Invalid duration");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            0, // Invalid duration
            100
        );
    }

    /// @notice Test that invalid proof interval fails
    function test_CreateSessionJobForModelWithToken_ValidatesProofInterval() public {
        vm.prank(user);
        vm.expectRevert("Invalid proof interval");
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            0 // Invalid proof interval
        );
    }

    /// @notice Test that invalid host address fails
    function test_CreateSessionJobForModelWithToken_ValidatesHostAddress() public {
        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionJobForModelWithToken(
            address(0), // Invalid host
            modelId,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }

    /// @notice Test session creation increments nextJobId
    function test_CreateSessionJobForModelWithToken_IncrementsNextJobId() public {
        uint256 initialJobId = marketplace.nextJobId();

        vm.prank(user);
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        assertEq(marketplace.nextJobId(), initialJobId + 1, "nextJobId should be incremented");
    }

    /// @notice Test token transfer occurs
    function test_CreateSessionJobForModelWithToken_TransfersTokens() public {
        uint256 deposit = 10e6;
        uint256 userBalanceBefore = usdcToken.balanceOf(user);
        uint256 marketplaceBalanceBefore = usdcToken.balanceOf(address(marketplace));

        vm.prank(user);
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        assertEq(usdcToken.balanceOf(user), userBalanceBefore - deposit, "User balance should decrease");
        assertEq(usdcToken.balanceOf(address(marketplace)), marketplaceBalanceBefore + deposit, "Marketplace balance should increase");
    }

    /// @notice Test token deposits are tracked
    function test_CreateSessionJobForModelWithToken_TracksTokenDeposits() public {
        uint256 deposit = 10e6;

        uint256 depositsBefore = marketplace.userDepositsToken(user, address(usdcToken));

        vm.prank(user);
        marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        assertEq(marketplace.userDepositsToken(user, address(usdcToken)), depositsBefore + deposit, "Token deposits should be tracked");
    }

    /// @notice Test session is added to user and host sessions arrays
    function test_CreateSessionJobForModelWithToken_UpdatesSessionArrays() public {
        uint256 deposit = 10e6;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        // Verify user sessions array was updated
        uint256 storedSessionId = marketplace.userSessions(user, 0);
        assertEq(storedSessionId, sessionId, "Session should be stored in user sessions");

        // Verify host sessions array was updated
        uint256 hostStoredSessionId = marketplace.hostSessions(host, 0);
        assertEq(hostStoredSessionId, sessionId, "Session should be stored in host sessions");
    }

    /// @notice Test different models can have different stable pricing
    function test_CreateSessionJobForModelWithToken_DifferentModelsHaveDifferentPrices() public {
        // Set different model-specific stable prices
        uint256 model1StablePrice = HOST_MIN_PRICE_STABLE * 2;
        uint256 model2StablePrice = HOST_MIN_PRICE_STABLE * 4;

        vm.startPrank(host);
        nodeRegistry.setModelPricing(modelId, HOST_MIN_PRICE_NATIVE, model1StablePrice);
        nodeRegistry.setModelPricing(modelId2, HOST_MIN_PRICE_NATIVE, model2StablePrice);
        vm.stopPrank();

        uint256 deposit = 10e6;

        // Create session for model1 with its specific price
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJobForModelWithToken(
            host,
            modelId,
            address(usdcToken),
            deposit,
            model1StablePrice,
            3600,
            100
        );

        // Create session for model2 with its specific price
        vm.prank(user);
        uint256 sessionId2 = marketplace.createSessionJobForModelWithToken(
            host,
            modelId2,
            address(usdcToken),
            deposit,
            model2StablePrice,
            3600,
            100
        );

        // Verify both sessions have different models stored
        assertEq(marketplace.sessionModel(sessionId1), modelId, "Session 1 should have model 1");
        assertEq(marketplace.sessionModel(sessionId2), modelId2, "Session 2 should have model 2");
    }
}
