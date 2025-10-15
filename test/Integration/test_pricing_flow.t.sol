// SPDX-License-Identifier: MIT
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
        uint256 hostMinPrice = 2000;

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
            hostMinPrice,  // Native (ETH) price
            hostMinPrice   // Stable (USDC) price - same for this test
        );
        vm.stopPrank();

        // Step 2: Verify pricing is stored (testing native token price for ETH sessions)
        uint256 storedPrice = nodeRegistry.getNodePricing(host1, address(0)); // address(0) = native
        assertEq(storedPrice, hostMinPrice, "Pricing should be stored");

        // Step 3: Create session above minimum (should succeed)
        vm.prank(user);
        uint256 sessionId = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            hostMinPrice + 500, // Above minimum
            1 hours,
            100
        );

        assertGt(sessionId, 0, "Session should be created");

        // Step 4: Verify session details
        (uint256 id, , , address sessionHost, , , uint256 sessionPrice, , , , , , , , , ,,) =
            marketplace.sessionJobs(sessionId);

        assertEq(id, sessionId, "Session ID correct");
        assertEq(sessionHost, host1, "Host correct");
        assertEq(sessionPrice, hostMinPrice + 500, "Price stored correctly");
    }

    function test_UpdatePricingAffectsSessions() public {
        // Step 1: Register host with initial pricing
        uint256 initialPrice = 2000;

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
            initialPrice,  // Native price
            initialPrice   // Stable price - same for this test
        );
        vm.stopPrank();

        // Step 2: Create session with initial price (succeeds)
        vm.prank(user);
        uint256 sessionId1 = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            initialPrice,
            1 hours,
            100
        );
        assertGt(sessionId1, 0, "Initial session created");

        // Step 3: Host updates pricing higher (native token for ETH sessions)
        uint256 newHigherPrice = 5000;
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
            initialPrice, // Old price is now too low
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
        uint256 initialHighPrice = 8000;

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
            initialHighPrice   // Stable price
        );
        vm.stopPrank();

        // Step 2: User tries to create session with lower price (fails)
        uint256 userDesiredPrice = 3000;
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            userDesiredPrice,
            1 hours,
            100
        );

        // Step 3: Host lowers pricing to be competitive
        uint256 newLowerPrice = 2500;
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
        uint256 host1Price = 1500;
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
            host1Price,  // Native price
            host1Price   // Stable price
        );
        vm.stopPrank();

        // Step 2: Register host2 with medium pricing
        uint256 host2Price = 3000;
        vm.prank(owner);
        fabToken.mint(host2, MIN_STAKE);

        vm.startPrank(host2);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata2",
            "https://api2.example.com",
            models,
            host2Price,  // Native price
            host2Price   // Stable price
        );
        vm.stopPrank();

        // Step 3: Register host3 with high pricing
        uint256 host3Price = 6000;
        vm.prank(owner);
        fabToken.mint(host3, MIN_STAKE);

        vm.startPrank(host3);
        fabToken.approve(address(nodeRegistry), MIN_STAKE);

        nodeRegistry.registerNode(
            "metadata3",
            "https://api3.example.com",
            models,
            host3Price,  // Native price
            host3Price   // Stable price
        );
        vm.stopPrank();

        // Step 4: User creates sessions with different hosts at appropriate prices

        // Session with host1 at medium price (succeeds - above their minimum)
        vm.prank(user);
        uint256 session1 = marketplace.createSessionJob{value: 0.1 ether}(
            host1,
            2500, // Above host1's 1500
            1 hours,
            100
        );
        assertGt(session1, 0, "Host1 session created");

        // Session with host2 at medium price (succeeds - at their minimum)
        vm.prank(user);
        uint256 session2 = marketplace.createSessionJob{value: 0.1 ether}(
            host2,
            3000, // Exactly host2's minimum
            1 hours,
            100
        );
        assertGt(session2, 0, "Host2 session created");

        // Session with host3 at medium price (fails - below their minimum)
        vm.prank(user);
        vm.expectRevert("Price below host minimum");
        marketplace.createSessionJob{value: 0.1 ether}(
            host3,
            2500, // Below host3's 6000
            1 hours,
            100
        );

        // Session with host3 at high price (succeeds)
        vm.prank(user);
        uint256 session3 = marketplace.createSessionJob{value: 0.1 ether}(
            host3,
            6500, // Above host3's 6000
            1 hours,
            100
        );
        assertGt(session3, 0, "Host3 session created");
    }

    function test_GetNodePricingMatchesRegistered() public {
        // Register multiple hosts with different pricing
        uint256[] memory prices = new uint256[](3);
        prices[0] = 1000;
        prices[1] = 5000;
        prices[2] = 9000;

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
                prices[i],  // Native price
                prices[i]   // Stable price - same for this test
            );
            vm.stopPrank();
        }

        // Verify all pricing queries match (testing native token queries)
        for (uint i = 0; i < hosts.length; i++) {
            uint256 queriedPrice = nodeRegistry.getNodePricing(hosts[i], address(0));
            assertEq(queriedPrice, prices[i], "getNodePricing should match registered price");
        }
    }

    function test_GetNodeFullInfoMatchesPricing() public {
        uint256 hostPrice = 4500;

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
            hostPrice,  // Native price
            hostPrice   // Stable price
        );
        vm.stopPrank();

        // Query via getNodePricing (native token)
        uint256 priceFromGetter = nodeRegistry.getNodePricing(host1, address(0));

        // Query via getNodeFullInfo (returns both native and stable)
        (, , , , , , uint256 nativePrice, uint256 stablePrice) = nodeRegistry.getNodeFullInfo(host1);

        // Both should match the registered price
        assertEq(priceFromGetter, hostPrice, "getNodePricing matches registered");
        assertEq(nativePrice, hostPrice, "getNodeFullInfo native matches registered");
        assertEq(stablePrice, hostPrice, "getNodeFullInfo stable matches registered");
        assertEq(priceFromGetter, nativePrice, "getNodePricing and native price match");
    }

    function test_CompleteFlowWithTokenPayments() public {
        // Register host with pricing
        uint256 hostPrice = 3500;

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
            hostPrice,  // Native price
            hostPrice   // Stable price
        );
        vm.stopPrank();

        // User creates USDC session (validates against stable price)
        vm.startPrank(user);
        usdcToken.approve(address(marketplace), 1000e6);

        uint256 sessionId = marketplace.createSessionJobWithToken(
            host1,
            address(usdcToken),
            20e6, // 20 USDC
            hostPrice + 1000, // Above minimum
            1 hours,
            100
        );
        vm.stopPrank();

        assertGt(sessionId, 0, "Token session created");

        // Verify pricing in session
        (, , , , , , uint256 sessionPrice, , , , , , , , , ,,) =
            marketplace.sessionJobs(sessionId);
        assertEq(sessionPrice, hostPrice + 1000, "Token session price correct");
    }
}
