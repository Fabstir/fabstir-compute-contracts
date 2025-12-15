// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title DeployUpgradeable
 * @dev Base deployment script with helpers for UUPS upgradeable contracts
 */
abstract contract DeployUpgradeable is Script {
    /**
     * @dev Deploy an implementation contract behind an ERC1967 proxy
     * @param implementation The implementation contract address
     * @param initData The initialization calldata (abi.encodeCall of initialize function)
     * @return proxy The deployed proxy address
     */
    function deployProxy(
        address implementation,
        bytes memory initData
    ) internal returns (address proxy) {
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("  Proxy deployed at:", proxy);
        console.log("  Implementation at:", implementation);
    }

    /**
     * @dev Upgrade an existing proxy to a new implementation
     * @param proxy The proxy contract address (must be UUPSUpgradeable)
     * @param newImplementation The new implementation address
     */
    function upgradeProxy(
        address proxy,
        address newImplementation
    ) internal {
        UUPSUpgradeable(proxy).upgradeToAndCall(newImplementation, "");
        console.log("  Proxy upgraded to:", newImplementation);
    }

    /**
     * @dev Upgrade an existing proxy to a new implementation with initialization data
     * @param proxy The proxy contract address (must be UUPSUpgradeable)
     * @param newImplementation The new implementation address
     * @param initData The initialization calldata for the new implementation
     */
    function upgradeProxyWithData(
        address proxy,
        address newImplementation,
        bytes memory initData
    ) internal {
        UUPSUpgradeable(proxy).upgradeToAndCall(newImplementation, initData);
        console.log("  Proxy upgraded to:", newImplementation);
        console.log("  With initialization data");
    }

    /**
     * @dev Get the implementation address of a proxy using ERC1967 storage slot
     * @param proxy The proxy contract address
     * @return impl The implementation address
     */
    function getImplementation(address proxy) internal view returns (address impl) {
        // ERC1967 implementation slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 value = vm.load(proxy, slot);
        impl = address(uint160(uint256(value)));
    }

    /**
     * @dev Log deployment summary
     */
    function logDeployment(
        string memory name,
        address proxy,
        address implementation
    ) internal pure {
        console.log("");
        console.log("===========================================");
        console.log(name, "Deployment");
        console.log("===========================================");
        console.log("Proxy Address:         ", proxy);
        console.log("Implementation Address:", implementation);
        console.log("===========================================");
        console.log("");
    }
}
