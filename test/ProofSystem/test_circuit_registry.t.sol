// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ProofSystem.sol";

contract CircuitRegistryTest is Test {
    ProofSystem public proofSystem;
    
    address public owner;
    address public nonOwner = address(0x1234);
    address public model1 = address(0x5001);
    address public model2 = address(0x5002);
    
    bytes32 public circuit1 = keccak256("circuit1");
    bytes32 public circuit2 = keccak256("circuit2");
    
    function setUp() public {
        owner = address(this);
        proofSystem = new ProofSystem();
    }
    
    function test_CircuitRegistrationByOwner() public {
        // Owner should be able to register a circuit
        proofSystem.registerModelCircuit(model1, circuit1);
        
        // Verify circuit is registered
        assertTrue(proofSystem.registeredCircuits(circuit1), "Circuit should be registered");
        
        // Verify model mapping
        assertEq(proofSystem.modelCircuits(model1), circuit1, "Model should map to circuit");
    }
    
    function test_NonOwnerCannotRegister() public {
        // Switch to non-owner
        vm.prank(nonOwner);
        
        // Should revert when non-owner tries to register
        vm.expectRevert("Only owner");
        proofSystem.registerModelCircuit(model1, circuit1);
    }
    
    function test_CircuitMarkedAsRegistered() public {
        // Initially circuit should not be registered
        assertFalse(proofSystem.registeredCircuits(circuit1), "Circuit should not be registered initially");
        
        // Register the circuit
        proofSystem.registerModelCircuit(model1, circuit1);
        
        // Now it should be registered
        assertTrue(proofSystem.registeredCircuits(circuit1), "Circuit should be registered after registration");
        
        // Check via isCircuitRegistered function
        assertTrue(proofSystem.isCircuitRegistered(circuit1), "isCircuitRegistered should return true");
    }
    
    function test_InvalidCircuitRejection() public {
        // Try to register with zero circuit hash
        vm.expectRevert("Invalid circuit");
        proofSystem.registerModelCircuit(model1, bytes32(0));
        
        // Try to register with zero model address
        vm.expectRevert("Invalid model");
        proofSystem.registerModelCircuit(address(0), circuit1);
    }
    
    function test_EventEmission() public {
        // Expect the CircuitRegistered event
        vm.expectEmit(true, true, false, true);
        emit ProofSystem.CircuitRegistered(circuit1, model1);
        
        // Register the circuit
        proofSystem.registerModelCircuit(model1, circuit1);
    }
    
    function test_MultipleCircuitRegistrations() public {
        // Register first circuit
        proofSystem.registerModelCircuit(model1, circuit1);
        
        // Register second circuit for different model
        proofSystem.registerModelCircuit(model2, circuit2);
        
        // Both circuits should be registered
        assertTrue(proofSystem.registeredCircuits(circuit1), "Circuit1 should be registered");
        assertTrue(proofSystem.registeredCircuits(circuit2), "Circuit2 should be registered");
        
        // Models should map correctly
        assertEq(proofSystem.modelCircuits(model1), circuit1, "Model1 should map to circuit1");
        assertEq(proofSystem.modelCircuits(model2), circuit2, "Model2 should map to circuit2");
    }
    
    function test_OwnerAccessControl() public {
        // Verify owner is set correctly
        assertEq(proofSystem.owner(), owner, "Owner should be contract deployer");
        
        // Owner can register
        proofSystem.registerModelCircuit(model1, circuit1);
        
        // Different address cannot register
        address otherUser = address(0x9999);
        vm.prank(otherUser);
        vm.expectRevert("Only owner");
        proofSystem.registerModelCircuit(model2, circuit2);
    }
}