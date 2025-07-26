// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {NodeRegistry} from "../../src/NodeRegistry.sol";

contract NodeRegistryTest is Test {
    NodeRegistry public nodeRegistry;
    
    address constant HOST = address(0x1);
    address constant HOST2 = address(0x2);
    uint256 constant STAKE_AMOUNT = 100 ether;
    string constant PEER_ID = "12D3KooWExample";
    string[] models = ["llama3", "mistral"];
    
    function setUp() public {
        nodeRegistry = new NodeRegistry();
        
        // Give test addresses some ETH
        vm.deal(HOST, 1000 ether);
        vm.deal(HOST2, 1000 ether);
    }
    
    function test_RegisterNode() public {
        // Test: Host should be able to register with stake
        vm.startPrank(HOST);
        
        nodeRegistry.registerNode{value: STAKE_AMOUNT}(
            PEER_ID,
            models,
            "us-east-1"
        );
        
        // Verify registration
        NodeRegistry.Node memory node = nodeRegistry.getNode(HOST);
        assertEq(node.operator, HOST);
        assertEq(node.peerId, PEER_ID);
        assertEq(node.stake, STAKE_AMOUNT);
        assertTrue(node.active);
        
        vm.stopPrank();
    }
    
    function test_CannotRegisterWithoutStake() public {
        vm.startPrank(HOST);
        
        vm.expectRevert("Insufficient stake");
        nodeRegistry.registerNode{value: 0}(
            PEER_ID,
            models,
            "us-east-1"
        );
        
        vm.stopPrank();
    }
    
    function test_CannotRegisterTwice() public {
        vm.startPrank(HOST);
        
        // First registration
        nodeRegistry.registerNode{value: STAKE_AMOUNT}(
            PEER_ID,
            models,
            "us-east-1"
        );
        
        // Try to register again
        vm.expectRevert("Already registered");
        nodeRegistry.registerNode{value: STAKE_AMOUNT}(
            PEER_ID,
            models,
            "us-east-1"
        );
        
        vm.stopPrank();
    }
}
