// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/NodeRegistryWithModels.sol";
import "../../../src/ModelRegistry.sol";
import "../../../src/HostEarnings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Malicious contract that attempts reentrancy
contract ReentrancyAttacker {
    JobMarketplaceWithModels public marketplace;
    uint256 public attackCount;

    constructor(JobMarketplaceWithModels _marketplace) {
        marketplace = _marketplace;
    }

    // Deposit funds to later attack
    function deposit() external payable {
        marketplace.depositNative{value: msg.value}();
    }

    // Attempt reentrancy attack
    function attack() external {
        marketplace.withdrawNative(1 ether);
    }

    // Receive function that tries to re-enter
    receive() external payable {
        attackCount++;
        if (attackCount < 10 && address(marketplace).balance > 0) {
            marketplace.withdrawNative(1 ether);
        }
    }
}

// Mock token that attempts reentrancy on transfer
contract MaliciousToken is ERC20 {
    JobMarketplaceWithModels public marketplace;
    uint256 public attackCount;

    constructor(JobMarketplaceWithModels _marketplace) ERC20("Malicious", "MAL") {
        marketplace = _marketplace;
        _mint(msg.sender, 1000 * 10**18);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        attackCount++;
        if (attackCount < 10) {
            try marketplace.withdrawToken(address(this), 1 * 10**18) {} catch {}
        }
        return super.transfer(to, amount);
    }
}

contract ReentrancyProtectionTest is Test {
    JobMarketplaceWithModels marketplace;
    ReentrancyAttacker attacker;

    function setUp() public {
        // Deploy marketplace
        address modelRegistry = address(new ModelRegistry(address(0x4444)));
        address nodeRegistry = address(new NodeRegistryWithModels(address(0x5555), modelRegistry));
        address hostEarnings = address(new HostEarnings());

        marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            payable(hostEarnings),
            1000 // 10% fee
        );

        // Deploy attacker
        attacker = new ReentrancyAttacker(marketplace);

        // Fund attacker
        vm.deal(address(attacker), 10 ether);
    }

    function test_ReentrancyProtectionOnNativeWithdraw() public {
        // Attacker deposits funds
        attacker.deposit{value: 5 ether}();

        // Attempt attack - should revert due to nonReentrant modifier
        vm.expectRevert(); // ReentrancyGuard: reentrant call

        attacker.attack();
    }

    function test_NormalWithdrawStillWorks() public {
        // Normal user can still withdraw
        vm.deal(address(0x9999), 5 ether);

        vm.startPrank(address(0x9999));
        marketplace.depositNative{value: 3 ether}();
        marketplace.withdrawNative(1 ether);
        vm.stopPrank();

        assertEq(marketplace.userDepositsNative(address(0x9999)), 2 ether);
    }
}