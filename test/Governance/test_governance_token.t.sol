// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {GovernanceToken} from "../../src/GovernanceToken.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken public token;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        token = new GovernanceToken("Fabstir Governance", "FABGOV", 1000000e18);
        
        // Distribute tokens
        token.transfer(alice, 100000e18);
        token.transfer(bob, 200000e18);
        token.transfer(charlie, 50000e18);
    }
    
    function test_InitialSupply() public {
        assertEq(token.totalSupply(), 1000000e18);
        assertEq(token.balanceOf(address(this)), 650000e18); // Remaining after transfers
    }
    
    function test_TokenMetadata() public {
        assertEq(token.name(), "Fabstir Governance");
        assertEq(token.symbol(), "FABGOV");
        assertEq(token.decimals(), 18);
    }
    
    function test_Delegation() public {
        // Initially no votes
        assertEq(token.getVotes(alice), 0);
        
        // Alice delegates to herself
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit DelegateChanged(alice, address(0), alice);
        token.delegate(alice);
        
        // Check voting power
        assertEq(token.getVotes(alice), 100000e18);
        assertEq(token.delegates(alice), alice);
    }
    
    function test_DelegateToOther() public {
        // Bob delegates to alice
        vm.prank(bob);
        token.delegate(alice);
        
        // Alice has both her tokens and Bob's delegated votes
        assertEq(token.getVotes(alice), 200000e18);
        assertEq(token.getVotes(bob), 0);
        
        // Bob still owns his tokens
        assertEq(token.balanceOf(bob), 200000e18);
    }
    
    function test_TransferUpdatesDelegation() public {
        // Setup delegation
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        
        assertEq(token.getVotes(alice), 100000e18);
        assertEq(token.getVotes(bob), 200000e18);
        
        // Alice transfers to Bob
        vm.prank(alice);
        token.transfer(bob, 50000e18);
        
        // Votes updated
        assertEq(token.getVotes(alice), 50000e18);
        assertEq(token.getVotes(bob), 250000e18);
    }
    
    function test_GetPastVotes() public {
        // Delegate at different blocks
        vm.prank(alice);
        token.delegate(alice);
        uint256 block1 = block.number;
        
        vm.roll(block.number + 10);
        vm.prank(bob);
        token.delegate(alice);
        uint256 block2 = block.number;
        
        vm.roll(block.number + 10);
        
        // Check past votes
        assertEq(token.getPastVotes(alice, block1), 100000e18);
        assertEq(token.getPastVotes(alice, block2), 300000e18); // alice + bob
    }
    
    function test_GetPastTotalSupply() public {
        uint256 block1 = block.number;
        
        vm.roll(block.number + 10);
        
        // Burn some tokens
        token.burn(50000e18);
        uint256 block2 = block.number;
        
        vm.roll(block.number + 10);
        
        // Check past total supply
        assertEq(token.getPastTotalSupply(block1), 1000000e18);
        assertEq(token.getPastTotalSupply(block2), 950000e18);
    }
    
    function test_Checkpoints() public {
        vm.prank(alice);
        token.delegate(alice);
        vm.roll(block.number + 1);
        
        // Multiple transfers to create checkpoints
        vm.prank(alice);
        token.transfer(bob, 10000e18);
        vm.roll(block.number + 1);
        
        vm.prank(alice);
        token.transfer(bob, 10000e18);
        vm.roll(block.number + 1);
        
        vm.prank(alice);
        token.transfer(bob, 10000e18);
        
        // Check number of checkpoints
        assertEq(token.numCheckpoints(alice), 4); // Initial + 3 transfers
    }
    
    function test_DelegateBySig() public {
        uint256 privateKey = 0xA11CE;
        address delegator = vm.addr(privateKey);
        token.transfer(delegator, 50000e18);
        
        // Create delegation signature
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)"),
                alice,
                0,
                block.timestamp + 1 days
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                structHash
            )
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        // Delegate by signature
        token.delegateBySig(alice, 0, block.timestamp + 1 days, v, r, s);
        
        assertEq(token.delegates(delegator), alice);
        assertEq(token.getVotes(alice), 50000e18);
    }
    
    function test_BurnReducesSupply() public {
        uint256 initialSupply = token.totalSupply();
        uint256 burnAmount = 100000e18;
        
        token.burn(burnAmount);
        
        assertEq(token.totalSupply(), initialSupply - burnAmount);
        assertEq(token.balanceOf(address(this)), 650000e18 - burnAmount);
    }
    
    function test_MintIncreasesSupply() public {
        uint256 initialSupply = token.totalSupply();
        uint256 mintAmount = 100000e18;
        
        token.mint(alice, mintAmount);
        
        assertEq(token.totalSupply(), initialSupply + mintAmount);
        assertEq(token.balanceOf(alice), 100000e18 + mintAmount);
    }
}