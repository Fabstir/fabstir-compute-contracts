// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ProofSystem.sol";
import "../src/JobMarketplaceFABWithS5.sol";

contract DeployNew is Script {
    function run() public {
        // Hardcoded addresses for Base Sepolia
        address nodeRegistry = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
        address payable hostEarnings = payable(address(0)); // Optional, using zero
        address payable treasury = payable(0x4e770e723B95A0d8923Db006E49A8a3cb0BAA078);
        address usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        address paymentEscrow = 0x7abC91AF9E5aaFdc954Ec7a02238d0796Bbf9a3C;
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========================================");
        console.log("Deploying with configuration:");
        console.log("NodeRegistry:", nodeRegistry);
        console.log("HostEarnings:", hostEarnings);
        console.log("Treasury:", treasury);
        console.log("USDC:", usdc);
        console.log("PaymentEscrow:", paymentEscrow);
        console.log("========================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy ProofSystem
        ProofSystem proofSystem = new ProofSystem();
        console.log("ProofSystem deployed at:", address(proofSystem));
        
        // 2. Deploy JobMarketplace
        JobMarketplaceFABWithS5 marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        console.log("JobMarketplace deployed at:", address(marketplace));
        
        // 3. Configure ProofSystem
        marketplace.setProofSystem(address(proofSystem));
        console.log("ProofSystem configured");
        
        // 4. Configure Treasury
        marketplace.setTreasuryAddress(treasury);
        console.log("Treasury configured");
        
        // 5. Configure USDC
        marketplace.setUsdcAddress(usdc);
        console.log("USDC configured");
        
        // 6. Configure PaymentEscrow (for legacy jobs)
        marketplace.setPaymentEscrow(paymentEscrow);
        console.log("PaymentEscrow configured");
        
        // 7. Enable USDC as accepted token with minimum
        marketplace.setAcceptedToken(usdc, true, 800000); // 0.80 USDC minimum
        console.log("USDC enabled as accepted token");
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("========================================");
        console.log("ProofSystem:", address(proofSystem));
        console.log("JobMarketplace:", address(marketplace));
        console.log("");
        console.log("Update your client configuration:");
        console.log("jobMarketplace:", address(marketplace));
        console.log("proofSystem:", address(proofSystem));
        console.log("========================================");
    }
}