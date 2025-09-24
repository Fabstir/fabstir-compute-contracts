# Governance & GovernanceToken Contracts

## Overview

The Governance system provides decentralized decision-making for the Fabstir marketplace through proposal creation, voting, and execution mechanisms. It works in tandem with the GovernanceToken, an ERC20 token with voting capabilities.

**Contract Addresses**: Not yet deployed (Governance system pending)
**Network**: Base Sepolia (planned)
**Sources**: 
- [`src/Governance.sol`](../../../src/Governance.sol)
- [`src/GovernanceToken.sol`](../../../src/GovernanceToken.sol)

### Key Features
- On-chain proposal and voting system
- Time-locked execution for safety
- Parameter updates and contract upgrades
- Emergency actions for critical situations
- ERC20Votes token with delegation
- Checkpoint-based historical voting power

---

# Governance Contract

## Constructor

```solidity
constructor(
    address _governanceToken,
    address _nodeRegistry,
    address _jobMarketplace,
    address _paymentEscrow,
    address _reputationSystem,
    address _proofSystem
)
```

### Parameters
All parameters are addresses of the respective contracts in the system.

## Constants

| Name | Type | Value | Description |
|------|------|-------|-------------|
| `votingDelay` | `uint256` | 1 block | Delay before voting starts |
| `votingPeriod` | `uint256` | 50,400 blocks | ~7 days voting period |
| `executionDelay` | `uint256` | 2 days | Time lock for execution |
| `proposalThreshold` | `uint256` | 10,000e18 | 1% of total supply required |
| `quorumPercentage` | `uint256` | 10 | 10% quorum requirement |

## Proposal Types

### ProposalType Enum
```solidity
enum ProposalType {
    ParameterUpdate,    // Change contract parameters
    ContractUpgrade,    // Upgrade implementation
    Emergency          // Emergency actions
}
```

### ProposalState Enum
```solidity
enum ProposalState {
    Pending,    // Before voting starts
    Active,     // Voting open
    Succeeded,  // Passed voting
    Defeated,   // Failed voting
    Queued,     // Awaiting execution
    Executed,   // Completed
    Cancelled   // Cancelled by proposer
}
```

## Core Functions

### proposeParameterUpdate

Create a proposal to update contract parameters.

```solidity
function proposeParameterUpdate(
    ParameterUpdate[] memory updates,
    string memory description
) external returns (uint256 proposalId)
```

#### ParameterUpdate Structure
```solidity
struct ParameterUpdate {
    address targetContract;     // Contract to update
    bytes4 functionSelector;   // Function to call
    string parameterName;      // Parameter name
    uint256 newValue;         // New value
}
```

#### Requirements
- Proposer must have ≥ 1% of voting power
- Valid updates array

#### Example Usage
```solidity
ParameterUpdate[] memory updates = new ParameterUpdate[](1);
updates[0] = ParameterUpdate({
    targetContract: address(nodeRegistry),
    functionSelector: NodeRegistry.updateStakeAmount.selector,
    parameterName: "minimumStake",
    newValue: 150 ether
});

uint256 proposalId = governance.proposeParameterUpdate(
    updates,
    "Increase minimum stake to 150 ETH"
);
```

### proposeContractUpgrade

Create a proposal for contract upgrade.

```solidity
function proposeContractUpgrade(
    address targetContract,
    address newImplementation,
    string memory description
) external returns (uint256 proposalId)
```

#### Requirements
- Proposer must have ≥ 1% voting power
- Requires 80% super-majority to pass

### castVote

Vote on an active proposal.

```solidity
function castVote(uint256 proposalId, bool support) external
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `proposalId` | `uint256` | Proposal to vote on |
| `support` | `bool` | true = for, false = against |

#### Requirements
- Proposal must be Active
- One vote per address
- Must have voting power at proposal start

#### Emitted Events
- `VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight)`

### queue

Queue a successful proposal for execution.

```solidity
function queue(uint256 proposalId) external
```

#### Requirements
- Proposal must have Succeeded state
- Quorum must be reached

#### Effects
- Sets execution time (current + 2 days)
- Changes state to Queued

#### Emitted Events
- `ProposalQueued(uint256 indexed proposalId, uint256 executionTime)`

### execute

Execute a queued proposal.

```solidity
function execute(uint256 proposalId) external
```

#### Requirements
- Proposal must be Queued
- Execution delay must have passed

#### Effects
- Executes proposal based on type
- Marks as Executed

#### Emitted Events
- `ProposalExecuted(uint256 indexed proposalId)`
- `ParameterUpdated` (for parameter changes)

### cancel

Cancel a proposal (proposer only).

```solidity
function cancel(uint256 proposalId) external
```

#### Requirements
- Only original proposer
- Not already executed

### state

Get current proposal state.

```solidity
function state(uint256 proposalId) public view returns (ProposalState)
```

#### State Determination
1. Cancelled → `Cancelled`
2. Executed → `Executed`
3. Before start → `Pending`
4. During voting → `Active`
5. After voting:
   - Queued → `Queued`
   - Passed quorum & majority → `Succeeded`
   - Otherwise → `Defeated`

## Emergency Functions

### executeEmergencyAction

Execute emergency actions.

```solidity
function executeEmergencyAction(
    string memory action,
    address targetContract
) external onlyRole(EMERGENCY_ROLE)
```

#### Supported Actions
- `"pause"` - Pause target contract
- `"unpause"` - Unpause target contract

#### Requirements
- EMERGENCY_ROLE required

## View Functions

### getProposal

Get proposal details.

```solidity
function getProposal(uint256 proposalId) external view returns (
    address proposer,
    uint256 startBlock,
    uint256 endBlock,
    uint256 forVotes,
    uint256 againstVotes,
    bool executed,
    bool cancelled
)
```

### getVotingPower

Get an address's current voting power.

```solidity
function getVotingPower(address account) external view returns (uint256)
```

### isUpgradeExecuted

Check if an upgrade proposal was executed.

```solidity
function isUpgradeExecuted(uint256 proposalId) external view returns (bool)
```

---

# GovernanceToken Contract

## Constructor

```solidity
constructor(
    string memory _name,
    string memory _symbol,
    uint256 _initialSupply
)
```

### Example Deployment
```solidity
GovernanceToken token = new GovernanceToken(
    "Fabstir Governance",
    "FAB",
    1_000_000 ether  // 1M tokens
);
```

## ERC20 Functions

### Standard Functions
- `totalSupply()` - Get total token supply
- `balanceOf(address)` - Get balance
- `transfer(address, uint256)` - Transfer tokens
- `approve(address, uint256)` - Approve spender
- `transferFrom(address, address, uint256)` - Transfer from
- `allowance(address, address)` - Check allowance

### Additional Functions

#### mint
```solidity
function mint(address to, uint256 amount) public onlyOwner
```
Mint new tokens (owner only).

#### burn
```solidity
function burn(uint256 amount) public
```
Burn tokens from caller's balance.

## Voting Functions

### delegate

Delegate voting power.

```solidity
function delegate(address delegatee) public
```

#### Effects
- Moves voting power to delegatee
- Self-delegation allowed

### delegateBySig

Delegate via signature (gasless).

```solidity
function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
) public
```

#### Requirements
- Valid signature
- Correct nonce
- Not expired

### getVotes

Get current voting power.

```solidity
function getVotes(address account) public view returns (uint256)
```

### getPastVotes

Get historical voting power.

```solidity
function getPastVotes(address account, uint256 blockNumber) 
    public view returns (uint256)
```

#### Requirements
- Block must be mined

### getPastTotalSupply

Get historical total supply.

```solidity
function getPastTotalSupply(uint256 blockNumber) 
    public view returns (uint256)
```

## Delegation Mechanics

### How It Works
1. Token holders can delegate to any address
2. Delegates vote with combined power
3. Delegation can be changed anytime
4. Historical checkpoints track changes

### Example Flow
```solidity
// Alice has 1000 tokens
token.delegate(bobAddress);  // Bob now votes with 1000 power

// Bob can vote in governance
governance.castVote(proposalId, true);  // Uses Alice's 1000 tokens

// Alice can redelegate anytime
token.delegate(aliceAddress);  // Takes back voting power
```

## Events

### Governance Events
```solidity
event ProposalCreated(uint256 indexed proposalId, address indexed proposer, ProposalType proposalType, string description)
event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight)
event ProposalQueued(uint256 indexed proposalId, uint256 executionTime)
event ProposalExecuted(uint256 indexed proposalId)
event ProposalCancelled(uint256 indexed proposalId)
event ParameterUpdated(address indexed contract_, string parameter, uint256 oldValue, uint256 newValue)
event EmergencyActionExecuted(address indexed executor, string action)
```

### Token Events
```solidity
event Transfer(address indexed from, address indexed to, uint256 value)
event Approval(address indexed owner, address indexed spender, uint256 value)
event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)
event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance)
```

## Security Considerations

### Governance
1. **Time Locks**: 2-day delay prevents rushed execution
2. **Quorum**: 10% participation required
3. **Threshold**: 1% tokens needed to propose
4. **Super Majority**: 80% for upgrades
5. **Role-Based**: Emergency actions restricted

### Token
1. **Checkpoint System**: Prevents double-voting
2. **EIP-712**: Secure signature delegation
3. **Overflow Protection**: Safe math throughout
4. **Access Control**: Only owner can mint

## Integration Examples

### Complete Governance Flow
```solidity
// 1. Create proposal
uint256 proposalId = governance.proposeParameterUpdate(
    updates,
    "Reduce fees to 1%"
);

// 2. Wait 1 block for voting to start

// 3. Token holders vote
governance.castVote(proposalId, true);

// 4. After 7 days, check if passed
if (governance.state(proposalId) == ProposalState.Succeeded) {
    // 5. Queue for execution
    governance.queue(proposalId);
    
    // 6. Wait 2 days
    
    // 7. Execute
    governance.execute(proposalId);
}
```

### Delegation Pattern
```solidity
// Setup delegation
token.delegate(trustedDelegate);

// Or delegate to self for direct voting
token.delegate(msg.sender);

// Check voting power
uint256 power = token.getVotes(msg.sender);
require(power >= governance.proposalThreshold(), "Insufficient power");
```

### Emergency Response
```solidity
// Grant emergency role
governance.grantRole(EMERGENCY_ROLE, emergencyMultisig);

// In emergency
governance.executeEmergencyAction("pause", jobMarketplace);

// After resolution
governance.executeEmergencyAction("unpause", jobMarketplace);
```

## Best Practices

1. **Proposal Creation**:
   - Clear descriptions
   - Batch related changes
   - Test parameters first

2. **Voting**:
   - Delegate early
   - Monitor proposal states
   - Participate in quorum

3. **Token Management**:
   - Keep tokens delegated
   - Use self-delegation for control
   - Monitor voting power

4. **Emergency Preparedness**:
   - Multi-sig for emergency role
   - Clear escalation procedures
   - Regular drills

## Limitations & Future Improvements

1. **Fixed Parameters**: Some values hardcoded
2. **Upgrade Mechanism**: Simplified implementation
3. **Vote Buying**: No prevention mechanism
4. **Participation**: No incentives for voting
5. **Proposal Spam**: Limited prevention