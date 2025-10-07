// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract TestChainConfig is Test {
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
    function test_ChainConfigStorage() public {
        // Test that chain config is stored and accessible
        (
            address nativeWrapper,
            address stablecoin,
            uint256 minDeposit,
            string memory nativeTokenSymbol
        ) = marketplace.chainConfig();

        assertEq(nativeWrapper, address(0), "Native wrapper should be uninitialized");
        assertEq(stablecoin, address(0), "Stablecoin should be uninitialized");
        assertEq(minDeposit, 0, "Min deposit should be uninitialized");
        assertEq(nativeTokenSymbol, "", "Native token symbol should be empty");
    }

    function test_InitializeChainConfig_AsOwner() public {
        // Prepare config
        JobMarketplaceWithModels.ChainConfig memory config =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x123),
                stablecoin: address(0x456),
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "ETH"
            });

        // Initialize as treasury (who has owner permissions)
        vm.prank(treasury);
        marketplace.initializeChainConfig(config);

        // Verify config is stored
        (
            address nativeWrapper,
            address stablecoin,
            uint256 minDeposit,
            string memory nativeTokenSymbol
        ) = marketplace.chainConfig();

        assertEq(nativeWrapper, address(0x123), "Native wrapper not set");
        assertEq(stablecoin, address(0x456), "Stablecoin not set");
        assertEq(minDeposit, 0.01 ether, "Min deposit not set");
        assertEq(nativeTokenSymbol, "ETH", "Native token symbol not set");
    }

    function test_InitializeChainConfig_NotOwnerReverts() public {
        JobMarketplaceWithModels.ChainConfig memory config =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x123),
                stablecoin: address(0x456),
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "ETH"
            });

        // Try to initialize as non-owner
        vm.prank(user);
        vm.expectRevert("Only owner");
        marketplace.initializeChainConfig(config);
    }

    function test_InitializeChainConfig_AlreadyInitializedReverts() public {
        JobMarketplaceWithModels.ChainConfig memory config1 =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: address(0x123),
                stablecoin: address(0x456),
                minDeposit: 0.01 ether,
                nativeTokenSymbol: "ETH"
            });

        // First initialization
        vm.prank(treasury);
        marketplace.initializeChainConfig(config1);

        // Try to initialize again
        vm.prank(treasury);
        vm.expectRevert("Already initialized");
        marketplace.initializeChainConfig(config1);
    }
}