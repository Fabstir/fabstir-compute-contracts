// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ModelRegistry.sol";

contract DeployModelRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address fabTokenAddress = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;

        vm.startBroadcast(deployerPrivateKey);

        ModelRegistry modelRegistry = new ModelRegistry(fabTokenAddress);

        console.log("ModelRegistry deployed to:", address(modelRegistry));

        vm.stopBroadcast();
    }
}