// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../../src/NodeRegistryFAB.sol";

contract TestProofRequirements is Test {
    JobMarketplaceFABWithS5 public marketplace;
    NodeRegistryFAB public nodeRegistry;
    
    address public user = address(0x1);
    address public host = address(0x2);
    
    uint256 constant DEPOSIT = 10 ether;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant MAX_DURATION = 7 days;
    
    event SessionProofRequirementSet(
        uint256 indexed jobId,
        uint256 checkpointInterval
    );
    
    function setUp() public {
        nodeRegistry = new NodeRegistryFAB();
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(0x999)));
        
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);
        
        vm.prank(host);
        nodeRegistry.registerNodeSimple{value: 10 ether}("host-metadata");
    }
    
    function test_ProofRequirements_IntervalValidation() public {
        vm.startPrank(user);
        
        // Valid interval
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            1000 // Valid interval
        );
        assertTrue(jobId > 0);
        
        vm.stopPrank();
    }
    
    function test_ProofRequirements_MinimumInterval() public {
        vm.startPrank(user);
        
        // Too small interval
        vm.expectRevert("Proof interval too small");
        marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            99 // Below minimum (assume 100)
        );
        
        // Minimum interval should work
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            100 // Minimum
        );
        assertTrue(jobId > 0);
        
        vm.stopPrank();
    }
    
    function test_ProofRequirements_CheckpointConfiguration() public {
        vm.prank(user);
        
        uint256 checkpointInterval = 5000;
        
        // Expect event with checkpoint interval
        vm.expectEmit(true, false, false, true);
        emit SessionProofRequirementSet(1, checkpointInterval);
        
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            checkpointInterval
        );
        
        // Verify stored correctly
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        assertEq(session.checkpointInterval, checkpointInterval);
    }
    
    function test_ProofRequirements_MaxInterval() public {
        vm.startPrank(user);
        
        // Very large interval (should have upper bound)
        vm.expectRevert("Proof interval too large");
        marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            1000001 // Over max (assume 1M tokens)
        );
        
        // Max interval should work
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            1000000 // Max
        );
        assertTrue(jobId > 0);
        
        vm.stopPrank();
    }
    
    function test_ProofRequirements_ZeroInterval() public {
        vm.startPrank(user);
        
        // Zero interval means no proofs required
        vm.expectRevert("Proof interval required");
        marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            0
        );
        
        vm.stopPrank();
    }
    
    function test_ProofRequirements_RelativeToDeposit() public {
        vm.startPrank(user);
        
        // Interval should be reasonable relative to max tokens from deposit
        uint256 smallDeposit = 0.1 ether;
        uint256 pricePerToken = 0.001 ether;
        uint256 maxTokens = smallDeposit / pricePerToken; // 100 tokens
        
        // Interval larger than max possible tokens
        vm.expectRevert("Interval exceeds max tokens");
        marketplace.createSessionJob{value: smallDeposit}(
            host,
            smallDeposit,
            pricePerToken,
            MAX_DURATION,
            200 // More than 100 tokens possible
        );
        
        vm.stopPrank();
    }
}