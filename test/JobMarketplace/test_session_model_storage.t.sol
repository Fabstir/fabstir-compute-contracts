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
 * @title SessionModelStorageTest
 * @notice Tests for sessionModel mapping (Phase 3.1)
 * @dev Verifies session model tracking storage is accessible
 */
contract SessionModelStorageTest is Test {
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
    uint256 constant HOST_MIN_PRICE_NATIVE = 3_000_000; // ~$0.013/million
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

        // Register host with minimum price
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

    // ============ Basic Storage Tests ============

    /// @notice Test that sessionModel mapping exists and is accessible
    function test_SessionModelMappingExists() public view {
        // Should be able to read from the mapping without reverting
        bytes32 model = marketplace.sessionModel(0);
        assertEq(model, bytes32(0), "Unset mapping value should return bytes32(0)");
    }

    /// @notice Test that sessionModel defaults to bytes32(0) for unset sessions
    function test_SessionModelDefaultsToZero() public view {
        // Test various session IDs
        assertEq(marketplace.sessionModel(0), bytes32(0), "Session 0 should default to bytes32(0)");
        assertEq(marketplace.sessionModel(1), bytes32(0), "Session 1 should default to bytes32(0)");
        assertEq(marketplace.sessionModel(999), bytes32(0), "Session 999 should default to bytes32(0)");
        assertEq(marketplace.sessionModel(type(uint256).max), bytes32(0), "Max session should default to bytes32(0)");
    }

    /// @notice Test that existing session creation still works (backward compatibility)
    function test_ExistingSessionCreationStillWorks() public {
        // Give user USDC for token sessions
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        // Approve marketplace to spend USDC
        vm.prank(user);
        usdcToken.approve(address(marketplace), 1000e6);

        // Create session using existing function (should still work)
        uint256 deposit = 200e6;
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

        // Verify session was created
        (uint256 id,,,,,,,,,,,,,,,,,) = marketplace.sessionJobs(sessionId);
        assertEq(id, sessionId, "Session should be created");

        // sessionModel should default to bytes32(0) for existing sessions
        assertEq(marketplace.sessionModel(sessionId), bytes32(0), "Model should default to bytes32(0)");
    }

    /// @notice Test that sessionModel is independent per session
    function test_SessionModelIsIndependentPerSession() public view {
        // Reading different session IDs should return independent values
        bytes32 model1 = marketplace.sessionModel(1);
        bytes32 model2 = marketplace.sessionModel(2);
        bytes32 model3 = marketplace.sessionModel(3);

        // All should be bytes32(0) since no setter exists yet
        assertEq(model1, bytes32(0), "Session 1 model");
        assertEq(model2, bytes32(0), "Session 2 model");
        assertEq(model3, bytes32(0), "Session 3 model");
    }

    /// @notice Test that sessionModel does not affect existing session data
    function test_SessionModelDoesNotAffectExistingData() public {
        // Give user USDC
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        vm.prank(user);
        usdcToken.approve(address(marketplace), 1000e6);

        // Create a session
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            200e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );

        // Verify session data is intact
        (
            uint256 id,
            address depositor,
            ,
            address sessionHost,
            address paymentToken,
            uint256 sessionDeposit,
            uint256 pricePerToken,
            ,,,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID");
        assertEq(depositor, user, "Depositor");
        assertEq(sessionHost, host, "Host");
        assertEq(paymentToken, address(usdcToken), "Payment token");
        assertEq(sessionDeposit, 200e6, "Deposit");
        assertEq(pricePerToken, HOST_MIN_PRICE_STABLE, "Price per token");
    }
}
