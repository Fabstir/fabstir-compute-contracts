// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract TreasuryFeesTest is Test {
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
    
    function test_TenPercentFeeCalculatedCorrectly() public {
        _setupSessionWithProofs(100, 0.01 ether); // 1 ether total
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // 10% of 1 ether = 0.1 ether
        assertEq(treasury.balance - treasuryBalanceBefore, 0.1 ether, "Treasury fee should be 10%");
    }
    
    function test_FeeGoesToTreasuryAddress() public {
        _setupSessionWithProofs(200, 0.001 ether); // 0.2 ether total
        
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 userBalanceBefore = user.balance;
        uint256 hostBalanceBefore = host.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // Fee should only go to treasury
        uint256 expectedFee = 0.02 ether; // 10% of 0.2
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee, "Fee goes to treasury");
        
        // Verify fee doesn't go elsewhere
        assertTrue(host.balance > hostBalanceBefore, "Host receives payment");
        assertTrue(user.balance >= userBalanceBefore, "User balance unchanged or receives refund");
    }
    
    function test_FeeHandlingWhenTreasuryNotSet() public {
        // Deploy new marketplace without treasury
        JobMarketplaceFABWithS5 marketplaceNoTreasury = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        marketplaceNoTreasury.setProofSystem(address(proofSystem));
        // Treasury address remains 0x0
        
        marketplaceNoTreasury.createSessionForTesting{value: 1 ether}(1, user, host, 1 ether, 0.001 ether);
        
        bytes memory proof = hex"1234";
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplaceNoTreasury.submitProofOfWork(1, proof, 100);
        
        // Complete without treasury - should not revert
        vm.prank(user);
        marketplaceNoTreasury.completeSessionJob(1);
        
        // Host should still get their payment minus fee
        assertTrue(host.balance > 1 ether, "Host receives payment even without treasury");
    }
    
    function test_FeeForVariousAmounts() public {
        uint256[5] memory tokenCounts = [uint256(10), 50, 123, 999, 10000];
        uint256[5] memory prices = [uint256(0.01 ether), 0.002 ether, 0.001 ether, 0.0001 ether, 0.00001 ether];
        
        for (uint i = 0; i < tokenCounts.length; i++) {
            setUp(); // Reset for each test
            
            _setupSessionWithProofs(tokenCounts[i], prices[i]);
            
            uint256 treasuryBalanceBefore = treasury.balance;
            
            vm.prank(user);
            marketplace.completeSessionJob(JOB_ID);
            
            uint256 totalPayment = tokenCounts[i] * prices[i];
            uint256 expectedFee = totalPayment / 10; // Always 10%
            
            assertEq(
                treasury.balance - treasuryBalanceBefore,
                expectedFee,
                string.concat("Fee incorrect for amount ", vm.toString(i))
            );
        }
    }
    
    function test_FeeConstantIsCorrect() public {
        // Verify the constant is set to 10
        assertEq(marketplace.TREASURY_FEE_PERCENT(), 10, "Treasury fee constant should be 10");
    }
    
    function test_TreasuryAddressCanBeSet() public {
        address newTreasury = address(0x999);
        
        marketplace.setTreasuryAddress(newTreasury);
        assertEq(marketplace.treasuryAddress(), newTreasury, "Treasury address should be updated");
    }
    
    function test_FeeForHostClaimPath() public {
        _setupSessionWithProofs(500, 0.001 ether); // 0.5 ether total
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        // Host claims instead of user completing
        vm.prank(host);
        marketplace.claimWithProof(JOB_ID);
        
        // Treasury should still get 10% fee
        uint256 expectedFee = 0.05 ether; // 10% of 0.5
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee, "Treasury gets fee on host claim");
    }
    
    function test_FeeWithMinimalAmount() public {
        // Test with very small amount
        _setupSessionWithProofs(1, 0.001 ether); // 0.001 ether total
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        // 10% of 0.001 = 0.0001 ether
        uint256 expectedFee = 0.0001 ether;
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee, "Small fee calculated correctly");
    }
    
    function test_FeeRoundingBehavior() public {
        // Test amount that doesn't divide evenly
        _setupSessionWithProofs(33, 0.0001 ether); // 0.0033 ether total
        
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 hostBalanceBefore = host.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(JOB_ID);
        
        uint256 total = 0.0033 ether;
        uint256 expectedFee = total / 10; // Rounds down in Solidity
        uint256 expectedPayment = total - expectedFee;
        
        assertEq(treasury.balance - treasuryBalanceBefore, expectedFee, "Fee rounds down correctly");
        assertEq(host.balance - hostBalanceBefore, expectedPayment, "Payment accounts for rounding");
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