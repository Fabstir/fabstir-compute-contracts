// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/ProofSystem.sol";

contract ModelMappingTest is Test {
    ProofSystem public proofSystem;
    
    address public owner;
    address public model1 = address(0x5001);
    address public model2 = address(0x5002);
    address public model3 = address(0x5003);
    address public unmappedModel = address(0x9999);
    
    bytes32 public circuit1 = keccak256("circuit1");
    bytes32 public circuit2 = keccak256("circuit2");
    bytes32 public sharedCircuit = keccak256("shared_circuit");
    
    function setUp() public {
        owner = address(this);
        proofSystem = new ProofSystem();
    }
    
    function test_ModelToCircuitMapping() public {
        // Register model with circuit
        proofSystem.registerModelCircuit(model1, circuit1);
        
        // Verify mapping exists
        bytes32 retrievedCircuit = proofSystem.modelCircuits(model1);
        assertEq(retrievedCircuit, circuit1, "Model should map to correct circuit");
    }
    
    function test_CircuitLookupForModel() public {
        // Register multiple models
        proofSystem.registerModelCircuit(model1, circuit1);
        proofSystem.registerModelCircuit(model2, circuit2);
        
        // Look up circuits using getModelCircuit function
        bytes32 model1Circuit = proofSystem.getModelCircuit(model1);
        bytes32 model2Circuit = proofSystem.getModelCircuit(model2);
        
        assertEq(model1Circuit, circuit1, "Should return correct circuit for model1");
        assertEq(model2Circuit, circuit2, "Should return correct circuit for model2");
    }
    
    function test_MultipleModelsCanUseSameCircuit() public {
        // Register multiple models with the same circuit
        proofSystem.registerModelCircuit(model1, sharedCircuit);
        proofSystem.registerModelCircuit(model2, sharedCircuit);
        proofSystem.registerModelCircuit(model3, sharedCircuit);
        
        // All models should map to the same circuit
        assertEq(proofSystem.modelCircuits(model1), sharedCircuit, "Model1 should use shared circuit");
        assertEq(proofSystem.modelCircuits(model2), sharedCircuit, "Model2 should use shared circuit");
        assertEq(proofSystem.modelCircuits(model3), sharedCircuit, "Model3 should use shared circuit");
        
        // Circuit should be registered only once
        assertTrue(proofSystem.registeredCircuits(sharedCircuit), "Shared circuit should be registered");
    }
    
    function test_ModelCircuitUpdates() public {
        // Register model with initial circuit
        proofSystem.registerModelCircuit(model1, circuit1);
        assertEq(proofSystem.modelCircuits(model1), circuit1, "Model should use circuit1 initially");
        
        // Update to new circuit
        proofSystem.registerModelCircuit(model1, circuit2);
        assertEq(proofSystem.modelCircuits(model1), circuit2, "Model should now use circuit2");
        
        // Both circuits should be registered
        assertTrue(proofSystem.registeredCircuits(circuit1), "Circuit1 should still be registered");
        assertTrue(proofSystem.registeredCircuits(circuit2), "Circuit2 should be registered");
    }
    
    function test_UnmappedModelReturnsZero() public {
        // Query unmapped model
        bytes32 result = proofSystem.modelCircuits(unmappedModel);
        assertEq(result, bytes32(0), "Unmapped model should return zero hash");
        
        // Also test with getModelCircuit function
        bytes32 lookupResult = proofSystem.getModelCircuit(unmappedModel);
        assertEq(lookupResult, bytes32(0), "getModelCircuit should return zero for unmapped model");
    }
    
    function test_CircuitPersistenceAfterModelUpdate() public {
        // Register two models with circuit1
        proofSystem.registerModelCircuit(model1, circuit1);
        proofSystem.registerModelCircuit(model2, circuit1);
        
        // Update model1 to circuit2
        proofSystem.registerModelCircuit(model1, circuit2);
        
        // Circuit1 should still be registered (model2 still uses it)
        assertTrue(proofSystem.registeredCircuits(circuit1), "Circuit1 should remain registered");
        assertTrue(proofSystem.registeredCircuits(circuit2), "Circuit2 should be registered");
        
        // Verify model mappings
        assertEq(proofSystem.modelCircuits(model1), circuit2, "Model1 should use circuit2");
        assertEq(proofSystem.modelCircuits(model2), circuit1, "Model2 should still use circuit1");
    }
    
    function test_DirectMappingAccess() public {
        // Register some models
        proofSystem.registerModelCircuit(model1, circuit1);
        proofSystem.registerModelCircuit(model2, circuit2);
        
        // Direct access to modelCircuits mapping
        bytes32 direct1 = proofSystem.modelCircuits(model1);
        bytes32 direct2 = proofSystem.modelCircuits(model2);
        
        // Function access
        bytes32 func1 = proofSystem.getModelCircuit(model1);
        bytes32 func2 = proofSystem.getModelCircuit(model2);
        
        // Both should return same values
        assertEq(direct1, func1, "Direct and function access should match for model1");
        assertEq(direct2, func2, "Direct and function access should match for model2");
    }
}