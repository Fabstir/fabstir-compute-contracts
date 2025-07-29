// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PaymentSplitter} from "../../src/PaymentSplitter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract PaymentSplitsTest is Test {
    PaymentSplitter public splitter;
    MockERC20 public usdc;
    MockERC20 public fab;
    
    address constant HOST = address(0x1);
    address constant PROTOCOL_TREASURY = address(0x2);
    address constant STAKERS_POOL = address(0x3);
    address constant RENTER = address(0x4);
    
    uint256 constant HOST_SHARE = 8500; // 85%
    uint256 constant PROTOCOL_SHARE = 1000; // 10%
    uint256 constant STAKERS_SHARE = 500; // 5%
    uint256 constant BASIS_POINTS = 10000;
    
    event PaymentSplit(
        uint256 indexed jobId,
        address indexed token,
        uint256 totalAmount,
        uint256 hostAmount,
        uint256 protocolAmount,
        uint256 stakersAmount
    );
    
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event StakersFeeUpdated(uint256 oldFee, uint256 newFee);
    
    function setUp() public {
        splitter = new PaymentSplitter(PROTOCOL_TREASURY, STAKERS_POOL);
        
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        
        // Mint tokens to renter
        usdc.mint(RENTER, 10000 * 10**6); // 10k USDC
        fab.mint(RENTER, 10000 ether);
        
        // Mint tokens to splitter for testing
        usdc.mint(address(splitter), 1000 * 10**6);
        fab.mint(address(splitter), 1000 ether);
    }
    
    function test_DefaultPaymentSplit() public {
        uint256 amount = 1000 * 10**6; // 1000 USDC
        uint256 jobId = 1;
        
        uint256 hostBalanceBefore = usdc.balanceOf(HOST);
        uint256 protocolBalanceBefore = usdc.balanceOf(PROTOCOL_TREASURY);
        uint256 stakersBalanceBefore = usdc.balanceOf(STAKERS_POOL);
        
        vm.expectEmit(true, true, true, true);
        emit PaymentSplit(
            jobId,
            address(usdc),
            amount,
            850 * 10**6, // 85%
            100 * 10**6, // 10%
            50 * 10**6   // 5%
        );
        
        splitter.splitPayment(jobId, amount, HOST, address(usdc));
        
        // Verify splits
        assertEq(usdc.balanceOf(HOST) - hostBalanceBefore, 850 * 10**6);
        assertEq(usdc.balanceOf(PROTOCOL_TREASURY) - protocolBalanceBefore, 100 * 10**6);
        assertEq(usdc.balanceOf(STAKERS_POOL) - stakersBalanceBefore, 50 * 10**6);
    }
    
    function test_PaymentSplitWithFAB() public {
        uint256 amount = 100 ether; // 100 FAB
        uint256 jobId = 2;
        
        vm.expectEmit(true, true, true, true);
        emit PaymentSplit(
            jobId,
            address(fab),
            amount,
            85 ether,  // 85%
            10 ether,  // 10%
            5 ether    // 5%
        );
        
        splitter.splitPayment(jobId, amount, HOST, address(fab));
        
        assertEq(fab.balanceOf(HOST), 85 ether);
        assertEq(fab.balanceOf(PROTOCOL_TREASURY), 10 ether);
        assertEq(fab.balanceOf(STAKERS_POOL), 5 ether);
    }
    
    function test_PaymentSplitWithETH() public {
        uint256 amount = 1 ether;
        uint256 jobId = 3;
        
        // Fund splitter with ETH
        vm.deal(address(splitter), amount);
        
        uint256 hostBalanceBefore = HOST.balance;
        uint256 protocolBalanceBefore = PROTOCOL_TREASURY.balance;
        uint256 stakersBalanceBefore = STAKERS_POOL.balance;
        
        splitter.splitPayment(jobId, amount, HOST, address(0));
        
        assertEq(HOST.balance - hostBalanceBefore, 0.85 ether);
        assertEq(PROTOCOL_TREASURY.balance - protocolBalanceBefore, 0.1 ether);
        assertEq(STAKERS_POOL.balance - stakersBalanceBefore, 0.05 ether);
    }
    
    function test_UpdateProtocolFee() public {
        uint256 newFee = 1500; // 15%
        
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(1000, newFee);
        
        splitter.updateProtocolFee(newFee);
        
        assertEq(splitter.protocolFeeBasisPoints(), newFee);
    }
    
    function test_UpdateStakersFee() public {
        uint256 newFee = 750; // 7.5%
        
        vm.expectEmit(true, true, true, true);
        emit StakersFeeUpdated(500, newFee);
        
        splitter.updateStakersFee(newFee);
        
        assertEq(splitter.stakersFeeBasisPoints(), newFee);
    }
    
    function test_CannotExceedMaxFees() public {
        // Try to set total fees > 30%
        vm.expectRevert("Total fees exceed maximum");
        splitter.updateProtocolFee(2600); // 26% + 5% = 31% > 30%
    }
    
    function test_BatchPaymentSplits() public {
        uint256[] memory jobIds = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        address[] memory hosts = new address[](3);
        
        jobIds[0] = 10;
        jobIds[1] = 11;
        jobIds[2] = 12;
        
        amounts[0] = 100 * 10**6; // 100 USDC
        amounts[1] = 200 * 10**6; // 200 USDC
        amounts[2] = 300 * 10**6; // 300 USDC
        
        hosts[0] = address(0x100);
        hosts[1] = address(0x101);
        hosts[2] = address(0x102);
        
        splitter.batchSplitPayments(jobIds, amounts, hosts, address(usdc));
        
        // Verify all hosts received correct amounts
        assertEq(usdc.balanceOf(hosts[0]), 85 * 10**6);
        assertEq(usdc.balanceOf(hosts[1]), 170 * 10**6);
        assertEq(usdc.balanceOf(hosts[2]), 255 * 10**6);
        
        // Protocol treasury should have 10% of total
        assertEq(usdc.balanceOf(PROTOCOL_TREASURY), 60 * 10**6);
        
        // Stakers pool should have 5% of total
        assertEq(usdc.balanceOf(STAKERS_POOL), 30 * 10**6);
    }
    
    function test_ZeroAmountReverts() public {
        vm.expectRevert("Amount must be greater than zero");
        splitter.splitPayment(1, 0, HOST, address(usdc));
    }
    
    function test_InvalidAddressReverts() public {
        vm.expectRevert("Invalid host address");
        splitter.splitPayment(1, 100 ether, address(0), address(usdc));
    }
    
    function test_GetPaymentBreakdown() public {
        uint256 amount = 1000 * 10**6; // 1000 USDC
        
        (uint256 hostAmount, uint256 protocolAmount, uint256 stakersAmount) = 
            splitter.getPaymentBreakdown(amount);
            
        assertEq(hostAmount, 850 * 10**6);
        assertEq(protocolAmount, 100 * 10**6);
        assertEq(stakersAmount, 50 * 10**6);
        assertEq(hostAmount + protocolAmount + stakersAmount, amount);
    }
}