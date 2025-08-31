// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/MockUSDC.sol";

contract TokenEscrowTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    MockUSDC public usdc;
    
    address public host1 = address(0x1);
    address public host2 = address(0x2);
    address public renter1 = address(0x3);
    address public renter2 = address(0x4);
    address public nodeRegistry = address(0x5);
    address payable public hostEarnings = payable(address(0x6));
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        usdc = new MockUSDC();
        
        // Enable USDC
        marketplace.setAcceptedToken(address(usdc), true);
        
        // Setup renters with USDC
        usdc.mint(renter1, 5000 * 10**6);
        usdc.mint(renter2, 5000 * 10**6);
        
        // Give ETH for gas
        vm.deal(renter1, 1 ether);
        vm.deal(renter2, 1 ether);
    }
    
    function test_USDCHeldInContract() public {
        uint256 deposit = 100 * 10**6;
        
        vm.startPrank(renter1);
        usdc.approve(address(marketplace), deposit);
        
        uint256 contractBalanceBefore = usdc.balanceOf(address(marketplace));
        
        marketplace.createSessionJobWithToken(
            host1,
            address(usdc),
            deposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
        
        // Verify USDC held in contract
        assertEq(usdc.balanceOf(address(marketplace)), contractBalanceBefore + deposit);
    }
    
    function test_MultipleTokenDeposits() public {
        uint256 deposit1 = 100 * 10**6;
        uint256 deposit2 = 200 * 10**6;
        
        // First deposit
        vm.startPrank(renter1);
        usdc.approve(address(marketplace), deposit1);
        marketplace.createSessionJobWithToken(host1, address(usdc), deposit1, 10000, 3600, 600);
        vm.stopPrank();
        
        // Second deposit
        vm.startPrank(renter2);
        usdc.approve(address(marketplace), deposit2);
        marketplace.createSessionJobWithToken(host2, address(usdc), deposit2, 10000, 3600, 600);
        vm.stopPrank();
        
        // Verify total held
        assertEq(usdc.balanceOf(address(marketplace)), deposit1 + deposit2);
    }
    
    function test_TokenBalanceQueries() public {
        uint256 deposit = 150 * 10**6;
        
        vm.startPrank(renter1);
        usdc.approve(address(marketplace), deposit);
        
        uint256 jobId = marketplace.createSessionJobWithToken(
            host1,
            address(usdc),
            deposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
        
        // Check if marked as token job
        assertTrue(marketplace.isTokenJob(jobId));
        
        // Verify contract holds the tokens
        assertEq(usdc.balanceOf(address(marketplace)), deposit);
    }
    
    function test_EscrowSeparationFromETH() public {
        uint256 usdcDeposit = 100 * 10**6;
        uint256 ethDeposit = 0.1 ether;
        
        // Create USDC job
        vm.startPrank(renter1);
        usdc.approve(address(marketplace), usdcDeposit);
        uint256 tokenJobId = marketplace.createSessionJobWithToken(
            host1,
            address(usdc),
            usdcDeposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
        
        // Create ETH job  
        vm.prank(renter2);
        marketplace.createSessionForTesting{value: ethDeposit}(
            2000, // Different ID
            renter2,
            host2,
            ethDeposit,
            10000
        );
        uint256 ethJobId = 2000;
        
        // Verify separate tracking
        assertTrue(marketplace.isTokenJob(tokenJobId));
        assertFalse(marketplace.isTokenJob(ethJobId));
        
        // Both escrows maintained
        assertEq(usdc.balanceOf(address(marketplace)), usdcDeposit);
        assertGe(address(marketplace).balance, ethDeposit);
    }
    
    function test_AcceptedTokensMapping() public {
        MockUSDC token1 = new MockUSDC();
        MockUSDC token2 = new MockUSDC();
        
        // Initially not accepted
        assertFalse(marketplace.acceptedTokens(address(token1)));
        assertFalse(marketplace.acceptedTokens(address(token2)));
        
        // Enable token1
        marketplace.setAcceptedToken(address(token1), true);
        assertTrue(marketplace.acceptedTokens(address(token1)));
        assertFalse(marketplace.acceptedTokens(address(token2)));
        
        // Enable token2
        marketplace.setAcceptedToken(address(token2), true);
        assertTrue(marketplace.acceptedTokens(address(token2)));
        
        // Disable token1
        marketplace.setAcceptedToken(address(token1), false);
        assertFalse(marketplace.acceptedTokens(address(token1)));
        assertTrue(marketplace.acceptedTokens(address(token2)));
    }
    
    function test_MultipleTokenTypes() public {
        MockUSDC altToken = new MockUSDC();
        marketplace.setAcceptedToken(address(altToken), true);
        
        uint256 usdcDeposit = 100 * 10**6;
        uint256 altDeposit = 50 * 10**6;
        
        altToken.mint(renter1, altDeposit);
        
        // Create job with USDC
        vm.startPrank(renter1);
        usdc.approve(address(marketplace), usdcDeposit);
        marketplace.createSessionJobWithToken(host1, address(usdc), usdcDeposit, 10000, 3600, 600);
        
        // Create job with alt token
        altToken.approve(address(marketplace), altDeposit);
        marketplace.createSessionJobWithToken(host2, address(altToken), altDeposit, 10000, 3600, 600);
        vm.stopPrank();
        
        // Verify both held
        assertEq(usdc.balanceOf(address(marketplace)), usdcDeposit);
        assertEq(altToken.balanceOf(address(marketplace)), altDeposit);
    }
}