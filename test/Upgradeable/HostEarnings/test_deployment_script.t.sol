// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {DeployHostEarningsUpgradeable} from "../../../script/DeployHostEarningsUpgradeable.s.sol";

/**
 * @title HostEarnings Deployment Script Tests
 * @dev Tests the deployment script for HostEarningsUpgradeable
 */
contract HostEarningsDeploymentScriptTest is Test {
    DeployHostEarningsUpgradeable public deployScript;

    function setUp() public {
        // Create deployment script
        deployScript = new DeployHostEarningsUpgradeable();
    }

    function test_DeploymentScriptWorks() public {
        // Run the deployment script
        (address proxy, address implementation) = deployScript.run();

        // Verify deployment
        assertTrue(proxy != address(0), "Proxy should be deployed");
        assertTrue(implementation != address(0), "Implementation should be deployed");
        assertTrue(proxy != implementation, "Proxy and implementation should be different");
    }

    function test_DeploymentInitializesCorrectly() public {
        (address proxy, ) = deployScript.run();

        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(proxy));

        // Verify initialization
        assertTrue(hostEarnings.owner() != address(0), "Owner should be set");
    }

    function test_DeploymentStoresCorrectImplementation() public {
        (address proxy, address implementation) = deployScript.run();

        // Get implementation address from ERC1967 storage slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, implementation, "Implementation addresses should match");
    }

    function test_DeployedContractIsUpgradeable() public {
        (address proxy, ) = deployScript.run();

        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(proxy));
        address originalOwner = hostEarnings.owner();

        // Deploy new implementation
        HostEarningsUpgradeable newImpl = new HostEarningsUpgradeable();

        // Upgrade should work (as owner)
        vm.prank(originalOwner);
        hostEarnings.upgradeToAndCall(address(newImpl), "");

        // Verify upgrade
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, address(newImpl));
    }

    function test_DeployedContractCanSetAuthorizedCaller() public {
        (address proxy, ) = deployScript.run();

        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(proxy));
        address owner = hostEarnings.owner();

        // Set an authorized caller
        address caller = address(0x100);
        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(caller, true);

        // Verify
        assertTrue(hostEarnings.authorizedCallers(caller));
    }

    function test_DeployedContractCanCreditAndWithdraw() public {
        (address proxy, ) = deployScript.run();

        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(proxy));
        address owner = hostEarnings.owner();

        // Set up authorized caller
        address caller = address(0x100);
        address host = address(0x200);

        vm.prank(owner);
        hostEarnings.setAuthorizedCaller(caller, true);

        // Fund the contract
        vm.deal(address(hostEarnings), 10 ether);

        // Credit earnings
        vm.prank(caller);
        hostEarnings.creditEarnings(host, 5 ether, address(0));

        // Verify balance
        assertEq(hostEarnings.getBalance(host, address(0)), 5 ether);

        // Withdraw
        vm.prank(host);
        hostEarnings.withdraw(2 ether, address(0));

        assertEq(hostEarnings.getBalance(host, address(0)), 3 ether);
    }
}
