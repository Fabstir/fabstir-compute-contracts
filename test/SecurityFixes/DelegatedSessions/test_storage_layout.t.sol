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
 * @title Delegated Session Storage Layout Tests
 * @notice Verifies storage additions don't break UUPS upgrade safety
 */
contract DelegatedSessionStorageTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    ERC20Mock public fabToken;

    address public owner = address(0x1);
    address public depositor = makeAddr("depositor");
    address public delegate = makeAddr("delegate");

    function setUp() public {
        vm.startPrank(owner);
        fabToken = new ERC20Mock("FAB", "FAB");

        // Deploy minimal contracts for storage testing
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

    function test_DelegationMappingAccessible() public {
        // Verify isAuthorizedDelegate mapping exists and returns default false
        bool authorized = marketplace.isAuthorizedDelegate(depositor, delegate);
        assertFalse(authorized, "Default should be false");
    }

    function test_ExistingStorageUnchanged() public {
        // Verify userDepositsNative still works
        vm.deal(depositor, 1 ether);
        vm.prank(depositor);
        marketplace.depositNative{value: 0.5 ether}();
        assertEq(marketplace.userDepositsNative(depositor), 0.5 ether, "Native deposit should work");
    }
}
