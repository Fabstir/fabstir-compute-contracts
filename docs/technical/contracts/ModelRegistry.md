# ModelRegistry Contract

## Overview

The ModelRegistry contract manages approved AI models that can be used in the Fabstir marketplace. It provides governance mechanisms for model approval, validation, and tracking.

**Contract Address**: `0x92b2De840bB2171203011A6dBA928d855cA8183E`
**Network**: Base Sepolia
**Source**: [`src/ModelRegistry.sol`](../../../src/ModelRegistry.sol)
**Status**: ✅ ACTIVE - Model governance with 2 approved models

### Key Features
- Model approval and governance system
- SHA256 hash verification for model integrity
- Community voting for model proposals
- Trusted model management by owner
- Integration with NodeRegistry for validation

## Constructor

```solidity
constructor(address _governanceToken)
```

### Parameters:
- `_governanceToken`: Address of the governance token contract

## Key Functions

### Read Functions

#### `isApprovedModel(bytes32 modelHash)`
Checks if a model hash is approved for use.

**Returns:**
- `bool`: True if the model is approved

#### `getModelInfo(bytes32 modelHash)`
Returns detailed information about a model.

**Returns:**
- `huggingfaceRepo`: HuggingFace repository URL
- `fileName`: Model file name
- `sha256Hash`: SHA256 hash of the model
- `proposer`: Address that proposed the model
- `approvalTimestamp`: When the model was approved
- `voteCount`: Number of votes received

#### `getAllApprovedModels()`
Returns all approved model hashes.

**Returns:**
- `bytes32[]`: Array of approved model hashes

#### `getModelProposal(bytes32 modelHash)`
Returns proposal details for a model.

**Returns:**
- `proposer`: Address that proposed the model
- `huggingfaceRepo`: Repository URL
- `fileName`: File name
- `endTime`: Proposal end timestamp
- `voteCount`: Current vote count
- `executed`: Whether proposal was executed

### Write Functions

#### `proposeModel(string huggingfaceRepo, string fileName, bytes32 sha256Hash)`
Propose a new model for approval (requires PROPOSAL_FEE).

**Parameters:**
- `huggingfaceRepo`: HuggingFace repository URL
- `fileName`: Model file name
- `sha256Hash`: SHA256 hash of the model

#### `voteForModel(bytes32 modelHash)`
Vote for a proposed model using governance tokens.

**Parameters:**
- `modelHash`: Hash of the model to vote for

#### `executeProposal(bytes32 modelHash)`
Execute a proposal that has met the approval threshold.

**Parameters:**
- `modelHash`: Hash of the model proposal to execute

### Admin Functions

#### `addTrustedModel(string huggingfaceRepo, string fileName, bytes32 sha256Hash)`
Add a trusted model directly (owner only).

**Parameters:**
- `huggingfaceRepo`: Repository URL
- `fileName`: File name
- `sha256Hash`: Model hash

#### `removeTrustedModel(bytes32 modelHash)`
Remove a trusted model (owner only).

**Parameters:**
- `modelHash`: Hash of the model to remove

## Constants

```solidity
uint256 public constant PROPOSAL_FEE = 10 * 10**18;        // 10 FAB tokens
uint256 public constant APPROVAL_THRESHOLD = 1000 * 10**18; // 1000 FAB votes
uint256 public constant PROPOSAL_DURATION = 3 days;
```

## Approved Models

Currently, there are **2 approved models** for MVP testing:

| Model | HuggingFace Repo | File | SHA256 Hash |
|-------|------------------|------|-------------|
| **TinyVicuna-1B** | CohereForAI/TinyVicuna-1B-32k-GGUF | tiny-vicuna-1b.q4_k_m.gguf | `0x329d002bc20d4e7baae25df802c9678b5a4340b3ce91f23e6a0644975e95935f` |
| **TinyLlama-1.1B** | TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF | tinyllama-1b.Q4_K_M.gguf | `0x45b71fe98efe5f530b825dce6f5049d738e9c16869f10be4370ab81a9912d4a6` |

## Events

```solidity
event ModelProposed(bytes32 indexed modelHash, address proposer, string repo);
event ModelVoted(bytes32 indexed modelHash, address voter, uint256 weight);
event ModelApproved(bytes32 indexed modelHash, string repo, string fileName);
event ModelRemoved(bytes32 indexed modelHash);
event ProposalExecuted(bytes32 indexed modelHash, bool approved);
```

## Integration Example

```javascript
const ModelRegistry = await ethers.getContractAt(
    "ModelRegistry",
    "0x92b2De840bB2171203011A6dBA928d855cA8183E"
);

// Check if a model is approved
const modelHash = "0x329d002bc20d4e7baae25df802c9678b5a4340b3ce91f23e6a0644975e95935f";
const isApproved = await ModelRegistry.isApprovedModel(modelHash);

// Get all approved models
const approvedModels = await ModelRegistry.getAllApprovedModels();

// Propose a new model (requires FAB tokens)
await ModelRegistry.proposeModel(
    "meta-llama/Llama-2-7b-hf",
    "llama-2-7b.gguf",
    "0x..." // model hash
);
```

## Security Considerations

1. **Model Verification**: All models must be verified by SHA256 hash
2. **Governance Process**: Community voting ensures quality control
3. **Trusted Models**: Owner can add emergency models if needed
4. **Proposal Fee**: Prevents spam proposals (10 FAB required)
5. **Vote Delegation**: Users can delegate voting power

## Related Contracts

- [`NodeRegistryWithModels`](./NodeRegistry.md): Uses ModelRegistry for validation
- [`JobMarketplaceWithModels`](./JobMarketplace.md): Enforces model requirements
- [`GovernanceToken`](./Governance.md): Provides voting power