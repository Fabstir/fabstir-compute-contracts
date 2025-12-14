// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title HostEarningsUpgradeable V2 (Mock for testing upgrades)
 * @dev Adds version function and extra state for testing upgrade preservation
 */
contract HostEarningsUpgradeableV2 is HostEarningsUpgradeable {
    // New storage variable (appended after existing storage)
    string public contractName;

    function initializeV2(string memory _name) external reinitializer(2) {
        contractName = _name;
    }

    function version() external pure returns (string memory) {
        return "v2";
    }
}

/**
 * @title HostEarningsUpgradeable Upgrade Tests
 * @dev Tests upgrade mechanics, state preservation, and authorization
 */
contract HostEarningsUpgradeTest is Test {
    HostEarningsUpgradeable public implementation;
    HostEarningsUpgradeable public hostEarnings;
    ERC20Mock public usdc;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public host1 = address(0x3);
    address public host2 = address(0x4);
    address public authorizedCaller = address(0x5);

    function setUp() public {
        // Deploy mock USDC
        usdc = new ERC20Mock("USD Coin", "USDC");

        // Deploy implementation
        implementation = new HostEarningsUpgradeable();

        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = address(new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ));
        hostEarnings = HostEarningsUpgradeable(payable(proxyAddr));

        // Setup state for testing preservation
        vm.startPrank(owner);
        hostEarnings.setAuthorizedCaller(authorizedCaller, true);
        vm.stopPrank();

        // Fund contract
        vm.deal(address(hostEarnings), 100 ether);
        usdc.mint(address(hostEarnings), 10000 * 10**18);

        // Credit some earnings
        vm.startPrank(authorizedCaller);
        hostEarnings.creditEarnings(host1, 10 ether, address(0));
        hostEarnings.creditEarnings(host2, 5 ether, address(0));
        hostEarnings.creditEarnings(host1, 1000 * 10**18, address(usdc));
        vm.stopPrank();
    }

    // ============================================================
    // Pre-Upgrade State Verification
    // ============================================================

    function test_PreUpgradeStateIsCorrect() public view {
        // Verify earnings
        assertEq(hostEarnings.getBalance(host1, address(0)), 10 ether);
        assertEq(hostEarnings.getBalance(host2, address(0)), 5 ether);
        assertEq(hostEarnings.getBalance(host1, address(usdc)), 1000 * 10**18);

        // Verify totals
        assertEq(hostEarnings.totalAccumulated(address(0)), 15 ether);
        assertEq(hostEarnings.totalAccumulated(address(usdc)), 1000 * 10**18);

        // Verify authorization
        assertTrue(hostEarnings.authorizedCallers(authorizedCaller));

        // Verify owner
        assertEq(hostEarnings.owner(), owner);
    }

    // ============================================================
    // Upgrade Authorization Tests
    // ============================================================

    function test_OnlyOwnerCanUpgrade() public {
        // Deploy V2 implementation
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        // Try to upgrade as non-owner - should revert
        vm.prank(user1);
        vm.expectRevert();
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");
    }

    function test_OwnerCanUpgrade() public {
        // Deploy V2 implementation
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        // Upgrade as owner - should succeed
        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        // Verify upgrade worked by calling V2 function
        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));
        assertEq(hostEarningsV2.version(), "v2");
    }

    // ============================================================
    // State Preservation Tests
    // ============================================================

    function test_UpgradePreservesOwner() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));
        assertEq(hostEarningsV2.owner(), owner);
    }

    function test_UpgradePreservesEarnings() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Verify earnings preserved
        assertEq(hostEarningsV2.getBalance(host1, address(0)), 10 ether);
        assertEq(hostEarningsV2.getBalance(host2, address(0)), 5 ether);
        assertEq(hostEarningsV2.getBalance(host1, address(usdc)), 1000 * 10**18);
    }

    function test_UpgradePreservesTotals() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Verify totals preserved
        assertEq(hostEarningsV2.totalAccumulated(address(0)), 15 ether);
        assertEq(hostEarningsV2.totalAccumulated(address(usdc)), 1000 * 10**18);
    }

    function test_UpgradePreservesAuthorizedCallers() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Verify authorized caller preserved
        assertTrue(hostEarningsV2.authorizedCallers(authorizedCaller));
    }

    // ============================================================
    // Upgrade With Initialization Tests
    // ============================================================

    function test_UpgradeWithV2Initialization() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        // Upgrade with V2 initialization
        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(HostEarningsUpgradeableV2.initializeV2, ("Host Earnings V2"))
        );

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Verify V2 initialization worked
        assertEq(hostEarningsV2.contractName(), "Host Earnings V2");
        assertEq(hostEarningsV2.version(), "v2");

        // Verify V1 state still preserved
        assertEq(hostEarningsV2.owner(), owner);
        assertEq(hostEarningsV2.getBalance(host1, address(0)), 10 ether);
        assertTrue(hostEarningsV2.authorizedCallers(authorizedCaller));
    }

    function test_V2InitializationCannotBeCalledTwice() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        // Upgrade with V2 initialization
        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(
            address(implementationV2),
            abi.encodeCall(HostEarningsUpgradeableV2.initializeV2, ("Host Earnings V2"))
        );

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Try to call initializeV2 again - should revert
        vm.expectRevert();
        hostEarningsV2.initializeV2("Another Name");
    }

    // ============================================================
    // Post-Upgrade Functionality Tests
    // ============================================================

    function test_CanCreditEarningsAfterUpgrade() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Credit more earnings after upgrade
        vm.prank(authorizedCaller);
        hostEarningsV2.creditEarnings(host1, 5 ether, address(0));

        assertEq(hostEarningsV2.getBalance(host1, address(0)), 15 ether);
    }

    function test_CanWithdrawAfterUpgrade() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        uint256 balanceBefore = host1.balance;

        // Withdraw after upgrade
        vm.prank(host1);
        hostEarningsV2.withdraw(5 ether, address(0));

        assertEq(host1.balance, balanceBefore + 5 ether);
        assertEq(hostEarningsV2.getBalance(host1, address(0)), 5 ether);
    }

    function test_CanSetAuthorizedCallerAfterUpgrade() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Set new authorized caller after upgrade
        address newCaller = address(0x999);
        vm.prank(owner);
        hostEarningsV2.setAuthorizedCaller(newCaller, true);

        assertTrue(hostEarningsV2.authorizedCallers(newCaller));
    }

    function test_CanTransferOwnershipAfterUpgrade() public {
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        HostEarningsUpgradeableV2 hostEarningsV2 = HostEarningsUpgradeableV2(payable(address(hostEarnings)));

        // Transfer ownership
        vm.prank(owner);
        hostEarningsV2.transferOwnership(user1);

        assertEq(hostEarningsV2.owner(), user1);

        // New owner can set authorized callers
        vm.prank(user1);
        hostEarningsV2.setAuthorizedCaller(address(0x888), true);
    }

    // ============================================================
    // Implementation Slot Verification
    // ============================================================

    function test_ImplementationSlotUpdatedAfterUpgrade() public {
        // Get implementation before upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implBefore = address(uint160(uint256(vm.load(address(hostEarnings), slot))));
        assertEq(implBefore, address(implementation));

        // Deploy and upgrade to V2
        HostEarningsUpgradeableV2 implementationV2 = new HostEarningsUpgradeableV2();

        vm.prank(owner);
        UUPSUpgradeable(address(hostEarnings)).upgradeToAndCall(address(implementationV2), "");

        // Verify implementation changed
        address implAfter = address(uint160(uint256(vm.load(address(hostEarnings), slot))));
        assertEq(implAfter, address(implementationV2));
        assertTrue(implAfter != implBefore);
    }
}
