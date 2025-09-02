// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/ProofSystem.sol";
import "../src/JobMarketplaceFABWithS5.sol";

contract DeploySessionJobs is Script {
    // Deployment addresses
    ProofSystem public proofSystem;
    JobMarketplaceFABWithS5 public marketplace;
    
    // Configuration
    address public nodeRegistry;
    address payable public hostEarnings;
    address payable public treasury;
    address public usdc;
    
    function setUp() public {
        // Load config based on chain
        if (block.chainid == 8453) {
            // Base Mainnet
            nodeRegistry = vm.envOr("MAINNET_NODE_REGISTRY", address(0));
            hostEarnings = payable(vm.envOr("MAINNET_HOST_EARNINGS", address(0)));
            treasury = payable(vm.envOr("MAINNET_TREASURY", msg.sender));
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
        } else if (block.chainid == 84532) {
            // Base Sepolia
            nodeRegistry = vm.envOr("TESTNET_NODE_REGISTRY", address(0));
            hostEarnings = payable(vm.envOr("TESTNET_HOST_EARNINGS", address(0)));
            treasury = payable(vm.envOr("TESTNET_TREASURY", msg.sender));
            usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC on Base Sepolia
        } else {
            // Local
            nodeRegistry = address(0x3);
            hostEarnings = payable(address(0x4));
            treasury = payable(msg.sender);
            usdc = address(0); // Will deploy mock
        }
    }
    
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy ProofSystem
        proofSystem = new ProofSystem();
        console.log("ProofSystem deployed at:", address(proofSystem));
        
        // 2. Deploy JobMarketplace with required constructor args
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        console.log("JobMarketplace deployed at:", address(marketplace));
        
        // 3. Configure contracts
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        // 4. Enable USDC if available
        if (usdc != address(0)) {
            marketplace.setAcceptedToken(usdc, true, 800000); // 0.80 USDC minimum
            console.log("USDC enabled at:", usdc);
        }
        
        // 5. Register example model circuits
        proofSystem.registerModelCircuit(
            address(0x1), // Example model address
            keccak256("llama-70b-circuit")
        );
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("========================================");
        console.log("Deployment Complete!");
        console.log("ProofSystem:", address(proofSystem));
        console.log("JobMarketplace:", address(marketplace));
        console.log("NodeRegistry:", nodeRegistry);
        console.log("HostEarnings:", hostEarnings);
        console.log("Treasury:", treasury);
        console.log("USDC:", usdc);
        console.log("Chain ID:", block.chainid);
        console.log("========================================");
        
        // Save addresses for verification (disabled in simulation)
        // _saveDeploymentAddresses();
    }
    
    function _saveDeploymentAddresses() internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "proofSystem", address(proofSystem));
        vm.serializeAddress(json, "marketplace", address(marketplace));
        vm.serializeAddress(json, "nodeRegistry", nodeRegistry);
        vm.serializeAddress(json, "hostEarnings", hostEarnings);
        vm.serializeAddress(json, "treasury", treasury);
        string memory output = vm.serializeAddress(json, "usdc", usdc);
        
        string memory filename = string.concat(
            "./deployments/",
            vm.toString(block.chainid),
            "-deployment.json"
        );
        
        // Write deployment info
        vm.writeJson(output, filename);
    }
}