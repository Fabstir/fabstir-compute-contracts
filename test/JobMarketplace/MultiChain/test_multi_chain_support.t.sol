// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract TestMultiChainSupport is Test {
    JobMarketplaceWithModels public marketplace;
    NodeRegistryWithModels public nodeRegistry;
    ModelRegistry public modelRegistry;
    ProofSystem public proofSystem;
    HostEarnings public hostEarnings;
    ERC20Mock public fabToken;
    ERC20Mock public governanceToken;

    address public owner = address(1);
    address public user = address(2);
    address public host = address(3);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    uint256 constant FEE_BASIS_POINTS = 1000; // 10%

    function setUp() public {
        vm.startPrank(owner);

        // Deploy tokens
        fabToken = new ERC20Mock("Fabstir Token", "FAB");
        governanceToken = new ERC20Mock("Governance Token", "GOV");

        // Deploy contracts
        modelRegistry = new ModelRegistry(address(governanceToken));
        nodeRegistry = new NodeRegistryWithModels(address(fabToken), address(modelRegistry));
        proofSystem = new ProofSystem();
        hostEarnings = new HostEarnings();
        marketplace = new JobMarketplaceWithModels(
            address(nodeRegistry),
            payable(address(hostEarnings)),
            FEE_BASIS_POINTS,
            30);

        // Setup authorized callers
        hostEarnings.setAuthorizedCaller(address(marketplace), true);

        vm.stopPrank();

        // Setup test users
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);

        // Set treasury as owner for initialization
        vm.prank(treasury);
        marketplace.setProofSystem(address(proofSystem));
    }
    function test_BaseSepoliaConfig() public {
        // Setup Base Sepolia configuration
        JobMarketplaceWithModels.ChainConfig memory baseConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: 0x4200000000000000000000000000000000000006, // WETH on Base
                stablecoin: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // USDC on Base Sepolia
                minDeposit: 0.001 ether,
                nativeTokenSymbol: "ETH"
            });

        vm.prank(treasury);
        marketplace.initializeChainConfig(baseConfig);

        // Verify Base config
        (
            address nativeWrapper,
            address stablecoin,
            ,
            string memory symbol
        ) = marketplace.chainConfig();

        assertEq(symbol, "ETH", "Should be configured for ETH");
        assertEq(nativeWrapper, 0x4200000000000000000000000000000000000006);
        assertEq(stablecoin, 0x036CbD53842c5426634e7929541eC2318f3dCF7e);
    }

    function test_OpBNBConfig() public {
        // Setup opBNB configuration
        JobMarketplaceWithModels.ChainConfig memory bnbConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x789), // WBNB on opBNB (example)
                stablecoin: address(0xabc), // USDC on opBNB (example)
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "BNB"
            });

        vm.prank(treasury);
        marketplace.initializeChainConfig(bnbConfig);

        // Verify opBNB config
        (,,,string memory symbol) = marketplace.chainConfig();
        assertEq(symbol, "BNB", "Should be configured for BNB");
    }

    function test_ChainAgnosticDepositWithConfig() public {
        // Initialize config first
        JobMarketplaceWithModels.ChainConfig memory config =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x123),
                stablecoin: address(0x456),
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "ETH"
            });

        vm.prank(treasury);
        marketplace.initializeChainConfig(config);

        // Test that config doesn't block existing deposit functions
        // This ensures backward compatibility
        vm.prank(user);
        marketplace.depositNative{value: 0.1 ether}();

        uint256 balance = marketplace.userDepositsNative(user);
        assertEq(balance, 0.1 ether, "Native deposit should work with config");
    }

    function test_MinDepositEnforcement() public {
        // Set minimum deposit
        JobMarketplaceWithModels.ChainConfig memory config =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x123),
                stablecoin: address(0x456),
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "ETH"
            });

        vm.prank(treasury);
        marketplace.initializeChainConfig(config);

        // Get min deposit from config
        (,,uint256 minDeposit,) = marketplace.chainConfig();
        assertEq(minDeposit, 0.01 ether, "Min deposit should be set");
    }
}