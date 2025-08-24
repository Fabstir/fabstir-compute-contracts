// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

contract JobMarketplaceMin {
    address public nodeRegistry;
    address public paymentEscrow;
    address public usdcAddress;
    
    constructor(address _nodeRegistry) {
        nodeRegistry = _nodeRegistry;
    }
    
    function setUsdcAddress(address _usdc) external {
        usdcAddress = _usdc;
    }
    
    function setPaymentEscrow(address _escrow) external {
        paymentEscrow = _escrow;
    }
}

contract NodeRegistryAdapterMin {
    address public fabRegistry;
    
    struct Node {
        address operator;
        string peerId;
        uint256 stake;
        bool active;
        string[] models;
        string region;
    }
    
    struct FabNode {
        address operator;
        uint256 stakedAmount;
        bool active;
        string metadata;
    }
    
    constructor(address _fabRegistry) {
        fabRegistry = _fabRegistry;
    }
    
    function getNode(address _operator) external view returns (Node memory) {
        // Call fabRegistry.nodes(_operator)
        (bool success, bytes memory data) = fabRegistry.staticcall(
            abi.encodeWithSignature("nodes(address)", _operator)
        );
        require(success, "Failed to get node");
        
        FabNode memory fabNode = abi.decode(data, (FabNode));
        
        string[] memory models = new string[](1);
        models[0] = "gpt-4";
        
        return Node({
            operator: fabNode.operator,
            peerId: fabNode.metadata,
            stake: fabNode.stakedAmount,
            active: fabNode.active,
            models: models,
            region: "us-west"
        });
    }
    
    function isNodeActive(address _operator) external view returns (bool) {
        (bool success, bytes memory data) = fabRegistry.staticcall(
            abi.encodeWithSignature("nodes(address)", _operator)
        );
        if (!success) return false;
        
        FabNode memory fabNode = abi.decode(data, (FabNode));
        return fabNode.active && fabNode.operator != address(0);
    }
    
    function getNodeController(address) external pure returns (address) {
        return address(0);
    }
}

contract DeployAdapterSimple is Script {
    address constant NODE_REGISTRY_FAB = 0x87516C13Ea2f99de598665e14cab64E191A0f8c4;
    address constant PAYMENT_ESCROW = 0x3b96fBD7b463e94463Ae4d0f2629e08cf1F25894;
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy adapter
        NodeRegistryAdapterMin adapter = new NodeRegistryAdapterMin(NODE_REGISTRY_FAB);
        console.log("Adapter deployed:", address(adapter));
        
        vm.stopBroadcast();
        
        console.log("\n========================================");
        console.log("Deploy JobMarketplace manually with:");
        console.log("NodeRegistry:", address(adapter));
        console.log("========================================");
    }
}