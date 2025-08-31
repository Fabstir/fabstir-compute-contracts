// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/MockUSDC.sol";
import "../../mocks/ProofSystemMock.sol";

contract TokenPaymentsTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    MockUSDC public usdc;
    ProofSystemMock public proofSystem;
    
    address public host = address(0x100);
    address public renter = address(0x200);
    address public nodeRegistry = address(0x3);
    address payable public hostEarnings = payable(address(0x4));
    address payable public treasury = payable(address(0x5));
    
    uint256 constant TREASURY_FEE_PERCENT = 10; // Match contract's hardcoded value
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        usdc = new MockUSDC();
        proofSystem = new ProofSystemMock();
        
        // Set proof system
        marketplace.setProofSystem(address(proofSystem));
        
        // Set treasury
        marketplace.setTreasuryAddress(treasury);
        
        // Enable USDC
        marketplace.setAcceptedToken(address(usdc), true);
        
        // Setup funds
        usdc.mint(renter, 10000 * 10**6);
        vm.deal(host, 1 ether);
        vm.deal(renter, 1 ether);
    }
    
    function test_HostReceivesUSDCPayment() public {
        uint256 deposit = 1000 * 10**6;
        uint256 pricePerToken = 10 * 10**6;
        uint256 provenTokens = 100; // Full usage
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            pricePerToken,
            3600,
            600
        );
        vm.stopPrank();
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        uint256 hostBalanceBefore = usdc.balanceOf(host);
        
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // Calculate expected payment (minus treasury fee)
        uint256 totalCost = provenTokens * pricePerToken;
        uint256 treasuryFee = (totalCost * TREASURY_FEE_PERCENT) / 100;
        uint256 expectedPayment = totalCost - treasuryFee;
        
        assertEq(usdc.balanceOf(host) - hostBalanceBefore, expectedPayment);
    }
    
    function test_TreasuryReceivesUSDCFee() public {
        uint256 deposit = 1000 * 10**6;
        uint256 pricePerToken = 10 * 10**6;
        uint256 provenTokens = 100;
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            pricePerToken,
            3600,
            600
        );
        vm.stopPrank();
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // Calculate expected fee
        uint256 totalCost = provenTokens * pricePerToken;
        uint256 expectedFee = (totalCost * TREASURY_FEE_PERCENT) / 100;
        
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, expectedFee);
    }
    
    function test_PaymentCalculationWithTokens() public {
        uint256 deposit = 2000 * 10**6;
        uint256 pricePerToken = 25 * 10**6;
        uint256 provenTokens = 40; // 1000 USDC used
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            pricePerToken,
            3600,
            600
        );
        vm.stopPrank();
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        uint256 hostBefore = usdc.balanceOf(host);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 renterBefore = usdc.balanceOf(renter);
        
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        uint256 totalCost = provenTokens * pricePerToken;
        uint256 treasuryFee = (totalCost * TREASURY_FEE_PERCENT) / 100;
        uint256 hostPayment = totalCost - treasuryFee;
        uint256 refund = deposit - totalCost;
        
        assertEq(usdc.balanceOf(host) - hostBefore, hostPayment);
        assertEq(usdc.balanceOf(treasury) - treasuryBefore, treasuryFee);
        assertEq(usdc.balanceOf(renter) - renterBefore, refund);
    }
    
    function test_TimeoutWithTokenRefund() public {
        uint256 deposit = 500 * 10**6;
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10 * 10**6,
            1, // Timeout immediately
            600
        );
        vm.stopPrank();
        
        // No proofs submitted
        vm.warp(block.timestamp + 2);
        
        uint256 renterBefore = usdc.balanceOf(renter);
        
        vm.prank(renter);
        marketplace.triggerSessionTimeout(jobId);
        
        // Full refund on timeout
        assertEq(usdc.balanceOf(renter) - renterBefore, deposit);
    }
    
    function test_AbandonmentWithTokenPayment() public {
        uint256 deposit = 800 * 10**6;
        uint256 pricePerToken = 20 * 10**6;
        uint256 provenTokens = 30; // 600 USDC used
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            pricePerToken,
            100, // Short duration
            10
        );
        vm.stopPrank();
        
        // Submit some proofs
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        // Wait for abandonment window (24 hours)
        vm.warp(block.timestamp + 24 hours + 1);
        
        uint256 hostBefore = usdc.balanceOf(host);
        uint256 treasuryBefore = usdc.balanceOf(treasury);
        uint256 renterBefore = usdc.balanceOf(renter);
        
        vm.prank(host);
        marketplace.claimAbandonedSession(jobId);
        
        // Verify payments
        uint256 totalCost = provenTokens * pricePerToken;
        uint256 treasuryFee = (totalCost * TREASURY_FEE_PERCENT) / 100;
        uint256 hostPayment = totalCost - treasuryFee;
        uint256 refund = deposit - totalCost;
        
        assertEq(usdc.balanceOf(host) - hostBefore, hostPayment);
        assertEq(usdc.balanceOf(treasury) - treasuryBefore, treasuryFee);
        assertEq(usdc.balanceOf(renter) - renterBefore, refund);
    }
    
    function test_GetTokenBalance() public {
        uint256 deposit = 300 * 10**6;
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10 * 10**6,
            3600,
            600
        );
        vm.stopPrank();
        
        // Check USDC balance
        uint256 usdcBalance = marketplace.getTokenBalance(address(usdc));
        assertEq(usdcBalance, deposit);
        
        // Check ETH balance
        uint256 ethBalance = marketplace.getTokenBalance(address(0));
        assertEq(ethBalance, address(marketplace).balance);
    }
}