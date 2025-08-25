// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/HostEarnings.sol";
import "../src/JobMarketplaceFABWithEarnings.sol";
import "../src/PaymentEscrowWithEarnings.sol";

contract DeployEarningsSystemComplete is Script {
    // Correct addresses
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant TREASURY_MANAGER = 0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    // Existing deployed contracts (keeping these)
    address constant HOST_EARNINGS = 0xcbD91249cC8A7634a88d437Eaa083496C459Ef4E;
    address constant PAYMENT_ESCROW = 0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C;
    
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        
        console.log("Deploying JobMarketplace with CORRECT NodeRegistry");
        console.log("Deployer:", deployer);
        console.log("NodeRegistry:", NODE_REGISTRY_FAB);
        
        vm.startBroadcast(deployerKey);
        
        // Deploy ONLY the new JobMarketplaceFABWithEarnings with correct NodeRegistry
        JobMarketplaceFABWithEarnings marketplace = new JobMarketplaceFABWithEarnings(
            NODE_REGISTRY_FAB,
            payable(HOST_EARNINGS)
        );
        console.log("New JobMarketplace deployed:", address(marketplace));
        
        // Configure the new marketplace
        marketplace.setPaymentEscrow(PAYMENT_ESCROW);
        marketplace.setUsdcAddress(USDC);
        console.log("Marketplace configured");
        
        // Update HostEarnings to authorize the new marketplace
        HostEarnings hostEarnings = HostEarnings(payable(HOST_EARNINGS));
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        console.log("HostEarnings updated with new marketplace");
        
        // Update PaymentEscrow to use new marketplace
        PaymentEscrowWithEarnings escrow = PaymentEscrowWithEarnings(payable(PAYMENT_ESCROW));
        escrow.setJobMarketplace(address(marketplace));
        console.log("PaymentEscrow updated with new marketplace");
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETE - CORRECTED SYSTEM");
        console.log("========================================");
        console.log("HostEarnings (unchanged):", HOST_EARNINGS);
        console.log("PaymentEscrow (unchanged):", PAYMENT_ESCROW);
        console.log("JobMarketplace (NEW):", address(marketplace));
        console.log("NodeRegistry (correct):", NODE_REGISTRY_FAB);
        console.log("========================================");
    }
}