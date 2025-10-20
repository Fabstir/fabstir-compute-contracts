// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokenForValidation is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract DepositValidationTest is Test {
    JobMarketplaceWithModels marketplace;
    MockTokenForValidation token;

    address constant ALICE = address(0x1111);

    function setUp() public {
        // Deploy marketplace with required dependencies
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000 // 10% fee,
                    30);

        // Deploy mock token
        token = new MockTokenForValidation();
        token.transfer(ALICE, 100 * 10**18);

        // Fund test account
        vm.deal(ALICE, 10 ether);
    }

    function test_RevertOnZeroNativeDeposit() public {
        vm.expectRevert("Zero deposit");

        vm.prank(ALICE);
        marketplace.depositNative{value: 0}();
    }

    function test_RevertOnZeroTokenDeposit() public {
        vm.startPrank(ALICE);
        token.approve(address(marketplace), 10 * 10**18);

        vm.expectRevert("Zero deposit");
        marketplace.depositToken(address(token), 0);
        vm.stopPrank();
    }

    function test_RevertOnInvalidTokenAddress() public {
        vm.expectRevert("Invalid token");

        vm.prank(ALICE);
        marketplace.depositToken(address(0), 10 * 10**18);
    }

    function test_RevertOnInsufficientAllowance() public {
        vm.startPrank(ALICE);
        // Only approve 5 tokens but try to deposit 10
        token.approve(address(marketplace), 5 * 10**18);

        vm.expectRevert(); // ERC20: transfer amount exceeds allowance
        marketplace.depositToken(address(token), 10 * 10**18);
        vm.stopPrank();
    }

    function test_RevertOnInsufficientTokenBalance() public {
        // Alice has 100 tokens, try to deposit 200
        vm.startPrank(ALICE);
        token.approve(address(marketplace), 200 * 10**18);

        vm.expectRevert(); // ERC20: transfer amount exceeds balance
        marketplace.depositToken(address(token), 200 * 10**18);
        vm.stopPrank();
    }
}