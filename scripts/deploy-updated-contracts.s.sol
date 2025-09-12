// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/NodeRegistryFAB.sol";
import "../src/JobMarketplaceFABWithS5Deploy.sol";
import "../src/HostEarnings.sol";

contract DeployUpdatedContracts is Script {
    // Existing contracts we'll reuse
    address constant FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    address constant HOST_EARNINGS = 0x908962e8c6CE72610021586f85ebDE09aAc97776;
    address constant PROOF_SYSTEM = 0x2ACcc60893872A499700908889B38C5420CBcFD1;
    address constant TREASURY = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from:", deployer);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy new NodeRegistryFAB with API URL support
        console.log("\n1. Deploying NodeRegistryFAB with API URL support...");
        NodeRegistryFAB nodeRegistry = new NodeRegistryFAB(FAB_TOKEN);
        console.log("NodeRegistryFAB deployed at:", address(nodeRegistry));
        
        // 2. Deploy new JobMarketplaceFABWithS5Deploy
        console.log("\n2. Deploying JobMarketplaceFABWithS5Deploy...");
        JobMarketplaceFABWithS5 marketplace = new JobMarketplaceFABWithS5(
            address(nodeRegistry),
            payable(HOST_EARNINGS)
        );
        console.log("JobMarketplaceFABWithS5Deploy deployed at:", address(marketplace));
        
        // 3. Configure the marketplace
        console.log("\n3. Configuring marketplace...");
        
        // Set ProofSystem
        marketplace.setProofSystem(PROOF_SYSTEM);
        console.log("ProofSystem set to:", PROOF_SYSTEM);
        
        // Set treasury
        marketplace.setTreasuryAddress(TREASURY);
        console.log("Treasury set to:", TREASURY);
        
        // Configure USDC (combined setter with minimum deposit)
        marketplace.setAcceptedToken(USDC, true, 800000); // 0.8 USDC minimum
        console.log("USDC configured with 0.8 USDC minimum");
        
        // 4. Authorize marketplace in HostEarnings (need to do this separately as owner)
        console.log("\n4. Authorization needed:");
        console.log("Run this command to authorize the new marketplace in HostEarnings:");
        console.log("cast send %s \"setAuthorizedCaller(address,bool)\" %s true --private-key $PRIVATE_KEY --rpc-url $BASE_SEPOLIA_RPC_URL", HOST_EARNINGS, address(marketplace));
        
        vm.stopBroadcast();
        
        // Print summary
        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("========================================");
        console.log("\nNew Contract Addresses:");
        console.log("NodeRegistryFAB (with API URLs):", address(nodeRegistry));
        console.log("JobMarketplaceFABWithS5Deploy:", address(marketplace));
        console.log("\nExisting Contracts Used:");
        console.log("HostEarnings:", HOST_EARNINGS);
        console.log("ProofSystem:", PROOF_SYSTEM);
        console.log("FAB Token:", FAB_TOKEN);
        console.log("USDC Token:", USDC);
        console.log("Treasury:", TREASURY);
        console.log("\n========================================");
    }
}