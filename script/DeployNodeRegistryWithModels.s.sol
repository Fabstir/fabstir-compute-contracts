// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/NodeRegistryWithModels.sol";

contract DeployNodeRegistryWithModels is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address modelRegistryAddress = 0x92b2De840bB2171203011A6dBA928d855cA8183E;
        address fabTokenAddress = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;

        vm.startBroadcast(deployerPrivateKey);

        NodeRegistryWithModels nodeRegistry = new NodeRegistryWithModels(
            fabTokenAddress,
            modelRegistryAddress
        );

        console.log("NodeRegistryWithModels deployed to:", address(nodeRegistry));

        vm.stopBroadcast();
    }
}