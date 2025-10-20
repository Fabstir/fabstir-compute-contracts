// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

contract VerifyContracts is Script {
    struct ContractInfo {
        address addr;
        string name;
        bytes constructorArgs;
    }
    
    function run() external {
        // Load deployment addresses
        string memory deploymentFile = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-deployment.json"
        );
        
        if (!vm.exists(deploymentFile)) {
            console.log("Deployment file not found:", deploymentFile);
            console.log("Please run DeploySessionJobs.s.sol first");
            return;
        }
        
        string memory json = vm.readFile(deploymentFile);
        address proofSystem = vm.parseJsonAddress(json, ".proofSystem");
        address marketplace = vm.parseJsonAddress(json, ".marketplace");
        address nodeRegistry = vm.parseJsonAddress(json, ".nodeRegistry");
        address hostEarnings = vm.parseJsonAddress(json, ".hostEarnings");
        
        console.log("========================================");
        console.log("Preparing contracts for BaseScan verification...");
        console.log("Chain ID:", block.chainid);
        console.log("========================================");
        
        // ProofSystem (no constructor args)
        console.log("\n1. ProofSystem");
        console.log("   Address:", proofSystem);
        console.log("   Constructor args: none");
        console.log("   Verify command:");
        console.log("   forge verify-contract", proofSystem, "ProofSystem \\");
        console.log("     --chain-id", block.chainid, "\\");
        console.log("     --etherscan-api-key $BASESCAN_API_KEY");
        
        // JobMarketplaceFABWithS5 (with constructor args)
        console.log("\n2. JobMarketplaceFABWithS5");
        console.log("   Address:", marketplace);
        console.log("   Constructor args:");
        console.log("     - nodeRegistry:", nodeRegistry);
        console.log("     - hostEarnings:", hostEarnings);
        
        // Encode constructor args for verification
        bytes memory marketplaceArgs = abi.encode(nodeRegistry, hostEarnings);
        console.log("   Encoded args:", vm.toString(marketplaceArgs));
        console.log("   Verify command:");
        console.log("   forge verify-contract", marketplace, "JobMarketplaceFABWithS5 \\");
        console.log("     --chain-id", block.chainid, "\\");
        console.log("     --constructor-args", vm.toString(marketplaceArgs), "\\");
        console.log("     --etherscan-api-key $BASESCAN_API_KEY");
        
        console.log("\n========================================");
        console.log("Verification URLs:");
        if (block.chainid == 8453) {
            console.log("ProofSystem: https://basescan.org/address/", proofSystem);
            console.log("JobMarketplace: https://basescan.org/address/", marketplace);
        } else if (block.chainid == 84532) {
            console.log("ProofSystem: https://sepolia.basescan.org/address/", proofSystem);
            console.log("JobMarketplace: https://sepolia.basescan.org/address/", marketplace);
        }
        console.log("========================================");
        
        // Save verification info
        _saveVerificationInfo(proofSystem, marketplace, nodeRegistry, hostEarnings);
    }
    
    function _saveVerificationInfo(
        address proofSystem,
        address marketplace,
        address nodeRegistry,
        address hostEarnings
    ) internal {
        string memory json = "verification";
        
        // ProofSystem info
        vm.serializeAddress(json, "proofSystem_address", proofSystem);
        vm.serializeString(json, "proofSystem_name", "ProofSystem");
        vm.serializeBytes(json, "proofSystem_args", "");
        
        // Marketplace info
        vm.serializeAddress(json, "marketplace_address", marketplace);
        vm.serializeString(json, "marketplace_name", "JobMarketplaceFABWithS5");
        bytes memory marketplaceArgs = abi.encode(nodeRegistry, hostEarnings);
        vm.serializeBytes(json, "marketplace_args", marketplaceArgs);
        
        // Chain info
        vm.serializeUint(json, "chainId", block.chainid);
        string memory output = vm.serializeUint(json, "timestamp", block.timestamp);
        
        string memory filename = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-verification.json"
        );
        
        vm.writeJson(output, filename);
        console.log("\nVerification info saved to:", filename);
    }
}