// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";
import {NodeRegistryWithModelsUpgradeable} from "src/NodeRegistryWithModelsUpgradeable.sol";
import {ModelRegistryUpgradeable} from "src/ModelRegistryUpgradeable.sol";
import {HostEarningsUpgradeable} from "src/HostEarningsUpgradeable.sol";
import {ProofSystemUpgradeable} from "src/ProofSystemUpgradeable.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

/**
 * @title MinTokensFee Cap Tests
 * @notice F202615258 (LOW): setMinTokensFee Function Has No Upper Bound
 *
 * Owner should not be able to set minTokensFee to an absurdly high value.
 * MAX_MIN_TOKENS_FEE (10000) caps the fee.
 */
contract MinTokensFeeCapTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    ERC20Mock public fabToken;
    ERC20Mock public usdc;

    address public owner = address(0x1);
    address public nonOwner = address(0x9);

    uint256 constant FEE_BASIS_POINTS = 1000;
    uint256 constant DISPUTE_WINDOW = 30;
    uint256 constant USDC_MIN_DEPOSIT = 500_000;
    uint256 constant USDC_MAX_DEPOSIT = 1_000_000_000_000;

    function setUp() public {
        vm.startPrank(owner);

        fabToken = new ERC20Mock("FAB Token", "FAB");
        usdc = new ERC20Mock("USD Coin", "USDC");

        // Deploy ModelRegistry
        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        ModelRegistryUpgradeable modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));

        // Deploy NodeRegistry
        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        // Deploy HostEarnings
        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        HostEarningsUpgradeable hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        // Deploy JobMarketplace
        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), FEE_BASIS_POINTS, DISPUTE_WINDOW))
        ))));

        vm.stopPrank();
    }

    /// @notice F202615258: setMinTokensFee at exactly MAX_MIN_TOKENS_FEE should succeed
    function test_SetMinTokensFee_AtMax_Succeeds() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(10000);
        assertEq(marketplace.minTokensFee(), 10000);
    }

    /// @notice F202615258: setMinTokensFee above MAX_MIN_TOKENS_FEE should revert
    function test_SetMinTokensFee_AboveMax_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("Fee too high");
        marketplace.setMinTokensFee(10001);
    }

    /// @notice setMinTokensFee(0) disables the fee — should always succeed
    function test_SetMinTokensFee_Zero_Succeeds() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(0);
        assertEq(marketplace.minTokensFee(), 0);
    }

    /// @notice Only owner can call setMinTokensFee (regression)
    function test_SetMinTokensFee_NonOwner_Reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        marketplace.setMinTokensFee(100);
    }

    /// @notice MAX_MIN_TOKENS_FEE constant is publicly accessible and equals 10000
    function test_MaxMinTokensFee_Constant() public view {
        assertEq(marketplace.MAX_MIN_TOKENS_FEE(), 10000);
    }

    /// @notice F202615258: setMinTokensFee emits MinTokensFeeUpdated event
    function test_SetMinTokensFee_EmitsEvent() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(500);

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit MinTokensFeeUpdated(500, 1000);
        marketplace.setMinTokensFee(1000);
    }

    /// @notice Phase 30.3: Fee set to one below max succeeds
    function test_SetMinTokensFee_BoundaryBelowMax() public {
        vm.prank(owner);
        marketplace.setMinTokensFee(9999);
        assertEq(marketplace.minTokensFee(), 9999, "Fee should be 9999");
    }

    event MinTokensFeeUpdated(uint256 oldFee, uint256 newFee);
}
