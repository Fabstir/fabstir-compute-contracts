# JobMarketplace Contract

## Overview

The JobMarketplace contract is the core engine of the Fabstir marketplace, managing the entire job lifecycle from posting to completion. It integrates with NodeRegistry for host verification and includes comprehensive security features like circuit breakers and rate limiting.

**Contract Address**: To be deployed  
**Source**: [`src/JobMarketplace.sol`](../../../src/JobMarketplace.sol)

### Key Features
- Job posting with escrow payment
- Host claiming and assignment
- Deadline enforcement
- Circuit breaker system with multiple protection levels
- Rate limiting and anti-spam measures
- Batch operations for gas efficiency
- Sybil attack detection
- Emergency pause functionality

### Dependencies
- NodeRegistry (host verification)
- ReputationSystem (quality tracking)
- OpenZeppelin ReentrancyGuard

## Constructor

```solidity
constructor(address _nodeRegistry)
```

### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_nodeRegistry` | `address` | Address of the NodeRegistry contract |

### Example Deployment
```solidity
JobMarketplace marketplace = new JobMarketplace(nodeRegistryAddress);
```

## State Variables

### Public Variables
| Name | Type | Description |
|------|------|-------------|
| `MAX_PAYMENT` | `uint256` | Maximum allowed payment (1000 ETH) |
| `nodeRegistry` | `NodeRegistry` | NodeRegistry contract instance |
| `reputationSystem` | `ReputationSystem` | ReputationSystem contract instance |
| `failureThreshold` | `uint256` | Failure count before auto-pause (default: 5) |
| `migrationHelper` | `address` | Address authorized for migration operations |

### Access Patterns
- Job data: Access via `getJob()` or `getJobStruct()`
- Circuit breaker status: `getCircuitBreakerLevel()`, `isPaused()`, `isThrottled()`
- Metrics: `getCircuitBreakerMetrics()`

## Core Functions

### createJob

Create a new job with payment in escrow.

```solidity
function createJob(
    string memory _modelId,
    string memory _inputHash,
    uint256 _maxPrice,
    uint256 _deadline
) external payable returns (uint256)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_modelId` | `string` | ID of the AI model required |
| `_inputHash` | `string` | Hash of input data |
| `_maxPrice` | `uint256` | Maximum payment for the job |
| `_deadline` | `uint256` | Unix timestamp deadline |

#### Requirements
- `msg.value` ≥ `_maxPrice`
- `_deadline` > current timestamp
- Contract not paused

#### Returns
- `uint256` - Unique job ID

#### Emitted Events
- `JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice)`

#### Example Usage
```solidity
uint256 jobId = marketplace.createJob{value: 1 ether}(
    "llama-2-70b",
    "QmInputHash123",
    1 ether,
    block.timestamp + 1 days
);
```

### postJob

Advanced job posting with detailed requirements.

```solidity
function postJob(
    IJobMarketplace.JobDetails memory details,
    IJobMarketplace.JobRequirements memory requirements,
    uint256 payment
) external payable returns (uint256)
```

#### Parameters
```solidity
struct JobDetails {
    string modelId;
    string prompt;
    uint256 maxTokens;
    uint256 temperature;
}

struct JobRequirements {
    uint256 maxTimeToComplete;  // in seconds
    uint256 minGPUMemory;       // in GB
}
```

#### Requirements
- Payment validation (0 < payment ≤ 1000 ETH)
- Valid parameters (tokens ≤ 1M, temperature ≤ 20000)
- Prompt size ≤ 10KB
- Deadline ≥ 60 seconds
- Rate limits not exceeded

#### Rate Limiting
- Short window: 3 posts per minute
- Long window: 10 posts per hour

#### Example Usage
```solidity
IJobMarketplace.JobDetails memory details = IJobMarketplace.JobDetails({
    modelId: "gpt-4",
    prompt: "Analyze this dataset...",
    maxTokens: 4000,
    temperature: 700  // 0.7 * 1000
});

IJobMarketplace.JobRequirements memory requirements = IJobMarketplace.JobRequirements({
    maxTimeToComplete: 3600,  // 1 hour
    minGPUMemory: 16         // 16GB
});

uint256 jobId = marketplace.postJob{value: 2 ether}(details, requirements, 2 ether);
```

### claimJob

Host claims a job for execution.

```solidity
function claimJob(uint256 _jobId) external
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_jobId` | `uint256` | ID of job to claim |

#### Requirements
- Job exists and is in Posted state
- Job not expired
- Caller is registered active host
- Not claimed by Sybil-related node
- Throttling cooldown respected (if active)

#### Sybil Detection
- Checks if node controller has failed this job before
- Prevents re-attempts by related nodes

#### Emitted Events
- `JobClaimed(uint256 indexed jobId, address indexed host)`

#### Reverts
| Error | Condition |
|-------|-----------|
| `"Job does not exist"` | Invalid job ID |
| `"Job expired"` | Past deadline |
| `"Job already claimed"` | Not in Posted state |
| `"Not a registered host"` | Caller not in NodeRegistry |
| `"Host not active"` | Host inactive |
| `"Sybil attack detected"` | Controller previously failed |
| `"Please wait before next operation"` | Throttling active |

### completeJob

Submit job completion with proof.

```solidity
function completeJob(
    uint256 _jobId,
    string memory _resultHash,
    bytes memory _proof
) external nonReentrant
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_jobId` | `uint256` | Job ID |
| `_resultHash` | `string` | Hash of result data |
| `_proof` | `bytes` | Proof of computation |

#### Requirements
- Caller is assigned host
- Job in Claimed state
- Before deadline
- Reentrancy protected

#### Effects
- Marks job as completed
- Transfers payment to host
- Updates reputation (if available)

#### Emitted Events
- `JobCompleted(uint256 indexed jobId, string resultCID)`

### releasePayment

Renter releases payment after verification.

```solidity
function releasePayment(uint256 _jobId) external nonReentrant
```

#### Requirements
- Caller is job renter
- Job completed
- Reentrancy protected

#### Suspicious Activity Detection
- Tracks quick releases (< 30 seconds)
- Throttles after threshold reached

#### Emitted Events
- `PaymentReleased(uint256 indexed jobId, address indexed node, uint256 amount)`
- `PaymentRefunded(uint256 indexed jobId, address indexed client, uint256 amount)` (on failure)

### getJob

Retrieve job information.

```solidity
function getJob(uint256 _jobId) external view returns (
    address renter,
    uint256 payment,
    IJobMarketplace.JobStatus status,
    address assignedHost,
    string memory resultHash,
    uint256 deadline
)
```

#### Returns
Tuple with job details compatible with IJobMarketplace interface.

### getJobStruct

Get complete job data structure.

```solidity
function getJobStruct(uint256 _jobId) external view returns (Job memory)
```

#### Returns
```solidity
struct Job {
    address renter;
    JobStatus status;
    address assignedHost;
    uint256 maxPrice;
    uint256 deadline;
    uint256 completedAt;
    string modelId;
    string inputHash;
    string resultHash;
}
```

## Batch Operations

### batchPostJobs

Post multiple jobs in single transaction.

```solidity
function batchPostJobs(
    IJobMarketplace.JobDetails[] memory detailsList,
    IJobMarketplace.JobRequirements[] memory requirementsList,
    uint256[] memory payments
) external payable returns (uint256[] memory)
```

#### Requirements
- Arrays same length
- 1-100 jobs per batch
- Total payment matches msg.value

#### Gas Optimization
- Single nextJobId update
- Reduced validation overhead
- ~30% gas savings vs individual posts

#### Example Usage
```solidity
// Prepare arrays
JobDetails[] memory details = new JobDetails[](3);
JobRequirements[] memory reqs = new JobRequirements[](3);
uint256[] memory payments = new uint256[](3);

// Fill arrays...

uint256[] memory jobIds = marketplace.batchPostJobs{value: 6 ether}(
    details,
    reqs,
    payments
);
```

### batchReleasePayments

Release payments for multiple completed jobs.

```solidity
function batchReleasePayments(uint256[] memory jobIds) external nonReentrant
```

#### Requirements
- Caller must be renter for all jobs
- Jobs must be completed
- Reentrancy protected

## Circuit Breaker System

### Protection Levels

| Level | Name | Description | Effects |
|-------|------|-------------|---------|
| 0 | Monitoring | Normal operation | Event logging only |
| 1 | Throttled | Elevated risk detected | 5-minute cooldown between operations |
| 2 | Paused | Critical failure | All operations blocked |

### emergencyPause

Pause all contract operations.

```solidity
function emergencyPause(string memory reason) external
```

#### Access Control
- Owner or Guardian role

#### Emitted Events
- `EmergencyPause(address by, string reason)`

### unpause

Resume operations after cooldown.

```solidity
function unpause() external onlyOwner
```

#### Requirements
- 1 hour cooldown period elapsed

### pauseFunction

Selectively pause specific functions.

```solidity
function pauseFunction(string memory functionName) external
```

#### Example
```solidity
marketplace.pauseFunction("postJob");  // Only disable job posting
```

### setCircuitBreakerLevel

Manually set protection level.

```solidity
function setCircuitBreakerLevel(uint256 level) external
```

#### Requirements
- Owner or Guardian role
- Valid level (0-2)
- No level skipping

### Auto-Recovery

Enable automatic recovery after incidents.

```solidity
function enableAutoRecovery(uint256 period) external onlyOwner
```

#### Example
```solidity
marketplace.enableAutoRecovery(1 days);  // Auto-unpause after 1 day
```

## Failed Job Handling

### markJobFailed

Mark a job as failed (internal use).

```solidity
function markJobFailed(uint256 _jobId, string memory reason) external
```

#### Effects
- Resets job to Posted state
- Tracks failed node for Sybil detection
- Increments failure counter
- May trigger auto-pause

#### Emitted Events
- `JobFailed(uint256 indexed jobId, address indexed host, string reason)`

### claimAbandonedPayment

Reclaim payment for long-abandoned jobs.

```solidity
function claimAbandonedPayment(uint256 _jobId) external nonReentrant
```

#### Requirements
- 30 days past deadline
- Job not completed
- Caller is renter

## Dispute Resolution

### disputeResult

Initiate dispute on completed job.

```solidity
function disputeResult(uint256 _jobId, string memory reason) external
```

#### Requirements
- Caller is job renter
- Job completed

#### Note
Currently emits event only - full resolution pending implementation.

### resolveDispute

Governance resolves dispute.

```solidity
function resolveDispute(uint256 _jobId, bool favorClient) external
```

#### Access Control
- Governance only

#### Emitted Events
- `DisputeResolved(uint256 indexed jobId, bool favorClient)`

## Access Control

### grantRole

Grant role to an address.

```solidity
function grantRole(bytes32 role, address account) external onlyOwner
```

#### Available Roles
- `GUARDIAN_ROLE`: Can pause/unpause functions

### setReputationSystem

Set reputation system contract (one-time).

```solidity
function setReputationSystem(address _reputationSystem) external
```

### setGovernance

Set governance contract (one-time).

```solidity
function setGovernance(address _governance) external
```

## View Functions

### getActiveJobIds

Get array of active job IDs.

```solidity
function getActiveJobIds() external view returns (uint256[] memory)
```

#### Returns
Up to 100 active (Posted or Claimed) job IDs.

### getCircuitBreakerMetrics

Get circuit breaker statistics.

```solidity
function getCircuitBreakerMetrics() external view returns (
    uint256 failureCount_,
    uint256 successCount,
    uint256 suspiciousActivities,
    uint256 lastIncidentTime_
)
```

### isThrottled

Check if throttling is active.

```solidity
function isThrottled() external view returns (bool)
```

### isMonitoring

Check if address is being monitored.

```solidity
function isMonitoring(address addr) external view returns (bool)
```

## Events

### Job Lifecycle
```solidity
event JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice)
event JobPosted(uint256 indexed jobId, address indexed client, uint256 payment)
event JobClaimed(uint256 indexed jobId, address indexed host)
event JobCompleted(uint256 indexed jobId, string resultCID)
event JobFailed(uint256 indexed jobId, address indexed host, string reason)
```

### Payments
```solidity
event PaymentReleased(uint256 indexed jobId, address indexed node, uint256 amount)
event PaymentRefunded(uint256 indexed jobId, address indexed client, uint256 amount)
```

### Circuit Breaker
```solidity
event EmergencyPause(address by, string reason)
event EmergencyUnpause(address by)
event CircuitBreakerTriggered(string reason, uint256 level)
```

### Disputes
```solidity
event DisputeResolved(uint256 indexed jobId, bool favorClient)
```

## Security Considerations

1. **Reentrancy Protection**: All payment functions use ReentrancyGuard
2. **Rate Limiting**: 
   - 3 posts/minute (rapid)
   - 10 posts/hour (sustained)
3. **Circuit Breakers**:
   - Auto-pause on high failure rate
   - Manual pause by guardians
   - Selective function pausing
4. **Sybil Detection**: Tracks failed nodes by controller
5. **Input Validation**:
   - Payment limits (1000 ETH max)
   - String size limits
   - Parameter range checks
6. **Deadline Enforcement**: Automatic expiry handling
7. **Access Control**: Owner and Guardian roles

## Gas Optimization

1. **Storage Packing**:
   - `renter` and `status` packed in single slot
   - Efficient Job struct layout

2. **Batch Operations**:
   - Up to 30% savings with batch posts
   - Reduced validation overhead

3. **View Functions**:
   - Avoid loops where possible
   - Limited array returns (100 max)

## Integration Examples

### Complete Job Flow
```solidity
// 1. Renter posts job
uint256 jobId = marketplace.createJob{value: 1 ether}(
    "llama-2-70b",
    "QmInputHash",
    1 ether,
    block.timestamp + 1 hours
);

// 2. Host claims job
marketplace.claimJob(jobId);

// 3. Host completes job
marketplace.completeJob(jobId, "QmResultHash", proofBytes);

// 4. Renter releases payment
marketplace.releasePayment(jobId);
```

### Integration with Circuit Breakers
```solidity
// Check if safe to proceed
if (marketplace.isPaused()) {
    revert("Marketplace paused");
}

if (marketplace.isThrottled()) {
    // Wait for cooldown
    uint256 waitTime = 5 minutes;
}

// Monitor failure rate
(uint256 failures, uint256 successes,,) = marketplace.getCircuitBreakerMetrics();
if (failures > successes / 10) {
    // High failure rate - proceed with caution
}
```

### Batch Job Posting
```solidity
function postMultipleJobs(
    string[] memory prompts,
    uint256 paymentPerJob
) external payable {
    uint256 count = prompts.length;
    
    JobDetails[] memory details = new JobDetails[](count);
    JobRequirements[] memory reqs = new JobRequirements[](count);
    uint256[] memory payments = new uint256[](count);
    
    for (uint i = 0; i < count; i++) {
        details[i] = JobDetails({
            modelId: "gpt-4",
            prompt: prompts[i],
            maxTokens: 2000,
            temperature: 700
        });
        
        reqs[i] = JobRequirements({
            maxTimeToComplete: 3600,
            minGPUMemory: 16
        });
        
        payments[i] = paymentPerJob;
    }
    
    marketplace.batchPostJobs{value: msg.value}(details, reqs, payments);
}
```