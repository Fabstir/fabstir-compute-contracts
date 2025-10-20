// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceWithModels.sol";

contract DeployJobMarketplaceWithModels is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Contract addresses
        address nodeRegistryWithModels = 0xC8dDD546e0993eEB4Df03591208aEDF6336342D7; // NEW: with pricing support
        address payable hostEarnings = payable(0x908962e8c6CE72610021586f85ebDE09aAc97776);

        vm.startBroadcast(deployerPrivateKey);

        // Default to 10% treasury fee (1000 basis points) if not specified
        uint256 feeBasisPoints = 1000; // 10% treasury fee

        // Get dispute window from env (default 30 seconds for testing)
        uint256 disputeWindow = vm.envOr("DISPUTE_WINDOW", uint256(30));

        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            nodeRegistryWithModels,
            hostEarnings,
            feeBasisPoints,
            disputeWindow
        );

        console.log("JobMarketplaceWithModels deployed to:", address(marketplace));
        console.log("Dispute window set to:", disputeWindow, "seconds");

        // Set proof system if needed (can be done later)
        // marketplace.setProofSystem(0x2ACcc60893872A499700908889B38C5420CBcFD1);

        vm.stopBroadcast();
    }
}