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

contract PriceValidationDepositTest is Test {
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
    uint256 constant HOST_MIN_PRICE = HOST_MIN_PRICE_NATIVE; // Alias for deposit tests
    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30; // 30 seconds

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
            HOST_MIN_PRICE_NATIVE,  // Native (ETH) price
            HOST_MIN_PRICE_STABLE   // Stable (USDC) price
        );
        vm.stopPrank();

        // Give user some native deposit
        vm.deal(user, 10 ether);
        vm.prank(user);
        marketplace.depositNative{value: 1 ether}();
    }

    function test_SessionWithPriceAboveMinimum() public {
        uint256 pricePerToken = HOST_MIN_PRICE + 500; // Above minimum

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(0), // Native token
            0.1 ether,
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session should be created");
    }

    function test_SessionWithPriceEqualToMinimum() public {
        uint256 pricePerToken = HOST_MIN_PRICE; // Exactly at minimum

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(0), // Native token
            0.1 ether,
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session should be created at minimum price");
    }

    function test_SessionWithPriceBelowMinimum() public {
        uint256 pricePerToken = HOST_MIN_PRICE - 500; // Below minimum

        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionFromDeposit(
            host,
            address(0), // Native token
            0.1 ether,
            pricePerToken,
            1 hours,
            100
        );
    }

    function test_SessionWithPriceZeroBelowMinimum() public {
        // This should fail due to existing "Invalid price" check first
        vm.prank(user);
        vm.expectRevert("Invalid price");
        marketplace.createSessionFromDeposit(
            host,
            address(0), // Native token
            0.1 ether,
            0, // Zero price
            1 hours,
            100
        );
    }

    function test_SessionWithTokenPriceAboveMinimum() public {
        // Setup USDC deposit
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        vm.startPrank(user);
        usdcToken.approve(address(marketplace), 1000e6);
        marketplace.depositToken(address(usdcToken), 100e6);
        vm.stopPrank();

        uint256 pricePerToken = HOST_MIN_PRICE_STABLE + 500;

        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(usdcToken),
            10e6,
            pricePerToken,
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Token session should be created");
    }

    function test_SessionWithTokenPriceBelowMinimum() public {
        // Setup USDC deposit
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);

        vm.startPrank(user);
        usdcToken.approve(address(marketplace), 1000e6);
        marketplace.depositToken(address(usdcToken), 100e6);
        vm.stopPrank();

        uint256 pricePerToken = HOST_MIN_PRICE_STABLE - 500;

        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionFromDeposit(
            host,
            address(usdcToken),
            10e6,
            pricePerToken,
            1 hours,
            100
        );
    }

    function test_PriceValidationWithUpdatedHostPricing() public {
        uint256 newMinPrice = 4_000_000; // ~$0.018/million @ $4400 ETH

        // Host updates pricing
        vm.prank(host);
        nodeRegistry.updatePricingNative(newMinPrice);

        // Old price should now fail
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            HOST_MIN_PRICE, // Old price is now too low
            1 hours,
            100
        );

        // New price should succeed
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionFromDeposit(
            host,
            address(0),
            0.1 ether,
            newMinPrice, // New minimum
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session with updated price should succeed");
    }
}
