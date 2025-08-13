// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/NodeRegistryFAB.sol";

contract DeployNodeRegistryFAB is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // FAB Token address on Base Sepolia
        address fabToken = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
        
        console.log("========================================");
        console.log("Deploying NodeRegistryFAB to Base Sepolia");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("FAB Token:", fabToken);
        
        vm.startBroadcast(deployerPrivateKey);
        
        NodeRegistryFAB registry = new NodeRegistryFAB(fabToken);
        
        console.log("\n[SUCCESS] NodeRegistryFAB deployed at:", address(registry));
        console.log("FAB token address:", fabToken);
        console.log("Minimum stake:", registry.minimumStake() / 10**18, "FAB");
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("Deployment Complete!");
        console.log("========================================");
        console.log("\nTo verify on BaseScan:");
        console.log("forge verify-contract", address(registry));
        console.log("    src/NodeRegistryFAB.sol:NodeRegistryFAB");
        console.log("    --etherscan-api-key $BASESCAN_API_KEY");
        console.log("    --chain base-sepolia");
        console.log("    --constructor-args", vm.toString(abi.encode(fabToken)));
    }
}