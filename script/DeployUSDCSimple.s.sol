// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";

contract DeployUSDCSimple is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("Deploying USDC-enabled JobMarketplace...");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy new JobMarketplace
        JobMarketplace marketplace = new JobMarketplace(
            0xF6420Cc8d44Ac92a6eE29A5E8D12D00aE91a73B3  // NodeRegistry
        );
        
        // Set USDC and PaymentEscrow
        marketplace.setUsdcAddress(0x036CbD53842c5426634e7929541eC2318f3dCF7e);
        marketplace.setPaymentEscrow(0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894);
        
        vm.stopBroadcast();
        
        console.log("JobMarketplace deployed at:", address(marketplace));
        console.log("USDC configured:", marketplace.usdcAddress());
        console.log("PaymentEscrow configured:", address(marketplace.paymentEscrow()));
    }
}