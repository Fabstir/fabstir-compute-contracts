// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../src/JobMarketplaceWithModelsUpgradeable.sol";

contract DeployJMImplementation is Script {
    function run() external {
        vm.startBroadcast();
        JobMarketplaceWithModelsUpgradeable impl = new JobMarketplaceWithModelsUpgradeable();
        console.log("Implementation deployed at:", address(impl));
        vm.stopBroadcast();
    }
}
