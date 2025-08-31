// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract SessionTimeoutPaymentTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x1002);
    address public treasury = address(0x1003);
    address public nodeRegistry = address(0x1004);
    address public hostEarnings = address(0x1005);
    
    uint256 constant JOB_ID = 1;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        // Fund user and host
        vm.deal(user, 10 ether);
        vm.deal(host, 10 ether);
        vm.deal(address(marketplace), 10 ether);
    }
    
    function test_PaymentWith10PercentPenaltyOnTimeout() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof for 500 tokens
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Calculate expected payments
        uint256 tokenCost = 500 * PRICE_PER_TOKEN; // 0.5 ETH
        uint256 treasuryFee = (tokenCost * 10) / 100; // 10% treasury on full amount = 0.05 ETH
        uint256 basePayment = tokenCost - treasuryFee; // 0.45 ETH
        uint256 hostPayment = (basePayment * 90) / 100; // 10% penalty = 0.405 ETH
        
        // Fast forward and trigger timeout
        vm.warp(block.timestamp + 2 hours);
        
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // Verify host received penalized payment
        assertEq(host.balance - hostBalanceBefore, hostPayment);
        
        // Verify treasury received fee
        assertEq(treasury.balance - treasuryBalanceBefore, treasuryFee);
    }
    
    function test_FullRefundIfNoProvenWork() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Fast forward without any proofs
        vm.warp(block.timestamp + 2 hours);
        
        uint256 userBalanceBefore = user.balance;
        uint256 hostBalanceBefore = host.balance;
        
        vm.prank(host);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // User gets full refund
        assertEq(user.balance - userBalanceBefore, DEPOSIT);
        
        // Host gets nothing
        assertEq(host.balance, hostBalanceBefore);
    }
    
    function test_PartialRefundCalculation() public {
        // Create session with 2 ETH deposit
        uint256 largeDeposit = 2 ether;
        vm.prank(user);
        marketplace.createSessionForTesting{value: largeDeposit}(
            JOB_ID, user, host, largeDeposit, PRICE_PER_TOKEN
        );
        
        // Submit proof for 500 tokens (costs 0.5 ETH)
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 500);
        
        // Fast forward and timeout
        vm.warp(block.timestamp + 2 hours);
        
        uint256 userBalanceBefore = user.balance;
        
        vm.prank(user);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // User should get refund of unused deposit
        uint256 tokenCost = 500 * PRICE_PER_TOKEN; // 0.5 ETH
        uint256 expectedRefund = largeDeposit - tokenCost; // 1.5 ETH
        assertEq(user.balance - userBalanceBefore, expectedRefund);
    }
    
    function test_TreasuryFeeOnTimeout() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 800);
        
        // Fast forward and timeout
        vm.warp(block.timestamp + 2 hours);
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // Verify treasury received fee
        assertGt(treasury.balance - treasuryBalanceBefore, 0);
    }
    
    function test_PaymentDistributionOnTimeout() public {
        // Create session
        uint256 deposit = 2 ether;
        vm.prank(user);
        marketplace.createSessionForTesting{value: deposit}(
            JOB_ID, user, host, deposit, PRICE_PER_TOKEN
        );
        
        // Submit proof for 1000 tokens (1 ETH worth)
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof_data", 1000);
        
        // Track all balances
        uint256 hostBalanceBefore = host.balance;
        uint256 userBalanceBefore = user.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 contractBalanceBefore = address(marketplace).balance;
        
        // Fast forward and timeout
        vm.warp(block.timestamp + 2 hours);
        vm.prank(user);
        marketplace.triggerSessionTimeout(JOB_ID);
        
        // Calculate expected distributions
        uint256 tokenCost = 1000 * PRICE_PER_TOKEN; // 1 ETH
        uint256 treasuryFee = (tokenCost * 10) / 100; // 0.1 ETH treasury on full amount
        uint256 basePayment = tokenCost - treasuryFee; // 0.9 ETH
        uint256 hostPayment = (basePayment * 90) / 100; // 10% penalty = 0.81 ETH
        uint256 userRefund = deposit - tokenCost; // 1 ETH
        
        // Verify distributions
        assertEq(host.balance - hostBalanceBefore, hostPayment);
        assertEq(user.balance - userBalanceBefore, userRefund);
        assertEq(treasury.balance - treasuryBalanceBefore, treasuryFee);
        
        // Contract should have distributed all funds
        assertEq(
            contractBalanceBefore,
            address(marketplace).balance + hostPayment + userRefund + treasuryFee
        );
    }
}