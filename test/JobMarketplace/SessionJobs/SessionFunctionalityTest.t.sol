// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/JobMarketplaceFABWithS5.sol";

contract SessionFunctionalityTest is Test {
    JobMarketplaceFABWithS5 public marketplace;
    address public mockNodeRegistry = address(0x1);
    address payable public mockHostEarnings = payable(address(0x2));
    address public mockToken = address(0x3);
    
    function setUp() public {
        // Deploy with mock addresses
        marketplace = new JobMarketplaceFABWithS5(mockNodeRegistry, mockHostEarnings);
    }
    
    function test_ProofSystemCanBeSet() public {
        address mockProofSystem = address(0x4);
        marketplace.setProofSystem(mockProofSystem);
        
        assertEq(address(marketplace.proofSystem()), mockProofSystem, "Proof system should be set");
    }
    
    function test_GetProvenTokensReturnsZero() public {
        uint256 tokens = marketplace.getProvenTokens(1);
        assertEq(tokens, 0, "Should return 0 for non-existent job");
    }
    
    function test_GetProofSubmissionsReturnsEmpty() public {
        JobMarketplaceFABWithS5.ProofSubmission[] memory submissions = marketplace.getProofSubmissions(1);
        assertEq(submissions.length, 0, "Should return empty array");
    }
    
    function test_SessionRequirementsCalculation() public {
        uint256 pricePerToken = 0.001 ether;
        (uint256 minDeposit, uint256 minProofInterval, uint256 maxDuration) = 
            marketplace.getSessionRequirements(pricePerToken);
        
        // Min deposit is pricePerToken * 100 = 0.1 ether, not 0.01
        assertEq(minDeposit, 0.1 ether, "Min deposit should be 0.1 ether");
        assertEq(minProofInterval, 100, "Min proof interval should be 100");
        assertEq(maxDuration, 365 days, "Max duration should be 365 days");
    }
    
    function test_InterfaceExists() public {
        // Test that IProofSystem interface is accessible
        IProofSystem proofSystem = IProofSystem(address(0));
        assertEq(address(proofSystem), address(0), "Interface should be accessible");
    }
}