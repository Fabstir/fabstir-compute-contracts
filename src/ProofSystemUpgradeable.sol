// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IProofSystem.sol";

/**
 * @title ProofSystemUpgradeable
 * @notice Proof replay protection system for the Fabstir P2P LLM marketplace (UUPS Upgradeable)
 * @dev Provides replay protection via verifiedProofs mapping. Authentication is handled
 *      by JobMarketplace via msg.sender == session.host check. Proofs are stored on S5
 *      for post-hoc auditing. Economic security is provided by host staking of FAB tokens.
 */
contract ProofSystemUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable, IProofSystem {
    // Track verified proofs to prevent replay
    mapping(bytes32 => bool) public verifiedProofs;

    // Access control for markProofUsed - restricts to authorized callers only
    mapping(address => bool) public authorizedCallers;

    // Events
    event ProofVerified(bytes32 indexed proofHash, address indexed prover, uint256 tokens);
    event AuthorizedCallerUpdated(address indexed caller, bool authorized);

    // Storage gap for future upgrades
    uint256[48] private __gap;

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
     * @notice Set authorized caller status for markProofUsed
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
     * @notice Mark a proof hash as used (replay protection only)
     * @dev Only callable by authorized contracts (JobMarketplace) or owner.
     *      Authentication is handled by JobMarketplace via msg.sender == host check.
     * @param proofHash The hash of the proof
     * @param prover The address of the prover (host) - for event logging
     * @param claimedTokens Number of tokens claimed - for event logging
     * @param modelId The model ID (unused, kept for interface consistency)
     * @return True if proof was marked, false if already used (replay protection)
     */
    function markProofUsed(
        bytes32 proofHash,
        address prover,
        uint256 claimedTokens,
        bytes32 modelId
    ) external override returns (bool) {
        require(authorizedCallers[msg.sender] || msg.sender == owner(), "Unauthorized");

        // Replay protection - return false if already used
        if (verifiedProofs[proofHash]) return false;

        verifiedProofs[proofHash] = true;
        emit ProofVerified(proofHash, prover, claimedTokens);

        return true;
    }
}
