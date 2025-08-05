# ProofSystem Contract

## Overview

The ProofSystem contract handles zero-knowledge proof verification for AI model outputs using EZKL. It provides a trustless way to verify computation correctness, supports proof challenges, and integrates with the reputation system for accountability.

**Contract Address**: To be deployed  
**Source**: [`src/ProofSystem.sol`](../../../src/ProofSystem.sol)

### Key Features
- EZKL proof submission and verification
- Challenge mechanism with staking
- Batch verification for efficiency
- Role-based access control
- Integration with JobMarketplace and ReputationSystem
- Reentrancy protection

### Dependencies
- IJobMarketplace interface
- IPaymentEscrow interface
- IReputationSystem interface
- IERC20 interface

## Constructor

```solidity
constructor(
    address _jobMarketplace,
    address _paymentEscrow,
    address _reputationSystem
)
```

### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_jobMarketplace` | `address` | JobMarketplace contract address |
| `_paymentEscrow` | `address` | PaymentEscrow contract address |
| `_reputationSystem` | `address` | ReputationSystem contract address |

### Example Deployment
```solidity
ProofSystem proofSystem = new ProofSystem(
    jobMarketplaceAddress,
    paymentEscrowAddress,
    reputationSystemAddress
);
```

## Constants

| Name | Type | Value | Description |
|------|------|-------|-------------|
| `CHALLENGE_PERIOD` | `uint256` | 3 days | Time window for challenging proofs |
| `CHALLENGE_STAKE_MIN` | `uint256` | 10e18 | Minimum stake for challenges (10 tokens) |
| `PENALTY_AMOUNT` | `uint256` | 20e18 | Penalty for invalid proofs |

## Role Management

### Roles
| Role | Constant | Description |
|------|----------|-------------|
| Default Admin | `DEFAULT_ADMIN_ROLE` | Can grant/revoke other roles |
| Admin | `ADMIN_ROLE` | Can grant verifier role |
| Verifier | `VERIFIER_ROLE` | Can verify proofs and resolve challenges |

### grantRole

Grant a role to an address.

```solidity
function grantRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE)
```

### revokeRole

Revoke a role from an address.

```solidity
function revokeRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE)
```

### hasRole

Check if address has a role.

```solidity
function hasRole(bytes32 role, address account) public view returns (bool)
```

## Data Structures

### EZKLProof
```solidity
struct EZKLProof {
    uint256[] instances;      // Public inputs/outputs
    uint256[] proof;         // ZK proof data
    uint256[] vk;           // Verification key
    bytes32 modelCommitment; // Commitment to AI model
    bytes32 inputHash;      // Hash of input data
    bytes32 outputHash;     // Hash of output
}
```

### ProofInfo
```solidity
struct ProofInfo {
    address prover;          // Host who submitted proof
    uint256 submissionTime;  // Timestamp
    ProofStatus status;      // Current status
    bytes32 proofHash;      // Hash of proof data
    EZKLProof proof;        // Full proof data
}
```

### ProofStatus
```solidity
enum ProofStatus {
    None,       // Not submitted
    Submitted,  // Awaiting verification
    Verified,   // Successfully verified
    Invalid     // Failed verification
}
```

### Challenge
```solidity
struct Challenge {
    address challenger;      // Who challenged
    uint256 stake;          // Staked amount
    bytes32 evidenceHash;   // Evidence supporting challenge
    ChallengeStatus status; // Current status
    uint256 deadline;       // Resolution deadline
    uint256 jobId;         // Associated job
}
```

### ChallengeStatus
```solidity
enum ChallengeStatus {
    None,       // No challenge
    Pending,    // Awaiting resolution
    Successful, // Challenge upheld
    Failed      // Challenge rejected
}
```

## Core Functions

### submitProof

Submit proof of computation for a job.

```solidity
function submitProof(uint256 jobId, EZKLProof calldata proof) external nonReentrant
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `jobId` | `uint256` | Job ID |
| `proof` | `EZKLProof` | Proof data structure |

#### Requirements
- Job must exist
- Caller must be assigned host
- Job in Claimed state
- No existing proof for job
- Reentrancy protected

#### Effects
- Stores proof data
- Calculates proof hash
- Sets status to Submitted

#### Emitted Events
- `ProofSubmitted(uint256 indexed jobId, address indexed prover, bytes32 proofHash, uint256 timestamp)`

#### Example Usage
```solidity
EZKLProof memory proof = EZKLProof({
    instances: instances,
    proof: proofData,
    vk: verificationKey,
    modelCommitment: modelHash,
    inputHash: inputHash,
    outputHash: outputHash
});

proofSystem.submitProof(jobId, proof);
```

### verifyProof

Verify a submitted proof.

```solidity
function verifyProof(uint256 jobId) external onlyRole(VERIFIER_ROLE)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `jobId` | `uint256` | Job ID with submitted proof |

#### Requirements
- Verifier role required
- Proof status must be Submitted

#### Verification Logic (Mock)
```solidity
// Valid proof requires:
// - 3 instances
// - instances[0] == modelCommitment
// - instances[1] == inputHash
// - instances[2] == outputHash
// - instances[2] != keccak256("wrong_output")
```

#### Effects
- Updates status to Verified or Invalid
- Records failure in reputation system if invalid

#### Emitted Events
- `ProofVerified(uint256 indexed jobId, address indexed verifier, bool isValid)`

### batchVerifyProofs

Verify multiple proofs efficiently.

```solidity
function batchVerifyProofs(uint256[] calldata jobIds) 
    external 
    onlyRole(VERIFIER_ROLE) 
    returns (bool[] memory results)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `jobIds` | `uint256[]` | Array of job IDs |

#### Returns
Array of verification results (true = valid)

#### Gas Optimization
- Processes multiple proofs in one transaction
- Tracks gas usage

#### Emitted Events
- `ProofVerified` (for each proof)
- `BatchVerificationCompleted(uint256[] jobIds, bool[] results, uint256 gasUsed)`

### challengeProof

Challenge a verified proof.

```solidity
function challengeProof(
    uint256 jobId,
    bytes32 evidenceHash,
    uint256 stakeAmount
) external nonReentrant returns (uint256 challengeId)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `jobId` | `uint256` | Job with verified proof |
| `evidenceHash` | `bytes32` | Hash of challenge evidence |
| `stakeAmount` | `uint256` | Amount to stake |

#### Requirements
- Proof must be Verified
- Stake ≥ CHALLENGE_STAKE_MIN
- Must transfer stake tokens
- Reentrancy protected

#### Returns
Unique challenge ID

#### Emitted Events
- `ProofChallenged(uint256 indexed jobId, address indexed challenger, bytes32 evidenceHash)`

### resolveChallenge

Resolve a pending challenge.

```solidity
function resolveChallenge(uint256 challengeId, bool challengeSuccessful) 
    external 
    onlyRole(VERIFIER_ROLE) 
    nonReentrant
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `challengeId` | `uint256` | Challenge ID |
| `challengeSuccessful` | `bool` | Whether challenge is valid |

#### Requirements
- Verifier role required
- Challenge must be Pending
- Before deadline
- Reentrancy protected

#### Effects (if successful)
- Proof marked Invalid
- Challenger receives stake back
- Host reputation decreased

#### Effects (if failed)
- Host receives challenger's stake
- Challenge marked Failed

#### Emitted Events
- `ChallengeResolved(uint256 indexed jobId, bool challengeSuccessful, address winner)`

### expireChallenge

Expire an unresolved challenge.

```solidity
function expireChallenge(uint256 challengeId) external nonReentrant
```

#### Requirements
- Challenge must be Pending
- Past deadline
- Reentrancy protected

#### Effects
- Challenge marked Failed
- Host receives stake

#### Emitted Events
- `ChallengeResolved(uint256 indexed jobId, false, address prover)`

## View Functions

### canCompleteJob

Check if job has valid proof.

```solidity
function canCompleteJob(uint256 jobId) external view returns (bool)
```

#### Returns
`true` if proof status is Verified

### getProofInfo

Get proof details for a job.

```solidity
function getProofInfo(uint256 jobId) 
    external 
    view 
    returns (address prover, uint256 submissionTime, ProofStatus status)
```

### getChallengeInfo

Get challenge details.

```solidity
function getChallengeInfo(uint256 challengeId)
    external
    view
    returns (
        address challenger,
        uint256 stake,
        bytes32 evidenceHash,
        ChallengeStatus status,
        uint256 deadline
    )
```

## Admin Functions

### grantVerifierRole

Grant verifier role to an address.

```solidity
function grantVerifierRole(address account) external onlyRole(ADMIN_ROLE)
```

### revokeVerifierRole

Revoke verifier role from an address.

```solidity
function revokeVerifierRole(address account) external onlyRole(ADMIN_ROLE)
```

## Events

### Proof Events
```solidity
event ProofSubmitted(
    uint256 indexed jobId,
    address indexed prover,
    bytes32 proofHash,
    uint256 timestamp
)

event ProofVerified(
    uint256 indexed jobId,
    address indexed verifier,
    bool isValid
)
```

### Challenge Events
```solidity
event ProofChallenged(
    uint256 indexed jobId,
    address indexed challenger,
    bytes32 evidenceHash
)

event ChallengeResolved(
    uint256 indexed jobId,
    bool challengeSuccessful,
    address winner
)
```

### Batch Events
```solidity
event BatchVerificationCompleted(
    uint256[] jobIds,
    bool[] results,
    uint256 gasUsed
)
```

## Security Considerations

1. **Reentrancy Protection**:
   - All state-changing functions protected
   - Uses custom guard implementation

2. **Access Control**:
   - Role-based permissions
   - Admin cannot verify proofs directly

3. **Economic Security**:
   - Minimum stake for challenges
   - Stakes locked during challenge period

4. **Timing Attacks**:
   - Challenge deadlines enforced
   - No late resolutions allowed

5. **Integration Security**:
   - Validates job state from marketplace
   - Checks host assignment

## Gas Optimization

1. **Batch Operations**:
   - Verify multiple proofs per transaction
   - Shared setup costs

2. **Storage Efficiency**:
   - Proof data stored efficiently
   - Hash used for comparison

3. **Early Returns**:
   - Skip invalid states quickly
   - Minimize external calls

## Integration Examples

### Complete Proof Workflow
```solidity
// 1. Host submits proof after computation
EZKLProof memory proof = generateProof(jobData);
proofSystem.submitProof(jobId, proof);

// 2. Verifier validates proof
proofSystem.verifyProof(jobId);

// 3. Job can now be completed
if (proofSystem.canCompleteJob(jobId)) {
    jobMarketplace.completeJob(jobId, resultHash, proofBytes);
}
```

### Challenge Flow
```solidity
// 1. Suspicious proof detected
uint256 challengeId = proofSystem.challengeProof(
    jobId,
    evidenceHash,
    10 ether  // Stake 10 tokens
);

// 2. Within 3 days, verifier investigates
proofSystem.resolveChallenge(challengeId, true);

// 3. Or after 3 days, anyone can expire
proofSystem.expireChallenge(challengeId);
```

### Batch Verification
```solidity
// Verifier processes queue
uint256[] memory pendingJobs = getPendingProofs();
bool[] memory results = proofSystem.batchVerifyProofs(pendingJobs);

for (uint i = 0; i < results.length; i++) {
    if (!results[i]) {
        // Handle invalid proof
        handleInvalidProof(pendingJobs[i]);
    }
}
```

### Mock Proof Generation
```solidity
function createValidProof(
    bytes32 modelCommitment,
    bytes32 inputHash,
    bytes32 outputHash
) pure returns (EZKLProof memory) {
    uint256[] memory instances = new uint256[](3);
    instances[0] = uint256(modelCommitment);
    instances[1] = uint256(inputHash);
    instances[2] = uint256(outputHash);
    
    return EZKLProof({
        instances: instances,
        proof: new uint256[](8),  // Mock proof data
        vk: new uint256[](4),     // Mock verification key
        modelCommitment: modelCommitment,
        inputHash: inputHash,
        outputHash: outputHash
    });
}
```

## Future Improvements

1. **Real EZKL Integration**:
   - Replace mock verifier with actual EZKL
   - Support multiple proof types

2. **Challenge Economics**:
   - Dynamic stake requirements
   - Reward for successful challenges

3. **Proof Aggregation**:
   - Combine multiple proofs
   - Reduce verification costs

4. **Time-based Verification**:
   - Priority queue for proofs
   - SLA enforcement

5. **Proof Storage**:
   - IPFS integration
   - Off-chain proof availability