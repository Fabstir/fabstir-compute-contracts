// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokenBatch is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract BatchQueriesTest is Test {
    JobMarketplaceWithModels marketplace;
    MockTokenBatch token1;
    MockTokenBatch token2;
    MockTokenBatch token3;

    address constant ALICE = address(0x1111);

    function setUp() public {
        // Deploy marketplace
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000 // 10% fee,
                    30);

        // Deploy tokens
        token1 = new MockTokenBatch("Token1", "TK1");
        token2 = new MockTokenBatch("Token2", "TK2");
        token3 = new MockTokenBatch("Token3", "TK3");

        // Setup various deposits
        vm.deal(ALICE, 10 ether);
        vm.prank(ALICE);
        marketplace.depositNative{value: 5 ether}();

        token1.transfer(ALICE, 100 * 10**18);
        token2.transfer(ALICE, 100 * 10**18);

        vm.startPrank(ALICE);
        token1.approve(address(marketplace), 30 * 10**18);
        marketplace.depositToken(address(token1), 30 * 10**18);

        token2.approve(address(marketplace), 20 * 10**18);
        marketplace.depositToken(address(token2), 20 * 10**18);
        vm.stopPrank();
    }

    function test_BatchQueryMixedTokens() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(0); // Native
        tokens[1] = address(token1);
        tokens[2] = address(token2);

        uint256[] memory balances = marketplace.getDepositBalances(ALICE, tokens);

        assertEq(balances.length, 3);
        assertEq(balances[0], 5 ether, "Native balance");
        assertEq(balances[1], 30 * 10**18, "Token1 balance");
        assertEq(balances[2], 20 * 10**18, "Token2 balance");
    }

    function test_BatchQueryEmptyArray() public {
        address[] memory tokens = new address[](0);
        uint256[] memory balances = marketplace.getDepositBalances(ALICE, tokens);

        assertEq(balances.length, 0, "Empty array should return empty");
    }

    function test_BatchQueryAllNative() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(0);
        tokens[1] = address(0);
        tokens[2] = address(0);

        uint256[] memory balances = marketplace.getDepositBalances(ALICE, tokens);

        assertEq(balances.length, 3);
        assertEq(balances[0], 5 ether, "Native balance");
        assertEq(balances[1], 5 ether, "Native balance repeated");
        assertEq(balances[2], 5 ether, "Native balance repeated");
    }

    function test_BatchQueryWithZeroBalances() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(token3); // No deposits
        tokens[1] = address(0xDEAD); // Random address
        tokens[2] = address(token1);

        uint256[] memory balances = marketplace.getDepositBalances(ALICE, tokens);

        assertEq(balances[0], 0, "Token3 should be zero");
        assertEq(balances[1], 0, "Random token should be zero");
        assertEq(balances[2], 30 * 10**18, "Token1 balance");
    }
}