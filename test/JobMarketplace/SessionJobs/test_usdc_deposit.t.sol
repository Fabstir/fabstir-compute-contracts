// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/MockUSDC.sol";

contract USDCDepositTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    MockUSDC public usdc;
    
    address public host = address(0x1);
    address public renter = address(0x2);
    address public nodeRegistry = address(0x3);
    address payable public hostEarnings = payable(address(0x4));
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        usdc = new MockUSDC();
        
        // Enable USDC as accepted token
        marketplace.setAcceptedToken(address(usdc), true, 800000);
        
        // Give renter some USDC
        usdc.mint(renter, 10000 * 10**6); // 10k USDC
    }
    
    function test_USDCTransferFromUserToContract() public {
        uint256 deposit = 100 * 10**6; // 100 USDC
        
        // Approve marketplace to spend USDC
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        
        uint256 balanceBefore = usdc.balanceOf(address(marketplace));
        
        // Create job with USDC
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10000, // price per token
            3600,  // 1 hour
            600    // 10 min interval
        );
        vm.stopPrank();
        
        // Verify transfer happened
        assertEq(usdc.balanceOf(address(marketplace)), balanceBefore + deposit);
        assertEq(usdc.balanceOf(renter), 10000 * 10**6 - deposit);
        assertTrue(jobId > 0);
    }
    
    function test_InsufficientBalanceRejection() public {
        uint256 deposit = 20000 * 10**6; // More than renter has
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        
        // Should revert on insufficient balance
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientBalance(address,uint256,uint256)")),
                renter,
                10000 * 10**6,
                deposit
            )
        );
        marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
    }
    
    function test_ApprovalRequirement() public {
        uint256 deposit = 100 * 10**6;
        
        vm.prank(renter);
        // Try without approval - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
                address(marketplace),
                0,
                deposit
            )
        );
        marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10000,
            3600,
            600
        );
    }
    
    function test_DepositAmountTracking() public {
        uint256 deposit = 150 * 10**6;
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
        
        // Verify deposit tracked in session details
        (,, uint256 depositAmount,,,,,) = marketplace.getSessionDetails(jobId);
        assertEq(depositAmount, deposit);
    }
    
    function test_EventEmissionWithTokenAddress() public {
        uint256 deposit = 200 * 10**6;
        
        vm.startPrank(renter);
        usdc.approve(address(marketplace), deposit);
        
        // Expect event
        vm.expectEmit(true, true, false, true);
        emit JobMarketplaceFABWithS5.SessionJobCreatedWithToken(1, address(usdc), deposit);
        
        marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
    }
    
    function test_UnacceptedTokenRejection() public {
        MockUSDC otherToken = new MockUSDC();
        uint256 deposit = 100 * 10**6;
        
        vm.startPrank(renter);
        otherToken.mint(renter, deposit);
        otherToken.approve(address(marketplace), deposit);
        
        // Should reject unaccepted token
        vm.expectRevert("Token not accepted");
        marketplace.createSessionJobWithToken(
            host,
            address(otherToken),
            deposit,
            10000,
            3600,
            600
        );
        vm.stopPrank();
    }
    
    function test_ZeroDepositRejection() public {
        vm.startPrank(renter);
        usdc.approve(address(marketplace), 1000 * 10**6);
        
        vm.expectRevert("Deposit required");
        marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            0, // Zero deposit
            10000,
            3600,
            600
        );
        vm.stopPrank();
    }
}