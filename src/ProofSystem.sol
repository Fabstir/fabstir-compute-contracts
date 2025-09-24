// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProofSystem.sol";

contract ProofSystem is IProofSystem {
    // Track verified proofs to prevent replay
    mapping(bytes32 => bool) public verifiedProofs;
    
    // Circuit registry state variables
    mapping(bytes32 => bool) public registeredCircuits;
    mapping(address => bytes32) public modelCircuits;
    address public owner;
    
    // Events
    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);
    event CircuitRegistered(bytes32 indexed circuitHash, address indexed model);
    event BatchProofVerified(bytes32[] proofHashes, address indexed prover, uint256 totalTokens);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    // Constructor
    constructor() {
        owner = msg.sender;
    }
    
    // Basic EZKL verification (simplified for now)
    function verifyEKZL(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external view override returns (bool) {
        return _verifyEKZL(proof, prover, claimedTokens);
    }
    
    // Internal verification logic
    function _verifyEKZL(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) internal view returns (bool) {
        // Basic validation
        if (proof.length < 64) return false;
        if (claimedTokens == 0) return false;
        if (prover == address(0)) return false;
        
        // Extract proof hash (first 32 bytes)
        bytes32 proofHash;
        assembly {
            proofHash := calldataload(proof.offset)
        }
        
        // Check not already verified (prevent replay)
        if (verifiedProofs[proofHash]) return false;
        
        // TODO: In production, call actual EZKL verifier
        // For now, basic validation only
        return true;
    }
    
    // Record a verified proof (only for testing now)
    function recordVerifiedProof(bytes32 proofHash) external {
        verifiedProofs[proofHash] = true;
        emit ProofVerified(proofHash, msg.sender, 0);
    }
    
    // Verify and mark proof as complete (prevents replay)
    function verifyAndMarkComplete(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external returns (bool) {
        // First verify using internal function
        if (!_verifyEKZL(proof, prover, claimedTokens)) {
            return false;
        }
        
        // Extract proof hash and mark as verified
        bytes32 proofHash;
        assembly {
            proofHash := calldataload(proof.offset)
        }
        
        verifiedProofs[proofHash] = true;
        emit ProofVerified(proofHash, prover, claimedTokens);
        
        return true;
    }
    
    // Circuit registry functions
    function registerModelCircuit(
        address model,
        bytes32 circuitHash
    ) external onlyOwner {
        require(model != address(0), "Invalid model");
        require(circuitHash != bytes32(0), "Invalid circuit");
        
        registeredCircuits[circuitHash] = true;
        modelCircuits[model] = circuitHash;
        
        emit CircuitRegistered(circuitHash, model);
    }
    
    function isCircuitRegistered(bytes32 circuitHash) external view returns (bool) {
        return registeredCircuits[circuitHash];
    }
    
    function getModelCircuit(address model) external view returns (bytes32) {
        return modelCircuits[model];
    }
    
    // Batch verification functions
    function verifyBatch(bytes[] calldata proofs, address prover, uint256[] calldata tokenCounts) external returns (bool) {
        require(proofs.length == tokenCounts.length, "Length mismatch");
        require(proofs.length > 0, "Empty batch");
        require(proofs.length <= 10, "Batch too large");
        
        bytes32[] memory proofHashes = new bytes32[](proofs.length);
        uint256 totalTokens = 0;
        
        for (uint256 i = 0; i < proofs.length; i++) {
            // Verify each proof using internal function
            require(_verifyEKZLInternal(proofs[i], prover, tokenCounts[i]), "Invalid proof at index");
            
            // Extract and record proof hash (first 32 bytes of proof)
            bytes32 proofHash;
            bytes calldata currentProof = proofs[i];
            assembly {
                proofHash := calldataload(currentProof.offset)
            }
            
            proofHashes[i] = proofHash;
            verifiedProofs[proofHash] = true;
            totalTokens += tokenCounts[i];
        }
        
        emit BatchProofVerified(proofHashes, prover, totalTokens);
        return true;
    }
    
    function verifyBatchView(bytes[] calldata proofs, address prover, uint256[] calldata tokenCounts) external view returns (bool[] memory results) {
        require(proofs.length == tokenCounts.length, "Length mismatch");
        
        results = new bool[](proofs.length);
        for (uint256 i = 0; i < proofs.length; i++) {
            results[i] = this.verifyEKZL(proofs[i], prover, tokenCounts[i]);
        }
    }
    
    function estimateBatchGas(uint256 batchSize) external pure returns (uint256) {
        return 50000 + (batchSize * 20000);
    }
    
    // Internal helper for batch verification (delegates to main internal function)
    function _verifyEKZLInternal(bytes calldata proof, address prover, uint256 claimedTokens) internal view returns (bool) {
        return _verifyEKZL(proof, prover, claimedTokens);
    }
}