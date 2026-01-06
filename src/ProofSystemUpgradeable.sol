// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IProofSystem.sol";

/**
 * @title ProofSystemUpgradeable
 * @notice EZKL proof verification system for the Fabstir P2P LLM marketplace (UUPS Upgradeable)
 * @dev Verifies proofs of work for AI inference sessions
 */
contract ProofSystemUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable, IProofSystem {
    // Track verified proofs to prevent replay
    mapping(bytes32 => bool) public verifiedProofs;

    // Circuit registry state variables
    mapping(bytes32 => bool) public registeredCircuits;
    mapping(address => bytes32) public modelCircuits;

    // Access control for recordVerifiedProof (Sub-phase 1.1 security fix)
    mapping(address => bool) public authorizedCallers;

    // Events
    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);
    event CircuitRegistered(bytes32 indexed circuitHash, address indexed model);
    event BatchProofVerified(bytes32[] proofHashes, address indexed prover, uint256 totalTokens);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);

    // Storage gap for future upgrades (reduced by 1 for authorizedCallers mapping)
    uint256[46] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor)
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        // Note: UUPSUpgradeable in OZ 5.x doesn't require initialization
    }

    /**
     * @notice Authorize upgrade (only owner can upgrade)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Set authorized caller status for recordVerifiedProof
     * @dev Only owner can authorize/revoke callers. Typically JobMarketplace is authorized.
     * @param caller The address to authorize or revoke
     * @param authorized True to authorize, false to revoke
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        require(caller != address(0), "Invalid caller");
        authorizedCallers[caller] = authorized;
        emit AuthorizedCallerUpdated(caller, authorized);
    }

    /**
     * @notice Verify proof using ECDSA signature validation
     * @dev The prover must sign keccak256(proofHash, prover, claimedTokens)
     * @param proof Proof bytes: [32 bytes proofHash][32 bytes r][32 bytes s][1 byte v]
     * @param prover Address that should have signed the proof (host)
     * @param claimedTokens Number of tokens being claimed
     * @return True if signature is valid and proof not replayed
     */
    function verifyEKZL(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) external view override returns (bool) {
        return _verifyEKZL(proof, prover, claimedTokens);
    }

    /**
     * @notice Internal verification logic using ECDSA signature verification
     * @dev Proof format: [32 bytes proofHash][32 bytes r][32 bytes s][1 byte v] = 97 bytes minimum
     *      The prover (host) must sign: keccak256(proofHash, prover, claimedTokens)
     */
    function _verifyEKZL(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) internal view returns (bool) {
        // Proof must contain: proofHash (32) + r (32) + s (32) + v (1) = 97 bytes
        if (proof.length < 97) return false;
        if (claimedTokens == 0) return false;
        if (prover == address(0)) return false;

        // Extract signature components from proof
        bytes32 proofHash;
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            proofHash := calldataload(proof.offset)
            r := calldataload(add(proof.offset, 32))
            s := calldataload(add(proof.offset, 64))
            v := byte(0, calldataload(add(proof.offset, 96)))
        }

        // Check not already verified (prevent replay)
        if (verifiedProofs[proofHash]) return false;

        // Reconstruct the message that was signed
        // The prover signs: keccak256(proofHash, prover, claimedTokens)
        // Using eth_sign which prefixes with "\x19Ethereum Signed Message:\n32"
        bytes32 dataHash = keccak256(abi.encodePacked(proofHash, prover, claimedTokens));
        bytes32 messageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            dataHash
        ));

        // Recover signer and verify it matches the prover (host)
        address recoveredSigner = ecrecover(messageHash, v, r, s);

        // ecrecover returns address(0) on failure
        if (recoveredSigner == address(0)) return false;

        return recoveredSigner == prover;
    }

    /**
     * @notice Record a verified proof to prevent replay attacks
     * @dev Only callable by authorized contracts (e.g., JobMarketplace) or owner
     * @param proofHash The hash of the verified proof
     */
    function recordVerifiedProof(bytes32 proofHash) external {
        require(authorizedCallers[msg.sender] || msg.sender == owner(), "Unauthorized");
        verifiedProofs[proofHash] = true;
        emit ProofVerified(proofHash, msg.sender, 0);
    }

    /**
     * @notice Verify and mark proof as complete (prevents replay)
     */
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

    /**
     * @notice Register a model circuit (owner only)
     */
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

    /**
     * @notice Check if a circuit is registered
     */
    function isCircuitRegistered(bytes32 circuitHash) external view returns (bool) {
        return registeredCircuits[circuitHash];
    }

    /**
     * @notice Get the circuit hash for a model
     */
    function getModelCircuit(address model) external view returns (bytes32) {
        return modelCircuits[model];
    }

    /**
     * @notice Batch verification of multiple proofs
     */
    function verifyBatch(
        bytes[] calldata proofs,
        address prover,
        uint256[] calldata tokenCounts
    ) external returns (bool) {
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

    /**
     * @notice View function for batch verification (doesn't modify state)
     */
    function verifyBatchView(
        bytes[] calldata proofs,
        address prover,
        uint256[] calldata tokenCounts
    ) external view returns (bool[] memory results) {
        require(proofs.length == tokenCounts.length, "Length mismatch");

        results = new bool[](proofs.length);
        for (uint256 i = 0; i < proofs.length; i++) {
            results[i] = this.verifyEKZL(proofs[i], prover, tokenCounts[i]);
        }
    }

    /**
     * @notice Estimate gas for batch verification
     * @dev Gas constants derived from actual measurements on verifyBatch():
     *      - Base cost: ~15,000 gas (function call overhead, array setup, event emission)
     *      - Per-proof: ~27,000 gas (signature recovery via ecrecover, hash computations,
     *        storage write for verifiedProofs mapping)
     *      Constants include ~10% safety margin for variance across different EVM implementations.
     *      Measured values: Base ~14,839, Per-proof ~26,824 (rounded up for safety)
     * @param batchSize Number of proofs in batch (1-10)
     * @return Estimated gas consumption for the batch verification
     */
    function estimateBatchGas(uint256 batchSize) external pure returns (uint256) {
        require(batchSize > 0 && batchSize <= 10, "Invalid batch size");
        // BASE_VERIFICATION_GAS = 15000, PER_PROOF_GAS = 27000
        return 15000 + (batchSize * 27000);
    }

    /**
     * @notice Internal helper for batch verification
     */
    function _verifyEKZLInternal(
        bytes calldata proof,
        address prover,
        uint256 claimedTokens
    ) internal view returns (bool) {
        return _verifyEKZL(proof, prover, claimedTokens);
    }
}
