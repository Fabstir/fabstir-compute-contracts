// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplace.sol";
import "../src/interfaces/IJobMarketplace.sol";

contract ValidateUSDCJob is Script {
    address constant JOB_MARKETPLACE = 0x6C4283A2aAee2f94BcD2EB04e951EfEa1c35b0B6;
    address constant USDC_ADDRESS = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external view {
        console.log("========================================");
        console.log("Validating postJobWithToken Structure");
        console.log("========================================");
        
        // Verify the function selector
        bytes4 selector = JobMarketplace.postJobWithToken.selector;
        console.log("Function selector:", vm.toString(selector));
        
        // Show the correct struct format
        console.log("\n[CORRECT STRUCT FORMAT]");
        console.log("\nJobDetails struct (6 fields required):");
        console.log("1. modelId: string");
        console.log("2. prompt: string");
        console.log("3. maxTokens: uint256");
        console.log("4. temperature: uint256");
        console.log("5. seed: uint32         <- MISSING IN FRONTEND");
        console.log("6. resultFormat: string <- MISSING IN FRONTEND");
        
        console.log("\nJobRequirements struct (4 fields required):");
        console.log("1. minGPUMemory: uint256");
        console.log("2. minReputationScore: uint256 <- MISSING IN FRONTEND");
        console.log("3. maxTimeToComplete: uint256");
        console.log("4. requiresProof: bool         <- MISSING IN FRONTEND");
        
        console.log("\n========================================");
        console.log("FRONTEND FIX REQUIRED");
        console.log("========================================");
        
        console.log("\nTypeScript/JavaScript Example:");
        console.log("```javascript");
        console.log("const jobDetails = {");
        console.log("  modelId: 'gpt-4',");
        console.log("  prompt: 'Your prompt here',");
        console.log("  maxTokens: 100,");
        console.log("  temperature: 1000,       // 1.0 = 1000 basis points");
        console.log("  seed: 42,                // ADD THIS FIELD");
        console.log("  resultFormat: 'json'     // ADD THIS FIELD");
        console.log("};");
        console.log("");
        console.log("const jobRequirements = {");
        console.log("  minGPUMemory: 8,");
        console.log("  minReputationScore: 0,   // ADD THIS FIELD");
        console.log("  maxTimeToComplete: 3600,");
        console.log("  requiresProof: false     // ADD THIS FIELD");
        console.log("};");
        console.log("");
        console.log("// Payment amount in USDC smallest units (6 decimals)");
        console.log("const paymentAmount = 10000; // 0.01 USDC");
        console.log("");
        console.log("await marketplace.postJobWithToken(");
        console.log("  jobDetails,");
        console.log("  jobRequirements,");
        console.log("  USDC_ADDRESS,");
        console.log("  paymentAmount");
        console.log(");");
        console.log("```");
        
        console.log("\n========================================");
        console.log("ABI ENCODING");
        console.log("========================================");
        console.log("The function expects these types in order:");
        console.log("1. (string,string,uint256,uint256,uint32,string) - JobDetails tuple");
        console.log("2. (uint256,uint256,uint256,bool) - JobRequirements tuple");
        console.log("3. address - payment token (USDC)");
        console.log("4. uint256 - payment amount");
    }
}