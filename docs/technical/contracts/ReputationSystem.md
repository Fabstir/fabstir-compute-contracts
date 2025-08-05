# ReputationSystem Contract

## Overview

The ReputationSystem contract tracks host performance and reputation across the Fabstir marketplace. It enables quality-based routing, incentive mechanisms, and maintains a decaying reputation score to ensure recent performance is weighted appropriately.

**Contract Address**: To be deployed  
**Source**: [`src/ReputationSystem.sol`](../../../src/ReputationSystem.sol)

### Key Features
- Performance-based reputation scoring
- Time-decay mechanism for scores
- 5-star rating system from renters
- Reputation-based host sorting
- Incentive eligibility tracking
- Governance-controlled slashing

### Dependencies
- NodeRegistry (host verification)
- JobMarketplace (job completion tracking)
- OpenZeppelin Ownable

## Constructor

```solidity
constructor(
    address _nodeRegistry,
    address _jobMarketplace,
    address _governance
) Ownable(msg.sender)
```

### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_nodeRegistry` | `address` | NodeRegistry contract address |
| `_jobMarketplace` | `address` | JobMarketplace contract address |
| `_governance` | `address` | Governance contract address |

### Example Deployment
```solidity
ReputationSystem reputation = new ReputationSystem(
    nodeRegistryAddress,
    jobMarketplaceAddress,
    governanceAddress
);
```

## Constants

| Name | Type | Value | Description |
|------|------|-------|-------------|
| `INITIAL_REPUTATION` | `uint256` | 100 | Starting reputation for new hosts |
| `SUCCESS_BONUS` | `uint256` | 10 | Points added for successful job |
| `FAILURE_PENALTY` | `uint256` | 20 | Points deducted for failed job |
| `DECAY_PERIOD` | `uint256` | 30 days | Time period for reputation decay |
| `DECAY_RATE` | `uint256` | 5 | Percentage decay per period |
| `INCENTIVE_THRESHOLD` | `uint256` | 150 | Minimum score for incentive eligibility |

## State Variables

### Public Variables
| Name | Type | Description |
|------|------|-------------|
| `nodeRegistry` | `NodeRegistry` | NodeRegistry contract instance |
| `jobMarketplace` | `JobMarketplace` | JobMarketplace contract instance |
| `governance` | `address` | Governance contract address |
| `authorizedContracts` | `mapping(address => bool)` | Contracts authorized to update reputation |
| `hostReputations` | `mapping(address => HostReputation)` | Host reputation data |
| `allHosts` | `address[]` | Array of all tracked hosts |
| `isTrackedHost` | `mapping(address => bool)` | Whether host is tracked |
| `migrationHelper` | `address` | Migration helper address |

### HostReputation Structure
```solidity
struct HostReputation {
    uint256 score;                              // Current reputation score
    uint256 totalRatings;                       // Number of ratings received
    uint256 sumRatings;                         // Sum of all ratings (1-5)
    uint256 lastActivityTimestamp;              // Last activity time
    mapping(uint256 => bool) hasRatedJob;       // Prevents double rating
}
```

## Core Functions

### addAuthorizedContract

Authorize a contract to update reputation.

```solidity
function addAuthorizedContract(address _contract) external onlyOwner
```

#### Requirements
- Only owner
- Valid address

#### Usage
Allows additional contracts (beyond JobMarketplace) to update reputation.

### updateReputation

Update a host's reputation score.

```solidity
function updateReputation(address host, uint256 change, bool positive) external
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `host` | `address` | Host address |
| `change` | `uint256` | Amount to change |
| `positive` | `bool` | true for increase, false for decrease |

#### Requirements
- Caller must be authorized contract

#### Effects
- Initializes host if first time
- Adds/subtracts score (floor at 0)

### getReputation

Get current reputation score with decay applied.

```solidity
function getReputation(address host) external view returns (uint256)
```

#### Returns
- 0 if host not registered in NodeRegistry
- Explicitly set score if available
- 0 if no activity recorded (for untracked hosts)
- Decayed score based on time since last activity

#### Decay Calculation
```solidity
periods = timePassed / DECAY_PERIOD
decayAmount = (score * periods * DECAY_RATE) / 100
finalScore = score - decayAmount
```

### recordJobCompletion

Record job completion outcome (JobMarketplace only).

```solidity
function recordJobCompletion(
    address host,
    uint256 jobId,
    bool success
) external onlyJobMarketplace
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `host` | `address` | Host who completed job |
| `jobId` | `uint256` | Job ID (for event tracking) |
| `success` | `bool` | Whether job succeeded |

#### Effects
- Success: +10 points (SUCCESS_BONUS)
- Failure: -20 points (FAILURE_PENALTY)
- Updates lastActivityTimestamp

#### Emitted Events
- `ReputationUpdated(address indexed host, int256 change, uint256 newScore)`

### rateHost

Submit a rating for completed job.

```solidity
function rateHost(
    address host,
    uint256 jobId,
    uint8 rating,
    string memory feedback
) external
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `host` | `address` | Host to rate |
| `jobId` | `uint256` | Completed job ID |
| `rating` | `uint8` | Rating 1-5 stars |
| `feedback` | `string` | Text feedback |

#### Requirements
- Rating between 1-5
- Caller must be job renter
- Host must be assigned to job
- Job must be completed
- No duplicate ratings

#### Bonus Reputation
- 4 stars: +2 reputation
- 5 stars: +4 reputation

#### Emitted Events
- `QualityReported(address indexed host, address indexed renter, uint8 rating, string feedback)`
- `ReputationUpdated(address indexed host, int256 change, uint256 newScore)` (if bonus applied)

### getAverageRating

Get host's average star rating.

```solidity
function getAverageRating(address host) external view returns (uint256)
```

#### Returns
- 0 if no ratings
- Average rating (1-5)

### sortHostsByReputation

Sort array of hosts by reputation (descending).

```solidity
function sortHostsByReputation(address[] memory hosts) external view returns (address[] memory)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `hosts` | `address[]` | Array of host addresses |

#### Returns
Same array sorted by reputation (highest first)

#### Algorithm
Bubble sort - O(n²) complexity

#### Example Usage
```solidity
address[] memory activeHosts = nodeRegistry.getActiveNodes();
address[] memory sortedHosts = reputation.sortHostsByReputation(activeHosts);
// sortedHosts[0] has highest reputation
```

### applyReputationDecay

Manually trigger reputation decay calculation.

```solidity
function applyReputationDecay(address host) external
```

#### Requirements
- Host must have recorded activity

#### Effects
- Calculates current decayed reputation
- Updates stored score
- Resets lastActivityTimestamp

### slashReputation

Reduce host reputation (governance only).

```solidity
function slashReputation(
    address host,
    uint256 amount,
    string memory reason
) external onlyGovernance
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `host` | `address` | Host to slash |
| `amount` | `uint256` | Amount to reduce |
| `reason` | `string` | Reason for slashing |

#### Requirements
- Only governance contract

#### Effects
- Reduces score (floor at 0)
- Initializes host if needed

#### Emitted Events
- `ReputationSlashed(address indexed host, uint256 amount, string reason)`
- `ReputationUpdated(address indexed host, int256 change, uint256 newScore)`

### isEligibleForIncentives

Check if host qualifies for additional incentives.

```solidity
function isEligibleForIncentives(address host) external view returns (bool)
```

#### Returns
- `true` if reputation ≥ 150 (INCENTIVE_THRESHOLD)
- `false` otherwise

### getTopHosts

Get the top N hosts by reputation.

```solidity
function getTopHosts(uint256 count) external view returns (address[] memory)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `count` | `uint256` | Number of top hosts to return |

#### Returns
Array of host addresses sorted by reputation

#### Algorithm
- O(n*count) complexity
- Returns fewer if not enough hosts

#### Example Usage
```solidity
// Get top 10 hosts
address[] memory topHosts = reputation.getTopHosts(10);
```

## Migration Functions

### setMigrationHelper

Set migration helper address.

```solidity
function setMigrationHelper(address _migrationHelper) external onlyOwner
```

### setMigratedReputation

Import reputation from previous contract.

```solidity
function setMigratedReputation(
    address node,
    uint256 score
) external onlyMigrationHelper
```

#### Effects
- Sets reputation score
- Updates lastActivityTimestamp
- Initializes tracking

### getNodesWithReputation

Get all tracked hosts.

```solidity
function getNodesWithReputation() external view returns (address[] memory)
```

#### Returns
Array of all hosts with reputation data

## Events

### ReputationUpdated
```solidity
event ReputationUpdated(address indexed host, int256 change, uint256 newScore)
```
Emitted when reputation changes.

### QualityReported
```solidity
event QualityReported(address indexed host, address indexed renter, uint8 rating, string feedback)
```
Emitted when host receives a rating.

### ReputationSlashed
```solidity
event ReputationSlashed(address indexed host, uint256 amount, string reason)
```
Emitted when governance slashes reputation.

## Access Modifiers

### onlyJobMarketplace
```solidity
modifier onlyJobMarketplace()
```
Restricts to JobMarketplace contract.

### onlyGovernance
```solidity
modifier onlyGovernance()
```
Restricts to governance contract.

## Security Considerations

1. **Access Control**:
   - JobMarketplace exclusive for job recording
   - Governance exclusive for slashing
   - Owner controls authorized contracts

2. **Rating Security**:
   - Job verification prevents fake ratings
   - One rating per job per renter
   - Must be completed job

3. **Score Manipulation**:
   - Authorized contracts only
   - Floor at 0 (no negative scores)
   - Decay prevents eternal high scores

4. **Initialization**:
   - Automatic host initialization
   - Consistent starting reputation

## Gas Optimization

1. **Storage Patterns**:
   - Host tracking prevents duplicate array entries
   - Checkpoint pattern for historical data

2. **View Functions**:
   - Decay calculated on-demand
   - No storage updates in views

3. **Batch Operations**:
   - sortHostsByReputation for bulk processing
   - getTopHosts for leaderboards

## Integration Examples

### Basic Reputation Flow
```solidity
// 1. Host completes job successfully
// JobMarketplace automatically calls:
reputation.recordJobCompletion(hostAddress, jobId, true);
// Host gains +10 reputation

// 2. Renter rates the host
reputation.rateHost(hostAddress, jobId, 5, "Excellent service!");
// Host gains +4 bonus reputation

// 3. Check reputation
uint256 score = reputation.getReputation(hostAddress);
// Returns 114 (100 initial + 10 success + 4 rating bonus)
```

### Quality-Based Host Selection
```solidity
function selectBestHost(address[] memory candidates) public view returns (address) {
    address bestHost = address(0);
    uint256 bestScore = 0;
    
    for (uint i = 0; i < candidates.length; i++) {
        uint256 score = reputation.getReputation(candidates[i]);
        if (score > bestScore) {
            bestScore = score;
            bestHost = candidates[i];
        }
    }
    
    return bestHost;
}
```

### Reputation Decay Example
```solidity
// Host has 200 reputation, inactive for 60 days
// Decay: 2 periods * 5% = 10% total
// 200 - (200 * 10 / 100) = 180
uint256 currentRep = reputation.getReputation(host);
// Returns 180
```

### Incentive Integration
```solidity
// In reward distribution
if (reputation.isEligibleForIncentives(host)) {
    // Provide bonus rewards
    uint256 bonusMultiplier = 120; // 20% bonus
    rewards = (baseRewards * bonusMultiplier) / 100;
}
```

### Leaderboard Implementation
```solidity
function displayLeaderboard() external view {
    address[] memory top10 = reputation.getTopHosts(10);
    
    for (uint i = 0; i < top10.length; i++) {
        uint256 score = reputation.getReputation(top10[i]);
        uint256 avgRating = reputation.getAverageRating(top10[i]);
        
        emit LeaderboardEntry(i + 1, top10[i], score, avgRating);
    }
}
```

## Best Practices

1. **Regular Activity**: Encourage hosts to maintain activity to prevent decay
2. **Rating Incentives**: Reward renters for providing ratings
3. **Reputation Thresholds**: Use reputation for tiered benefits
4. **Decay Management**: Consider manual decay triggers for gas efficiency
5. **Score Visibility**: Make reputation transparent for trust

## Limitations & Future Improvements

1. **Sorting Efficiency**: Current O(n²) sort could be optimized
2. **Historical Data**: No detailed history tracking
3. **Weighted Ratings**: All ratings count equally
4. **Decay Granularity**: Fixed 30-day periods
5. **Multi-factor Reputation**: Could include job complexity, value, etc.