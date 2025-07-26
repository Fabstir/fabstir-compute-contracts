// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PaymentEscrow} from "../../src/PaymentEscrow.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract PaymentEscrowTest is Test {
    PaymentEscrow public escrow;
    MockERC20 public fabToken;
    MockERC20 public usdcToken;
    
    address constant RENTER = address(0x1);
    address constant HOST = address(0x2);
    address constant ARBITER = address(0x3);
    
    uint256 constant ESCROW_AMOUNT = 100 ether;
    uint256 constant ESCROW_FEE_BPS = 250; // 2.5%
    
    bytes32 constant JOB_ID = keccak256("job_123");
    
    event EscrowCreated(bytes32 indexed jobId, address indexed renter, address indexed host, uint256 amount, address token);
    event EscrowReleased(bytes32 indexed jobId, uint256 amount, uint256 fee);
    event EscrowDisputed(bytes32 indexed jobId, address disputer);
    event DisputeResolved(bytes32 indexed jobId, address winner);
    
    function setUp() public {
        escrow = new PaymentEscrow(ARBITER, ESCROW_FEE_BPS);
        
        // Deploy mock tokens
        fabToken = new MockERC20("Fabstir Token", "FAB", 18);
        usdcToken = new MockERC20("USD Coin", "USDC", 6);
        
        // Setup test accounts
        vm.deal(RENTER, 1000 ether);
        vm.deal(HOST, 1000 ether);
        
        // Mint tokens to renter
        fabToken.mint(RENTER, 10000 ether);
        usdcToken.mint(RENTER, 10000 * 10**6); // 10k USDC
    }
    
    function test_CreateEscrowWithETH() public {
        vm.startPrank(RENTER);
        
        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(JOB_ID, RENTER, HOST, ESCROW_AMOUNT, address(0));
        
        escrow.createEscrow{value: ESCROW_AMOUNT}(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(0) // ETH
        );
        
        PaymentEscrow.Escrow memory escrowData = escrow.getEscrow(JOB_ID);
        assertEq(escrowData.renter, RENTER);
        assertEq(escrowData.host, HOST);
        assertEq(escrowData.amount, ESCROW_AMOUNT);
        assertEq(escrowData.token, address(0));
        assertEq(uint256(escrowData.status), uint256(PaymentEscrow.EscrowStatus.Active));
        
        vm.stopPrank();
    }
    
    function test_CreateEscrowWithToken() public {
        vm.startPrank(RENTER);
        
        // Approve token transfer
        fabToken.approve(address(escrow), ESCROW_AMOUNT);
        
        escrow.createEscrow(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(fabToken)
        );
        
        PaymentEscrow.Escrow memory escrowData = escrow.getEscrow(JOB_ID);
        assertEq(escrowData.token, address(fabToken));
        assertEq(fabToken.balanceOf(address(escrow)), ESCROW_AMOUNT);
        
        vm.stopPrank();
    }
    
    function test_ReleaseEscrow() public {
        // Create escrow
        vm.prank(RENTER);
        escrow.createEscrow{value: ESCROW_AMOUNT}(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(0)
        );
        
        uint256 hostBalanceBefore = HOST.balance;
        uint256 expectedFee = (ESCROW_AMOUNT * ESCROW_FEE_BPS) / 10000;
        uint256 expectedPayment = ESCROW_AMOUNT - expectedFee;
        
        // Release escrow (either renter or host can release)
        vm.prank(RENTER);
        
        vm.expectEmit(true, false, false, true);
        emit EscrowReleased(JOB_ID, expectedPayment, expectedFee);
        
        escrow.releaseEscrow(JOB_ID);
        
        // Verify payment
        assertEq(HOST.balance, hostBalanceBefore + expectedPayment);
        assertEq(uint256(escrow.getEscrow(JOB_ID).status), uint256(PaymentEscrow.EscrowStatus.Released));
    }
    
    function test_OnlyPartiesCanReleaseEscrow() public {
        // Create escrow
        vm.prank(RENTER);
        escrow.createEscrow{value: ESCROW_AMOUNT}(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(0)
        );
        
        // Random address tries to release
        address random = address(0x999);
        vm.prank(random);
        vm.expectRevert("Not authorized");
        escrow.releaseEscrow(JOB_ID);
    }
    
    function test_DisputeEscrow() public {
        // Create escrow
        vm.prank(RENTER);
        escrow.createEscrow{value: ESCROW_AMOUNT}(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(0)
        );
        
        // Host disputes
        vm.prank(HOST);
        
        vm.expectEmit(true, false, false, false);
        emit EscrowDisputed(JOB_ID, HOST);
        
        escrow.disputeEscrow(JOB_ID);
        
        assertEq(uint256(escrow.getEscrow(JOB_ID).status), uint256(PaymentEscrow.EscrowStatus.Disputed));
    }
    
    function test_ResolveDispute() public {
        // Create and dispute escrow
        vm.prank(RENTER);
        escrow.createEscrow{value: ESCROW_AMOUNT}(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(0)
        );
        
        vm.prank(HOST);
        escrow.disputeEscrow(JOB_ID);
        
        uint256 hostBalanceBefore = HOST.balance;
        
        // Arbiter resolves in favor of host
        vm.prank(ARBITER);
        
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(JOB_ID, HOST);
        
        escrow.resolveDispute(JOB_ID, HOST);
        
        // Verify payment went to host (minus fee)
        uint256 expectedFee = (ESCROW_AMOUNT * ESCROW_FEE_BPS) / 10000;
        uint256 expectedPayment = ESCROW_AMOUNT - expectedFee;
        assertEq(HOST.balance, hostBalanceBefore + expectedPayment);
        assertEq(uint256(escrow.getEscrow(JOB_ID).status), uint256(PaymentEscrow.EscrowStatus.Resolved));
    }
    
    function test_OnlyArbiterCanResolveDispute() public {
        // Create and dispute
        vm.prank(RENTER);
        escrow.createEscrow{value: ESCROW_AMOUNT}(JOB_ID, HOST, ESCROW_AMOUNT, address(0));
        
        vm.prank(HOST);
        escrow.disputeEscrow(JOB_ID);
        
        // Non-arbiter tries to resolve
        vm.prank(RENTER);
        vm.expectRevert("Only arbiter");
        escrow.resolveDispute(JOB_ID, HOST);
    }
    
    function test_RefundEscrow() public {
        // Create escrow
        vm.prank(RENTER);
        escrow.createEscrow{value: ESCROW_AMOUNT}(
            JOB_ID,
            HOST,
            ESCROW_AMOUNT,
            address(0)
        );
        
        uint256 renterBalanceBefore = RENTER.balance;
        
        // Both parties must agree to refund
        vm.prank(HOST);
        escrow.requestRefund(JOB_ID);
        
        vm.prank(RENTER);
        escrow.confirmRefund(JOB_ID);
        
        // Verify refund
        assertEq(RENTER.balance, renterBalanceBefore + ESCROW_AMOUNT);
        assertEq(uint256(escrow.getEscrow(JOB_ID).status), uint256(PaymentEscrow.EscrowStatus.Refunded));
    }
    
    function test_MultiTokenSupport() public {
        // Test with USDC
        vm.startPrank(RENTER);
        
        uint256 usdcAmount = 1000 * 10**6; // 1000 USDC
        usdcToken.approve(address(escrow), usdcAmount);
        
        bytes32 usdcJobId = keccak256("usdc_job");
        escrow.createEscrow(
            usdcJobId,
            HOST,
            usdcAmount,
            address(usdcToken)
        );
        
        assertEq(usdcToken.balanceOf(address(escrow)), usdcAmount);
        
        // Release and verify
        escrow.releaseEscrow(usdcJobId);
        
        uint256 expectedFee = (usdcAmount * ESCROW_FEE_BPS) / 10000;
        uint256 expectedPayment = usdcAmount - expectedFee;
        assertEq(usdcToken.balanceOf(HOST), expectedPayment);
        
        vm.stopPrank();
    }
}
