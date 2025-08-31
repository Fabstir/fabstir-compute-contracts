// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../../src/NodeRegistryFAB.sol";

contract TestDepositLock is Test {
    JobMarketplaceFABWithS5 public marketplace;
    NodeRegistryFAB public nodeRegistry;
    
    address public user = address(0x1);
    address public host = address(0x2);
    
    uint256 constant DEPOSIT = 10 ether;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant MAX_DURATION = 7 days;
    uint256 constant PROOF_INTERVAL = 1000;
    
    function setUp() public {
        nodeRegistry = new NodeRegistryFAB();
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(0x999)));
        
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);
        
        vm.prank(host);
        nodeRegistry.registerNodeSimple{value: 10 ether}("host-metadata");
    }
    
    function test_DepositLock_TransferToContract() public {
        uint256 userBalanceBefore = user.balance;
        uint256 contractBalanceBefore = address(marketplace).balance;
        
        vm.prank(user);
        marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        // Check funds transferred
        assertEq(user.balance, userBalanceBefore - DEPOSIT);
        assertEq(address(marketplace).balance, contractBalanceBefore + DEPOSIT);
    }
    
    function test_DepositLock_InsufficientDeposit() public {
        vm.startPrank(user);
        
        // Try to create session with less ETH than deposit amount
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJob{value: DEPOSIT - 1 ether}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        vm.stopPrank();
    }
    
    function test_DepositLock_ETHHandling() public {
        vm.startPrank(user);
        
        // Test exact deposit
        uint256 jobId1 = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        assertTrue(jobId1 > 0);
        
        // Test overpayment (should accept but only lock specified deposit)
        uint256 jobId2 = marketplace.createSessionJob{value: DEPOSIT + 1 ether}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        assertTrue(jobId2 > jobId1);
        
        vm.stopPrank();
    }
    
    function test_DepositLock_TrackingPerJob() public {
        vm.startPrank(user);
        
        // Create multiple sessions with different deposits
        uint256 jobId1 = marketplace.createSessionJob{value: 5 ether}(
            host,
            5 ether,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        uint256 jobId2 = marketplace.createSessionJob{value: 10 ether}(
            host,
            10 ether,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        // Check each job has correct deposit recorded
        JobMarketplaceFABWithS5.SessionDetails memory session1 = marketplace.sessions(jobId1);
        assertEq(session1.depositAmount, 5 ether);
        
        JobMarketplaceFABWithS5.SessionDetails memory session2 = marketplace.sessions(jobId2);
        assertEq(session2.depositAmount, 10 ether);
        
        vm.stopPrank();
    }
    
    function test_DepositLock_ZeroDeposit() public {
        vm.startPrank(user);
        
        vm.expectRevert("Deposit must be positive");
        marketplace.createSessionJob{value: 0}(
            host,
            0,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        vm.stopPrank();
    }
}