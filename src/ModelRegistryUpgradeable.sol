// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ModelRegistryUpgradeable
 * @notice Manages approved AI models for the Fabstir P2P LLM marketplace (UUPS Upgradeable)
 * @dev Implements a two-tier system: owner-curated trusted models and community-proposed models
 */
contract ModelRegistryUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Model metadata structure
    struct Model {
        string huggingfaceRepo;     // e.g., "TheBloke/Llama-2-7B-GGUF"
        string fileName;            // e.g., "llama-2-7b.Q4_K_M.gguf"
        bytes32 sha256Hash;         // SHA256 hash for integrity verification
        uint256 approvalTier;       // 1 = trusted (owner), 2 = community approved
        bool active;                // Whether model is currently active
        uint256 timestamp;          // When model was added
    }

    // Model proposal for community voting
    struct ModelProposal {
        bytes32 modelId;            // Unique model identifier
        address proposer;           // Who proposed the model
        uint256 votesFor;           // FAB tokens voted in favor
        uint256 votesAgainst;       // FAB tokens voted against
        uint256 proposalTime;       // When proposal was created
        bool executed;              // Whether proposal has been executed
        Model modelData;            // The model data being proposed
    }

    // State variables (governanceToken was immutable, now regular storage)
    IERC20 public governanceToken;                        // FAB token for voting
    uint256 public constant PROPOSAL_DURATION = 3 days;
    uint256 public constant APPROVAL_THRESHOLD = 100000 * 10**18; // 100k FAB tokens
    uint256 public constant PROPOSAL_FEE = 100 * 10**18;          // 100 FAB to propose

    // Mappings
    mapping(bytes32 => Model) public models;           // modelId => Model data
    mapping(bytes32 => bool) public trustedModels;     // modelId => is trusted (tier 1)
    mapping(bytes32 => ModelProposal) public proposals; // modelId => Proposal
    mapping(bytes32 => mapping(address => uint256)) public votes; // modelId => voter => vote amount

    bytes32[] public modelList;                        // List of all model IDs
    bytes32[] public activeProposals;                  // List of active proposal IDs

    // Events
    event ModelAdded(bytes32 indexed modelId, string huggingfaceRepo, string fileName, uint256 tier);
    event ModelProposed(bytes32 indexed modelId, address indexed proposer, string huggingfaceRepo);
    event VoteCast(bytes32 indexed modelId, address indexed voter, uint256 amount, bool support);
    event ProposalExecuted(bytes32 indexed modelId, bool approved);
    event ModelDeactivated(bytes32 indexed modelId);
    event ModelReactivated(bytes32 indexed modelId);

    // Storage gap for future upgrades (50 slots minus 1 for governanceToken)
    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor)
     * @param _governanceToken The FAB token address for voting
     */
    function initialize(address _governanceToken) public initializer {
        __Ownable_init(msg.sender);
        // Note: UUPSUpgradeable in OZ 5.x doesn't require initialization

        require(_governanceToken != address(0), "Invalid token address");
        governanceToken = IERC20(_governanceToken);
    }

    /**
     * @notice Authorize upgrade (only owner can upgrade)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Generate a unique model ID from repo and filename
     */
    function getModelId(string memory repo, string memory fileName) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(repo, "/", fileName));
    }

    /**
     * @notice Add a trusted model (owner only)
     */
    function addTrustedModel(
        string memory huggingfaceRepo,
        string memory fileName,
        bytes32 sha256Hash
    ) external onlyOwner {
        bytes32 modelId = getModelId(huggingfaceRepo, fileName);
        require(models[modelId].timestamp == 0, "Model already exists");

        models[modelId] = Model({
            huggingfaceRepo: huggingfaceRepo,
            fileName: fileName,
            sha256Hash: sha256Hash,
            approvalTier: 1,
            active: true,
            timestamp: block.timestamp
        });

        trustedModels[modelId] = true;
        modelList.push(modelId);

        emit ModelAdded(modelId, huggingfaceRepo, fileName, 1);
    }

    /**
     * @notice Propose a new model for community approval
     */
    function proposeModel(
        string memory huggingfaceRepo,
        string memory fileName,
        bytes32 sha256Hash
    ) external {
        bytes32 modelId = getModelId(huggingfaceRepo, fileName);
        require(models[modelId].timestamp == 0, "Model already exists");
        require(proposals[modelId].proposalTime == 0, "Proposal already exists");

        // Charge proposal fee to prevent spam
        require(governanceToken.transferFrom(msg.sender, address(this), PROPOSAL_FEE), "Fee transfer failed");

        proposals[modelId] = ModelProposal({
            modelId: modelId,
            proposer: msg.sender,
            votesFor: 0,
            votesAgainst: 0,
            proposalTime: block.timestamp,
            executed: false,
            modelData: Model({
                huggingfaceRepo: huggingfaceRepo,
                fileName: fileName,
                sha256Hash: sha256Hash,
                approvalTier: 2,
                active: false,
                timestamp: 0
            })
        });

        activeProposals.push(modelId);
        emit ModelProposed(modelId, msg.sender, huggingfaceRepo);
    }

    /**
     * @notice Vote on a model proposal
     */
    function voteOnProposal(bytes32 modelId, uint256 amount, bool support) external {
        ModelProposal storage proposal = proposals[modelId];
        require(proposal.proposalTime > 0, "Proposal does not exist");
        require(!proposal.executed, "Proposal already executed");
        require(block.timestamp <= proposal.proposalTime + PROPOSAL_DURATION, "Voting period ended");

        // Transfer tokens from voter (tokens are locked until proposal ends)
        require(governanceToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        if (support) {
            proposal.votesFor += amount;
        } else {
            proposal.votesAgainst += amount;
        }

        votes[modelId][msg.sender] += amount;
        emit VoteCast(modelId, msg.sender, amount, support);
    }

    /**
     * @notice Execute a proposal after voting period
     */
    function executeProposal(bytes32 modelId) external {
        ModelProposal storage proposal = proposals[modelId];
        require(proposal.proposalTime > 0, "Proposal does not exist");
        require(!proposal.executed, "Already executed");
        require(block.timestamp > proposal.proposalTime + PROPOSAL_DURATION, "Voting still active");

        proposal.executed = true;

        // Check if proposal passed
        bool approved = proposal.votesFor >= APPROVAL_THRESHOLD &&
                       proposal.votesFor > proposal.votesAgainst;

        if (approved) {
            // Add the model
            models[modelId] = proposal.modelData;
            models[modelId].active = true;
            models[modelId].timestamp = block.timestamp;
            modelList.push(modelId);

            emit ModelAdded(modelId, proposal.modelData.huggingfaceRepo,
                          proposal.modelData.fileName, 2);
        }

        // Return proposal fee to proposer if approved
        if (approved) {
            governanceToken.transfer(proposal.proposer, PROPOSAL_FEE);
        }

        // Remove from active proposals
        _removeFromActiveProposals(modelId);

        emit ProposalExecuted(modelId, approved);
    }

    /**
     * @notice Withdraw voting tokens after proposal execution
     */
    function withdrawVotes(bytes32 modelId) external {
        ModelProposal storage proposal = proposals[modelId];
        require(proposal.executed ||
                block.timestamp > proposal.proposalTime + PROPOSAL_DURATION + 7 days,
                "Cannot withdraw yet");

        uint256 amount = votes[modelId][msg.sender];
        require(amount > 0, "No votes to withdraw");

        votes[modelId][msg.sender] = 0;
        governanceToken.transfer(msg.sender, amount);
    }

    /**
     * @notice Check if a model is approved (either trusted or community approved)
     */
    function isModelApproved(bytes32 modelId) external view returns (bool) {
        return models[modelId].active;
    }

    /**
     * @notice Get model verification hash
     */
    function getModelHash(bytes32 modelId) external view returns (bytes32) {
        return models[modelId].sha256Hash;
    }

    /**
     * @notice Deactivate a model (owner only, for emergencies)
     */
    function deactivateModel(bytes32 modelId) external onlyOwner {
        require(models[modelId].timestamp > 0, "Model does not exist");
        models[modelId].active = false;
        emit ModelDeactivated(modelId);
    }

    /**
     * @notice Reactivate a model (owner only)
     */
    function reactivateModel(bytes32 modelId) external onlyOwner {
        require(models[modelId].timestamp > 0, "Model does not exist");
        models[modelId].active = true;
        emit ModelReactivated(modelId);
    }

    /**
     * @notice Get all model IDs
     */
    function getAllModels() external view returns (bytes32[] memory) {
        return modelList;
    }

    /**
     * @notice Get active proposal IDs
     */
    function getActiveProposals() external view returns (bytes32[] memory) {
        return activeProposals;
    }

    /**
     * @notice Get model details
     */
    function getModel(bytes32 modelId) external view returns (Model memory) {
        return models[modelId];
    }

    /**
     * @notice Remove from active proposals list
     */
    function _removeFromActiveProposals(bytes32 modelId) private {
        for (uint i = 0; i < activeProposals.length; i++) {
            if (activeProposals[i] == modelId) {
                activeProposals[i] = activeProposals[activeProposals.length - 1];
                activeProposals.pop();
                break;
            }
        }
    }

    /**
     * @notice Batch add trusted models (owner only, for initial setup)
     */
    function batchAddTrustedModels(
        string[] memory repos,
        string[] memory fileNames,
        bytes32[] memory hashes
    ) external onlyOwner {
        require(repos.length == fileNames.length && repos.length == hashes.length, "Array length mismatch");

        for (uint i = 0; i < repos.length; i++) {
            bytes32 modelId = getModelId(repos[i], fileNames[i]);
            if (models[modelId].timestamp == 0) {
                models[modelId] = Model({
                    huggingfaceRepo: repos[i],
                    fileName: fileNames[i],
                    sha256Hash: hashes[i],
                    approvalTier: 1,
                    active: true,
                    timestamp: block.timestamp
                });

                trustedModels[modelId] = true;
                modelList.push(modelId);

                emit ModelAdded(modelId, repos[i], fileNames[i], 1);
            }
        }
    }
}
