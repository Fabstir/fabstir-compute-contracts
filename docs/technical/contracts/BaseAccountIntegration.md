# BaseAccountIntegration Contract

## Overview

The BaseAccountIntegration contract provides ERC-4337 account abstraction support for the Fabstir marketplace, enabling gasless transactions, batch operations, session keys, and payment streaming. It acts as a bridge between smart wallets and the marketplace contracts.

**Contract Address**: To be deployed  
**Source**: [`src/BaseAccountIntegration.sol`](../../../src/BaseAccountIntegration.sol)

### Key Features
- ERC-4337 UserOperation handling
- Gasless transaction sponsorship
- Session key management
- Batch operation execution
- Payment streaming
- Smart wallet integration

### Dependencies
- JobMarketplace contract
- NodeRegistry contract
- IAccount interface
- UserOperation struct

## Constructor

```solidity
constructor(
    address _entryPoint,
    address _paymaster,
    address _jobMarketplace,
    address _nodeRegistry
)
```

### Parameters
| Name | Type | Description |
|------|------|-------------|
| `_entryPoint` | `address` | ERC-4337 EntryPoint contract |
| `_paymaster` | `address` | Paymaster for gas sponsorship |
| `_jobMarketplace` | `address` | JobMarketplace contract |
| `_nodeRegistry` | `address` | NodeRegistry contract |

### Example Deployment
```solidity
BaseAccountIntegration integration = new BaseAccountIntegration(
    entryPointAddress,
    paymasterAddress,
    jobMarketplaceAddress,
    nodeRegistryAddress
);
```

## Data Structures

### Operation
```solidity
struct Operation {
    address target;    // Contract to call
    uint256 value;    // ETH value to send
    bytes data;       // Encoded function call
}
```

### SessionKey
```solidity
struct SessionKey {
    uint256 expires;   // Expiration timestamp
    bool isActive;     // Active status
}
```

### PaymentStream
```solidity
struct PaymentStream {
    address from;          // Payer
    address to;           // Recipient
    uint256 totalAmount;  // Total stream value
    uint256 startTime;    // Stream start
    uint256 duration;     // Stream duration
    uint256 withdrawn;    // Amount withdrawn
    bool active;          // Stream status
}
```

## ERC-4337 Integration

### handleOp

Process UserOperation from EntryPoint.

```solidity
function handleOp(
    UserOperation calldata userOp,
    uint256 gasUsed
) external payable onlyEntryPoint
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `userOp` | `UserOperation` | ERC-4337 operation data |
| `gasUsed` | `uint256` | Gas consumed |

#### UserOperation Structure
```solidity
struct UserOperation {
    address sender;           // Wallet address
    uint256 nonce;           // Anti-replay
    bytes initCode;          // Wallet deployment
    bytes callData;          // Execution data
    uint256 callGasLimit;    // Execution gas
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;  // Paymaster info
    bytes signature;         // Validation signature
}
```

#### Effects
- Validates callData format
- Executes operation on behalf of wallet
- Handles special integration functions
- Emits sponsorship events

#### Emitted Events
- `GaslessTransactionSponsored(address indexed wallet, address indexed paymaster, uint256 gasUsed)`

### createJobViaAccount

Create job through smart wallet.

```solidity
function createJobViaAccount(
    string memory modelId,
    string memory inputHash,
    uint256 maxPrice,
    uint256 deadline
) external payable onlyEntryPoint returns (uint256)
```

#### Requirements
- Only callable by EntryPoint
- Uses tx.origin as wallet (simplified)

#### Returns
Job ID from JobMarketplace

### registerNodeViaAccount

Register node through smart wallet.

```solidity
function registerNodeViaAccount(
    string memory peerId,
    string[] memory models,
    string memory region
) external payable onlyEntryPoint
```

#### Requirements
- Only callable by EntryPoint
- Forwards stake to NodeRegistry

## Session Key Management

### addSessionKey

Grant temporary permissions to an address.

```solidity
function addSessionKey(
    address sessionKey,
    uint256 expires
) external
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `sessionKey` | `address` | Address to grant permissions |
| `expires` | `uint256` | Expiration timestamp |

#### Requirements
- Expiration must be future
- Caller becomes the granter

#### Emitted Events
- `SessionKeyAdded(address indexed wallet, address indexed sessionKey, uint256 expires)`

### revokeSessionKey

Revoke session key permissions.

```solidity
function revokeSessionKey(address sessionKey) external
```

#### Effects
- Sets isActive to false
- Immediate revocation

#### Emitted Events
- `SessionKeyRevoked(address indexed wallet, address indexed sessionKey)`

### isValidSessionKey

Check session key validity.

```solidity
function isValidSessionKey(
    address wallet,
    address sessionKey
) external view returns (bool)
```

#### Returns
`true` if key is active and not expired

### claimJobViaSessionKey

Session key claims job for wallet.

```solidity
function claimJobViaSessionKey(
    address wallet,
    uint256 jobId
) external validSessionKey(wallet, msg.sender)
```

#### Requirements
- Valid session key for wallet
- Session key not expired

## Batch Operations

### executeBatch

Execute multiple operations atomically.

```solidity
function executeBatch(
    Operation[] calldata ops
) external payable
```

#### Parameters
Array of Operation structs to execute

#### Requirements
- Sufficient ETH for all operations
- All operations must succeed

#### Special Handling
- JobMarketplace: Converts createJob to createJobFor
- NodeRegistry: Converts registerNode to registerNodeFor

#### Emitted Events
- `BatchExecuted(address indexed wallet, uint256 operations)`

#### Example Usage
```solidity
Operation[] memory ops = new Operation[](3);

// Create job
ops[0] = Operation({
    target: address(jobMarketplace),
    value: 1 ether,
    data: abi.encodeWithSelector(
        JobMarketplace.createJob.selector,
        "gpt-4", "inputHash", 1 ether, deadline
    )
});

// Register node
ops[1] = Operation({
    target: address(nodeRegistry),
    value: 100 ether,
    data: abi.encodeWithSelector(
        NodeRegistry.registerNode.selector,
        "peerId", models, "us-east"
    )
});

// Custom operation
ops[2] = Operation({
    target: customContract,
    value: 0,
    data: customCalldata
});

integration.executeBatch{value: 101 ether}(ops);
```

## Payment Streaming

### createPaymentStream

Create a vesting payment stream.

```solidity
function createPaymentStream(
    address to,
    uint256 totalAmount,
    uint256 duration
) external payable returns (uint256)
```

#### Parameters
| Name | Type | Description |
|------|------|-------------|
| `to` | `address` | Recipient address |
| `totalAmount` | `uint256` | Total stream amount |
| `duration` | `uint256` | Vesting duration in seconds |

#### Requirements
- msg.value == totalAmount
- Valid recipient
- Duration > 0

#### Returns
Stream ID for tracking

#### Emitted Events
- `PaymentStreamCreated(uint256 indexed streamId, address indexed from, address indexed to, uint256 amount)`

### withdrawFromStream

Withdraw vested amount from stream.

```solidity
function withdrawFromStream(uint256 streamId) external
```

#### Requirements
- Stream must be active
- Caller must be recipient
- Vested amount available

#### Vesting Calculation
```solidity
elapsed = now - startTime
vested = (totalAmount * elapsed) / duration
available = vested - withdrawn
```

#### Emitted Events
- `PaymentStreamWithdrawn(uint256 indexed streamId, uint256 amount)`

### cancelPaymentStream

Cancel stream and distribute remaining funds.

```solidity
function cancelPaymentStream(uint256 streamId) external
```

#### Requirements
- Stream must be active
- Caller must be creator

#### Effects
- Sends vested amount to recipient
- Refunds unvested to creator
- Marks stream inactive

#### Emitted Events
- `PaymentStreamCancelled(uint256 indexed streamId)`

## Events

### ERC-4337 Events
```solidity
event GaslessTransactionSponsored(address indexed wallet, address indexed paymaster, uint256 gasUsed)
event BatchExecuted(address indexed wallet, uint256 operations)
```

### Session Key Events
```solidity
event SessionKeyAdded(address indexed wallet, address indexed sessionKey, uint256 expires)
event SessionKeyRevoked(address indexed wallet, address indexed sessionKey)
```

### Payment Stream Events
```solidity
event PaymentStreamCreated(uint256 indexed streamId, address indexed from, address indexed to, uint256 amount)
event PaymentStreamWithdrawn(uint256 indexed streamId, uint256 amount)
event PaymentStreamCancelled(uint256 indexed streamId)
```

## Access Modifiers

### onlyEntryPoint
```solidity
modifier onlyEntryPoint()
```
Restricts to ERC-4337 EntryPoint.

### onlyWalletOwner
```solidity
modifier onlyWalletOwner(address wallet)
```
Restricts to wallet owner.

### validSessionKey
```solidity
modifier validSessionKey(address wallet, address sessionKey)
```
Validates session key permissions.

## Security Considerations

1. **EntryPoint Trust**: Only EntryPoint can execute wallet operations
2. **Session Key Limits**: Time-based expiration
3. **Batch Atomicity**: All operations succeed or all fail
4. **Stream Security**: Only recipient can withdraw
5. **Reentrancy**: Native ETH transfers use call pattern

## Gas Optimization

1. **Batch Efficiency**: Single transaction for multiple operations
2. **Gasless Transactions**: Paymaster sponsorship reduces user costs
3. **Efficient Routing**: Direct contract interactions where possible
4. **Storage Patterns**: Minimal storage updates

## Integration Examples

### Smart Wallet Job Creation
```solidity
// 1. Prepare UserOperation
UserOperation memory userOp = UserOperation({
    sender: walletAddress,
    nonce: nonce,
    initCode: "",
    callData: abi.encodeWithSelector(
        IAccount.execute.selector,
        address(integration),
        1 ether,
        abi.encodeWithSelector(
            BaseAccountIntegration.createJobViaAccount.selector,
            "llama-2", "inputHash", 1 ether, deadline
        )
    ),
    // ... gas parameters
    paymasterAndData: abi.encodePacked(paymasterAddress),
    signature: signature
});

// 2. Submit to EntryPoint
entryPoint.handleOps(userOps, beneficiary);
```

### Session Key Usage
```solidity
// 1. Wallet grants session key
integration.addSessionKey(trustedApp, block.timestamp + 7 days);

// 2. App can claim jobs for wallet
integration.claimJobViaSessionKey(walletAddress, jobId);

// 3. Wallet can revoke anytime
integration.revokeSessionKey(trustedApp);
```

### Payment Stream Example
```solidity
// Create 12-month vesting stream
uint256 streamId = integration.createPaymentStream{value: 12 ether}(
    employeeAddress,
    12 ether,
    365 days
);

// Employee withdraws monthly
for (uint month = 1; month <= 12; month++) {
    // Wait 30 days
    integration.withdrawFromStream(streamId);
    // Receives ~1 ETH
}
```

### Batch Job Management
```solidity
function postMultipleJobsGasless(
    string[] memory prompts
) external {
    Operation[] memory ops = new Operation[](prompts.length);
    uint256 totalValue = prompts.length * 1 ether;
    
    for (uint i = 0; i < prompts.length; i++) {
        ops[i] = Operation({
            target: address(jobMarketplace),
            value: 1 ether,
            data: abi.encodeWithSelector(
                JobMarketplace.createJob.selector,
                "gpt-4",
                prompts[i],
                1 ether,
                block.timestamp + 1 hours
            )
        });
    }
    
    // Submit as UserOperation for gasless execution
    submitUserOperation(ops, totalValue);
}
```

## Best Practices

1. **Session Keys**: Set reasonable expiration times
2. **Batch Limits**: Keep batch sizes reasonable for gas limits
3. **Stream Duration**: Consider minimum viable durations
4. **Error Handling**: Check operation results in batches
5. **Paymaster Integration**: Validate paymaster limits

## Future Improvements

1. **Session Key Permissions**: Granular action permissions
2. **Stream Types**: Support for cliff vesting
3. **Batch Optimization**: Parallel execution where possible
4. **Enhanced Validation**: More robust UserOp validation
5. **Multi-chain Support**: Cross-chain account abstraction