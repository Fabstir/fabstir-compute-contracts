// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceWithModels.sol";

contract DeployJobMarketplaceWithModels is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Contract addresses
        address nodeRegistryWithModels = 0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218;
        address payable hostEarnings = payable(0x908962e8c6CE72610021586f85ebDE09aAc97776);

        vm.startBroadcast(deployerPrivateKey);

        // Default to 10% treasury fee (1000 basis points) if not specified
        uint256 feeBasisPoints = 1000; // 10% treasury fee

        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            nodeRegistryWithModels,
            hostEarnings,
            feeBasisPoints
        );

        console.log("JobMarketplaceWithModels deployed to:", address(marketplace));

        // Set proof system if needed (can be done later)
        // marketplace.setProofSystem(0x2ACcc60893872A499700908889B38C5420CBcFD1);

        vm.stopBroadcast();
    }
}