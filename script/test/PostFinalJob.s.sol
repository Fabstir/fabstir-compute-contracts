// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceFAB.sol";
import "../src/interfaces/IJobMarketplace.sol";

contract PostFinalJob is Script {
    address constant JOB_MARKETPLACE_FAB = 0xC30cAA786A6b39eD55e39F6aB275fCB9FD5FAf65;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 userPrivateKey = vm.envUint("TEST_USER_1_PRIVATE_KEY");
        
        vm.startBroadcast(userPrivateKey);
        
        JobMarketplaceFAB marketplace = JobMarketplaceFAB(JOB_MARKETPLACE_FAB);
        
        IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
            modelId: "gpt-4",
            prompt: "final test job",
            maxTokens: 100,
            temperature: 70,
            seed: 42,
            resultFormat: "json"
        });
        
        IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
            minGPUMemory: 16,
            minReputationScore: 0,
            maxTimeToComplete: 3600,
            requiresProof: false
        });
        
        bytes32 jobId = marketplace.postJobWithToken(details, requirements, USDC, 300000);
        console.log("Job posted with ID:", uint256(jobId));
        console.log("Internal job ID: 1");
        
        vm.stopBroadcast();
    }
}