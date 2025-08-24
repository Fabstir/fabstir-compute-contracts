// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/NodeRegistryFAB.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RegisterHostWithFAB is Script {
    // Base Sepolia addresses
    address constant FAB_TOKEN = 0xC78949004B4EB6dEf2D66e49Cd81231472612D62;
    
    // Test accounts
    address constant TEST_HOST_1 = 0x4594F755F593B517Bb3194F4DeC20C48a3f04504;
    address constant TEST_USER_1 = 0x8D642988E3e7b6DB15b6058461d5563835b04bF6;
    
    function run() external {
        // Get NodeRegistryFAB address from environment or previous deployment
        address nodeRegistryFAB = vm.envAddress("NODE_REGISTRY_FAB");
        
        uint256 hostPrivateKey = vm.envUint("HOST_PRIVATE_KEY");
        address host = vm.addr(hostPrivateKey);
        
        console.log("========================================");
        console.log("Host Registration with FAB Tokens");
        console.log("========================================");
        console.log("Host address:", host);
        console.log("NodeRegistryFAB:", nodeRegistryFAB);
        console.log("FAB Token:", FAB_TOKEN);
        
        vm.startBroadcast(hostPrivateKey);
        
        NodeRegistryFAB registry = NodeRegistryFAB(nodeRegistryFAB);
        IERC20 fabToken = IERC20(FAB_TOKEN);
        
        // Check FAB balance
        uint256 fabBalance = fabToken.balanceOf(host);
        uint256 requiredStake = registry.MIN_STAKE();
        
        console.log("\nFAB Balance:", fabBalance / 10**18, "FAB");
        console.log("Required Stake:", requiredStake / 10**18, "FAB");
        
        if (fabBalance < requiredStake) {
            console.log("\n❌ Insufficient FAB tokens!");
            console.log("   Need:", requiredStake / 10**18, "FAB");
            console.log("   Have:", fabBalance / 10**18, "FAB");
            revert("Insufficient FAB tokens for staking");
        }
        
        // Check if already registered
        NodeRegistryFAB.Node memory existingNode = registry.nodes(host);
        if (existingNode.operator != address(0)) {
            console.log("\n⚠️  Host already registered");
            console.log("   Staked amount:", existingNode.stakedAmount / 10**18, "FAB");
            console.log("   Active:", existingNode.active);
            vm.stopBroadcast();
            return;
        }
        
        // Approve FAB spending
        console.log("\nApproving FAB token spending...");
        fabToken.approve(nodeRegistryFAB, requiredStake);
        console.log("[OK] Approved", requiredStake / 10**18, "FAB");
        
        // Register as host
        console.log("\nRegistering as host...");
        string memory metadata = string.concat(
            '{"peerId":"peer-',
            vm.toString(host),
            '","models":["gpt-4","llama-2-70b"],"region":"us-west"}'
        );
        
        registry.registerNode(metadata);
        console.log("[OK] Host registered successfully!");
        
        // Verify registration
        NodeRegistryFAB.Node memory node = registry.nodes(host);
        console.log("\n✅ Registration Verified:");
        console.log("   Operator:", node.operator);
        console.log("   Staked:", node.stakedAmount / 10**18, "FAB");
        console.log("   Active:", node.active);
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("Host Registration Complete!");
        console.log("========================================");
        console.log("\n✅ Host is now ready to:");
        console.log("   1. Claim jobs");
        console.log("   2. Complete jobs");
        console.log("   3. Receive USDC payments");
    }
    
    // Function to check host status
    function checkStatus() external view {
        address nodeRegistryFAB = vm.envAddress("NODE_REGISTRY_FAB");
        address host = vm.envAddress("HOST_ADDRESS");
        
        NodeRegistryFAB registry = NodeRegistryFAB(nodeRegistryFAB);
        NodeRegistryFAB.Node memory node = registry.nodes(host);
        
        console.log("Host Status for:", host);
        console.log("- Registered:", node.operator != address(0));
        console.log("- Active:", node.active);
        console.log("- Staked:", node.stakedAmount / 10**18, "FAB");
        
        // Check if host can be used in JobMarketplace
        console.log("\n✅ Can claim jobs:", node.active && node.stakedAmount >= registry.MIN_STAKE());
    }
}