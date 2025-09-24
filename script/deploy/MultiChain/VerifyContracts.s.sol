// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../../../src/JobMarketplaceWithModels.sol";
import "../../../src/HostEarnings.sol";

contract VerifyContracts is Script {
    function run() external view {
        // Get the deployed contract address from environment or command line
        address marketplace = vm.envAddress("MARKETPLACE_ADDRESS");

        console.log("\n=== VERIFYING DEPLOYMENT ===");
        console.log("Marketplace Address:", marketplace);

        // 1. Verify ProofSystem configuration
        address proofSystem = address(JobMarketplaceWithModels(payable(marketplace)).proofSystem());
        require(proofSystem != address(0), "ProofSystem not configured");
        console.log("[OK] ProofSystem configured:", proofSystem);

        // 2. Verify HostEarnings configuration
        address hostEarnings = address(JobMarketplaceWithModels(payable(marketplace)).hostEarnings());
        require(hostEarnings != address(0), "HostEarnings not configured");
        console.log("[OK] HostEarnings configured:", hostEarnings);

        // 3. Verify HostEarnings authorization
        bool isAuthorized = HostEarnings(payable(hostEarnings)).authorizedCallers(marketplace);
        require(isAuthorized, "Marketplace not authorized in HostEarnings");
        console.log("[OK] Marketplace authorized in HostEarnings");

        // 4. Verify ChainConfig
        (
            address nativeWrapper,
            address stablecoin,
            uint256 minDeposit,
            string memory nativeTokenSymbol
        ) = JobMarketplaceWithModels(payable(marketplace)).chainConfig();

        require(nativeWrapper != address(0), "Native wrapper not configured");
        require(stablecoin != address(0), "Stablecoin not configured");
        require(minDeposit > 0, "Min deposit not set");
        require(bytes(nativeTokenSymbol).length > 0, "Native token symbol not set");

        console.log("[OK] ChainConfig verified:");
        console.log("  - Native Wrapper:", nativeWrapper);
        console.log("  - Stablecoin:", stablecoin);
        console.log("  - Min Deposit:", minDeposit);
        console.log("  - Native Token:", nativeTokenSymbol);

        // 5. Verify treasury configuration
        address treasury = JobMarketplaceWithModels(payable(marketplace)).treasuryAddress();
        require(treasury != address(0), "Treasury not configured");
        console.log("[OK] Treasury configured:", treasury);

        // 6. Verify fee configuration
        uint256 feeBasisPoints = JobMarketplaceWithModels(payable(marketplace)).FEE_BASIS_POINTS();
        console.log("[OK] Fee basis points:", feeBasisPoints);
        console.log("     Fee percentage:", feeBasisPoints / 100);

        console.log("\n[OK] ALL VERIFICATIONS PASSED [OK]");
        console.log("\nRun these manual checks:");
        console.log("1. Test deposit native:");
        console.log("   cast send", marketplace, '"depositNative()" --value 0.001ether');
        console.log("2. Check balance:");
        console.log("   cast call", marketplace, '"userDepositsNative(address)(uint256)" <YOUR_ADDRESS>');
    }

    function verifyChain(string memory chainName) external view {
        address marketplace = vm.envAddress("MARKETPLACE_ADDRESS");

        console.log("\n=== CHAIN-SPECIFIC VERIFICATION:", chainName, "===");

        (,,, string memory nativeTokenSymbol) =
            JobMarketplaceWithModels(payable(marketplace)).chainConfig();

        console.log("Expected token:", chainName);
        console.log("Configured token:", nativeTokenSymbol);

        if (keccak256(bytes(chainName)) == keccak256(bytes("ETH"))) {
            require(
                keccak256(bytes(nativeTokenSymbol)) == keccak256(bytes("ETH")),
                "Chain mismatch: Expected ETH"
            );
            console.log("[OK] Base/Ethereum chain configuration verified");
        } else if (keccak256(bytes(chainName)) == keccak256(bytes("BNB"))) {
            require(
                keccak256(bytes(nativeTokenSymbol)) == keccak256(bytes("BNB")),
                "Chain mismatch: Expected BNB"
            );
            console.log("[OK] opBNB chain configuration verified");
        }
    }
}