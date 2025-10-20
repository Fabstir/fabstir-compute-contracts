// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceWithModels.sol";

contract DeployJobMarketplace is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address nodeRegistry = 0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218;
        address payable hostEarnings = payable(0x908962e8c6CE72610021586f85ebDE09aAc97776);

        vm.startBroadcast(deployerPrivateKey);

        // Default to 10% treasury fee (1000 basis points)
        uint256 feeBasisPoints = 1000;
        uint256 disputeWindow = 30; // 30 seconds

        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            nodeRegistry,
            hostEarnings,
            feeBasisPoints,
            disputeWindow
        );

        console.log("JobMarketplace deployed to:", address(marketplace));

        // Configure ProofSystem
        marketplace.setProofSystem(0x2ACcc60893872A499700908889B38C5420CBcFD1);
        console.log("ProofSystem configured");

        // Note: HostEarnings authorization must be done separately by HostEarnings owner
        console.log("IMPORTANT: Authorize this in HostEarnings:", address(marketplace));

        vm.stopBroadcast();
    }
}