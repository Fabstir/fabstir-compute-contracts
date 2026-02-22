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

/// @notice F202615003: Missing Zero-Address Checks Across Contracts
contract ZeroAddressChecksTest is Test {
    JobMarketplaceWithModelsUpgradeable public marketplace;
    HostEarningsUpgradeable public hostEarnings;
    ProofSystemUpgradeable public proofSystem;

    address public owner = address(0x1);

    function setUp() public {
        vm.startPrank(owner);

        ERC20Mock fabToken = new ERC20Mock("FAB Token", "FAB");

        ModelRegistryUpgradeable modelRegistryImpl = new ModelRegistryUpgradeable();
        ModelRegistryUpgradeable modelRegistry = ModelRegistryUpgradeable(address(new ERC1967Proxy(
            address(modelRegistryImpl),
            abi.encodeCall(ModelRegistryUpgradeable.initialize, (address(fabToken)))
        )));

        NodeRegistryWithModelsUpgradeable nodeRegistryImpl = new NodeRegistryWithModelsUpgradeable();
        NodeRegistryWithModelsUpgradeable nodeRegistry = NodeRegistryWithModelsUpgradeable(address(new ERC1967Proxy(
            address(nodeRegistryImpl),
            abi.encodeCall(NodeRegistryWithModelsUpgradeable.initialize, (address(fabToken), address(modelRegistry)))
        )));

        HostEarningsUpgradeable hostEarningsImpl = new HostEarningsUpgradeable();
        hostEarnings = HostEarningsUpgradeable(payable(address(new ERC1967Proxy(
            address(hostEarningsImpl), abi.encodeCall(HostEarningsUpgradeable.initialize, ())
        ))));

        ProofSystemUpgradeable proofSystemImpl = new ProofSystemUpgradeable();
        proofSystem = ProofSystemUpgradeable(address(new ERC1967Proxy(
            address(proofSystemImpl), abi.encodeCall(ProofSystemUpgradeable.initialize, ())
        )));

        JobMarketplaceWithModelsUpgradeable marketplaceImpl = new JobMarketplaceWithModelsUpgradeable();
        marketplace = JobMarketplaceWithModelsUpgradeable(payable(address(new ERC1967Proxy(
            address(marketplaceImpl),
            abi.encodeCall(JobMarketplaceWithModelsUpgradeable.initialize,
                (address(nodeRegistry), payable(address(hostEarnings)), 1000, 30))
        ))));

        vm.stopPrank();
    }

    /// @notice setProofSystem(address(0)) should revert
    function test_SetProofSystem_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert("Zero address");
        marketplace.setProofSystem(address(0));
    }

    /// @notice setProofSystem with valid address should succeed
    function test_SetProofSystem_ValidAddress_Succeeds() public {
        vm.prank(owner);
        marketplace.setProofSystem(address(proofSystem));
        // No revert = success
    }
}
