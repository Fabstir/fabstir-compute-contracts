// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";
import "../../mocks/ProofSystemMock.sol";

contract PaginationTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    ProofSystemMock public proofSystem;
    
    address public user = address(0x1001);
    address public host = address(0x2001);
    address public otherHost = address(0x2002);
    address public treasury = address(0x3001);
    address public nodeRegistry = address(0x4001);
    address public hostEarnings = address(0x5001);
    
    uint256 constant PRICE_PER_TOKEN = 0.001 ether;
    uint256 constant DEPOSIT = 1 ether;
    
    function setUp() public {
        marketplace = new JobMarketplaceFABWithS5(nodeRegistry, payable(hostEarnings));
        proofSystem = new ProofSystemMock();
        
        marketplace.setProofSystem(address(proofSystem));
        marketplace.setTreasuryAddress(treasury);
        
        vm.deal(user, 100 ether);
        vm.deal(host, 10 ether);
        vm.deal(otherHost, 10 ether);
        vm.deal(address(marketplace), 100 ether);
    }
    
    function test_PaginationWithVariousOffsets() public {
        // Create 10 sessions for host
        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, host, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        // Test offset 0
        (uint256[] memory jobIds, uint256 totalCount) = 
            marketplace.getSessionsPaginated(host, 0, 3);
        assertEq(jobIds.length, 3);
        assertEq(totalCount, 10);
        assertEq(jobIds[0], 1);
        assertEq(jobIds[1], 2);
        assertEq(jobIds[2], 3);
        
        // Test offset 3
        (jobIds, totalCount) = marketplace.getSessionsPaginated(host, 3, 3);
        assertEq(jobIds.length, 3);
        assertEq(totalCount, 10);
        assertEq(jobIds[0], 4);
        assertEq(jobIds[1], 5);
        assertEq(jobIds[2], 6);
        
        // Test offset 8
        (jobIds, totalCount) = marketplace.getSessionsPaginated(host, 8, 3);
        assertEq(jobIds.length, 2); // Only 2 remaining
        assertEq(totalCount, 10);
        assertEq(jobIds[0], 9);
        assertEq(jobIds[1], 10);
    }
    
    function test_PaginationWithDifferentLimits() public {
        // Create 8 sessions for host
        for (uint256 i = 1; i <= 8; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, host, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        // Test limit 1
        (uint256[] memory jobIds, uint256 totalCount) = 
            marketplace.getSessionsPaginated(host, 0, 1);
        assertEq(jobIds.length, 1);
        assertEq(totalCount, 8);
        assertEq(jobIds[0], 1);
        
        // Test limit 5
        (jobIds, totalCount) = marketplace.getSessionsPaginated(host, 0, 5);
        assertEq(jobIds.length, 5);
        assertEq(totalCount, 8);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(jobIds[i], i + 1);
        }
        
        // Test limit 10 (more than total)
        (jobIds, totalCount) = marketplace.getSessionsPaginated(host, 0, 10);
        assertEq(jobIds.length, 8);
        assertEq(totalCount, 8);
    }
    
    function test_PaginationWhenOffsetGreaterThanTotal() public {
        // Create 5 sessions for host
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, host, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        // Test offset beyond total
        (uint256[] memory jobIds, uint256 totalCount) = 
            marketplace.getSessionsPaginated(host, 10, 5);
        assertEq(jobIds.length, 0);
        assertEq(totalCount, 5);
        
        // Test offset exactly at total
        (jobIds, totalCount) = marketplace.getSessionsPaginated(host, 5, 5);
        assertEq(jobIds.length, 0);
        assertEq(totalCount, 5);
    }
    
    function test_PaginationReturnsCorrectTotalCount() public {
        // Create sessions for different hosts
        for (uint256 i = 1; i <= 7; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, host, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        for (uint256 i = 8; i <= 10; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, otherHost, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        // Check total count for host
        (, uint256 totalCount) = marketplace.getSessionsPaginated(host, 0, 1);
        assertEq(totalCount, 7);
        
        // Check total count for otherHost
        (, totalCount) = marketplace.getSessionsPaginated(otherHost, 0, 1);
        assertEq(totalCount, 3);
        
        // Check with different pagination params (total should stay same)
        (, totalCount) = marketplace.getSessionsPaginated(host, 3, 2);
        assertEq(totalCount, 7);
    }
    
    function test_PaginationForHostWithManySessions() public {
        // Create 25 sessions for host
        for (uint256 i = 1; i <= 25; i++) {
            vm.prank(user);
            marketplace.createSessionForTesting{value: DEPOSIT}(
                i, user, host, DEPOSIT, PRICE_PER_TOKEN
            );
        }
        
        // Page through all sessions
        uint256 pageSize = 5;
        uint256[] memory allJobIds = new uint256[](25);
        uint256 index = 0;
        
        for (uint256 offset = 0; offset < 25; offset += pageSize) {
            (uint256[] memory jobIds, uint256 totalCount) = 
                marketplace.getSessionsPaginated(host, offset, pageSize);
            
            assertEq(totalCount, 25);
            
            // Copy to full array
            for (uint256 i = 0; i < jobIds.length; i++) {
                allJobIds[index++] = jobIds[i];
            }
        }
        
        // Verify we got all job IDs in order
        assertEq(index, 25);
        for (uint256 i = 0; i < 25; i++) {
            assertEq(allJobIds[i], i + 1);
        }
    }
}