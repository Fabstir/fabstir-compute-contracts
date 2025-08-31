// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract ProofQueriesTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x2001);
    address public treasury = address(0x3001);
    address public nodeRegistry = address(0x4001);
    address public hostEarnings = address(0x5001);
    
    uint256 constant JOB_ID = 1;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        vm.deal(user, 10 ether);
        vm.deal(host, 10 ether);
        vm.deal(address(marketplace), 10 ether);
    }
    
    function test_GetProofSubmissionsReturnsHistory() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit multiple proofs
        proofSystem.setVerificationResult(true);
        
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof1", 100);
        
        vm.warp(block.timestamp + 1 hours);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof2", 150);
        
        vm.warp(block.timestamp + 1 hours);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof3", 200);
        
        // Get proof submissions
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = 
            marketplace.getProofSubmissions(JOB_ID);
        
        assertEq(proofs.length, 3);
        assertEq(proofs[0].tokensClaimed, 100);
        assertEq(proofs[1].tokensClaimed, 150);
        assertEq(proofs[2].tokensClaimed, 200);
        assertEq(proofs[0].verified, true);
        assertEq(proofs[1].verified, true);
        assertEq(proofs[2].verified, true);
    }
    
    function test_GetProvenTokensReturnsTotal() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Submit proofs
        proofSystem.setVerificationResult(true);
        
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof1", 100);
        
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof2", 200);
        
        // Get proven tokens
        uint256 provenTokens = marketplace.getProvenTokens(JOB_ID);
        assertEq(provenTokens, 300);
    }
    
    function test_ProofQueriesForSessionsWithNoProofs() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Get proof submissions (should be empty)
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = 
            marketplace.getProofSubmissions(JOB_ID);
        assertEq(proofs.length, 0);
        
        // Get proven tokens (should be 0)
        uint256 provenTokens = marketplace.getProvenTokens(JOB_ID);
        assertEq(provenTokens, 0);
    }
    
    function test_ProofQueriesAfterSubmissions() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Check before any proofs
        uint256 tokensBefore = marketplace.getProvenTokens(JOB_ID);
        assertEq(tokensBefore, 0);
        
        // Submit first proof
        proofSystem.setVerificationResult(true);
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof1", 100);
        
        // Check after first proof
        uint256 tokensAfterFirst = marketplace.getProvenTokens(JOB_ID);
        assertEq(tokensAfterFirst, 100);
        
        // Submit second proof
        vm.prank(host);
        marketplace.submitProofOfWork(JOB_ID, "proof2", 150);
        
        // Check after second proof
        uint256 tokensAfterSecond = marketplace.getProvenTokens(JOB_ID);
        assertEq(tokensAfterSecond, 250);
        
        // Verify full history
        JobMarketplaceFABWithS5.ProofSubmission[] memory proofs = 
            marketplace.getProofSubmissions(JOB_ID);
        assertEq(proofs.length, 2);
        assertEq(proofs[0].tokensClaimed, 100);
        assertEq(proofs[1].tokensClaimed, 150);
    }
    
    function test_GetRequiredProofInterval() public {
        // Create session
        vm.prank(user);
        marketplace.createSessionForTesting{value: DEPOSIT}(
            JOB_ID, user, host, DEPOSIT, PRICE_PER_TOKEN
        );
        
        // Get required proof interval
        uint256 interval = marketplace.getRequiredProofInterval(JOB_ID);
        
        // createSessionForTesting sets checkpointInterval to 100
        assertEq(interval, 100);
    }
}