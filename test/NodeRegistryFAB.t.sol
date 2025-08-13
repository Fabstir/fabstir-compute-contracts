// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/NodeRegistryFAB.sol";
import "../src/GovernanceToken.sol";

contract NodeRegistryFABTest is Test {
    NodeRegistryFAB public registry;
    GovernanceToken public fabToken;
    
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);
    
    uint256 constant MIN_STAKE = 1000 * 10**18;
    
    function setUp() public {
        // Deploy a mock FAB token for testing
        fabToken = new GovernanceToken("Fabstir Token", "FAB", 10_000_000 * 10**18);
        registry = new NodeRegistryFAB(address(fabToken));
        
        // Give test users some FAB tokens
        fabToken.transfer(user1, 5000 * 10**18);
        fabToken.transfer(user2, 5000 * 10**18);
        fabToken.transfer(user3, 500 * 10**18); // Less than minimum
    }
    
    function testRegisterWithFAB() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1 Metadata");
        vm.stopPrank();
        
        assertEq(registry.getNodeStake(user1), MIN_STAKE);
        assertTrue(registry.isNodeActive(user1));
    }
    
    function testCannotRegisterWithoutApproval() public {
        vm.startPrank(user1);
        vm.expectRevert();
        registry.registerNode("Node 1 Metadata");
        vm.stopPrank();
    }
    
    function testMinimumStakeEnforced() public {
        uint256 insufficientStake = 999 * 10**18;
        vm.startPrank(user1);
        fabToken.approve(address(registry), insufficientStake);
        vm.expectRevert("ERC20: insufficient allowance");
        registry.registerNode("Node 1 Metadata");
        vm.stopPrank();
    }
    
    function testUnregisterReturnsStake() public {
        // Register first
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1 Metadata");
        
        uint256 balanceBefore = fabToken.balanceOf(user1);
        registry.unregisterNode();
        uint256 balanceAfter = fabToken.balanceOf(user1);
        vm.stopPrank();
        
        assertEq(balanceAfter - balanceBefore, MIN_STAKE);
        assertFalse(registry.isNodeActive(user1));
    }
    
    function testGetNodeStake() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1 Metadata");
        vm.stopPrank();
        
        assertEq(registry.getNodeStake(user1), MIN_STAKE);
    }
    
    function testCannotRegisterTwice() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE * 2);
        registry.registerNode("Node 1 Metadata");
        
        vm.expectRevert("Already registered");
        registry.registerNode("Node 1 Again");
        vm.stopPrank();
    }
    
    function testCannotUnregisterIfNotRegistered() public {
        vm.startPrank(user1);
        vm.expectRevert("Not registered");
        registry.unregisterNode();
        vm.stopPrank();
    }
    
    function testStakeAdditionalTokens() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE * 2);
        registry.registerNode("Node 1 Metadata");
        
        uint256 additionalStake = 500 * 10**18;
        registry.stake(additionalStake);
        vm.stopPrank();
        
        assertEq(registry.getNodeStake(user1), MIN_STAKE + additionalStake);
    }
    
    function testCannotStakeIfNotRegistered() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        vm.expectRevert("Not registered");
        registry.stake(MIN_STAKE);
        vm.stopPrank();
    }
    
    function testMultipleNodesCanRegister() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1");
        vm.stopPrank();
        
        vm.startPrank(user2);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 2");
        vm.stopPrank();
        
        assertTrue(registry.isNodeActive(user1));
        assertTrue(registry.isNodeActive(user2));
    }
    
    function testGetNodeMetadata() public {
        string memory metadata = "Test Node Metadata";
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode(metadata);
        vm.stopPrank();
        
        assertEq(registry.getNodeMetadata(user1), metadata);
    }
    
    function testUpdateNodeMetadata() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Initial Metadata");
        
        string memory newMetadata = "Updated Metadata";
        registry.updateMetadata(newMetadata);
        vm.stopPrank();
        
        assertEq(registry.getNodeMetadata(user1), newMetadata);
    }
    
    function testCannotUpdateMetadataIfNotRegistered() public {
        vm.startPrank(user1);
        vm.expectRevert("Not registered");
        registry.updateMetadata("New Metadata");
        vm.stopPrank();
    }
    
    function testMinimumStakeConstant() public {
        assertEq(registry.minimumStake(), MIN_STAKE);
    }
    
    function testFabTokenAddress() public {
        assertEq(address(registry.fabToken()), address(fabToken));
    }
    
    function testGetAllActiveNodes() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1");
        vm.stopPrank();
        
        vm.startPrank(user2);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 2");
        vm.stopPrank();
        
        address[] memory activeNodes = registry.getAllActiveNodes();
        assertEq(activeNodes.length, 2);
    }
    
    function testContractBalanceTracking() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1");
        vm.stopPrank();
        
        vm.startPrank(user2);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 2");
        vm.stopPrank();
        
        assertEq(fabToken.balanceOf(address(registry)), MIN_STAKE * 2);
    }
    
    function testEmergencyWithdraw() public {
        vm.startPrank(user1);
        fabToken.approve(address(registry), MIN_STAKE);
        registry.registerNode("Node 1");
        vm.stopPrank();
        
        uint256 ownerBalanceBefore = fabToken.balanceOf(address(this));
        registry.emergencyWithdraw();
        uint256 ownerBalanceAfter = fabToken.balanceOf(address(this));
        
        assertEq(ownerBalanceAfter - ownerBalanceBefore, MIN_STAKE);
    }
    
    function testOnlyOwnerCanEmergencyWithdraw() public {
        vm.startPrank(user1);
        vm.expectRevert();
        registry.emergencyWithdraw();
        vm.stopPrank();
    }
}