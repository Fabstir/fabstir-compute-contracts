// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract EarningsCalcTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x2001);
    address public treasury = address(0x3001);
    address public nodeRegistry = address(0x4001);
    address public hostEarnings = address(0x5001);
    
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 10 ether;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        vm.deal(user, 100 ether);
        vm.deal(host, 10 ether);
        vm.deal(address(marketplace), 100 ether);
    }
    
    function test_CalculateCurrentEarningsAccuracy() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            1, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof for 500 tokens
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(1, "proof", 500);
        
        // Calculate earnings
        (
            uint256 grossEarnings,
            uint256 treasuryFee,
            uint256 netEarnings
        ) = marketplace.calculateCurrentEarnings(1);
        
        // Verify calculations
        uint256 expectedGross = 500 * PRICE_PER_TOKEN; // 0.5 ETH
        uint256 expectedFee = (expectedGross * 10) / 100; // 0.05 ETH
        uint256 expectedNet = expectedGross - expectedFee; // 0.45 ETH
        
        assertEq(grossEarnings, expectedGross);
        assertEq(treasuryFee, expectedFee);
        assertEq(netEarnings, expectedNet);
    }
    
    function test_TreasuryFeeCalculation() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            1, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proof for 1000 tokens
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(1, "proof", 1000);
        
        // Calculate earnings
        (
            uint256 grossEarnings,
            uint256 treasuryFee,
            uint256 netEarnings
        ) = marketplace.calculateCurrentEarnings(1);
        
        // Treasury fee should be exactly 10%
        assertEq(treasuryFee, grossEarnings / 10);
        assertEq(netEarnings, (grossEarnings * 90) / 100);
    }
    
    function test_EarningsForZeroTokens() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            1, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Calculate earnings without any proofs
        (
            uint256 grossEarnings,
            uint256 treasuryFee,
            uint256 netEarnings
        ) = marketplace.calculateCurrentEarnings(1);
        
        assertEq(grossEarnings, 0);
        assertEq(treasuryFee, 0);
        assertEq(netEarnings, 0);
    }
    
    function test_EarningsForLargeAmounts() public {
        // Create session with higher price and larger deposit
        uint256 highPrice = 0.01 ether;
        uint256 largeDeposit = 100 ether;
        vm.prank(user);
        marketplace.createSessionForTesting{value: largeDeposit}(
            1, user, host, largeDeposit, highPrice
        );
        
        // Submit proof for 9000 tokens (90 ETH worth, within 100 ETH deposit)
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(1, "proof", 9000);
        
        // Calculate earnings
        (
            uint256 grossEarnings,
            uint256 treasuryFee,
            uint256 netEarnings
        ) = marketplace.calculateCurrentEarnings(1);
        
        // Verify large amount calculations
        uint256 expectedGross = 9000 * highPrice; // 90 ETH
        uint256 expectedFee = expectedGross / 10; // 9 ETH
        uint256 expectedNet = expectedGross - expectedFee; // 81 ETH
        
        assertEq(grossEarnings, expectedGross);
        assertEq(treasuryFee, expectedFee);
        assertEq(netEarnings, expectedNet);
    }
    
    function test_NetVsGrossEarnings() public {
        // Create multiple sessions with different token amounts
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, host, DEPOSIT, PRICE_PER_TOKEN
            );
            
            // Submit proofs
            proofSystem.setVerificationResult(true);
            vm.prank(host);
            marketplace.submitProofOfWork(i, "proof", i * 100);
        }
        
        // Check earnings for each session
        for (uint256 i = 1; i <= 3; i++) {
            (
                uint256 gross,
                uint256 fee,
                uint256 net
            ) = marketplace.calculateCurrentEarnings(i);
            
            // Net should always be 90% of gross
            assertEq(net, (gross * 90) / 100);
            // Fee should always be 10% of gross
            assertEq(fee, gross / 10);
            // Gross should equal net + fee
            assertEq(gross, net + fee);
        }
    }
}