// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {JobMarketplaceWithModelsUpgradeable} from "../src/JobMarketplaceWithModelsUpgradeable.sol";

contract DeployJobMarketplaceImpl is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        JobMarketplaceWithModelsUpgradeable implementation = new JobMarketplaceWithModelsUpgradeable();

        vm.stopBroadcast();
    }
}
