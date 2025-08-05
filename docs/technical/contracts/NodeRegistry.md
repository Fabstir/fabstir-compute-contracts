# NodeRegistry Contract

## Overview

The NodeRegistry contract manages GPU host registration and staking for the Fabstir marketplace. It enforces minimum stake requirements, tracks node capabilities, and provides the foundation for decentralized compute provision.

**Contract Address**: To be deployed  
**Source**: [`src/NodeRegistry.sol`](../../../src/NodeRegistry.sol)

### Key Features
- Host registration with minimum 100 ETH stake
- Support for multiple AI models per node
- Regional node tracking
- Sybil attack detection
- Circuit breaker for registration spam
- Migration support for contract upgrades

### Dependencies
- OpenZeppelin Ownable

## Constructor

```solidity
constructor(uint256 _minStake) Ownable(msg.sender)
```

### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_minStake` | `uint256` | Minimum stake required for node registration (typically 100 ETH) |

### Example Deployment
```solidity
// Deploy with 100 ETH minimum stake
NodeRegistry registry = new NodeRegistry(100 ether);
```

## State Variables

### Public Variables
| Name | Type | Description |
|------|------|-------------|
| `MIN_STAKE` | `uint256` | Minimum stake required for registration |
| `migrationHelper` | `address` | Address authorized to add migrated nodes |

### Access Patterns
- `MIN_STAKE`: Read via `requiredStake()` or `minimumStake()`
- Node data: Access via `getNode()` for full details
- Governance: Access via `getGovernance()`

## Functions

### registerNodeSimple

Simplified node registration with automatic validation and rate limiting.

```solidity
function registerNodeSimple(string memory metadata) external payable
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `metadata` | `string` | Node peer ID or metadata (max 10KB) |

#### Requirements
- Registration not paused
- Metadata not empty and ≤ 10KB
- Valid characters (no control characters)
- `msg.value` ≥ `MIN_STAKE`
- Node not already registered
- Rate limit not exceeded (10 registrations/hour)

#### Emitted Events
- `NodeRegistered(address indexed node, string metadata)`

#### Reverts
| Error | Condition |
|-------|-----------|
| `"Registration is paused"` | Circuit breaker activated |
| `"Empty metadata"` | No metadata provided |
| `"Metadata too long"` | Metadata > 10KB |
| `"Invalid characters"` | Control characters in metadata |
| `"Insufficient stake"` | Sent ETH < MIN_STAKE |
| `"Already registered"` | Node already exists |

#### Gas Considerations
- ~150,000 gas
- Refunds excess ETH automatically

#### Example Usage
```solidity
// Register with exactly minimum stake
registry.registerNodeSimple{value: 100 ether}("QmPeerId123");

// Register with excess (auto-refunded)
registry.registerNodeSimple{value: 150 ether}("QmPeerId123");
```

### registerNode

Full node registration with model and region specification.

```solidity
function registerNode(
    string memory _peerId,
    string[] memory _models,
    string memory _region
) external payable
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_peerId` | `string` | IPFS peer ID or unique identifier |
| `_models` | `string[]` | Array of supported model IDs |
| `_region` | `string` | Geographic region code |

#### Requirements
- `msg.value` ≥ `MIN_STAKE`
- Node not already registered

#### Example Usage
```solidity
string[] memory models = new string[](2);
models[0] = "llama-2-70b";
models[1] = "mistral-7b";

registry.registerNode{value: 100 ether}(
    "QmPeerId123",
    models,
    "us-east-1"
);
```

### registerNodeFor

Register a node on behalf of another address (for ERC-4337 integration).

```solidity
function registerNodeFor(
    address operator,
    string memory _peerId,
    string[] memory _models,
    string memory _region
) external payable
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `operator` | `address` | Address to register as node operator |
| `_peerId` | `string` | IPFS peer ID |
| `_models` | `string[]` | Supported models |
| `_region` | `string` | Region code |

#### Access Control
- Can be called by anyone providing stake
- Typically used by BaseAccountIntegration

### getNode

Retrieve complete node information.

```solidity
function getNode(address _operator) external view returns (Node memory)
```

#### Returns
```solidity
struct Node {
    address operator;    // Node operator address
    string peerId;      // IPFS peer ID
    uint256 stake;      // Current stake amount
    bool active;        // Active status
    string[] models;    // Supported models
    string region;      // Geographic region
}
```

#### Example Usage
```solidity
NodeRegistry.Node memory node = registry.getNode(operatorAddress);
if (node.active && node.stake >= registry.requiredStake()) {
    // Node is valid for job assignment
}
```

### isNodeActive

Quick check if a node is registered and active.

```solidity
function isNodeActive(address _operator) external view returns (bool)
```

#### Returns
- `true` if node exists and is active
- `false` otherwise

### isActiveNode

Alternative active check with stake validation.

```solidity
function isActiveNode(address operator) external view returns (bool)
```

#### Returns
- `true` if node is active AND has sufficient stake
- `false` otherwise

### getNodeStake

Get current stake amount for a node.

```solidity
function getNodeStake(address _operator) external view returns (uint256)
```

### getActiveNodes

Retrieve all currently active nodes.

```solidity
function getActiveNodes() external view returns (address[] memory)
```

#### Returns
Array of addresses for all active nodes

#### Gas Considerations
- O(n) complexity where n = total registered nodes
- Can be expensive with many nodes
- Consider pagination in production

### slashNode

Slash a portion of node's stake (governance only).

```solidity
function slashNode(
    address node,
    uint256 amount,
    string memory reason
) external
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `node` | `address` | Node to slash |
| `amount` | `uint256` | Amount to slash from stake |
| `reason` | `string` | Reason for slashing |

#### Access Control
- Only callable by governance contract

#### Emitted Events
- `NodeSlashed(address indexed node, uint256 amount, string reason)`

### restoreStake

Add additional stake to an existing node.

```solidity
function restoreStake() external payable
```

#### Requirements
- Sender must be registered node
- `msg.value` > 0

#### Emitted Events
- `StakeRestored(address indexed node, uint256 amount)`

### unregisterNode

Attempt to unregister and withdraw stake.

```solidity
function unregisterNode() external
```

#### Requirements
- Node must be registered and active
- No active jobs (currently always reverts)

#### Note
Currently not implemented - always reverts with "Node has active jobs"

### updateStakeAmount

Update the minimum stake requirement.

```solidity
function updateStakeAmount(uint256 newAmount) external onlyOwner
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `newAmount` | `uint256` | New minimum stake amount |

#### Requirements
- Only owner
- `newAmount` > 0
- `newAmount` < 10,000 ETH

### setGovernance

Set the governance contract address (one-time).

```solidity
function setGovernance(address _governance) external onlyOwner
```

#### Requirements
- Only owner
- Governance not already set
- Valid address

## Sybil Detection Functions

### registerControlledNode

Register a node controlled by another address.

```solidity
function registerControlledNode(
    string memory metadata,
    address nodeOperator
) external payable
```

#### Purpose
- Track controller-node relationships
- Detect potential Sybil attacks
- Flag suspicious controllers

### isSuspiciousController

Check if a controller has registered too many nodes.

```solidity
function isSuspiciousController(address controller) external view returns (bool)
```

#### Returns
- `true` if controller has ≥ 3 nodes (SYBIL_THRESHOLD)

### getNodeController

Get the controller address for a node.

```solidity
function getNodeController(address node) external view returns (address)
```

## Circuit Breaker Functions

### isRegistrationPaused

Check if registration is currently paused.

```solidity
function isRegistrationPaused() external view returns (bool)
```

#### Automatic Pausing
- Pauses after 10 registrations within 1 hour
- Prevents registration spam attacks

## Migration Functions

### setMigrationHelper

Set address authorized to add migrated nodes.

```solidity
function setMigrationHelper(address _migrationHelper) external onlyOwner
```

### addMigratedNode

Add a node from previous contract version.

```solidity
function addMigratedNode(
    address operator,
    string memory peerId,
    string[] memory models,
    string memory region
) external payable onlyMigrationHelper
```

#### Access Control
- Only migration helper
- Used during contract upgrades

## Events

### NodeRegistered
```solidity
event NodeRegistered(address indexed node, string metadata)
```
Emitted when a new node is registered.

### NodeSlashed
```solidity
event NodeSlashed(address indexed node, uint256 amount, string reason)
```
Emitted when a node's stake is slashed.

### StakeRestored
```solidity
event StakeRestored(address indexed node, uint256 amount)
```
Emitted when additional stake is added.

## Errors

Common revert reasons:
- `"Insufficient stake"` - Sent ETH below minimum
- `"Already registered"` - Node exists
- `"Registration is paused"` - Circuit breaker active
- `"Not registered"` - Node doesn't exist
- `"Only governance"` - Unauthorized slashing attempt

## Security Considerations

1. **Reentrancy**: Uses checks-effects-interactions pattern
2. **Stake Validation**: Enforces minimum stake requirements
3. **Rate Limiting**: Maximum 10 registrations per hour
4. **Input Validation**: 
   - Metadata size limits (10KB)
   - Character validation (no control characters)
   - Stake amount limits
5. **Sybil Detection**: Tracks controller relationships
6. **Access Control**: Owner and governance roles

## Gas Optimization

1. **Storage Efficiency**:
   - Packs `operator` and `active` in same slot
   - Uses memory for temporary operations

2. **Batch Operations**:
   - `getActiveNodes()` for bulk retrieval
   - Consider off-chain indexing for large datasets

3. **Refund Pattern**:
   - Automatic refund of excess stake
   - Reduces user gas costs

## Integration Examples

### Basic Host Registration
```solidity
// Register as a host
string[] memory models = new string[](1);
models[0] = "gpt-3.5-turbo";

registry.registerNode{value: 100 ether}(
    "QmYourPeerId",
    models,
    "us-west-2"
);
```

### Check Node Eligibility
```solidity
function canAssignJob(address host) public view returns (bool) {
    NodeRegistry.Node memory node = registry.getNode(host);
    return node.active && 
           node.stake >= registry.requiredStake() &&
           !registry.isSuspiciousController(registry.getNodeController(host));
}
```

### Integration with JobMarketplace
```solidity
// In JobMarketplace.claimJob()
require(nodeRegistry.isActiveNode(msg.sender), "Not active host");
```