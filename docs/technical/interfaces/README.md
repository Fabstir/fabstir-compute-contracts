# Fabstir Contracts - Interface Documentation

This directory contains documentation for all interfaces used in the Fabstir compute contracts. These interfaces define the standard interactions between contracts and external integrators.

## Core Interfaces

### Account Abstraction
- **[IAccount](#iaccount)** - ERC-4337 account interface for smart wallets
- **[UserOperation](#useroperation)** - ERC-4337 operation structure

### Marketplace Core
- **[IJobMarketplace](#ijobmarketplace)** - Job lifecycle management interface
- **[INodeRegistry](#inoderegistry)** - Node registration interface

### Financial
- **[IPaymentEscrow](#ipaymentescrow)** - Escrow system interface
- **[IERC20](#ierc20)** - Standard ERC20 token interface

### Quality & Trust
- **[IReputationSystem](#ireputationsystem)** - Reputation tracking interface

---

## IAccount

ERC-4337 account interface for smart wallet implementations.

**Source**: [`src/interfaces/IAccount.sol`](../../../src/interfaces/IAccount.sol)

### Functions

#### execute
```solidity
function execute(address dest, uint256 value, bytes calldata func) external
```

Execute a single operation from the account.

**Parameters:**
- `dest` - Target contract address
- `value` - ETH value to send
- `func` - Encoded function call data

#### executeBatch
```solidity
function executeBatch(
    address[] calldata dest,
    uint256[] calldata value,
    bytes[] calldata func
) external
```

Execute multiple operations in a single transaction.

**Parameters:**
- `dest` - Array of target addresses
- `value` - Array of ETH values
- `func` - Array of encoded function calls

### Integration Example
```solidity
// Single operation
account.execute(
    jobMarketplace,
    1 ether,
    abi.encodeWithSelector(JobMarketplace.createJob.selector, ...)
);

// Batch operations
address[] memory targets = new address[](2);
uint256[] memory values = new uint256[](2);
bytes[] memory calls = new bytes[](2);

targets[0] = nodeRegistry;
values[0] = 100 ether;
calls[0] = abi.encodeWithSelector(NodeRegistry.registerNode.selector, ...);

targets[1] = jobMarketplace;
values[1] = 1 ether;
calls[1] = abi.encodeWithSelector(JobMarketplace.createJob.selector, ...);

account.executeBatch(targets, values, calls);
```

---

## UserOperation

ERC-4337 UserOperation structure for account abstraction.

**Source**: [`src/interfaces/UserOperation.sol`](../../../src/interfaces/UserOperation.sol)

### Structure
```solidity
struct UserOperation {
    address sender;                  // Smart wallet address
    uint256 nonce;                  // Anti-replay nonce
    bytes initCode;                 // Wallet deployment code (if needed)
    bytes callData;                 // Execution calldata
    uint256 callGasLimit;           // Gas for execution
    uint256 verificationGasLimit;   // Gas for verification
    uint256 preVerificationGas;     // Base gas cost
    uint256 maxFeePerGas;          // Max fee per gas (EIP-1559)
    uint256 maxPriorityFeePerGas;  // Max priority fee (EIP-1559)
    bytes paymasterAndData;         // Paymaster address + data
    bytes signature;                // Signature over operation
}
```

### Field Descriptions
- **sender**: The smart wallet contract address
- **nonce**: Sequential nonce for replay protection
- **initCode**: Factory address + deployment data (empty if wallet exists)
- **callData**: Encoded call to execute on the account
- **callGasLimit**: Gas limit for the main execution
- **verificationGasLimit**: Gas limit for signature verification
- **preVerificationGas**: Gas to compensate bundler
- **maxFeePerGas**: Maximum total fee per gas
- **maxPriorityFeePerGas**: Maximum priority fee per gas
- **paymasterAndData**: Paymaster contract + context data
- **signature**: Wallet owner's signature

### Usage Example
```solidity
UserOperation memory op = UserOperation({
    sender: walletAddress,
    nonce: 0,
    initCode: "",  // Wallet already deployed
    callData: abi.encodeWithSelector(
        IAccount.execute.selector,
        targetContract,
        0,
        targetCalldata
    ),
    callGasLimit: 200000,
    verificationGasLimit: 100000,
    preVerificationGas: 21000,
    maxFeePerGas: 30 gwei,
    maxPriorityFeePerGas: 2 gwei,
    paymasterAndData: abi.encodePacked(paymasterAddress),
    signature: walletSignature
});
```

---

## IJobMarketplace

Interface for interacting with the job marketplace contract.

**Source**: [`src/interfaces/IJobMarketplace.sol`](../../../src/interfaces/IJobMarketplace.sol)

### Enums

#### JobStatus
```solidity
enum JobStatus {
    Posted,     // Job available for claiming
    Claimed,    // Job assigned to host
    Completed   // Job finished
}
```

### Structs

#### JobDetails
```solidity
struct JobDetails {
    string modelId;       // AI model identifier
    string prompt;        // Input prompt
    uint256 maxTokens;    // Maximum output tokens
    uint256 temperature;  // Sampling temperature (scaled by 1000)
    uint32 seed;         // Random seed
    string resultFormat;  // Expected output format
}
```

#### JobRequirements
```solidity
struct JobRequirements {
    uint256 minGPUMemory;        // Minimum GPU memory in GB
    uint256 minReputationScore;  // Minimum host reputation
    uint256 maxTimeToComplete;   // Maximum seconds to complete
    bool requiresProof;          // Whether proof is required
}
```

### Functions

#### getJob
```solidity
function getJob(uint256 jobId) external view returns (
    address renter,
    string memory modelId,
    string memory inputHash,
    address paymentToken,
    JobStatus status,
    address assignedHost,
    string memory resultHash,
    bytes32 modelCommitment,
    bytes32 inputHashBytes
)
```

Retrieve comprehensive job information.

#### postJob
```solidity
function postJob(
    string memory modelId,
    uint256 maxPrice,
    address paymentToken,
    uint256 deadline,
    bytes32 modelCommitment,
    bytes32 inputHash
) external returns (uint256)
```

Post a new job to the marketplace.

**Returns**: Job ID

#### claimJob
```solidity
function claimJob(uint256 jobId) external
```

Host claims a job for execution.

#### completeJob
```solidity
function completeJob(uint256 jobId, bytes32 outputHash) external
```

Submit job completion with output hash.

#### postJobWithToken
```solidity
function postJobWithToken(
    JobDetails memory details,
    JobRequirements memory requirements,
    address paymentToken,
    uint256 paymentAmount
) external returns (bytes32)
```

Post a job with ERC20 token payment (currently USDC only).

**Parameters:**
- `details` - Job execution details (see JobDetails struct)
- `requirements` - Job requirements (see JobRequirements struct)  
- `paymentToken` - Token address (must be USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e)
- `paymentAmount` - Payment amount in token units (6 decimals for USDC)

**Returns**: bytes32 job ID for escrow tracking

#### grantRole
```solidity
function grantRole(bytes32 role, address account) external
```

Grant a role to an address (admin function).

#### PROOF_SYSTEM_ROLE
```solidity
function PROOF_SYSTEM_ROLE() external view returns (bytes32)
```

Get the proof system role identifier.

### Integration Example
```solidity
// Post a job with ETH
uint256 jobId = marketplace.postJob(
    "gpt-4",
    1 ether,
    address(0),  // ETH payment
    block.timestamp + 1 hours,
    keccak256("model"),
    keccak256("input")
);

// Post a job with USDC
JobDetails memory details = JobDetails({
    modelId: "gpt-4",
    prompt: "Your prompt",
    maxTokens: 2000,
    temperature: 700,  // 0.7 * 1000
    seed: 42,
    resultFormat: "json"
});

JobRequirements memory requirements = JobRequirements({
    minGPUMemory: 16,
    minReputationScore: 0,
    maxTimeToComplete: 3600,
    requiresProof: false
});

bytes32 tokenJobId = marketplace.postJobWithToken(
    details,
    requirements,
    0x036CbD53842c5426634e7929541eC2318f3dCF7e,  // USDC on Base Sepolia
    10000  // 0.01 USDC
);

// Claim as host
marketplace.claimJob(jobId);

// Complete job
marketplace.completeJob(jobId, keccak256("output"));
```

---

## INodeRegistry

Interface for node registration and verification.

**Source**: [`src/interfaces/INodeRegistry.sol`](../../../src/interfaces/INodeRegistry.sol)

### Functions

#### isActiveNode
```solidity
function isActiveNode(address operator) external view returns (bool)
```

Check if an address is a registered and active node.

**Parameters:**
- `operator` - Address to check

**Returns:** true if node is active

#### getNodeController
```solidity
function getNodeController(address node) external view returns (address)
```

Get the controller address for a node (for Sybil detection).

**Parameters:**
- `node` - Node address

**Returns:** Controller address (0x0 if none)

### Usage Example
```solidity
// Verify host before job assignment
require(nodeRegistry.isActiveNode(hostAddress), "Not active host");

// Check for Sybil attacks
address controller = nodeRegistry.getNodeController(hostAddress);
if (controller != address(0)) {
    // Check if controller has suspicious activity
}
```

---

## IPaymentEscrow

Interface for payment escrow operations.

**Source**: [`src/interfaces/IPaymentEscrow.sol`](../../../src/interfaces/IPaymentEscrow.sol)

### Functions

#### grantRole
```solidity
function grantRole(bytes32 role, address account) external
```

Grant a role to an address.

#### PROOF_SYSTEM_ROLE
```solidity
function PROOF_SYSTEM_ROLE() external view returns (bytes32)
```

Get the proof system role identifier.

### Note
This is a minimal interface. The actual PaymentEscrow contract has additional functionality not exposed through this interface.

---

## IReputationSystem

Interface for reputation tracking and updates.

**Source**: [`src/interfaces/IReputationSystem.sol`](../../../src/interfaces/IReputationSystem.sol)

### Functions

#### recordJobCompletion
```solidity
function recordJobCompletion(
    address host,
    uint256 jobId,
    bool success
) external
```

Record the outcome of a job for reputation tracking.

**Parameters:**
- `host` - Host address
- `jobId` - Job identifier
- `success` - Whether job succeeded

#### getReputation
```solidity
function getReputation(address host) external view returns (uint256)
```

Get current reputation score for a host.

**Parameters:**
- `host` - Host address

**Returns:** Current reputation score

### Integration Example
```solidity
// After job completion
reputationSystem.recordJobCompletion(hostAddress, jobId, true);

// Check reputation before assignment
uint256 reputation = reputationSystem.getReputation(hostAddress);
require(reputation >= minReputation, "Insufficient reputation");
```

---

## IERC20

Standard ERC20 token interface for payment tokens.

**Source**: [`src/interfaces/IERC20.sol`](../../../src/interfaces/IERC20.sol)

### Functions

#### transfer
```solidity
function transfer(address to, uint256 amount) external returns (bool)
```

Transfer tokens to an address.

#### transferFrom
```solidity
function transferFrom(
    address from,
    address to,
    uint256 amount
) external returns (bool)
```

Transfer tokens from one address to another (requires allowance).

#### balanceOf
```solidity
function balanceOf(address account) external view returns (uint256)
```

Get token balance of an address.

#### approve
```solidity
function approve(address spender, uint256 amount) external returns (bool)
```

Approve an address to spend tokens.

#### allowance
```solidity
function allowance(
    address owner,
    address spender
) external view returns (uint256)
```

Check spending allowance.

### Usage Example
```solidity
// Approve escrow to take payment
IERC20(token).approve(escrowAddress, jobPayment);

// Check balance before job posting
require(IERC20(token).balanceOf(msg.sender) >= jobPayment, "Insufficient balance");
```

---

## Integration Best Practices

### 1. Interface Versioning
Always check interface compatibility when integrating:
```solidity
// Verify interface support
require(
    IERC165(target).supportsInterface(type(IJobMarketplace).interfaceId),
    "Interface not supported"
);
```

### 2. Error Handling
Interfaces don't specify revert conditions, always handle failures:
```solidity
try marketplace.claimJob(jobId) {
    // Success
} catch Error(string memory reason) {
    // Handle specific error
} catch {
    // Handle unknown error
}
```

### 3. Gas Optimization
Batch operations when possible:
```solidity
// Instead of multiple calls
for (uint i = 0; i < jobs.length; i++) {
    marketplace.claimJob(jobs[i]);
}

// Use batch interfaces where available
marketplace.batchClaimJobs(jobs);
```

### 4. Access Control
Check roles before privileged operations:
```solidity
bytes32 role = marketplace.PROOF_SYSTEM_ROLE();
marketplace.grantRole(role, proofSystemAddress);
```

### 5. Type Safety
Use interface types for better safety:
```solidity
IJobMarketplace marketplace = IJobMarketplace(marketplaceAddress);
// Instead of calling address directly
```