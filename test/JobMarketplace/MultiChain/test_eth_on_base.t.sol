// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract TestEthOnBase is Test {
    JobMarketplaceWithModels public marketplace;
    address public user = address(0x1234);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    // Base-specific addresses
    address constant WETH_ON_BASE = 0x4200000000000000000000000000000000000006;
    address constant USDC_ON_BASE = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    event DepositReceived(address indexed depositor, uint256 amount, address indexed token);
    event WithdrawalProcessed(address indexed depositor, uint256 amount, address indexed token);

    function setUp() public {
        // Deploy marketplace
        ERC20Mock fabToken = new ERC20Mock("FAB", "FAB");
        ERC20Mock govToken = new ERC20Mock("GOV", "GOV");
        ModelRegistry modelReg = new ModelRegistry(address(govToken));
        NodeRegistryWithModels nodeReg = new NodeRegistryWithModels(address(fabToken), address(modelReg));
        ProofSystem proofSys = new ProofSystem();
        HostEarnings hostEarn = new HostEarnings();

        marketplace = new JobMarketplaceWithModels(
            address(nodeReg),
            payable(address(hostEarn)),
            1000, // 10% fee
            30
        );

        hostEarn.setAuthorizedCaller(address(marketplace), true);

        // Configure for Base chain
        JobMarketplaceWithModels.ChainConfig memory baseConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: WETH_ON_BASE,
                stablecoin: USDC_ON_BASE,
                minDeposit: 0.001 ether,
                nativeTokenSymbol: "ETH"
            });

        vm.prank(treasury);
        marketplace.initializeChainConfig(baseConfig);

        // Fund user with ETH
        vm.deal(user, 10 ether);
    }

    function test_DepositNativeWorksWithETH() public {
        uint256 depositAmount = 1 ether;

        vm.prank(user);
        marketplace.depositNative{value: depositAmount}();

        assertEq(marketplace.userDepositsNative(user), depositAmount, "ETH deposit failed");
    }

    function test_WithdrawNativeReturnsETH() public {
        // First deposit
        vm.prank(user);
        marketplace.depositNative{value: 2 ether}();

        uint256 balanceBefore = user.balance;

        // Withdraw
        vm.prank(user);
        marketplace.withdrawNative(1 ether);

        assertEq(user.balance, balanceBefore + 1 ether, "ETH withdrawal failed");
        assertEq(marketplace.userDepositsNative(user), 1 ether, "Remaining balance incorrect");
    }

    function test_ChainConfigShowsETH() public {
        (,,,string memory symbol) = marketplace.chainConfig();
        assertEq(symbol, "ETH", "Should be configured for ETH on Base");
    }

    function test_WETHWrapperAddressConfigured() public {
        (address wrapper,,,) = marketplace.chainConfig();
        assertEq(wrapper, WETH_ON_BASE, "WETH address should be configured");
    }
}