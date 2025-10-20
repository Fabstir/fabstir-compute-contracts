// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";

contract WalletAgnosticTest is Test {
    JobMarketplaceWithModels marketplace;

    address constant EOA_WALLET = address(0x1111);
    address constant SMART_WALLET = address(0x2222);
    address constant CONTRACT_ADDR = address(0x3333);

    function setUp() public {
        // Deploy marketplace with required dependencies
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000, // 10% fee
            30
        );
    }

    function test_MappingsWorkForEOA() public view {
        // EOA addresses should work with deposit mappings
        marketplace.userDepositsNative(EOA_WALLET);
        marketplace.userDepositsToken(EOA_WALLET, address(0));
    }

    function test_MappingsWorkForSmartWallet() public view {
        // Smart wallet addresses should work identically
        marketplace.userDepositsNative(SMART_WALLET);
        marketplace.userDepositsToken(SMART_WALLET, address(0));
    }

    function test_MappingsWorkForContract() public view {
        // Contract addresses should work identically
        marketplace.userDepositsNative(CONTRACT_ADDR);
        marketplace.userDepositsToken(CONTRACT_ADDR, address(0));
    }

    function test_NoSpecialHandlingByAddressType() public {
        // All address types should return same initial value (0)
        uint256 eoaBalance = marketplace.userDepositsNative(EOA_WALLET);
        uint256 smartBalance = marketplace.userDepositsNative(SMART_WALLET);
        uint256 contractBalance = marketplace.userDepositsNative(CONTRACT_ADDR);

        assertEq(eoaBalance, 0, "EOA should start at 0");
        assertEq(smartBalance, 0, "Smart wallet should start at 0");
        assertEq(contractBalance, 0, "Contract should start at 0");
    }

    function test_ConsistentBehaviorAcrossAddressTypes() public {
        address TOKEN = address(0x9999);

        uint256 eoaTokenBalance = marketplace.userDepositsToken(EOA_WALLET, TOKEN);
        uint256 smartTokenBalance = marketplace.userDepositsToken(SMART_WALLET, TOKEN);
        uint256 contractTokenBalance = marketplace.userDepositsToken(CONTRACT_ADDR, TOKEN);

        assertEq(eoaTokenBalance, 0);
        assertEq(smartTokenBalance, 0);
        assertEq(contractTokenBalance, 0);
    }

    function test_ZeroAddressHandling() public view {
        // Even address(0) should work (though not practical)
        marketplace.userDepositsNative(address(0));
        marketplace.userDepositsToken(address(0), address(0));
    }
}