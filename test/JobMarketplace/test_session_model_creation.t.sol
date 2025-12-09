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
 * @title SessionModelCreationTest
 * @notice Tests for createSessionJobForModel() function (Phase 3.2)
 * @dev Verifies model-aware session creation with per-model pricing validation
 */
contract SessionModelCreationTest is Test {
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
    uint256 constant MIN_DEPOSIT = 0.0002 ether;

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

        // Fund user for native sessions
        vm.deal(user, 100 ether);
    }

    // ============ Basic Functionality Tests ============

    /// @notice Test successful model-aware session creation
    function test_CreateSessionJobForModel_Success() public {
        uint256 deposit = 1 ether;
        uint256 pricePerToken = HOST_MIN_PRICE_NATIVE;
        uint256 maxDuration = 3600;
        uint256 proofInterval = 100;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
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
        assertEq(paymentToken, address(0), "Payment token should be ETH");
        assertEq(sessionDeposit, deposit, "Deposit should match");
        assertEq(storedPrice, pricePerToken, "Price per token should match");
        assertEq(storedMaxDuration, maxDuration, "Max duration should match");
    }

    /// @notice Test that model ID is stored in sessionModel mapping
    function test_CreateSessionJobForModel_StoresModelId() public {
        uint256 deposit = 1 ether;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        bytes32 storedModel = marketplace.sessionModel(sessionId);
        assertEq(storedModel, modelId, "Model ID should be stored in sessionModel mapping");
    }

    /// @notice Test that creation fails if host does not support the model
    function test_CreateSessionJobForModel_FailsIfHostDoesNotSupportModel() public {
        uint256 deposit = 1 ether;

        vm.prank(user);
        vm.expectRevert("Host does not support model");
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            unsupportedModelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );
    }

    /// @notice Test that creation fails if price is below host's model minimum
    function test_CreateSessionJobForModel_FailsIfPriceBelowModelMinimum() public {
        // Set a higher minimum price for the specific model
        uint256 modelMinPrice = HOST_MIN_PRICE_NATIVE * 2;

        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, modelMinPrice, HOST_MIN_PRICE_STABLE);

        uint256 deposit = 1 ether;
        uint256 lowPrice = HOST_MIN_PRICE_NATIVE; // Below model minimum

        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            lowPrice,
            3600,
            100
        );
    }

    /// @notice Test that model-specific pricing is used when set
    function test_CreateSessionJobForModel_UsesModelOverridePricing() public {
        // Set model-specific pricing higher than default
        uint256 modelMinPrice = HOST_MIN_PRICE_NATIVE * 3;

        vm.prank(host);
        nodeRegistry.setModelPricing(modelId, modelMinPrice, HOST_MIN_PRICE_STABLE);

        uint256 deposit = 1 ether;

        // Should fail with default price
        vm.prank(user);
        vm.expectRevert("Price below host minimum for model");
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        // Should succeed with model-specific price
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            modelMinPrice,
            3600,
            100
        );

        assertGt(sessionId, 0, "Session should be created with model-specific price");
    }

    /// @notice Test that default pricing is used when no model override exists
    function test_CreateSessionJobForModel_FallsBackToDefaultPricing() public {
        // No model-specific pricing set, should use default
        uint256 deposit = 1 ether;

        // Get default pricing for native token
        uint256 defaultNative = nodeRegistry.getNodePricing(host, address(0));

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            defaultNative,
            3600,
            100
        );

        assertGt(sessionId, 0, "Session should be created with default pricing");
    }

    /// @notice Test that both SessionJobCreated and SessionJobCreatedForModel events are emitted
    function test_CreateSessionJobForModel_EmitsEvents() public {
        uint256 deposit = 1 ether;
        uint256 expectedJobId = marketplace.nextJobId();

        vm.prank(user);

        // Expect SessionJobCreated event
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(expectedJobId, user, host, deposit);

        // Expect SessionJobCreatedForModel event
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreatedForModel(expectedJobId, user, host, modelId, deposit);

        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );
    }

    /// @notice Test that deposit validation works (MIN_DEPOSIT check)
    function test_CreateSessionJobForModel_ValidatesDeposit() public {
        uint256 lowDeposit = MIN_DEPOSIT / 2; // Below minimum

        vm.prank(user);
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJobForModel{value: lowDeposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );
    }

    /// @notice Test that proof interval validation works
    function test_CreateSessionJobForModel_ValidatesProofRequirements() public {
        uint256 deposit = 1 ether;

        // Zero proof interval should fail
        vm.prank(user);
        vm.expectRevert("Invalid proof interval");
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            0 // Invalid proof interval
        );
    }

    // ============ Additional Validation Tests ============

    /// @notice Test that invalid price fails
    function test_CreateSessionJobForModel_ValidatesPrice() public {
        uint256 deposit = 1 ether;

        vm.prank(user);
        vm.expectRevert("Invalid price");
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            0, // Invalid price
            3600,
            100
        );
    }

    /// @notice Test that invalid duration fails
    function test_CreateSessionJobForModel_ValidatesDuration() public {
        uint256 deposit = 1 ether;

        vm.prank(user);
        vm.expectRevert("Invalid duration");
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            0, // Invalid duration
            100
        );
    }

    /// @notice Test that invalid host address fails
    function test_CreateSessionJobForModel_ValidatesHostAddress() public {
        uint256 deposit = 1 ether;

        vm.prank(user);
        vm.expectRevert("Invalid host");
        marketplace.createSessionJobForModel{value: deposit}(
            address(0), // Invalid host
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );
    }

    /// @notice Test session creation increments nextJobId
    function test_CreateSessionJobForModel_IncrementsNextJobId() public {
        uint256 initialJobId = marketplace.nextJobId();
        uint256 deposit = 1 ether;

        vm.prank(user);
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        assertEq(marketplace.nextJobId(), initialJobId + 1, "nextJobId should be incremented");
    }

    /// @notice Test session is added to user and host sessions arrays
    function test_CreateSessionJobForModel_UpdatesSessionArrays() public {
        uint256 deposit = 1 ether;

        // Create a session and verify it gets a valid session ID
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        // Verify user sessions array was updated by checking userSessions[user][0]
        uint256 storedSessionId = marketplace.userSessions(user, 0);
        assertEq(storedSessionId, sessionId, "Session should be stored in user sessions");

        // Verify host sessions array was updated by checking hostSessions[host][0]
        uint256 hostStoredSessionId = marketplace.hostSessions(host, 0);
        assertEq(hostStoredSessionId, sessionId, "Session should be stored in host sessions");
    }

    /// @notice Test native deposits are tracked
    function test_CreateSessionJobForModel_TracksNativeDeposits() public {
        uint256 deposit = 1 ether;

        uint256 depositsBefore = marketplace.userDepositsNative(user);

        vm.prank(user);
        marketplace.createSessionJobForModel{value: deposit}(
            host,
            modelId,
            HOST_MIN_PRICE_NATIVE,
            3600,
            100
        );

        assertEq(marketplace.userDepositsNative(user), depositsBefore + deposit, "Native deposits should be tracked");
    }
}
