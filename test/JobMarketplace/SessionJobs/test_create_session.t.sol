// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../../src/NodeRegistryFAB.sol";

contract TestCreateSession is Test {
    JobMarketplaceFABWithS5 public marketplace;
    NodeRegistryFAB public nodeRegistry;
    
    address public user = address(0x1);
    address public host = address(0x2);
    
    uint256 constant DEPOSIT = 10 ether;
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant MAX_DURATION = 7 days;
    uint256 constant PROOF_INTERVAL = 1000; // tokens
    
    event SessionJobCreated(
        uint256 indexed jobId,
        address indexed user,
        address indexed host,
        uint256 deposit,
        uint256 pricePerToken,
        uint256 maxDuration
    );
    
    function setUp() public {
        nodeRegistry = new NodeRegistryFAB();
        marketplace = new JobMarketplaceFABWithS5(address(nodeRegistry), payable(address(0x999)));
        
        // Fund users
        vm.deal(user, 100 ether);
        vm.deal(host, 100 ether);
        
        // Register host as node
        vm.prank(host);
        nodeRegistry.registerNodeSimple{value: 10 ether}("host-metadata");
    }
    
    function test_CreateSession_Success() public {
        vm.startPrank(user);
        
        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, user, host, DEPOSIT, PRICE_PER_TOKEN, MAX_DURATION);
        
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        assertEq(jobId, 1);
        vm.stopPrank();
    }
    
    function test_CreateSession_JobIdGeneration() public {
        vm.startPrank(user);
        
        uint256 jobId1 = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        uint256 jobId2 = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        assertEq(jobId1, 1);
        assertEq(jobId2, 2);
        assertTrue(jobId2 > jobId1);
        
        vm.stopPrank();
    }
    
    function test_CreateSession_EventEmission() public {
        vm.startPrank(user);
        
        // Check all event parameters
        vm.expectEmit(true, true, true, true);
        emit SessionJobCreated(1, user, host, DEPOSIT, PRICE_PER_TOKEN, MAX_DURATION);
        
        marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        vm.stopPrank();
    }
    
    function test_CreateSession_StorageCorrect() public {
        vm.prank(user);
        uint256 jobId = marketplace.createSessionJob{value: DEPOSIT}(
            host,
            DEPOSIT,
            PRICE_PER_TOKEN,
            MAX_DURATION,
            PROOF_INTERVAL
        );
        
        // Check session details stored correctly
        JobMarketplaceFABWithS5.SessionDetails memory session = marketplace.sessions(jobId);
        
        assertEq(session.depositAmount, DEPOSIT);
        assertEq(session.pricePerToken, PRICE_PER_TOKEN);
        assertEq(session.maxDuration, MAX_DURATION);
        assertEq(session.assignedHost, host);
        assertEq(uint(session.status), uint(JobMarketplaceFABWithS5.SessionStatus.Active));
        assertEq(session.checkpointInterval, PROOF_INTERVAL);
        assertTrue(session.sessionStartTime > 0);
        
        // Check job type is Session
        assertEq(uint(marketplace.jobTypes(jobId)), uint(JobMarketplaceFABWithS5.JobType.Session));
    }
}