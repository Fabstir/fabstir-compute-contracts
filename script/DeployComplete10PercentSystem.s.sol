// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

contract DeployComplete10PercentSystem is Script {
    // Base Sepolia addresses
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("========================================");
        console.log("COMPLETE 10% FEE SYSTEM DEPLOYMENT");
        console.log("========================================");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy TreasuryManager
        console.log("\n1. Deploying TreasuryManager...");
        address treasury = deployCode(
            "TreasuryManager.sol:TreasuryManager",
            abi.encode(deployer, deployer, deployer, deployer, deployer, deployer)
        );
        console.log("   TreasuryManager:", treasury);
        
        // Set token addresses on TreasuryManager
        (bool success1,) = treasury.call(
            abi.encodeWithSignature("setTokenAddresses(address,address)", FAB_TOKEN, USDC_ADDRESS)
        );
        require(success1, "Failed to set token addresses");
        console.log("   Tokens configured");
        
        // Step 2: Deploy PaymentEscrow with 10% fee
        console.log("\n2. Deploying PaymentEscrow (10% fee)...");
        address escrow = deployCode(
            "PaymentEscrow.sol:PaymentEscrow",
            abi.encode(treasury, uint256(1000)) // 1000 basis points = 10%
        );
        console.log("   PaymentEscrow:", escrow);
        
        // Step 3: Deploy JobMarketplaceFAB
        console.log("\n3. Deploying JobMarketplaceFAB...");
        address marketplace = deployCode(
            "JobMarketplaceFAB.sol:JobMarketplaceFAB",
            abi.encode(NODE_REGISTRY_FAB)
        );
        console.log("   JobMarketplaceFAB:", marketplace);
        
        // Step 4: Configure contracts
        console.log("\n4. Configuring contracts...");
        
        // Set USDC on marketplace
        (bool success2,) = marketplace.call(
            abi.encodeWithSignature("setUsdcAddress(address)", USDC_ADDRESS)
        );
        require(success2, "Failed to set USDC");
        
        // Set PaymentEscrow on marketplace
        (bool success3,) = marketplace.call(
            abi.encodeWithSignature("setPaymentEscrow(address)", escrow)
        );
        require(success3, "Failed to set PaymentEscrow");
        
        // Set JobMarketplace on PaymentEscrow
        (bool success4,) = escrow.call(
            abi.encodeWithSignature("setJobMarketplace(address)", marketplace)
        );
        require(success4, "Failed to set JobMarketplace");
        
        console.log("   All configurations complete!");
        
        vm.stopBroadcast();
        
        // Verify configuration
        console.log("\n========================================");
        console.log("DEPLOYMENT VERIFICATION");
        console.log("========================================");
        
        // Check fee configuration
        (bool success5, bytes memory data) = escrow.staticcall(
            abi.encodeWithSignature("feeBasisPoints()")
        );
        require(success5, "Failed to get fee");
        uint256 fee = abi.decode(data, (uint256));
        console.log("Fee Rate: 1000 basis points = 10%");
        
        (bool success6, bytes memory data2) = escrow.staticcall(
            abi.encodeWithSignature("arbiter()")
        );
        require(success6, "Failed to get arbiter");
        address arbiter = abi.decode(data2, (address));
        console.log("Fee Recipient:", arbiter);
        require(arbiter == treasury, "Arbiter not set to treasury!");
        
        console.log("\n========================================");
        console.log("FINAL CONTRACT ADDRESSES");
        console.log("========================================");
        console.log("TreasuryManager:", treasury);
        console.log("PaymentEscrow:", escrow);
        console.log("JobMarketplaceFAB:", marketplace);
        console.log("\nFee Structure: 10% platform fee");
        console.log("Fee goes to: TreasuryManager for distribution");
    }
}