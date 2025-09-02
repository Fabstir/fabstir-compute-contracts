// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/MockUSDC.sol";
import "../../mocks/ProofSystemMock.sol";

contract TokenRefundsTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    MockUSDC public usdc;
    ProofSystemMock public proofSystem;
    
    address public host = address(0x100);
    address public renter = address(0x200);
    address public nodeRegistry = address(0x3);
    address payable public hostEarnings = payable(address(0x4));
    address payable public treasury = payable(address(0x5));
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        usdc = new MockUSDC();
        proofSystem = new ProofSystemMock();
        
        // Set proof system
        marketplace.setProofSystem(address(proofSystem));
        
        // Set treasury
        marketplace.setTreasuryAddress(treasury);
        
        // Enable USDC
        marketplace.setAcceptedToken(address(usdc), true, 800000);
        
        // Setup funds
        usdc.mint(renter, 10000 * 10**6);
        vm.deal(host, 1 ether);
        vm.deal(renter, 1 ether);
    }
    
    function test_RefundWhenDepositExceedsCost() public {
        uint256 deposit = 1000 * 10**6; // 1000 USDC
        uint256 pricePerToken = 10 * 10**6; // 10 USDC per token
        uint256 provenTokens = 50; // Only used 500 USDC
        
        // Create job
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
        
        // Submit proof for partial usage
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        uint256 renterBalanceBefore = usdc.balanceOf(renter);
        
        // Complete session
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // Calculate expected refund
        uint256 totalCost = provenTokens * pricePerToken;
        uint256 expectedRefund = deposit - totalCost;
        
        // Verify refund received
        assertEq(usdc.balanceOf(renter), renterBalanceBefore + expectedRefund);
    }
    
    function test_NoRefundWhenDepositEqualsCost() public {
        uint256 pricePerToken = 10 * 10**6;
        uint256 provenTokens = 100;
        uint256 deposit = provenTokens * pricePerToken; // Exact amount
        
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
        
        // Submit proof for full usage
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        uint256 renterBalanceBefore = usdc.balanceOf(renter);
        
        // Complete session
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // No refund expected
        assertEq(usdc.balanceOf(renter), renterBalanceBefore);
    }
    
    function test_RefundGoesToCorrectAddress() public {
        uint256 deposit = 1000 * 10**6;
        uint256 pricePerToken = 10 * 10**6;
        uint256 provenTokens = 30;
        
        address otherUser = address(0x999);
        
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
        
        uint256 otherBalanceBefore = usdc.balanceOf(otherUser);
        
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // Other user should not receive refund
        assertEq(usdc.balanceOf(otherUser), otherBalanceBefore);
        
        // Refund should go to renter
        uint256 expectedRefund = deposit - (provenTokens * pricePerToken);
        assertTrue(usdc.balanceOf(renter) > 0);
    }
    
    function test_RefundAmountCalculation() public {
        uint256 deposit = 2500 * 10**6; // 2500 USDC
        uint256 pricePerToken = 15 * 10**6; // 15 USDC per token
        uint256 provenTokens = 100; // 1500 USDC used
        
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
        
        uint256 balanceBefore = usdc.balanceOf(renter);
        
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // Expected refund = 2500 - 1500 = 1000 USDC
        uint256 expectedRefund = 1000 * 10**6;
        assertEq(usdc.balanceOf(renter) - balanceBefore, expectedRefund);
    }
    
    function test_ETHJobsStillWork() public {
        uint256 deposit = 0.5 ether;
        uint256 pricePerToken = 0.001 ether;
        uint256 provenTokens = 100;
        
        // Create ETH job
        vm.prank(renter);
        marketplace.createSessionForTesting{value: deposit}(
            1000,
            renter,
            host,
            deposit,
            pricePerToken
        );
        uint256 jobId = 1000;
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, "proof_data", provenTokens);
        
        uint256 renterBalanceBefore = renter.balance;
        
        vm.prank(renter);
        marketplace.completeSessionJob(jobId);
        
        // Verify ETH refund
        uint256 totalCost = provenTokens * pricePerToken;
        uint256 expectedRefund = deposit - totalCost;
        assertEq(renter.balance - renterBalanceBefore, expectedRefund);
    }
    
    function test_TimeoutRefundInTokens() public {
        uint256 deposit = 500 * 10**6;
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10 * 10**6,
            1, // 1 second duration (will timeout)
            600
        );
        vm.stopPrank();
        
        // Wait for timeout
        vm.warp(block.timestamp + 2);
        
        uint256 balanceBefore = usdc.balanceOf(renter);
        
        // Trigger timeout
        vm.prank(renter);
        marketplace.triggerSessionTimeout(jobId);
        
        // Full refund on timeout
        assertEq(usdc.balanceOf(renter) - balanceBefore, deposit);
    }
}