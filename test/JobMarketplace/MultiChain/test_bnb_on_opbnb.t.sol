// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModels} from "../../../src/JobMarketplaceWithModels.sol";
import {NodeRegistryWithModels} from "../../../src/NodeRegistryWithModels.sol";
import {ModelRegistry} from "../../../src/ModelRegistry.sol";
import {ProofSystem} from "../../../src/ProofSystem.sol";
import {HostEarnings} from "../../../src/HostEarnings.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

contract TestBnbOnOpBNB is Test {
    JobMarketplaceWithModels public marketplace;
    address public user = address(0x5678);
    address public treasury = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    // opBNB-specific addresses (testnet examples)
    address constant WBNB_ON_OPBNB = address(0x9999); // Example WBNB address
    address constant USDC_ON_OPBNB = address(0x8888); // Example USDC on opBNB

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

        // Configure for opBNB chain
        JobMarketplaceWithModels.ChainConfig memory bnbConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: WBNB_ON_OPBNB,
                stablecoin: USDC_ON_OPBNB,
                minDeposit: 0.01 ether, // Different min for BNB
                nativeTokenSymbol: "BNB"
            });

        vm.prank(treasury);
        marketplace.initializeChainConfig(bnbConfig);

        // Fund user with BNB (simulated as ETH in tests)
        vm.deal(user, 100 ether);
    }

    function test_DepositNativeWorksWithBNB() public {
        // BNB uses same depositNative function
        uint256 depositAmount = 5 ether; // 5 BNB

        vm.prank(user);
        marketplace.depositNative{value: depositAmount}();

        assertEq(marketplace.userDepositsNative(user), depositAmount, "BNB deposit failed");
    }

    function test_WithdrawNativeReturnsBNB() public {
        // First deposit BNB
        vm.prank(user);
        marketplace.depositNative{value: 10 ether}(); // 10 BNB

        uint256 balanceBefore = user.balance;

        // Withdraw BNB
        vm.prank(user);
        marketplace.withdrawNative(3 ether); // 3 BNB

        assertEq(user.balance, balanceBefore + 3 ether, "BNB withdrawal failed");
        assertEq(marketplace.userDepositsNative(user), 7 ether, "Remaining BNB incorrect");
    }

    function test_ChainConfigShowsBNB() public {
        (,,,string memory symbol) = marketplace.chainConfig();
        assertEq(symbol, "BNB", "Should be configured for BNB on opBNB");
    }

    function test_WBNBWrapperAddressConfigured() public {
        (address wrapper,,,) = marketplace.chainConfig();
        assertEq(wrapper, WBNB_ON_OPBNB, "WBNB address should be configured");
    }

    function test_MinDepositDifferentForBNB() public {
        (,,uint256 minDeposit,) = marketplace.chainConfig();
        assertEq(minDeposit, 0.01 ether, "Min deposit should be 0.01 BNB");
    }
}