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

contract PriceValidationTokenTest is Test {
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
    address public host = address(3);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant HOST_MIN_PRICE_NATIVE = 3_000_000_000; // Host requires 3B wei per token (above MIN_PRICE_NATIVE)
    uint256 constant HOST_MIN_PRICE_STABLE = 5000; // Host requires 5000 for stablecoins
    uint256 constant HOST_MIN_PRICE = HOST_MIN_PRICE_STABLE; // Alias for token tests (tests USDC)
    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30; // 30 seconds

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
            HOST_MIN_PRICE_NATIVE,  // Native (ETH) price
            HOST_MIN_PRICE_STABLE   // Stable (USDC) price
        );
        vm.stopPrank();

        // Give user USDC for token sessions
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        vm.prank(user);
        usdcToken.approve(address(marketplace), 1000e6);
    }

    function test_TokenSessionWithPriceAboveMinimum() public {
        uint256 pricePerToken = HOST_MIN_PRICE + 500; // Above minimum

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6, // 10 USDC
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Token session should be created");
    }

    function test_TokenSessionWithPriceEqualToMinimum() public {
        uint256 pricePerToken = HOST_MIN_PRICE; // Exactly at minimum

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Token session at minimum price should succeed");
    }

    function test_TokenSessionWithPriceBelowMinimum() public {
        uint256 pricePerToken = HOST_MIN_PRICE - 500; // Below minimum

        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            pricePerToken,
            1 hours,
            100
        );
    }

    function test_TokenSessionWithZeroPrice() public {
        // This should fail due to existing "Invalid price" check first
        vm.prank(user);
        vm.expectRevert("Invalid price");
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            0, // Zero price
            1 hours,
            100
        );
    }

    function test_TokenSessionAfterHostPriceUpdate() public {
        uint256 newMinPrice = 8000; // Within stable price range

        // Host updates stable pricing (for USDC sessions)
        vm.prank(host);
        nodeRegistry.updatePricingStable(newMinPrice);

        // Old price should now fail
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE, // Old price is now too low
            1 hours,
            100
        );

        // New price should succeed
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            newMinPrice, // New minimum
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session with updated price should succeed");
    }

    function test_TokenSessionMultipleHostsDifferentPricing() public {
        // Setup second host with different pricing
        address host2 = address(4);
        uint256 host2MinPrice = 7000; // Within stable price range

        vm.prank(owner);
        fabToken.mint(host2, MIN_STAKE);

        vm.startPrank(host2);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata2",
            "https://api2.example.com",
            models,
            HOST_MIN_PRICE_NATIVE,  // Native (ETH) price
            host2MinPrice   // Stable (USDC) price
        );
        vm.stopPrank();

        // Session with host1 at host1's price should succeed
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE,
            1 hours,
            100
        );
        assertGt(sessionId1, 0, "Host1 session created");

        // Session with host2 at host1's price should fail (too low for host2)
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJobWithToken(
            host2,
            address(usdcToken),
            10e6,
            HOST_MIN_PRICE, // Too low for host2
            1 hours,
            100
        );

        // Session with host2 at host2's price should succeed
        vm.prank(user);
        uint256 sessionId2 = marketplace.createSessionJobWithToken(
            host2,
            address(usdcToken),
            10e6,
            host2MinPrice,
            1 hours,
            100
        );
        assertGt(sessionId2, 0, "Host2 session created");
    }

    function test_TokenSessionWithDifferentToken() public {
        // Setup DAI token
        vm.prank(owner);
        daiToken.mint(user, 1000e18);

        vm.prank(user);
        daiToken.approve(address(marketplace), 1000e18);

        // Note: DAI won't be accepted by marketplace unless configured
        // This test would need marketplace.acceptToken() call
        // For now, test with USDC only
        uint256 pricePerToken = HOST_MIN_PRICE;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            20e6, // 20 USDC
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session with different deposit amount works");
    }

    function test_TokenSessionLargeDeposit() public {
        // Give user more USDC
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        vm.prank(user);
        usdcToken.approve(address(marketplace), 1000e6);

        uint256 pricePerToken = HOST_MIN_PRICE;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host,
            address(usdcToken),
            100e6, // 100 USDC
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Large deposit token session should work");
    }
}
