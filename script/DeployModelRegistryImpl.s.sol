// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {ModelRegistryUpgradeable} from "../src/ModelRegistryUpgradeable.sol";

contract DeployModelRegistryImpl is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        ModelRegistryUpgradeable impl = new ModelRegistryUpgradeable();
        
        console.log("ModelRegistryUpgradeable Implementation deployed at:", address(impl));
        
        vm.stopBroadcast();
    }
}
