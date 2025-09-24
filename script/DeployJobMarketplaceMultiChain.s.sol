// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/JobMarketplaceWithModels.sol";
import "../src/HostEarnings.sol";

contract DeployJobMarketplaceMultiChain is Script {
    // Existing contract addresses on Base Sepolia
    address constant NODE_REGISTRY = 0x2AA37Bb6E9f0a5d0F3b2836f3a5F656755906218;
    address payable constant HOST_EARNINGS = payable(0x908962e8c6CE72610021586f85ebDE09aAc97776);
    address constant PROOF_SYSTEM = 0x2ACcc60893872A499700908889B38C5420CBcFD1;
    address constant TREASURY = 0xbeaBB2a5AEd358aA0bd442dFFd793411519Bdc11;

    // Base Sepolia configuration
    address constant WETH_ON_BASE = 0x4200000000000000000000000000000000000006;
    address constant USDC_ON_BASE = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy new JobMarketplaceWithModels
        console.log("Deploying JobMarketplaceWithModels...");
        uint256 feeBasisPoints = 1000; // 10% treasury fee

        JobMarketplaceWithModels marketplace = new JobMarketplaceWithModels(
            NODE_REGISTRY,
            HOST_EARNINGS,
            feeBasisPoints
        );

        console.log("JobMarketplaceWithModels deployed to:", address(marketplace));

        // Step 2: Configure ProofSystem
        console.log("Configuring ProofSystem...");
        marketplace.setProofSystem(PROOF_SYSTEM);
        console.log("ProofSystem configured");

        // Step 3: Authorize in HostEarnings
        console.log("Authorizing marketplace in HostEarnings...");
        HostEarnings(HOST_EARNINGS).setAuthorizedCaller(address(marketplace), true);
        console.log("Marketplace authorized in HostEarnings");

        // Step 4: Initialize ChainConfig for Base
        console.log("Initializing ChainConfig for Base Sepolia...");
        JobMarketplaceWithModels.ChainConfig memory baseConfig =
            JobMarketplaceWithModels.ChainConfig({
                nativeWrapper: WETH_ON_BASE,
                stablecoin: USDC_ON_BASE,
                minDeposit: 0.0002 ether, // Keep existing MIN_DEPOSIT
                nativeTokenSymbol: "ETH"
            });

        marketplace.initializeChainConfig(baseConfig);
        console.log("ChainConfig initialized for Base with ETH");

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("JobMarketplaceWithModels:", address(marketplace));
        console.log("ProofSystem:", PROOF_SYSTEM);
        console.log("HostEarnings:", HOST_EARNINGS);
        console.log("NodeRegistry:", NODE_REGISTRY);
        console.log("Treasury:", TREASURY);
        console.log("Chain: Base Sepolia (ETH)");
        console.log("\n=== CONFIGURATION ===");
        console.log("Treasury Fee: 10% (1000 basis points)");
        console.log("Native Token: ETH");
        console.log("Native Wrapper: WETH at", WETH_ON_BASE);
        console.log("Stablecoin: USDC at", USDC_ON_BASE);
        console.log("Min Deposit: 0.0002 ETH");
        console.log("\n=== POST-DEPLOYMENT VERIFICATION ===");
        console.log("Run these commands to verify:");
        console.log("1. Check ProofSystem:");
        console.log("   cast call <MARKETPLACE> proofSystem() --rpc-url $BASE_SEPOLIA_RPC_URL");
        console.log("2. Check HostEarnings authorization:");
        console.log("   cast call <HOST_EARNINGS> authorizedCallers(address) <MARKETPLACE> --rpc-url $BASE_SEPOLIA_RPC_URL");
        console.log("3. Check ChainConfig:");
        console.log("   cast call <MARKETPLACE> chainConfig() --rpc-url $BASE_SEPOLIA_RPC_URL");
    }
}