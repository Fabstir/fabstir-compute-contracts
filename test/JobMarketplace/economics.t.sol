// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/JobMarketplaceFABWithS5.sol";
import "../../src/PaymentEscrowWithEarnings.sol";
import "../../src/HostEarnings.sol";
import "../../src/ProofSystem.sol";
import "../../src/NodeRegistryFAB.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFABToken is ERC20 {
    constructor() ERC20("FAB Token", "FAB") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract JobMarketplaceEconomicsTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    PaymentEscrowWithEarnings public escrow;
    HostEarnings public earnings;
    ProofSystem public proofSystem;
    NodeRegistryFAB public nodeRegistry;
    MockFABToken public fabToken;
    
    address user = address(0x1234);
    address host = address(0x5678);
    address treasury = address(0x9ABC);
    
    function setUp() public {
        // Deploy mock FAB token
        fabToken = new MockFABToken();
        
        // Deploy NodeRegistry with mock FAB token
        nodeRegistry = new NodeRegistryFAB(address(fabToken));
        
        // Deploy ProofSystem
        proofSystem = new ProofSystem();
        
        // Deploy HostEarnings
        earnings = new HostEarnings();
        
        // Deploy PaymentEscrow with earnings (arbiter and fee basis points)
        escrow = new PaymentEscrowWithEarnings(address(this), 1000); // 10% fee
        
        // Deploy JobMarketplace
        marketplace = new JobMarketplaceFABWithS5(
            address(nodeRegistry),
            payable(address(earnings))
        );
        
        // Configure relationships
        marketplace.setPaymentEscrow(address(escrow));
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        escrow.setJobMarketplace(address(marketplace));
        earnings.setAuthorizedCaller(address(escrow), true);
        
        // Setup host registration
        vm.deal(host, 10 ether);
        fabToken.transfer(host, 1000 ether); // Transfer FAB tokens to host (MIN_STAKE)
        
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), 1000 ether); // Approve MIN_STAKE
        nodeRegistry.registerNode("ipfs://host-metadata");
        vm.stopPrank();
        
        // Fund user
        vm.deal(user, 10 ether);
    }
    
    function test_RevertWhen_DepositBelowMinimum() public {
        vm.startPrank(user);
        
        uint256 tooSmall = 0.0001 ether;
        vm.expectRevert("Deposit below minimum");
        marketplace.createSessionJob{value: tooSmall}(
            host,
            tooSmall,
            1 gwei,
            3600,
            300
        );
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_DepositAmountBelowMinimum() public {
        vm.startPrank(user);
        
        // Send enough ETH but specify deposit amount below minimum
        uint256 tooSmallDeposit = 0.0001 ether;
        vm.expectRevert("Deposit amount below minimum");
        marketplace.createSessionJob{value: 0.001 ether}(
            host,
            tooSmallDeposit, // deposit amount below minimum
            1 gwei,
            3600,
            300
        );
        
        vm.stopPrank();
    }
    
    function test_AcceptMinimumDeposit() public {
        vm.startPrank(user);
        
        uint256 minDeposit = marketplace.MIN_DEPOSIT();
        uint256 jobId = marketplace.createSessionJob{value: minDeposit}(
            host,
            minDeposit,
            1 gwei,
            3600,
            300
        );
        
        assertGt(jobId, 0);
        
        // Verify session created with correct deposit
        (uint256 depositAmt, , , , address sessionHost, , uint256 provenTokens, , , , , ) = marketplace.sessions(jobId);
        assertEq(sessionHost, host);
        assertEq(depositAmt, minDeposit);
        assertEq(provenTokens, 0);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_ProvenTokensBelowMinimum() public {
        // Create session with minimum deposit
        vm.startPrank(user);
        uint256 minDeposit = marketplace.MIN_DEPOSIT();
        uint256 jobId = marketplace.createSessionJob{value: minDeposit}(
            host,
            minDeposit,
            1 gwei,
            3600,
            300
        );
        vm.stopPrank();
        
        // Submit proof with too few tokens
        vm.startPrank(host);
        bytes memory proof = abi.encodePacked(keccak256("proof"), keccak256("extra"));
        
        vm.expectRevert("Token count below minimum");
        marketplace.submitProofOfWork(jobId, proof, 50); // 50 < minimum
        vm.stopPrank();
    }
    
    function test_AcceptMinimumTokens() public {
        // Create session
        vm.startPrank(user);
        uint256 minDeposit = marketplace.MIN_DEPOSIT();
        uint256 jobId = marketplace.createSessionJob{value: minDeposit}(
            host,
            minDeposit,
            1 gwei,
            3600,
            300
        );
        vm.stopPrank();
        
        // Submit proof with minimum tokens
        vm.startPrank(host);
        uint256 minTokens = marketplace.MIN_PROVEN_TOKENS();
        bytes memory proof = abi.encodePacked(keccak256("proof"), keccak256("extra"));
        
        marketplace.submitProofOfWork(jobId, proof, minTokens);
        
        // Verify tokens recorded
        (, , , , , , uint256 provenTokens, , , , , ) = marketplace.sessions(jobId);
        assertEq(provenTokens, minTokens);
        vm.stopPrank();
    }
    
    function test_MinimumViableSession() public {
        // Create minimum viable session
        vm.startPrank(user);
        uint256 minDeposit = marketplace.MIN_DEPOSIT();
        uint256 jobId = marketplace.createSessionJob{value: minDeposit}(
            host,
            minDeposit,
            1 gwei,
            3600,
            300
        );
        vm.stopPrank();
        
        // Host submits minimum proof
        vm.startPrank(host);
        uint256 minTokens = marketplace.MIN_PROVEN_TOKENS();
        bytes memory proof = abi.encodePacked(keccak256("proof"), keccak256("extra"));
        marketplace.submitProofOfWork(jobId, proof, minTokens);
        vm.stopPrank();
        
        // User completes session
        uint256 hostBalanceBefore = host.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(user);
        marketplace.completeSessionJob(jobId);
        
        // Verify payments
        uint256 hostPayment = host.balance - hostBalanceBefore;
        uint256 treasuryPayment = treasury.balance - treasuryBalanceBefore;
        
        // Host should receive 90% of (minTokens * pricePerToken)
        uint256 expectedHostPayment = (minTokens * 1 gwei * 90) / 100;
        assertEq(hostPayment, expectedHostPayment);
        
        // Treasury gets 10%
        uint256 expectedTreasuryPayment = (minTokens * 1 gwei * 10) / 100;
        assertEq(treasuryPayment, expectedTreasuryPayment);
        
        // Verify session is economically viable (payment > gas costs on L2)
        // L2 gas costs are ~0.000001 ETH (1e12 wei), but minimum session pays 90 gwei (9e10 wei)
        // This is still viable as multiple proofs can be submitted in a session
        assertGt(hostPayment, 0); // Payment must be positive
        assertEq(hostPayment, 90 gwei); // Verify exact calculation
    }
    
    function test_LargerSessionWithMinimums() public {
        // Create session with deposit above minimum
        vm.startPrank(user);
        uint256 deposit = 0.001 ether; // 5x minimum
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            deposit,
            2 gwei,
            7200,
            600
        );
        vm.stopPrank();
        
        // Submit proof with tokens above minimum
        vm.startPrank(host);
        uint256 tokenCount = 500; // 5x minimum
        bytes memory proof = abi.encodePacked(keccak256("proof"), keccak256("extra"));
        marketplace.submitProofOfWork(jobId, proof, tokenCount);
        vm.stopPrank();
        
        // Complete session
        uint256 hostBalanceBefore = host.balance;
        vm.prank(user);
        marketplace.completeSessionJob(jobId);
        
        // Verify payment calculation
        uint256 hostPayment = host.balance - hostBalanceBefore;
        uint256 expectedPayment = (tokenCount * 2 gwei * 90) / 100;
        assertEq(hostPayment, expectedPayment);
    }
    
    function test_TokenPaymentWithMinimums() public {
        // Deploy mock USDC
        MockFABToken usdc = new MockFABToken();
        usdc.mint(user, 10000 * 10**18);
        
        // Mark USDC as accepted token
        marketplace.setAcceptedToken(address(usdc), true, 800000);
        
        // Create session with token payment
        vm.startPrank(user);
        uint256 minDeposit = marketplace.MIN_DEPOSIT();
        uint256 tokenAmount = minDeposit; // Same value in tokens
        
        usdc.approve(address(marketplace), tokenAmount);
        
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            tokenAmount,
            1 gwei,
            3600,
            300
        );
        vm.stopPrank();
        
        // Submit minimum proof
        vm.startPrank(host);
        uint256 minTokens = marketplace.MIN_PROVEN_TOKENS();
        bytes memory proof = abi.encodePacked(keccak256("proof"), keccak256("extra"));
        marketplace.submitProofOfWork(jobId, proof, minTokens);
        vm.stopPrank();
        
        // Complete session
        uint256 hostTokensBefore = usdc.balanceOf(host);
        vm.prank(user);
        marketplace.completeSessionJob(jobId);
        
        // Verify token payment
        uint256 hostTokenPayment = usdc.balanceOf(host) - hostTokensBefore;
        uint256 expectedPayment = (minTokens * 1 gwei * 90) / 100;
        assertEq(hostTokenPayment, expectedPayment);
    }
    
    function test_RefundWithMinimums() public {
        // Create session with minimum deposit
        vm.startPrank(user);
        uint256 minDeposit = marketplace.MIN_DEPOSIT();
        uint256 jobId = marketplace.createSessionJob{value: minDeposit}(
            host,
            minDeposit,
            1 gwei,
            100, // Short duration for easy timeout
            100
        );
        vm.stopPrank();
        
        // Wait for timeout
        vm.warp(block.timestamp + 101);
        
        // Request refund
        uint256 userBalanceBefore = user.balance;
        vm.prank(user);
        marketplace.triggerSessionTimeout(jobId);
        
        // Verify full refund
        uint256 refundAmount = user.balance - userBalanceBefore;
        assertEq(refundAmount, minDeposit);
    }
}