// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/JobMarketplaceFABWithS5.sol";
import "../../src/ProofSystem.sol";
import "../mocks/MockERC20.sol";

contract ProofJobIntegrationTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystem public proofSystem;
    MockERC20 public usdcToken;
    
    address public host = address(0x1);
    address public renter = address(0x2);
    address public nodeRegistry = address(0x3);
    address payable public hostEarnings = payable(address(0x4));
    
    function setUp() public {
        // Deploy ProofSystem
        proofSystem = new ProofSystem();
        
        // Deploy USDC token for payments
        usdcToken = new MockERC20("USDC", "USDC", 6);
        
        // Deploy JobMarketplace with required dependencies
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, hostEarnings);
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setUsdcAddress(address(usdcToken));
        
        // Setup balances
        usdcToken.mint(renter, 1000 * 10**6); // 1000 USDC
        vm.prank(renter);
        usdcToken.approve(address(marketplace), 1000 * 10**6);
        
        // Give ETH for gas and payments
        vm.deal(host, 1 ether);
        vm.deal(renter, 1 ether);
        vm.deal(address(marketplace), 10 ether);
    }
    
    function test_JobMarketplaceCallsProofSystem() public {
        // Create session job
        uint256 jobId = 1;
        uint256 deposit = 10 * 10**6;
        uint256 pricePerToken = 10000; // 0.01 USDC per token
        
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, deposit, pricePerToken);
        
        // Submit proof that should be verified by ProofSystem
        bytes memory proof = new bytes(64);
        proof[0] = 0x01;
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, proof, 100);
        
        // Get session details to verify - access sessions mapping directly
        (,,,,,, uint256 provenTokens,,,,,) = marketplace.sessions(jobId);
        assertEq(provenTokens, 50, "Tokens should be updated");
    }
    
    function test_ProofRejectionAffectsSession() public {
        uint256 jobId = 2;
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, 10 * 10**6, 10000);
        
        // Submit invalid proof (too short)
        bytes memory invalidProof = new bytes(32);
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, invalidProof, 100);
        
        // Verify tokens NOT updated
        (,,,,,, uint256 provenTokens,,,,,) = marketplace.sessions(jobId);
        assertEq(provenTokens, 0, "Tokens should not be updated for invalid proof");
    }
    
    function test_VerifiedProofsUpdateTokens() public {
        uint256 jobId = 3;
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, 10 * 10**6, 10000);
        
        // Submit valid proof
        bytes memory validProof = new bytes(64);
        validProof[0] = 0x02;
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, validProof, 100);
        
        // Verify tokens updated correctly
        (,,,,,, uint256 provenTokens,,,,,) = marketplace.sessions(jobId);
        assertEq(provenTokens, 75, "Tokens should match claim");
    }
    
    function test_ProofSystemCanBeUpdated() public {
        // Deploy new ProofSystem
        ProofSystem newProofSystem = new ProofSystem();
        
        // Update marketplace
        marketplace.setProofSystem(address(newProofSystem));
        
        // Create session
        uint256 jobId = 4;
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, 10 * 10**6, 10000);
        
        // Submit proof to new system
        bytes memory proof = new bytes(64);
        proof[0] = 0x03;
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, proof, 30);
        
        // Verify new system was used
        (,,,,,, uint256 provenTokens,,,,,) = marketplace.sessions(jobId);
        assertEq(provenTokens, 30, "New proof system should verify");
    }
    
    function test_MultipleProofsAccumulateTokens() public {
        uint256 jobId = 5;
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, 10 * 10**6, 10000);
        
        // Submit first proof
        bytes memory proof1 = new bytes(64);
        proof1[0] = 0x04;
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, proof1, 25);
        
        // Submit second proof
        bytes memory proof2 = new bytes(64);
        proof2[0] = 0x05;
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, proof2, 30);
        
        // Verify accumulated tokens
        (,,,,,, uint256 provenTokens,,,,,) = marketplace.sessions(jobId);
        assertEq(provenTokens, 55, "Tokens should accumulate");
    }
    
    function test_InvalidProofSystemAddressReverts() public {
        vm.expectRevert("Invalid proof system");
        marketplace.setProofSystem(address(0));
    }
    
    function test_ProofRecordedInSubmissions() public {
        uint256 jobId = 6;
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, 10 * 10**6, 10000);
        
        bytes memory proof = new bytes(64);
        proof[0] = 0x06;
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, proof, 40);
        
        // Get proof submissions
        JobMarketplaceFABWithS5.ProofSubmission[] memory submissions = marketplace.getProofSubmissions(jobId);
        assertEq(submissions.length, 1, "Should have one submission");
        assertEq(submissions[0].tokensClaimed, 40, "Should record tokens");
        assertTrue(submissions[0].verified, "Should be marked verified");
    }
    
    function test_UnverifiedProofNotRecorded() public {
        uint256 jobId = 7;
        vm.prank(renter);
        marketplace.createSessionForTesting(jobId, renter, host, 10 * 10**6, 10000);
        
        // Submit invalid proof (too short)
        bytes memory proof = new bytes(32);
        
        vm.prank(host);
        marketplace.submitProofOfWork(jobId, proof, 100);
        
        // Should not record failed proof
        JobMarketplaceFABWithS5.ProofSubmission[] memory submissions = marketplace.getProofSubmissions(jobId);
        assertEq(submissions.length, 0, "Failed proof should not be recorded");
    }
}