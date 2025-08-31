// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract RefundsTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public treasury = address(0x1003);
    address public nodeRegistry = address(0x1004);
    address public hostEarnings = address(0x1005);
    uint256 public constant JOB_ID = 1;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        vm.deal(user, 100 ether);
        vm.deal(host, 1 ether);
    }
    
    function test_RefundWhenDepositGreaterThanCost() public {
        // Deposit 1 ether, but only use 100 tokens at 0.001 ether = 0.1 ether total
        _setupSessionWithDeposit(1 ether, 0.001 ether);
        _submitProofs(100);
        
        uint256 userBalanceBefore = user.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Cost: 100 * 0.001 = 0.1 ether
        // Refund: 1 - 0.1 = 0.9 ether
        uint256 expectedRefund = 0.9 ether;
        assertEq(user.balance - userBalanceBefore, expectedRefund, "User should receive refund");
    }
    
    function test_NoRefundWhenDepositEqualsCost() public {
        // Deposit 0.5 ether, use 500 tokens at 0.001 ether = 0.5 ether total
        _setupSessionWithDeposit(0.5 ether, 0.001 ether);
        _submitProofs(500);
        
        uint256 userBalanceBefore = user.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // No refund expected
        assertEq(user.balance, userBalanceBefore, "No refund when deposit equals cost");
    }
    
    function test_RefundGoesToUserAddress() public {
        _setupSessionWithDeposit(2 ether, 0.001 ether);
        _submitProofs(200); // Cost: 0.2 ether
        
        uint256 userBalanceBefore = user.balance;
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Refund should only go to user
        uint256 expectedRefund = 1.8 ether; // 2 - 0.2
        assertEq(user.balance - userBalanceBefore, expectedRefund, "Refund goes to user");
        
        // Host gets payment, not refund
        uint256 expectedPayment = 0.18 ether; // 0.2 * 0.9 (after fee)
        assertEq(host.balance - hostBalanceBefore, expectedPayment, "Host gets payment only");
        
        // Treasury gets fee, not refund
        uint256 expectedFee = 0.02 ether; // 0.2 * 0.1
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee, "Treasury gets fee only");
    }
    
    function test_RefundAmountCalculation() public {
        // Test various deposit and usage combinations
        uint256[3] memory deposits = [uint256(5 ether), 3 ether, 10 ether];
        uint256[3] memory tokenUsage = [uint256(1000), 2000, 5000];
        uint256 pricePerToken = 0.001 ether;
        
        for (uint i = 0; i < deposits.length; i++) {
            setUp(); // Reset for each test
            
            _setupSessionWithDeposit(deposits[i], pricePerToken);
            _submitProofs(tokenUsage[i]);
            
            uint256 userBalanceBefore = user.balance;
            
            vm.prank(user);
            marketplace.completeSessionJob(JOB_ID);
            
            uint256 totalCost = tokenUsage[i] * pricePerToken;
            uint256 expectedRefund = deposits[i] > totalCost ? deposits[i] - totalCost : 0;
            
            assertEq(
                user.balance - userBalanceBefore,
                expectedRefund,
                string.concat("Refund calculation incorrect for test ", vm.toString(i))
            );
        }
    }
    
    function test_RefundInSessionCompletedEvent() public {
        _setupSessionWithDeposit(3 ether, 0.001 ether);
        _submitProofs(500); // Cost: 0.5 ether, Refund: 2.5 ether
        
        vm.expectEmit(true, true, false, true);
        emit JobMarketplaceFABWithS5.SessionCompleted(
            JOB_ID,
            user,
            500, // proven tokens
            0.45 ether, // payment after fee (0.5 * 0.9)
            2.5 ether // refund amount
        );
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
    }
    
    function test_LargeRefundHandledCorrectly() public {
        // Test with large deposit and small usage
        _setupSessionWithDeposit(50 ether, 0.001 ether);
        _submitProofs(10); // Only 0.01 ether used
        
        uint256 userBalanceBefore = user.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Refund: 50 - 0.01 = 49.99 ether
        uint256 expectedRefund = 49.99 ether;
        assertEq(user.balance - userBalanceBefore, expectedRefund, "Large refund handled correctly");
    }
    
    function test_NoRefundForHostClaim() public {
        _setupSessionWithDeposit(1 ether, 0.001 ether);
        _submitProofs(100);
        
        uint256 userBalanceBefore = user.balance;
        
        // Host claims instead of user completing
        vm.prank(host);
        marketplace.claimWithProof(JOB_ID);
        
        // User should not receive refund when host claims
        assertEq(user.balance, userBalanceBefore, "No refund when host claims");
    }
    
    // Helper functions
    function _setupSessionWithDeposit(uint256 deposit, uint256 pricePerToken) internal {
        marketplace.createSessionForTesting{value: deposit}(JOB_ID, user, host, deposit, pricePerToken);
    }
    
    function _submitProofs(uint256 tokenCount) internal {
        if (tokenCount > 0) {
            bytes memory proof = hex"1234";
            proofSystem.setVerificationResult(true);
            
            vm.prank(host);
            marketplace.submitProofOfWork(JOB_ID, proof, tokenCount);
        }
    }
}