// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../../src/NodeRegistryFAB.sol";

contract TestHostAssignment is Test {
    JobMarketplaceFABWithS5 public marketplace;
    NodeRegistryFAB public nodeRegistry;
    
    address public user = address(0x1);
    address public validHost = address(0x2);
    address public invalidHost = address(0x3);
    address public inactiveHost = address(0x4);
    
    uint256 constant DEPOSIT = 10 ether;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant MAX_DURATION = 7 days;
    uint256 constant PROOF_INTERVAL = 1000;
    
    function setUp() public {
        nodeRegistry = new NodeRegistryFAB();
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(0x999)));
        
        vm.deal(user, 100 ether);
        vm.deal(validHost, 100 ether);
        vm.deal(inactiveHost, 100 ether);
        
        // Register valid host
        vm.prank(validHost);
        nodeRegistry.registerNodeSimple{value: 10 ether}("valid-host");
        
        // Register inactive host then deactivate
        vm.prank(inactiveHost);
        nodeRegistry.registerNodeSimple{value: 10 ether}("inactive-host");
        vm.prank(inactiveHost);
        nodeRegistry.unregisterNode();
    }
    
    function test_HostAssignment_ValidHost() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            validHost,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        assertEq(session.assignedHost, validHost);
    }
    
    function test_HostAssignment_InvalidHost() public {
        vm.startPrank(user);
        
        // Host not registered
        vm.expectRevert("Host not registered");
        marketplace.createSessionJob{value: DEPOSIT}(
            invalidHost,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        vm.stopPrank();
    }
    
    function test_HostAssignment_InactiveHost() public {
        vm.startPrank(user);
        
        // Host registered but inactive
        vm.expectRevert("Host not active");
        marketplace.createSessionJob{value: DEPOSIT}(
            inactiveHost,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        vm.stopPrank();
    }
    
    function test_HostAssignment_ZeroAddress() public {
        vm.startPrank(user);
        
        vm.expectRevert("Invalid host address");
        marketplace.createSessionJob{value: DEPOSIT}(
            address(0),
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        vm.stopPrank();
    }
    
    function test_HostAssignment_SelfAssignment() public {
        // Register user as host
        vm.prank(user);
        nodeRegistry.registerNodeSimple{value: 10 ether}("user-host");
        
        // Should allow self-assignment
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            user,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        assertEq(session.assignedHost, user);
    }
    
    function test_HostAssignment_CheckStake() public {
        // Create a host with insufficient stake
        address lowStakeHost = address(0x5);
        vm.deal(lowStakeHost, 100 ether);
        
        // Register with minimum stake
        vm.prank(lowStakeHost);
        nodeRegistry.registerNodeSimple{value: nodeRegistry.MIN_STAKE()}("low-stake");
        
        // Should work with minimum stake
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            lowStakeHost,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        assertTrue(jobId > 0);
    }
}