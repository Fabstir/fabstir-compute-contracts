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
 * @title TokenAcceptanceTest
 * @notice Tests for addAcceptedToken() function (Phase 2.4)
 * @dev Verifies treasury can add new stablecoin tokens
 */
contract TokenAcceptanceTest is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    HostEarnings public hostEarnings;
    ProofSystem public proofSystem;
    ERC20Mock public fabToken;
    ERC20Mock public usdcToken;
    ERC20Mock public eurToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public nonTreasury = address(4);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    uint256 constant MIN_STAKE = 1000 * 10**18;
    // With PRICE_PRECISION=1000: prices are 1000x for sub-cent granularity
    uint256 constant HOST_MIN_PRICE_NATIVE = 3_000_000; // ~$0.013/million
    uint256 constant HOST_MIN_PRICE_STABLE = 5000; // $5/million
    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;

    uint256 constant EUR_MIN_DEPOSIT = 100e6; // 100 EUR tokens minimum

    // Event to test
    event TokenAccepted(address indexed token, uint256 minDeposit);

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdcToken = new ERC20Mock("USDC Token", "USDC");
        eurToken = new ERC20Mock("EUR Stablecoin", "EURS");
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

    // ============ Basic Functionality Tests ============

    /// @notice Test that treasury can add new accepted token
    function test_TreasuryCanAddAcceptedToken() public {
        vm.prank(treasury);
        marketplace.addAcceptedToken(address(eurToken), EUR_MIN_DEPOSIT);

        assertTrue(marketplace.acceptedTokens(address(eurToken)), "Token should be accepted");
        assertEq(marketplace.tokenMinDeposits(address(eurToken)), EUR_MIN_DEPOSIT, "Min deposit should be set");
    }

    /// @notice Test that non-treasury cannot add token
    function test_NonTreasuryCannotAddToken() public {
        vm.prank(nonTreasury);
        vm.expectRevert("Only treasury");
        marketplace.addAcceptedToken(address(eurToken), EUR_MIN_DEPOSIT);
    }

    /// @notice Test that owner (not treasury) cannot add token
    function test_OwnerCannotAddToken() public {
        vm.prank(owner);
        vm.expectRevert("Only treasury");
        marketplace.addAcceptedToken(address(eurToken), EUR_MIN_DEPOSIT);
    }

    // ============ Validation Tests ============

    /// @notice Test that cannot add already accepted token
    function test_CannotAddAlreadyAcceptedToken() public {
        // USDC is already accepted in constructor
        vm.prank(treasury);
        vm.expectRevert("Token already accepted");
        marketplace.addAcceptedToken(address(usdcToken), EUR_MIN_DEPOSIT);
    }

    /// @notice Test that cannot add with zero minDeposit
    function test_CannotAddWithZeroMinDeposit() public {
        vm.prank(treasury);
        vm.expectRevert("Invalid minimum deposit");
        marketplace.addAcceptedToken(address(eurToken), 0);
    }

    /// @notice Test that cannot add zero address token
    function test_CannotAddZeroAddress() public {
        vm.prank(treasury);
        vm.expectRevert("Invalid token address");
        marketplace.addAcceptedToken(address(0), EUR_MIN_DEPOSIT);
    }

    // ============ Event Tests ============

    /// @notice Test that TokenAccepted event is emitted correctly
    function test_TokenAcceptedEventEmitted() public {
        vm.prank(treasury);
        vm.expectEmit(true, false, false, true);
        emit TokenAccepted(address(eurToken), EUR_MIN_DEPOSIT);
        marketplace.addAcceptedToken(address(eurToken), EUR_MIN_DEPOSIT);
    }

    // ============ Multiple Token Tests ============

    /// @notice Test that multiple tokens can be added
    function test_MultipleTokensCanBeAdded() public {
        ERC20Mock gbpToken = new ERC20Mock("GBP Stablecoin", "GBPS");
        ERC20Mock jpyToken = new ERC20Mock("JPY Stablecoin", "JPYS");

        vm.startPrank(treasury);
        marketplace.addAcceptedToken(address(eurToken), 100e6);
        marketplace.addAcceptedToken(address(gbpToken), 80e6);
        marketplace.addAcceptedToken(address(jpyToken), 15000e6);
        vm.stopPrank();

        assertTrue(marketplace.acceptedTokens(address(eurToken)), "EUR should be accepted");
        assertTrue(marketplace.acceptedTokens(address(gbpToken)), "GBP should be accepted");
        assertTrue(marketplace.acceptedTokens(address(jpyToken)), "JPY should be accepted");

        assertEq(marketplace.tokenMinDeposits(address(eurToken)), 100e6, "EUR min deposit");
        assertEq(marketplace.tokenMinDeposits(address(gbpToken)), 80e6, "GBP min deposit");
        assertEq(marketplace.tokenMinDeposits(address(jpyToken)), 15000e6, "JPY min deposit");
    }

    // ============ Integration Tests ============

    /// @notice Test that sessions can be created with newly accepted token
    function test_SessionsCanBeCreatedWithNewToken() public {
        // Add EUR token
        vm.prank(treasury);
        marketplace.addAcceptedToken(address(eurToken), EUR_MIN_DEPOSIT);

        // Give user EUR tokens
        vm.prank(owner);
        eurToken.mint(user, 1000e6);

        // Approve marketplace to spend EUR
        vm.prank(user);
        eurToken.approve(address(marketplace), 1000e6);

        // Create session with EUR token
        // createSessionJobWithToken(host, token, deposit, pricePerToken, maxDuration, proofInterval)
        uint256 deposit = 200e6;
        uint256 pricePerToken = HOST_MIN_PRICE_STABLE; // Must meet host minimum
        uint256 maxDuration = 3600; // 1 hour
        uint256 proofInterval = 100; // Every 100 tokens

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(eurToken),
            deposit,
            pricePerToken,
            maxDuration,
            proofInterval
        );

        // Verify session was created by checking key fields
        (
            uint256 id,
            address depositor,
            ,  // requester (deprecated)
            address sessionHost,
            address paymentToken,
            uint256 sessionDeposit,
            ,,,,,,,,,,,
        ) = marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID should match");
        assertEq(depositor, user, "Session depositor should match");
        assertEq(sessionHost, host, "Session host should match");
        assertEq(paymentToken, address(eurToken), "Payment token should be EUR");
        assertEq(sessionDeposit, deposit, "Session deposit should match");
    }

    /// @notice Test that session creation fails with non-accepted token
    function test_SessionCreationFailsWithNonAcceptedToken() public {
        ERC20Mock unknownToken = new ERC20Mock("Unknown Token", "UNK");

        // Give user tokens
        vm.prank(owner);
        unknownToken.mint(user, 1000e6);

        // Approve marketplace
        vm.prank(user);
        unknownToken.approve(address(marketplace), 1000e6);

        // Try to create session with non-accepted token
        // createSessionJobWithToken(host, token, deposit, pricePerToken, maxDuration, proofInterval)
        vm.prank(user);
        vm.expectRevert("Token not accepted");
        marketplace.createSessionJobWithToken(
            host,
            address(unknownToken),
            200e6,
            HOST_MIN_PRICE_STABLE,
            3600,
            100
        );
    }
}
