// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/JobMarketplaceFABWithS5.sol";
import "../../src/HostEarnings.sol";
import "../../src/NodeRegistryFAB.sol";
import "../../src/ProofSystem.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**6); // 1M USDC
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract TreasuryAccumulationTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    HostEarnings public hostEarnings;
    NodeRegistryFAB public nodeRegistry;
    ProofSystem public proofSystem;
    MockUSDC public usdc;
    
    address public treasury = address(0x1234);
    address public user = address(0x5678);
    address public host = address(0x9ABC);
    
    uint256 constant MIN_DEPOSIT = 0.001 ether;
    uint256 constant PRICE_PER_TOKEN = 0.000001 ether;
    uint256 constant TOKENS_TO_PROVE = 1000;
    
    function setUp() public {
        // Deploy mock FAB token
        ERC20 fabToken = new MockUSDC();
        
        // Deploy contracts
        nodeRegistry = new NodeRegistryFAB(address(fabToken));
        hostEarnings = new HostEarnings();
        proofSystem = new ProofSystem();
        marketplace = new JobMarketplaceFABWithS5(
            address(nodeRegistry),
            payable(address(hostEarnings))
        );
        
        // Configure marketplace
        marketplace.setTreasuryAddress(treasury);
        marketplace.setProofSystem(address(proofSystem));
        
        // Deploy and configure USDC
        usdc = new MockUSDC();
        marketplace.setUsdcAddress(address(usdc));
        marketplace.setAcceptedToken(address(usdc), true, 800000); // 0.80 USDC minimum
        
        // Authorize marketplace in HostEarnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        
        // Register host
        vm.startPrank(host);
        fabToken.approve(address(nodeRegistry), 1000 ether);
        deal(address(fabToken), host, 1000 ether);
        nodeRegistry.registerNode("test-region");
        vm.stopPrank();
        
        // Fund user
        vm.deal(user, 10 ether);
        deal(address(usdc), user, 10000 * 10**6); // 10000 USDC
    }
    
    function testETHTreasuryAccumulation() public {
        vm.startPrank(user);
        
        // Create ETH session job
        uint256 deposit = 0.01 ether;
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            deposit,
            PRICE_PER_TOKEN,
            3600,
            100
        );
        
        vm.stopPrank();
        
        // Host submits proof (must be at least 64 bytes for ProofSystem)
        vm.startPrank(host);
        bytes memory proof = abi.encodePacked(
            keccak256("proof1"), // 32 bytes
            keccak256("proof2")  // 32 bytes
        );
        marketplace.submitProofOfWork(jobId, proof, TOKENS_TO_PROVE);
        vm.stopPrank();
        
        // Complete job
        vm.startPrank(user);
        marketplace.completeSessionJob(jobId);
        vm.stopPrank();
        
        // Check treasury accumulation
        uint256 expectedTreasuryFee = (TOKENS_TO_PROVE * PRICE_PER_TOKEN * 10) / 100; // 10% fee
        assertEq(marketplace.accumulatedTreasuryETH(), expectedTreasuryFee, "Treasury ETH not accumulated correctly");
        
        // Treasury withdraws
        uint256 treasuryBalanceBefore = treasury.balance;
        vm.prank(treasury);
        marketplace.withdrawTreasuryETH();
        
        // Verify withdrawal
        assertEq(marketplace.accumulatedTreasuryETH(), 0, "Accumulated ETH not reset");
        assertEq(treasury.balance - treasuryBalanceBefore, expectedTreasuryFee, "Treasury didn't receive ETH");
    }
    
    function testUSDCTreasuryAccumulation() public {
        vm.startPrank(user);
        
        // Approve USDC
        uint256 deposit = 5 * 10**6; // 5 USDC
        usdc.approve(address(marketplace), deposit);
        
        // Create USDC session job
        uint256 jobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            deposit,
            5000, // 0.005 USDC per token
            3600,
            100
        );
        
        vm.stopPrank();
        
        // Host submits proof (must be at least 64 bytes for ProofSystem)
        vm.startPrank(host);
        bytes memory proof = abi.encodePacked(
            keccak256("usdcproof1"), // 32 bytes
            keccak256("usdcproof2")  // 32 bytes
        );
        marketplace.submitProofOfWork(jobId, proof, 1000); // Prove 1000 tokens
        vm.stopPrank();
        
        // Complete job
        vm.startPrank(user);
        marketplace.completeSessionJob(jobId);
        vm.stopPrank();
        
        // Check treasury accumulation
        uint256 expectedTreasuryFee = (1000 * 5000 * 10) / 100; // 10% fee = 0.5 USDC
        assertEq(marketplace.accumulatedTreasuryTokens(address(usdc)), expectedTreasuryFee, "Treasury USDC not accumulated correctly");
        
        // Treasury withdraws
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);
        vm.prank(treasury);
        marketplace.withdrawTreasuryTokens(address(usdc));
        
        // Verify withdrawal
        assertEq(marketplace.accumulatedTreasuryTokens(address(usdc)), 0, "Accumulated USDC not reset");
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, expectedTreasuryFee, "Treasury didn't receive USDC");
    }
    
    function testBatchWithdrawal() public {
        // Create both ETH and USDC jobs
        vm.startPrank(user);
        
        // ETH job
        uint256 ethDeposit = 0.01 ether;
        uint256 ethJobId = marketplace.createSessionJob{value: ethDeposit}(
            host,
            ethDeposit,
            PRICE_PER_TOKEN,
            3600,
            100
        );
        
        // USDC job
        uint256 usdcDeposit = 5 * 10**6; // 5 USDC
        usdc.approve(address(marketplace), usdcDeposit);
        uint256 usdcJobId = marketplace.createSessionJobWithToken(
            host,
            address(usdc),
            usdcDeposit,
            5000,
            3600,
            100
        );
        
        vm.stopPrank();
        
        // Host submits proofs (must be at least 64 bytes for ProofSystem)
        vm.startPrank(host);
        bytes memory ethProof = abi.encodePacked(
            keccak256("ethproof1"), // 32 bytes
            keccak256("ethproof2")  // 32 bytes
        );
        bytes memory usdcProof = abi.encodePacked(
            keccak256("usdcproof1b"), // 32 bytes  
            keccak256("usdcproof2b")  // 32 bytes
        );
        marketplace.submitProofOfWork(ethJobId, ethProof, TOKENS_TO_PROVE);
        marketplace.submitProofOfWork(usdcJobId, usdcProof, 1000);
        vm.stopPrank();
        
        // Complete jobs
        vm.startPrank(user);
        marketplace.completeSessionJob(ethJobId);
        marketplace.completeSessionJob(usdcJobId);
        vm.stopPrank();
        
        // Check accumulations
        uint256 expectedETHFee = (TOKENS_TO_PROVE * PRICE_PER_TOKEN * 10) / 100;
        uint256 expectedUSDCFee = (1000 * 5000 * 10) / 100;
        
        assertEq(marketplace.accumulatedTreasuryETH(), expectedETHFee, "ETH not accumulated");
        assertEq(marketplace.accumulatedTreasuryTokens(address(usdc)), expectedUSDCFee, "USDC not accumulated");
        
        // Batch withdraw
        uint256 treasuryETHBefore = treasury.balance;
        uint256 treasuryUSDCBefore = usdc.balanceOf(treasury);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        vm.prank(treasury);
        marketplace.withdrawAllTreasuryFees(tokens);
        
        // Verify all withdrawn
        assertEq(marketplace.accumulatedTreasuryETH(), 0, "ETH not cleared");
        assertEq(marketplace.accumulatedTreasuryTokens(address(usdc)), 0, "USDC not cleared");
        assertEq(treasury.balance - treasuryETHBefore, expectedETHFee, "ETH not received");
        assertEq(usdc.balanceOf(treasury) - treasuryUSDCBefore, expectedUSDCFee, "USDC not received");
    }
    
    function testOnlyTreasuryCanWithdraw() public {
        // Accumulate some fees
        vm.startPrank(user);
        uint256 deposit = 0.01 ether;
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            deposit,
            PRICE_PER_TOKEN,
            3600,
            100
        );
        vm.stopPrank();
        
        vm.startPrank(host);
        bytes memory proof = abi.encodePacked(
            keccak256("testproof1"), // 32 bytes
            keccak256("testproof2")  // 32 bytes
        );
        marketplace.submitProofOfWork(jobId, proof, TOKENS_TO_PROVE);
        vm.stopPrank();
        
        vm.prank(user);
        marketplace.completeSessionJob(jobId);
        
        // Non-treasury tries to withdraw
        vm.prank(user);
        vm.expectRevert("Only treasury");
        marketplace.withdrawTreasuryETH();
        
        vm.prank(host);
        vm.expectRevert("Only treasury");
        marketplace.withdrawTreasuryETH();
        
        // Treasury can withdraw
        vm.prank(treasury);
        marketplace.withdrawTreasuryETH(); // Should not revert
    }
    
    function testEmergencyWithdrawRespectsAccumulation() public {
        // Accumulate treasury fees
        vm.startPrank(user);
        uint256 deposit = 0.01 ether;
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            deposit,
            PRICE_PER_TOKEN,
            3600,
            100
        );
        vm.stopPrank();
        
        vm.startPrank(host);
        bytes memory proof = abi.encodePacked(
            keccak256("emergproof1"), // 32 bytes
            keccak256("emergproof2")  // 32 bytes
        );
        marketplace.submitProofOfWork(jobId, proof, TOKENS_TO_PROVE);
        vm.stopPrank();
        
        vm.prank(user);
        marketplace.completeSessionJob(jobId);
        
        uint256 accumulatedFees = marketplace.accumulatedTreasuryETH();
        
        // Send extra ETH to contract (simulating stuck funds)
        vm.deal(address(marketplace), address(marketplace).balance + 0.005 ether);
        
        // Emergency withdraw should only take the stuck funds, not accumulated fees
        uint256 treasuryBefore = treasury.balance;
        vm.prank(treasury);
        marketplace.emergencyWithdraw(address(0));
        
        // Should have withdrawn only the stuck 0.005 ether
        assertEq(treasury.balance - treasuryBefore, 0.005 ether, "Wrong amount withdrawn");
        assertEq(marketplace.accumulatedTreasuryETH(), accumulatedFees, "Accumulated fees affected");
    }
}