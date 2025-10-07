// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokenQuery is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract BalanceQueriesTest is Test {
    JobMarketplaceWithModels marketplace;
    MockTokenQuery token1;
    MockTokenQuery token2;

    address constant ALICE = address(0x1111);
    address constant BOB = address(0x2222);
    address constant CHARLIE = address(0x3333);

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
        token1 = new MockTokenQuery();
        token2 = new MockTokenQuery();

        // Setup deposits for testing
        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);

        vm.prank(ALICE);
        marketplace.depositNative{value: 3 ether}();

        token1.transfer(ALICE, 100 * 10**18);
        vm.startPrank(ALICE);
        token1.approve(address(marketplace), 50 * 10**18);
        marketplace.depositToken(address(token1), 50 * 10**18);
        vm.stopPrank();

        vm.prank(BOB);
        marketplace.depositNative{value: 2 ether}();
    }

    function test_GetNativeBalance() public {
        uint256 balance = marketplace.getDepositBalance(ALICE, address(0));
        assertEq(balance, 3 ether, "Should return native balance");
    }

    function test_GetTokenBalance() public {
        uint256 balance = marketplace.getDepositBalance(ALICE, address(token1));
        assertEq(balance, 50 * 10**18, "Should return token balance");
    }

    function test_GetZeroBalance() public {
        uint256 balance = marketplace.getDepositBalance(CHARLIE, address(0));
        assertEq(balance, 0, "Should return zero for no deposits");
    }

    function test_GetZeroTokenBalance() public {
        uint256 balance = marketplace.getDepositBalance(BOB, address(token1));
        assertEq(balance, 0, "Should return zero for no token deposits");
    }

    function test_DifferentUsersHaveDifferentBalances() public {
        uint256 aliceNative = marketplace.getDepositBalance(ALICE, address(0));
        uint256 bobNative = marketplace.getDepositBalance(BOB, address(0));

        assertEq(aliceNative, 3 ether);
        assertEq(bobNative, 2 ether);
    }

    function test_UnusedTokenReturnsZero() public {
        uint256 balance = marketplace.getDepositBalance(ALICE, address(token2));
        assertEq(balance, 0, "Should return zero for unused token");
    }
}