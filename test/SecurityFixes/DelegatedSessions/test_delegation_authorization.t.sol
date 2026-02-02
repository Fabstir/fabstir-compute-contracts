// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../../../src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "../../../src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "../../../src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "../../../src/HostEarningsUpgradeable.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";

/**
 * @title Delegation Authorization Tests
 * @notice Tests for authorizeDelegate() and isDelegateAuthorized() functions
 */
contract DelegationAuthorizationTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public depositor;
    address public delegate;
    address public otherDepositor;
    address public otherDelegate;

    event DelegateAuthorized(address indexed depositor, address indexed delegate, bool authorized);

    function setUp() public {
        depositor = makeAddr("depositor");
        delegate = makeAddr("delegate");
        otherDepositor = makeAddr("otherDepositor");
        otherDelegate = makeAddr("otherDelegate");

        vm.startPrank(owner);
        fabToken = new ERC20Mock("FAB", "FAB");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        address modelRegistryProxy = address(
            new ERC1967Proxy(address(modelRegistryImpl), abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken))))
        );

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        address nodeRegistryProxy = address(
            new ERC1967Proxy(address(nodeRegistryImpl), abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), modelRegistryProxy)))
        );

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        address hostEarningsProxy = address(
            new ERC1967Proxy(address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ()))
        );

        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        address marketplaceProxy = address(
            new ERC1967Proxy(address(marketplaceImpl), abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize, (nodeRegistryProxy, payable(hostEarningsProxy), 1000, 30)))
        );
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(marketplaceProxy));
        vm.stopPrank();
    }

    function test_AuthorizeDelegate_Success() public {
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_RevokeDelegate_Success() public {
        vm.startPrank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        marketplace.authorizeDelegate(delegate, false);
        vm.stopPrank();
        assertFalse(marketplace.isDelegateAuthorized(depositor, delegate));
    }

    function test_AuthorizeDelegate_ZeroAddress_Reverts() public {
        vm.prank(depositor);
        vm.expectRevert("Invalid delegate address");
        marketplace.authorizeDelegate(address(0), true);
    }

    function test_AuthorizeDelegate_Self_Reverts() public {
        vm.prank(depositor);
        vm.expectRevert("Cannot delegate to self");
        marketplace.authorizeDelegate(depositor, true);
    }

    function test_AuthorizeDelegate_EmitsEvent() public {
        vm.prank(depositor);
        vm.expectEmit(true, true, false, true);
        emit DelegateAuthorized(depositor, delegate, true);
        marketplace.authorizeDelegate(delegate, true);
    }

    function test_RevokeDelegate_EmitsEvent() public {
        vm.startPrank(depositor);
        marketplace.authorizeDelegate(delegate, true);
        vm.expectEmit(true, true, false, true);
        emit DelegateAuthorized(depositor, delegate, false);
        marketplace.authorizeDelegate(delegate, false);
        vm.stopPrank();
    }

    function test_MultipleDelegatorsIndependentDelegates() public {
        // Each depositor can authorize their own delegates
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);

        vm.prank(otherDepositor);
        marketplace.authorizeDelegate(otherDelegate, true);

        // Verify authorizations are independent
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        assertFalse(marketplace.isDelegateAuthorized(depositor, otherDelegate));
        assertTrue(marketplace.isDelegateAuthorized(otherDepositor, otherDelegate));
        assertFalse(marketplace.isDelegateAuthorized(otherDepositor, delegate));
    }

    function test_OneDelegateMultipleDepositors() public {
        // Same delegate can be authorized by multiple depositors
        vm.prank(depositor);
        marketplace.authorizeDelegate(delegate, true);

        vm.prank(otherDepositor);
        marketplace.authorizeDelegate(delegate, true);

        // Same delegate authorized for both depositors
        assertTrue(marketplace.isDelegateAuthorized(depositor, delegate));
        assertTrue(marketplace.isDelegateAuthorized(otherDepositor, delegate));
    }

    function test_DefaultAuthorizationIsFalse() public view {
        // Unset authorizations should return false
        assertFalse(marketplace.isDelegateAuthorized(depositor, delegate));
    }
}
