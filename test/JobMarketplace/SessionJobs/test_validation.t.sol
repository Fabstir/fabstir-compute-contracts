// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../../src/NodeRegistryFAB.sol";

contract TestValidation is Test {
    JobMarketplaceFABWithS5 public marketplace;
    NodeRegistryFAB public nodeRegistry;
    
    address public user = address(0x1);
    address public host = address(0x2);
    
    function setUp() public {
        nodeRegistry = new NodeRegistryFAB();
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(0x999)));
        
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);
        
        vm.prank(host);
        nodeRegistry.registerNodeSimple{value: 10 ether}("host-metadata");
    }
    
    function test_Validation_AllInputs() public {
        vm.startPrank(user);
        
        // Test all zero values
        vm.expectRevert("Deposit must be positive");
        marketplace.createSessionJob{value: 0}(
            host,
            0,
            0,
            0,
            0
        );
        
        // Test zero price per token
        vm.expectRevert("Price per token must be positive");
        marketplace.createSessionJob{value: 1 ether}(
            host,
            1 ether,
            0,
            1 days,
            1000
        );
        
        // Test zero duration
        vm.expectRevert("Duration must be positive");
        marketplace.createSessionJob{value: 1 ether}(
            host,
            1 ether,
            0.001 ether,
            0,
            1000
        );
        
        vm.stopPrank();
    }
    
    function test_Validation_EdgeCases() public {
        vm.startPrank(user);
        
        // Test maximum values
        uint256 maxDeposit = 1000 ether;
        vm.expectRevert("Deposit too large");
        marketplace.createSessionJob{value: maxDeposit + 1}(
            host,
            maxDeposit + 1,
            0.001 ether,
            365 days,
            1000
        );
        
        // Test maximum duration
        vm.expectRevert("Duration too long");
        marketplace.createSessionJob{value: 10 ether}(
            host,
            10 ether,
            0.001 ether,
            366 days, // Over 1 year
            1000
        );
        
        vm.stopPrank();
    }
    
    function test_Validation_RequirementCalculations() public {
        // Test getSessionRequirements function
        (
            uint256 minDeposit,
            uint256 minProofInterval,
            uint256 maxDuration
        ) = marketplace.getSessionRequirements(0.001 ether);
        
        // Check reasonable values
        assertGt(minDeposit, 0);
        assertGt(minProofInterval, 0);
        assertGt(maxDuration, 0);
        assertLe(maxDuration, 365 days);
    }
    
    function test_Validation_ParameterBounds() public {
        vm.startPrank(user);
        
        // Test minimum viable session
        uint256 minDeposit = 0.01 ether;
        uint256 jobId = marketplace.createSessionJob{value: minDeposit}(
            host,
            minDeposit,
            0.00001 ether, // Very small price per token
            1 hours, // Short duration
            100 // Min proof interval
        );
        assertTrue(jobId > 0);
        
        // Test maximum viable session
        uint256 maxDeposit = 1000 ether;
        uint256 jobId2 = marketplace.createSessionJob{value: maxDeposit}(
            host,
            maxDeposit,
            1 ether, // High price per token
            365 days, // Max duration
            1000000 // Max proof interval
        );
        assertTrue(jobId2 > jobId);
        
        vm.stopPrank();
    }
    
    function test_Validation_DepositMatchesValue() public {
        vm.startPrank(user);
        
        // Value sent doesn't match deposit parameter
        vm.expectRevert("Insufficient deposit");
        marketplace.createSessionJob{value: 5 ether}(
            host,
            10 ether, // Deposit higher than value
            0.001 ether,
            7 days,
            1000
        );
        
        vm.stopPrank();
    }
    
    function test_Validation_MinimumTokens() public {
        vm.startPrank(user);
        
        // Deposit too small for even minimum tokens
        uint256 tinyDeposit = 0.0001 ether;
        uint256 highPrice = 0.001 ether;
        
        vm.expectRevert("Deposit covers less than minimum tokens");
        marketplace.createSessionJob{value: tinyDeposit}(
            host,
            tinyDeposit,
            highPrice, // Only covers 0.1 tokens
            7 days,
            100
        );
        
        vm.stopPrank();
    }
    
    function test_Validation_ConsistencyChecks() public {
        vm.startPrank(user);
        
        // Price per token vs deposit vs proof interval consistency
        uint256 deposit = 1 ether;
        uint256 pricePerToken = 0.01 ether; // 100 tokens max
        uint256 proofInterval = 50; // Every 50 tokens
        
        uint256 jobId = marketplace.createSessionJob{value: deposit}(
            host,
            deposit,
            pricePerToken,
            7 days,
            proofInterval
        );
        
        // Should create at least 2 checkpoints (100/50)
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        uint256 maxTokens = session.depositAmount / session.pricePerToken;
        uint256 expectedCheckpoints = maxTokens / session.checkpointInterval;
        assertGe(expectedCheckpoints, 1);
        
        vm.stopPrank();
    }
}