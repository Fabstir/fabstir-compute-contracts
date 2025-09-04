// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/JobMarketplaceFABWithS5.sol";
import "../../src/HostEarnings.sol";
import "../../src/NodeRegistryFAB.sol";
import "../../src/ProofSystem.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HostEarningsAccumulationTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    HostEarnings public hostEarnings;
    NodeRegistryFAB public nodeRegistry;
    ProofSystem public proofSystem;
    
    address constant HOST = address(0x1234);
    address constant USER = address(0x5678);
    address constant TREASURY = address(0x9ABC);
    
    uint256 constant MIN_STAKE = 1000 ether; // FAB tokens
    uint256 constant SESSION_DEPOSIT = 0.005 ether;
    uint256 constant PRICE_PER_TOKEN = 5000 gwei;
    uint256 constant TOKENS_TO_PROVE = 1000;
    
    function setUp() public {
        // Deploy contracts
        address FAB_TOKEN = address(0xFAB);  // Mock FAB token for testing
        nodeRegistry = new NodeRegistryFAB(FAB_TOKEN);
        hostEarnings = new HostEarnings();
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(hostEarnings)));
        proofSystem = new ProofSystem();
        
        // Configure marketplace
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(TREASURY);
        
        // Authorize marketplace to credit earnings
        hostEarnings.setAuthorizedCaller(address(marketplace), true);
        
        // Mock FAB token and approve for host registration
        // For simplicity, we'll skip actual FAB token interaction
        // and directly set the host as registered in storage
        vm.deal(HOST, 10 ether);
        
        // Mock host registration (bypass FAB requirement for test)
        vm.store(
            address(nodeRegistry),
            keccak256(abi.encode(HOST, uint256(0))), // nodes mapping slot for HOST
            bytes32(uint256(uint160(HOST))) // Set operator to HOST
        );
        vm.store(
            address(nodeRegistry),
            bytes32(uint256(keccak256(abi.encode(HOST, uint256(0)))) + 1), // stakedAmount slot
            bytes32(MIN_STAKE)
        );
        vm.store(
            address(nodeRegistry),
            bytes32(uint256(keccak256(abi.encode(HOST, uint256(0)))) + 2), // active slot
            bytes32(uint256(1)) // Set active = true
        );
        
        // Fund user
        vm.deal(USER, 10 ether);
    }
    
    function testHostEarningsAccumulation() public {
        // Create 3 session jobs to demonstrate accumulation
        uint256[] memory jobIds = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(USER);
            jobIds[i] = marketplace.createSessionJob{value: SESSION_DEPOSIT}(
                HOST,
                SESSION_DEPOSIT,
                PRICE_PER_TOKEN,
                1 hours,
                100 // proof interval
            );
            
            // Host submits proof
            bytes memory proof = abi.encodePacked(keccak256("proof"), i);
            vm.prank(HOST);
            marketplace.submitProofOfWork(jobIds[i], proof, TOKENS_TO_PROVE);
            
            // User completes session
            vm.prank(USER);
            marketplace.completeSessionJob(jobIds[i]);
        }
        
        // Check host earnings accumulated in HostEarnings contract
        uint256 hostBalance = hostEarnings.getBalance(HOST, address(0)); // ETH
        uint256 expectedPerJob = (TOKENS_TO_PROVE * PRICE_PER_TOKEN * 90) / 100; // 90% to host
        uint256 expectedTotal = expectedPerJob * 3;
        
        assertEq(hostBalance, expectedTotal, "Host earnings not accumulated correctly");
        
        // Verify host hasn't received direct payment
        assertEq(HOST.balance, 10 ether - MIN_STAKE, "Host shouldn't receive direct payment");
        
        // Host withdraws all accumulated earnings in one transaction
        uint256 hostBalanceBefore = HOST.balance;
        vm.prank(HOST);
        hostEarnings.withdrawAll(address(0)); // Withdraw ETH
        
        // Verify host received all accumulated earnings
        assertEq(HOST.balance, hostBalanceBefore + expectedTotal, "Host didn't receive accumulated earnings");
        assertEq(hostEarnings.getBalance(HOST, address(0)), 0, "Host balance not cleared after withdrawal");
        
        // Log gas savings
        console.log("Accumulated earnings for 3 jobs: ", expectedTotal);
        console.log("Single withdrawal transaction instead of 3 separate transfers");
        console.log("Estimated gas saved: ~40,000 gas per job (2 jobs) = 80,000 gas");
    }
    
    function testMultipleHostsAccumulation() public {
        address host2 = address(0x2222);
        
        // Register second host (mock FAB staking)
        vm.deal(host2, 10 ether);
        
        // Mock host2 registration
        vm.store(
            address(nodeRegistry),
            keccak256(abi.encode(host2, uint256(0))),
            bytes32(uint256(uint160(host2)))
        );
        vm.store(
            address(nodeRegistry),
            bytes32(uint256(keccak256(abi.encode(host2, uint256(0)))) + 1),
            bytes32(MIN_STAKE)
        );
        vm.store(
            address(nodeRegistry),
            bytes32(uint256(keccak256(abi.encode(host2, uint256(0)))) + 2),
            bytes32(uint256(1))
        );
        
        // Create jobs for different hosts
        vm.startPrank(USER);
        uint256 job1 = marketplace.createSessionJob{value: SESSION_DEPOSIT}(
            HOST, SESSION_DEPOSIT, PRICE_PER_TOKEN, 1 hours, 100
        );
        uint256 job2 = marketplace.createSessionJob{value: SESSION_DEPOSIT}(
            host2, SESSION_DEPOSIT, PRICE_PER_TOKEN, 1 hours, 100
        );
        vm.stopPrank();
        
        // Submit proofs and complete
        bytes memory proof1 = abi.encodePacked(keccak256("proof1"));
        bytes memory proof2 = abi.encodePacked(keccak256("proof2"));
        
        vm.prank(HOST);
        marketplace.submitProofOfWork(job1, proof1, TOKENS_TO_PROVE);
        
        vm.prank(host2);
        marketplace.submitProofOfWork(job2, proof2, TOKENS_TO_PROVE);
        
        vm.prank(USER);
        marketplace.completeSessionJob(job1);
        vm.prank(USER);
        marketplace.completeSessionJob(job2);
        
        // Verify each host has their own accumulated earnings
        uint256 expectedPayment = (TOKENS_TO_PROVE * PRICE_PER_TOKEN * 90) / 100;
        assertEq(hostEarnings.getBalance(HOST, address(0)), expectedPayment, "Host1 earnings incorrect");
        assertEq(hostEarnings.getBalance(host2, address(0)), expectedPayment, "Host2 earnings incorrect");
        
        // Each host can withdraw independently
        vm.prank(HOST);
        hostEarnings.withdrawAll(address(0));
        
        vm.prank(host2);
        hostEarnings.withdrawAll(address(0));
        
        // Verify withdrawals
        assertEq(hostEarnings.getBalance(HOST, address(0)), 0, "Host1 balance not cleared");
        assertEq(hostEarnings.getBalance(host2, address(0)), 0, "Host2 balance not cleared");
    }
    
    function testDirectPaymentFallback() public {
        // Remove HostEarnings to test fallback
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(0)));
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(TREASURY);
        
        // Create and complete a session job
        vm.prank(USER);
        uint256 jobId = marketplace.createSessionJob{value: SESSION_DEPOSIT}(
            HOST, SESSION_DEPOSIT, PRICE_PER_TOKEN, 1 hours, 100
        );
        
        bytes memory proof = abi.encodePacked(keccak256("proof"));
        vm.prank(HOST);
        marketplace.submitProofOfWork(jobId, proof, TOKENS_TO_PROVE);
        
        uint256 hostBalanceBefore = HOST.balance;
        vm.prank(USER);
        marketplace.completeSessionJob(jobId);
        
        // Verify host received direct payment (fallback behavior)
        uint256 expectedPayment = (TOKENS_TO_PROVE * PRICE_PER_TOKEN * 90) / 100;
        assertEq(HOST.balance, hostBalanceBefore + expectedPayment, "Host didn't receive direct payment");
    }
}