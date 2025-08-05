// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/utils/VerificationHelper.sol";
import "../src/NodeRegistry.sol";
import "../src/JobMarketplace.sol";
import "../src/PaymentEscrow.sol";
import "../src/ReputationSystem.sol";
import "../src/ProofSystem.sol";
import "../src/Governance.sol";
import "../src/GovernanceToken.sol";
import "../src/BaseAccountIntegration.sol";

contract VerifyScript is Script, VerificationHelper {

    // Network configurations
    mapping(uint256 => NetworkConfig) public networks;
    
    // Contract deployment addresses (would be loaded from deployment artifacts)
    struct DeployedContracts {
        address nodeRegistry;
        address jobMarketplace;
        address paymentEscrow;
        address reputationSystem;
        address proofSystem;
        address governance;
        address governanceToken;
        address baseAccountIntegration;
    }

    function setUp() public {
        // Base Mainnet
        networks[8453] = NetworkConfig({
            name: "base",
            chainId: 8453,
            apiUrl: "https://api.basescan.org/api",
            apiKey: vm.envOr("BASESCAN_API_KEY", string("")),
            browserUrl: "https://basescan.org"
        });

        // Base Sepolia
        networks[84532] = NetworkConfig({
            name: "base-sepolia",
            chainId: 84532,
            apiUrl: "https://api-sepolia.basescan.org/api",
            apiKey: vm.envOr("BASESCAN_API_KEY", string("")),
            browserUrl: "https://sepolia.basescan.org"
        });
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get network config
        uint256 chainId = block.chainid;
        NetworkConfig memory network = networks[chainId];
        require(bytes(network.name).length > 0, "Unsupported network");

        // Load deployed contracts (in production, this would read from deployment artifacts)
        DeployedContracts memory deployed = loadDeployedContracts();

        // Verify all contracts
        verifyAllContracts(deployed, network);

        vm.stopBroadcast();
    }

    function verifyContract(
        address contractAddress,
        string memory contractName,
        bytes memory constructorArgs,
        NetworkConfig memory network
    ) public returns (VerificationResult memory) {
        console2.log("Verifying", contractName, "at", contractAddress);

        VerificationParams memory params = VerificationParams({
            contractAddress: contractAddress,
            contractName: contractName,
            sourceCode: getSourceCode(contractName),
            compilerVersion: "0.8.19",
            optimizationEnabled: true,
            optimizationRuns: 200,
            constructorArguments: constructorArgs
        });

        return submitVerification(params, network);
    }

    function verifyAllContracts(
        DeployedContracts memory deployed,
        NetworkConfig memory network
    ) public {
        // Prepare contract addresses and names for batch verification
        address[] memory contracts = new address[](8);
        string[] memory names = new string[](8);

        contracts[0] = deployed.nodeRegistry;
        names[0] = "NodeRegistry";

        contracts[1] = deployed.jobMarketplace;
        names[1] = "JobMarketplace";

        contracts[2] = deployed.paymentEscrow;
        names[2] = "PaymentEscrow";

        contracts[3] = deployed.reputationSystem;
        names[3] = "ReputationSystem";

        contracts[4] = deployed.proofSystem;
        names[4] = "ProofSystem";

        contracts[5] = deployed.governance;
        names[5] = "Governance";

        contracts[6] = deployed.governanceToken;
        names[6] = "GovernanceToken";

        contracts[7] = deployed.baseAccountIntegration;
        names[7] = "BaseAccountIntegration";

        // Batch verify
        (uint256 successCount, uint256 failedCount) = batchVerifyContracts(
            contracts,
            names,
            network
        );

        console2.log("Verification complete:");
        console2.log("- Success:", successCount);
        console2.log("- Failed:", failedCount);
    }

    function verifyWithRetry(
        address contractAddress,
        string memory contractName,
        bytes memory constructorArgs,
        NetworkConfig memory network,
        uint256 maxRetries
    ) public returns (VerificationResult memory) {
        VerificationParams memory params = VerificationParams({
            contractAddress: contractAddress,
            contractName: contractName,
            sourceCode: getSourceCode(contractName),
            compilerVersion: "0.8.19",
            optimizationEnabled: true,
            optimizationRuns: 200,
            constructorArguments: constructorArgs
        });

        return submitVerificationWithRetry(params, network, maxRetries);
    }

    function checkStatus(
        string memory guid,
        NetworkConfig memory network
    ) public view returns (string memory) {
        return checkVerificationStatus(guid, network);
    }

    function pollUntilComplete(
        string memory guid,
        NetworkConfig memory network,
        uint256 maxAttempts,
        uint256 delaySeconds
    ) public returns (string memory) {
        return pollVerificationStatus(guid, network, maxAttempts, delaySeconds);
    }

    function loadDeployedContracts() internal view returns (DeployedContracts memory) {
        // In production, this would read from deployment artifacts
        // For testing, we return mock addresses
        return DeployedContracts({
            nodeRegistry: address(0x1),
            jobMarketplace: address(0x2),
            paymentEscrow: address(0x3),
            reputationSystem: address(0x4),
            proofSystem: address(0x5),
            governance: address(0x6),
            governanceToken: address(0x7),
            baseAccountIntegration: address(0x8)
        });
    }

    function getSourceCode(string memory contractName) internal pure returns (string memory) {
        // In production, this would read the actual source code
        // For testing, we return a placeholder
        return string(abi.encodePacked("// Source code for ", contractName));
    }

    function getConstructorArgs(string memory contractName) internal pure returns (bytes memory) {
        // In production, this would return the actual constructor arguments
        // For testing, we return appropriate arguments based on contract type
        if (keccak256(bytes(contractName)) == keccak256(bytes("NodeRegistry"))) {
            return abi.encode(10 ether);
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("Governance"))) {
            return abi.encode(
                address(0x7), // token
                address(0x0), // timelock
                1 days,       // voting delay
                1 weeks,      // voting period
                100000e18     // proposal threshold
            );
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("GovernanceToken"))) {
            return abi.encode("Fabstir Governance Token", "FGT");
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("BaseAccountIntegration"))) {
            return abi.encode(address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789)); // EntryPoint
        }
        return "";
    }
}