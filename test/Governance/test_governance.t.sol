// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Governance} from "../../src/Governance.sol";
import {GovernanceToken} from "../../src/GovernanceToken.sol";
import {JobMarketplaceMock} from "../mocks/JobMarketplaceMock.sol";
import {ProofSystemMock} from "../mocks/ProofSystemMock.sol";
import {TestSetup} from "../TestSetup.t.sol";

contract GovernanceTest is TestSetup {
    Governance public governance;
    GovernanceToken public govToken;
    
    // Test accounts
    address public voter1 = address(0x1234);
    address public voter2 = address(0x5678);
    address public voter3 = address(0x9ABC);
    address public emergencyAdmin = address(0xDEF0);
    
    // Proposal types
    enum ProposalType { ParameterUpdate, ContractUpgrade, Emergency }
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        ProposalType proposalType,
        string description
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    
    event ProposalQueued(
        uint256 indexed proposalId,
        uint256 executionTime
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId
    );
    
    event ProposalCancelled(
        uint256 indexed proposalId
    );
    
    event ParameterUpdated(
        address indexed contract_,
        string parameter,
        uint256 oldValue,
        uint256 newValue
    );
    
    event EmergencyActionExecuted(
        address indexed executor,
        string action
    );
    
    function setUp() public override {
        super.setUp();
        
        // Deploy governance token
        govToken = new GovernanceToken("Fabstir Governance", "FABGOV", 1000000e18);
        
        // Deploy ProofSystem (needed for complete setup)
        ProofSystemMock proofSystem = new ProofSystemMock();
        
        // Deploy Governance
        governance = new Governance(
            address(govToken),
            address(nodeRegistry),
            address(jobMarketplace),
            address(paymentEscrow),
            address(reputationSystem),
            address(proofSystem)
        );
        
        // Grant governance roles to contracts
        nodeRegistry.grantRole(nodeRegistry.GOVERNANCE_ROLE(), address(governance));
        jobMarketplace.grantRole(jobMarketplace.GOVERNANCE_ROLE(), address(governance));
        paymentEscrow.grantRole(paymentEscrow.GOVERNANCE_ROLE(), address(governance));
        reputationSystem.grantRole(reputationSystem.GOVERNANCE_ROLE(), address(governance));
        
        // Setup emergency admin
        governance.grantRole(governance.EMERGENCY_ROLE(), emergencyAdmin);
        
        // Distribute governance tokens
        govToken.transfer(voter1, 100000e18);
        govToken.transfer(voter2, 150000e18);
        govToken.transfer(voter3, 50000e18);
        
        // Voters delegate to themselves
        vm.prank(voter1);
        govToken.delegate(voter1);
        vm.prank(voter2);
        govToken.delegate(voter2);
        vm.prank(voter3);
        govToken.delegate(voter3);
        
        // Advance block for delegation to take effect
        vm.roll(block.number + 1);
    }
    
    function test_CreateParameterUpdateProposal() public {
        // Create proposal to update minimum stake
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(nodeRegistry),
            functionSelector: nodeRegistry.setMinimumStake.selector,
            parameterName: "minimumStake",
            newValue: 200e18
        });
        
        vm.prank(voter1);
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated(
            1,
            voter1,
            ProposalType.ParameterUpdate,
            "Increase minimum stake to 200 tokens"
        );
        
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Increase minimum stake to 200 tokens"
        );
        
        assertEq(proposalId, 1);
        
        // Check proposal details
        (
            address proposer,
            uint256 startBlock,
            uint256 endBlock,
            uint256 forVotes,
            uint256 againstVotes,
            bool executed,
            bool cancelled
        ) = governance.getProposal(proposalId);
        
        assertEq(proposer, voter1);
        assertEq(startBlock, block.number + governance.votingDelay());
        assertEq(endBlock, startBlock + governance.votingPeriod());
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertFalse(executed);
        assertFalse(cancelled);
    }
    
    function test_VoteOnProposal() public {
        // Create proposal
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(jobMarketplace),
            functionSelector: jobMarketplace.setMaxJobDuration.selector,
            parameterName: "maxJobDuration",
            newValue: 14 days
        });
        
        vm.prank(voter1);
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Extend max job duration to 14 days"
        );
        
        // Advance to voting period
        vm.roll(block.number + governance.votingDelay() + 1);
        
        // Voter1 votes for
        vm.prank(voter1);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(proposalId, voter1, true, 100000e18);
        governance.castVote(proposalId, true);
        
        // Voter2 votes against
        vm.prank(voter2);
        vm.expectEmit(true, true, true, true);
        emit VoteCast(proposalId, voter2, false, 150000e18);
        governance.castVote(proposalId, false);
        
        // Check vote counts
        (,,,uint256 forVotes, uint256 againstVotes,,) = governance.getProposal(proposalId);
        assertEq(forVotes, 100000e18);
        assertEq(againstVotes, 150000e18);
        
        // Cannot vote twice
        vm.prank(voter1);
        vm.expectRevert("Already voted");
        governance.castVote(proposalId, true);
    }
    
    function test_QueueAndExecuteProposal() public {
        // Create and pass proposal
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(paymentEscrow),
            functionSelector: paymentEscrow.setFeePercentage.selector,
            parameterName: "feePercentage",
            newValue: 250 // 2.5%
        });
        
        vm.prank(voter1);
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Update fee to 2.5%"
        );
        
        // Vote (majority for)
        vm.roll(block.number + governance.votingDelay() + 1);
        vm.prank(voter1);
        governance.castVote(proposalId, true);
        vm.prank(voter2);
        governance.castVote(proposalId, true);
        
        // Advance past voting period
        vm.roll(block.number + governance.votingPeriod() + 1);
        
        // Queue proposal
        vm.expectEmit(true, true, true, true);
        emit ProposalQueued(proposalId, block.timestamp + governance.executionDelay());
        governance.queue(proposalId);
        
        // Cannot execute immediately
        vm.expectRevert("Execution delay not met");
        governance.execute(proposalId);
        
        // Advance time
        vm.warp(block.timestamp + governance.executionDelay() + 1);
        
        // Execute proposal
        vm.expectEmit(true, true, true, true);
        emit ParameterUpdated(
            address(paymentEscrow),
            "feePercentage",
            200, // old value
            250  // new value
        );
        vm.expectEmit(true, true, true, true);
        emit ProposalExecuted(proposalId);
        
        governance.execute(proposalId);
        
        // Verify parameter was updated
        assertEq(paymentEscrow.feePercentage(), 250);
    }
    
    function test_ProposalQuorumRequired() public {
        // Create proposal
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(reputationSystem),
            functionSelector: reputationSystem.setDecayRate.selector,
            parameterName: "decayRate",
            newValue: 95 // 95%
        });
        
        vm.prank(voter1);
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Adjust reputation decay rate"
        );
        
        // Only voter3 votes (not enough for quorum)
        vm.roll(block.number + governance.votingDelay() + 1);
        vm.prank(voter3);
        governance.castVote(proposalId, true);
        
        // Advance past voting period
        vm.roll(block.number + governance.votingPeriod() + 1);
        
        // Should fail quorum
        vm.expectRevert("Quorum not reached");
        governance.queue(proposalId);
    }
    
    function test_ContractUpgradeProposal() public {
        // Deploy new implementation
        address newImplementation = address(new JobMarketplaceMock());
        
        // Create upgrade proposal
        vm.prank(voter1);
        vm.expectEmit(true, true, true, true);
        emit ProposalCreated(
            1,
            voter1,
            ProposalType.ContractUpgrade,
            "Upgrade JobMarketplace to v2"
        );
        
        uint256 proposalId = governance.proposeContractUpgrade(
            address(jobMarketplace),
            newImplementation,
            "Upgrade JobMarketplace to v2"
        );
        
        // Pass the proposal with super majority (80%+ required for upgrades)
        vm.roll(block.number + governance.votingDelay() + 1);
        vm.prank(voter1);
        governance.castVote(proposalId, true);
        vm.prank(voter2);
        governance.castVote(proposalId, true);
        vm.prank(voter3);
        governance.castVote(proposalId, true);
        
        // Queue and execute
        vm.roll(block.number + governance.votingPeriod() + 1);
        governance.queue(proposalId);
        
        vm.warp(block.timestamp + governance.executionDelay() + 1);
        governance.execute(proposalId);
        
        // Verify upgrade occurred (would need upgradeable contracts in real implementation)
        assertTrue(governance.isUpgradeExecuted(proposalId));
    }
    
    function test_EmergencyAction() public {
        // Only emergency admin can execute
        vm.expectRevert("Caller is not emergency admin");
        governance.executeEmergencyAction("pause", address(jobMarketplace));
        
        // Emergency admin pauses job marketplace
        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit EmergencyActionExecuted(emergencyAdmin, "pause");
        
        governance.executeEmergencyAction("pause", address(jobMarketplace));
        
        // Verify marketplace is paused
        assertTrue(jobMarketplace.paused());
        
        // Emergency admin unpauses
        vm.prank(emergencyAdmin);
        vm.expectEmit(true, true, true, true);
        emit EmergencyActionExecuted(emergencyAdmin, "unpause");
        
        governance.executeEmergencyAction("unpause", address(jobMarketplace));
        
        // Verify marketplace is unpaused
        assertFalse(jobMarketplace.paused());
    }
    
    function test_CancelProposal() public {
        // Create proposal
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(nodeRegistry),
            functionSelector: nodeRegistry.setMinimumStake.selector,
            parameterName: "minimumStake",
            newValue: 500e18
        });
        
        vm.prank(voter1);
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Increase minimum stake"
        );
        
        // Only proposer can cancel
        vm.prank(voter2);
        vm.expectRevert("Only proposer can cancel");
        governance.cancel(proposalId);
        
        // Proposer cancels
        vm.prank(voter1);
        vm.expectEmit(true, true, true, true);
        emit ProposalCancelled(proposalId);
        governance.cancel(proposalId);
        
        // Cannot vote on cancelled proposal
        vm.roll(block.number + governance.votingDelay() + 1);
        vm.prank(voter2);
        vm.expectRevert("Proposal cancelled");
        governance.castVote(proposalId, true);
    }
    
    function test_ProposalThresholdRequired() public {
        // Create account with insufficient tokens
        address smallHolder = address(0x1111);
        govToken.transfer(smallHolder, 100e18); // Below threshold
        
        vm.prank(smallHolder);
        govToken.delegate(smallHolder);
        vm.roll(block.number + 1);
        
        // Try to create proposal
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(nodeRegistry),
            functionSelector: nodeRegistry.setMinimumStake.selector,
            parameterName: "minimumStake",
            newValue: 150e18
        });
        
        vm.prank(smallHolder);
        vm.expectRevert("Below proposal threshold");
        governance.proposeParameterUpdate(updates, "Test proposal");
    }
    
    function test_MultipleParameterUpdates() public {
        // Create proposal with multiple updates
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](3);
        
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(nodeRegistry),
            functionSelector: nodeRegistry.setMinimumStake.selector,
            parameterName: "minimumStake",
            newValue: 150e18
        });
        
        updates[1] = Governance.ParameterUpdate({
            targetContract: address(jobMarketplace),
            functionSelector: jobMarketplace.setMaxJobDuration.selector,
            parameterName: "maxJobDuration",
            newValue: 10 days
        });
        
        updates[2] = Governance.ParameterUpdate({
            targetContract: address(paymentEscrow),
            functionSelector: paymentEscrow.setFeePercentage.selector,
            parameterName: "feePercentage",
            newValue: 300 // 3%
        });
        
        vm.prank(voter1);
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Multiple parameter updates"
        );
        
        // Pass and execute
        vm.roll(block.number + governance.votingDelay() + 1);
        vm.prank(voter1);
        governance.castVote(proposalId, true);
        vm.prank(voter2);
        governance.castVote(proposalId, true);
        
        vm.roll(block.number + governance.votingPeriod() + 1);
        governance.queue(proposalId);
        
        vm.warp(block.timestamp + governance.executionDelay() + 1);
        governance.execute(proposalId);
        
        // Verify all parameters updated
        assertEq(nodeRegistry.minimumStake(), 150e18);
        assertEq(jobMarketplace.maxJobDuration(), 10 days);
        assertEq(paymentEscrow.feePercentage(), 300);
    }
    
    function test_GovernanceTokenDelegation() public {
        // Create new voter
        address newVoter = address(0x2222);
        govToken.transfer(newVoter, 50000e18);
        
        // Check voting power before delegation
        assertEq(governance.getVotingPower(newVoter), 0);
        
        // Delegate to voter1
        vm.prank(newVoter);
        govToken.delegate(voter1);
        vm.roll(block.number + 1);
        
        // Check voting power transferred
        assertEq(governance.getVotingPower(voter1), 150000e18); // Original 100k + 50k delegated
        assertEq(governance.getVotingPower(newVoter), 0);
    }
    
    function test_ProposalStateTransitions() public {
        // Create proposal
        Governance.ParameterUpdate[] memory updates = new Governance.ParameterUpdate[](1);
        updates[0] = Governance.ParameterUpdate({
            targetContract: address(nodeRegistry),
            functionSelector: nodeRegistry.setMinimumStake.selector,
            parameterName: "minimumStake",
            newValue: 175e18
        });
        
        vm.prank(voter1);
        uint256 proposalId = governance.proposeParameterUpdate(
            updates,
            "Test state transitions"
        );
        
        // Check initial state
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Pending));
        
        // Move to active
        vm.roll(block.number + governance.votingDelay() + 1);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Active));
        
        // Vote and move to succeeded
        vm.prank(voter2);
        governance.castVote(proposalId, true);
        vm.roll(block.number + governance.votingPeriod() + 1);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Succeeded));
        
        // Queue
        governance.queue(proposalId);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Queued));
        
        // Execute
        vm.warp(block.timestamp + governance.executionDelay() + 1);
        governance.execute(proposalId);
        assertEq(uint8(governance.state(proposalId)), uint8(Governance.ProposalState.Executed));
    }
}