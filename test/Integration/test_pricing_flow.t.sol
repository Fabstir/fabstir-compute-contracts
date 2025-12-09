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

contract PricingFlowIntegrationTest is Test {
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
    address public host1 = address(3);
    address public host2 = address(4);
    address public host3 = address(5);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    bytes32 public modelId = keccak256(abi.encodePacked("CohereForAI/TinyVicuna-1B-32k-GGUF", "/", "tiny-vicuna-1b.q4_k_m.gguf"));
    uint256 constant MIN_STAKE = 1000 * 10**18;
    uint256 constant FEE_BASIS_POINTS = 1000; // 10%
    uint256 constant DISPUTE_WINDOW = 30; // 30 seconds
    // With PRICE_PRECISION=1000: prices are 1000x for sub-cent granularity
    uint256 constant HOST_MIN_PRICE_NATIVE = 500_000; // ~$2.2/million @ $4400 ETH
    uint256 constant HOST_MIN_PRICE_STABLE = 2000; // $2/million

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

        // Give user funds
        vm.deal(user, 10 ether);
        vm.prank(owner);
        usdcToken.mint(user, 1000e6);
    }

    function test_CompleteFlowRegistrationToSession() public {
        // Step 1: Register host with pricing
        vm.prank(owner);
        fabToken.mint(host1, MIN_STAKE);

        vm.startPrank(host1);
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

        // Step 2: Verify pricing is stored (testing native token price for ETH sessions)
        uint256 storedPrice = nodeRegistry.getNodePricing(host1, address(0)); // address(0) = native
        assertEq(storedPrice, HOST_MIN_PRICE_NATIVE, "Pricing should be stored");

        // Step 3: Create session above minimum (should succeed)
        uint256 sessionPrice = HOST_MIN_PRICE_NATIVE + 50000;
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            sessionPrice, // Above minimum
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session should be created");

        // Step 4: Verify session details
        (uint256 id, , , address sessionHost, , , uint256 storedSessionPrice, , , , , , , , , ,,) =
            marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID correct");
        assertEq(sessionHost, host1, "Host correct");
        assertEq(storedSessionPrice, sessionPrice, "Price stored correctly");
    }

    function test_UpdatePricingAffectsSessions() public {
        // Step 1: Register host with initial pricing
        uint256 initialNativePrice = HOST_MIN_PRICE_NATIVE;

        vm.prank(owner);
        fabToken.mint(host1, MIN_STAKE);

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            initialNativePrice,  // Native price
            HOST_MIN_PRICE_STABLE   // Stable price
        );
        vm.stopPrank();

        // Step 2: Create session with initial price (succeeds)
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            initialNativePrice,
            1 hours,
            100
        );
        assertGt(sessionId1, 0, "Initial session created");

        // Step 3: Host updates pricing higher (native token for ETH sessions)
        uint256 newHigherPrice = HOST_MIN_PRICE_NATIVE * 2;
        vm.prank(host1);
        nodeRegistry.updatePricingNative(newHigherPrice);

        // Step 4: Verify updated pricing
        uint256 updatedPrice = nodeRegistry.getNodePricing(host1, address(0));
        assertEq(updatedPrice, newHigherPrice, "Pricing should be updated");

        // Step 5: Try to create session with old price (should fail)
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            initialNativePrice, // Old price is now too low
            1 hours,
            100
        );

        // Step 6: Create session with new price (succeeds)
        vm.prank(user);
        uint256 sessionId2 = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            newHigherPrice,
            1 hours,
            100
        );
        assertGt(sessionId2, 0, "New session with higher price created");
    }

    function test_LowerPricingEnablesMoreSessions() public {
        // Step 1: Register host with high initial pricing
        uint256 initialHighPrice = HOST_MIN_PRICE_NATIVE * 2;

        vm.prank(owner);
        fabToken.mint(host1, MIN_STAKE);

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            initialHighPrice,  // Native price
            HOST_MIN_PRICE_STABLE   // Stable price
        );
        vm.stopPrank();

        // Step 2: User tries to create session with lower price (fails)
        uint256 userDesiredPrice = HOST_MIN_PRICE_NATIVE + 100000;
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            userDesiredPrice,
            1 hours,
            100
        );

        // Step 3: Host lowers pricing to be competitive
        uint256 newLowerPrice = HOST_MIN_PRICE_NATIVE;
        vm.prank(host1);
        nodeRegistry.updatePricingNative(newLowerPrice);

        // Step 4: Now user can create session with their desired price
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            userDesiredPrice, // Now acceptable
            1 hours,
            100
        );
        assertGt(sessionId, 0, "Session created after price lowering");
    }

    function test_MultipleHostsDifferentPricing() public {
        // Step 1: Register host1 with low pricing
        uint256 host1NativePrice = HOST_MIN_PRICE_NATIVE;
        vm.prank(owner);
        fabToken.mint(host1, MIN_STAKE);

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata1",
            "https://api1.example.com",
            models,
            host1NativePrice,  // Native price
            HOST_MIN_PRICE_STABLE   // Stable price
        );
        vm.stopPrank();

        // Step 2: Register host2 with medium pricing
        uint256 host2NativePrice = HOST_MIN_PRICE_NATIVE * 2;
        vm.prank(owner);
        fabToken.mint(host2, MIN_STAKE);

        vm.startPrank(host2);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata2",
            "https://api2.example.com",
            models,
            host2NativePrice,  // Native price
            HOST_MIN_PRICE_STABLE   // Stable price
        );
        vm.stopPrank();

        // Step 3: Register host3 with high pricing
        uint256 host3NativePrice = HOST_MIN_PRICE_NATIVE * 3;
        vm.prank(owner);
        fabToken.mint(host3, MIN_STAKE);

        vm.startPrank(host3);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata3",
            "https://api3.example.com",
            models,
            host3NativePrice,  // Native price
            HOST_MIN_PRICE_STABLE   // Stable price
        );
        vm.stopPrank();

        // Step 4: User creates sessions with different hosts at appropriate prices

        // Session with host1 at medium price (succeeds - above their minimum)
        vm.prank(user);
        uint256 session1 = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            host1NativePrice + 100000, // Above host1's minimum
            1 hours,
            100
        );
        assertGt(session1, 0, "Host1 session created");

        // Session with host2 at its minimum price (succeeds - at their minimum)
        vm.prank(user);
        uint256 session2 = marketplace.createSessionJob{value: 0.1 ether}(
            host2,
            host2NativePrice, // Exactly host2's minimum
            1 hours,
            100
        );
        assertGt(session2, 0, "Host2 session created");

        // Session with host3 at host1's price (fails - below their minimum)
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJob{value: 0.1 ether}(
            host3,
            host1NativePrice, // Below host3's minimum
            1 hours,
            100
        );

        // Session with host3 at high price (succeeds)
        vm.prank(user);
        uint256 session3 = marketplace.createSessionJob{value: 0.1 ether}(
            host3,
            host3NativePrice + 100000, // Above host3's minimum
            1 hours,
            100
        );
        assertGt(session3, 0, "Host3 session created");
    }

    function test_GetNodePricingMatchesRegistered() public {
        // Register multiple hosts with different native pricing (above MIN_PRICE_NATIVE)
        uint256[] memory nativePrices = new uint256[](3);
        nativePrices[0] = HOST_MIN_PRICE_NATIVE;
        nativePrices[1] = HOST_MIN_PRICE_NATIVE * 2;
        nativePrices[2] = HOST_MIN_PRICE_NATIVE * 3;

        uint256[] memory stablePrices = new uint256[](3);
        stablePrices[0] = 1000;
        stablePrices[1] = 5000;
        stablePrices[2] = 9000;

        address[] memory hosts = new address[](3);
        hosts[0] = host1;
        hosts[1] = host2;
        hosts[2] = host3;

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        for (uint i = 0; i < hosts.length; i++) {
            vm.prank(owner);
            fabToken.mint(hosts[i], MIN_STAKE);

            vm.startPrank(hosts[i]);
            fabToken.approve(address(nodeRegistry), MIN_STAKE);

            nodeRegistry.registerNode(
                string(abi.encodePacked("metadata", i)),
                string(abi.encodePacked("https://api", i, ".example.com")),
                models,
                nativePrices[i],  // Native price
                stablePrices[i]   // Stable price
            );
            vm.stopPrank();
        }

        // Verify all pricing queries match (testing native token queries)
        for (uint i = 0; i < hosts.length; i++) {
            uint256 queriedNativePrice = nodeRegistry.getNodePricing(hosts[i], address(0));
            assertEq(queriedNativePrice, nativePrices[i], "getNodePricing native should match registered price");

            uint256 queriedStablePrice = nodeRegistry.getNodePricing(hosts[i], address(usdcToken));
            assertEq(queriedStablePrice, stablePrices[i], "getNodePricing stable should match registered price");
        }
    }

    function test_GetNodeFullInfoMatchesPricing() public {
        uint256 hostNativePrice = HOST_MIN_PRICE_NATIVE;
        uint256 hostStablePrice = 4500;

        vm.prank(owner);
        fabToken.mint(host1, MIN_STAKE);

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            hostNativePrice,  // Native price
            hostStablePrice   // Stable price
        );
        vm.stopPrank();

        // Query via getNodePricing (native token)
        uint256 nativePriceFromGetter = nodeRegistry.getNodePricing(host1, address(0));

        // Query via getNodeFullInfo (returns both native and stable)
        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host1);

        // Both should match the registered prices
        assertEq(nativePriceFromGetter, hostNativePrice, "getNodePricing native matches registered");
        assertEq(nativePrice, hostNativePrice, "getNodeFullInfo native matches registered");
        assertEq(stablePrice, hostStablePrice, "getNodeFullInfo stable matches registered");
        assertEq(nativePriceFromGetter, nativePrice, "getNodePricing and native price match");
    }

    function test_CompleteFlowWithTokenPayments() public {
        // Register host with pricing
        uint256 hostStablePrice = 3500;

        vm.prank(owner);
        fabToken.mint(host1, MIN_STAKE);

        vm.startPrank(host1);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        bytes32[] memory models = new bytes32[](1);
        models[0] = modelId;

        nodeRegistry.registerNode(
            "metadata",
            "https://api.example.com",
            models,
            HOST_MIN_PRICE_NATIVE,  // Native price
            hostStablePrice   // Stable price
        );
        vm.stopPrank();

        // User creates USDC session (validates against stable price)
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), 1000e6);

        uint256 sessionPrice = hostStablePrice + 1000;
        uint256 sessionId = marketplace.createSessionJobWithToken(
            host1,
            address(usdcToken),
            20e6, // 20 USDC
            sessionPrice, // Above minimum
            1 hours,
            100
        );
        vm.stopPrank();

        assertGt(sessionId, 0, "Token session created");

        // Verify pricing in session
        (, , , , , , uint256 storedSessionPrice, , , , , , , , , ,,) =
            marketplace.sessionJobs(sessionId);
        assertEq(storedSessionPrice, sessionPrice, "Token session price correct");
    }
}
