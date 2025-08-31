// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract PaymentCalculationTest is Test {
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
    
    function test_CorrectPaymentCalculation() public {
        // Test with 100 tokens at 0.001 ether each
        _setupSessionWithProofs(100, 0.001 ether);
        
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Total: 100 * 0.001 = 0.1 ether
        // Treasury fee (10%): 0.01 ether
        // Host payment: 0.09 ether
        assertEq(host.balance - hostBalanceBefore, 0.09 ether, "Host payment incorrect");
        assertEq(treasury.balance - treasuryBalanceBefore, 0.01 ether, "Treasury fee incorrect");
    }
    
    function test_TreasuryFeeIsTenPercent() public {
        // Test with different amounts
        uint256[3] memory tokenCounts = [uint256(50), 200, 1000];
        uint256[3] memory prices = [uint256(0.002 ether), 0.001 ether, 0.0001 ether];
        
        for (uint i = 0; i < tokenCounts.length; i++) {
            // Reset for each test
            setUp();
            _setupSessionWithProofs(tokenCounts[i], prices[i]);
            
            uint256 treasuryBalanceBefore = treasury.balance;
            
            vm.prank(user);
            marketplace.completeSessionJob(JOB_ID);
            
            uint256 expectedTotal = tokenCounts[i] * prices[i];
            uint256 expectedFee = expectedTotal / 10; // 10%
            
            assertEq(
                treasury.balance - treasuryBalanceBefore, 
                expectedFee, 
                string.concat("Treasury fee should be 10% for test ", vm.toString(i))
            );
        }
    }
    
    function test_PaymentEqualsTokensMinusFee() public {
        _setupSessionWithProofs(250, 0.001 ether);
        
        uint256 hostBalanceBefore = host.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Total: 250 * 0.001 = 0.25 ether
        // Fee: 0.025 ether
        // Payment: 0.225 ether
        assertEq(host.balance - hostBalanceBefore, 0.225 ether, "Payment should be total minus fee");
    }
    
    function test_EdgeCaseZeroTokens() public {
        _setupSessionWithProofs(0, 0.001 ether); // No proven tokens
        
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        assertEq(host.balance, hostBalanceBefore, "No payment for zero tokens");
        assertEq(treasury.balance, treasuryBalanceBefore, "No fee for zero tokens");
    }
    
    function test_EdgeCaseLargeNumbers() public {
        // Test with maximum reasonable values
        uint256 largeTokenCount = 1000000; // 1 million tokens
        uint256 pricePerToken = 0.00001 ether;
        
        _setupSessionWithProofs(largeTokenCount, pricePerToken);
        
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Total: 1,000,000 * 0.00001 = 10 ether
        // Fee: 1 ether
        // Payment: 9 ether
        assertEq(host.balance - hostBalanceBefore, 9 ether, "Large payment calculation incorrect");
        assertEq(treasury.balance - treasuryBalanceBefore, 1 ether, "Large fee calculation incorrect");
    }
    
    function test_PaymentRoundingHandledCorrectly() public {
        // Test with amount that doesn't divide evenly by 10
        _setupSessionWithProofs(33, 0.001 ether);
        
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Total: 33 * 0.001 = 0.033 ether
        // Fee: 0.0033 ether (rounded down in Solidity)
        // Payment: 0.0297 ether
        uint256 total = 0.033 ether;
        uint256 expectedFee = total / 10; // 0.0033 ether
        uint256 expectedPayment = total - expectedFee;
        
        assertEq(host.balance - hostBalanceBefore, expectedPayment, "Rounded payment incorrect");
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee, "Rounded fee incorrect");
    }
    
    // Helper functions
    function _setupSessionWithProofs(uint256 tokenCount, uint256 pricePerToken) internal {
        marketplace.createSessionForTesting{value: 10 ether}(JOB_ID, user, host, 10 ether, pricePerToken);
        
        if (tokenCount > 0) {
            bytes memory proof = hex"1234";
            proofSystem.setVerificationResult(true);
            
            vm.prank(host);
            marketplace.submitProofOfWork(JOB_ID, proof, tokenCount);
        }
    }
}