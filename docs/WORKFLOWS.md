# Usage Workflows

**Version:** 1.1
**Last Updated:** January 15, 2026
**Network:** Base Sepolia (Testnet)

This document provides step-by-step guides for common operations with code examples.

---

## Table of Contents

1. [Host Registration Workflow](#1-host-registration-workflow)
2. [Session Creation Workflow (Depositor)](#2-session-creation-workflow-depositor)
3. [Proof Submission Workflow (Host)](#3-proof-submission-workflow-host)
4. [Session Completion Workflow](#4-session-completion-workflow)
5. [Model Governance Workflow](#5-model-governance-workflow)
6. [Host Earnings Withdrawal](#6-host-earnings-withdrawal)
7. [Error Handling Guide](#7-error-handling-guide)

---

## 1. Host Registration Workflow

### Prerequisites
- FAB tokens for staking (minimum 1000 FAB)
- Approved model IDs from ModelRegistry
- Node metadata and API URL prepared

### Steps

```
┌─────────────────────────────────────────────────────────────┐
│                 HOST REGISTRATION FLOW                       │
├─────────────────────────────────────────────────────────────┤
│  1. Approve FAB tokens for NodeRegistry                     │
│  2. Call registerNode() with:                               │
│     - metadata: JSON description of node                    │
│     - apiUrl: endpoint URL for AI inference                 │
│     - modelIds: array of supported model hashes             │
│     - minPricePerTokenNative: ETH pricing (with precision)  │
│     - minPricePerTokenStable: USDC pricing (with precision) │
│  3. Verify registration via getNodeFullInfo()               │
└─────────────────────────────────────────────────────────────┘
```

### Code Example (ethers.js)

```javascript
import { ethers } from 'ethers';

// Contract addresses (Base Sepolia)
const NODE_REGISTRY = '0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22';
const FAB_TOKEN = '0xC78949004B4EB6dEf2D66e49Cd81231472612D62';
const MIN_STAKE = ethers.parseEther('1000');

// Step 1: Approve FAB tokens
const fabToken = new ethers.Contract(FAB_TOKEN, [
  'function approve(address spender, uint256 amount) returns (bool)'
], signer);

const approveTx = await fabToken.approve(NODE_REGISTRY, MIN_STAKE);
await approveTx.wait();
console.log('✅ FAB tokens approved');

// Step 2: Register node
const nodeRegistry = new ethers.Contract(NODE_REGISTRY, NodeRegistryABI, signer);

const metadata = JSON.stringify({
  name: 'My GPU Node',
  gpuType: 'RTX 4090',
  memory: '24GB',
  location: 'US-East'
});

const apiUrl = 'https://my-node.example.com/api/inference';

// Model IDs (get these from ModelRegistry)
const modelIds = [
  ethers.keccak256(ethers.toUtf8Bytes('TinyVicuna-1B')),
  ethers.keccak256(ethers.toUtf8Bytes('TinyLlama-1.1B'))
];

// Pricing with PRICE_PRECISION (1000x)
// Native: ~$0.00001 per token at $4400 ETH
const minPricePerTokenNative = 227_273n;  // MIN_PRICE_PER_TOKEN_NATIVE
// Stable: $0.000001 per token
const minPricePerTokenStable = 1n;        // MIN_PRICE_PER_TOKEN_STABLE

const registerTx = await nodeRegistry.registerNode(
  metadata,
  apiUrl,
  modelIds,
  minPricePerTokenNative,
  minPricePerTokenStable
);
await registerTx.wait();
console.log('✅ Node registered');

// Step 3: Verify registration
const nodeInfo = await nodeRegistry.getNodeFullInfo(signer.address);
console.log('Node info:', {
  operator: nodeInfo[0],
  stakedAmount: ethers.formatEther(nodeInfo[1]),
  active: nodeInfo[2],
  supportedModels: nodeInfo[5],
  nativePrice: nodeInfo[6].toString(),
  stablePrice: nodeInfo[7].toString()
});
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Already registered` | Node already exists | Call `unregisterNode()` first |
| `Empty metadata` | Metadata string is empty | Provide valid JSON metadata |
| `Must support at least one model` | Empty modelIds array | Include at least one approved model |
| `Model not approved` | Model not in ModelRegistry | Use only approved model IDs |
| `Native price below minimum` | Price too low | Use MIN_PRICE_PER_TOKEN_NATIVE (227,273) |

---

## 2. Session Creation Workflow (Depositor)

### Prerequisites
- ETH or USDC for deposit
- Host address with active node
- Model ID that host supports

### Steps

```
┌─────────────────────────────────────────────────────────────┐
│              SESSION CREATION FLOW (ETH)                     │
├─────────────────────────────────────────────────────────────┤
│  1. Query host pricing: getNodePricing(host, address(0))    │
│  2. Verify model support: nodeSupportsModel(host, modelId)  │
│  3. Calculate deposit: estimatedTokens × pricePerToken      │
│  4. Call createSessionJobForModel() with ETH value          │
│  5. Receive jobId from SessionJobCreated event              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              SESSION CREATION FLOW (USDC)                    │
├─────────────────────────────────────────────────────────────┤
│  1. Query host pricing: getNodePricing(host, USDC_ADDRESS)  │
│  2. Verify model support: nodeSupportsModel(host, modelId)  │
│  3. Approve USDC for JobMarketplace                         │
│  4. Call createSessionJobForModelWithToken()                │
│  5. Receive jobId from SessionJobCreated event              │
└─────────────────────────────────────────────────────────────┘
```

### Code Example (ETH Session)

```javascript
const JOB_MARKETPLACE = '0x3CaCbf3f448B420918A93a88706B26Ab27a3523E';
const NODE_REGISTRY = '0x8BC0Af4aAa2dfb99699B1A24bA85E507de10Fd22';

const marketplace = new ethers.Contract(JOB_MARKETPLACE, JobMarketplaceABI, signer);
const nodeRegistry = new ethers.Contract(NODE_REGISTRY, NodeRegistryABI, signer);

// Step 1: Query host pricing
const hostAddress = '0x...'; // Host you want to use
const nativePrice = await nodeRegistry.getNodePricing(hostAddress, ethers.ZeroAddress);
console.log('Host native price:', nativePrice.toString());

// Step 2: Verify model support
const modelId = ethers.keccak256(ethers.toUtf8Bytes('TinyVicuna-1B'));
const supportsModel = await nodeRegistry.nodeSupportsModel(hostAddress, modelId);
if (!supportsModel) throw new Error('Host does not support this model');

// Step 3: Calculate deposit
const estimatedTokens = 10000n;  // Estimate how many tokens you'll use
const pricePerToken = nativePrice;  // Use host's minimum or higher
const depositAmount = estimatedTokens * pricePerToken / 1000n;  // Adjust for PRICE_PRECISION
console.log('Deposit amount:', ethers.formatEther(depositAmount), 'ETH');

// Step 4: Create session
const maxDuration = 3600;  // 1 hour
const proofInterval = 100;  // Proof every 100 tokens

const createTx = await marketplace.createSessionJobForModel(
  hostAddress,
  modelId,           // modelId is 2nd parameter
  pricePerToken,
  maxDuration,
  proofInterval,
  { value: depositAmount }
);

const receipt = await createTx.wait();

// Step 5: Get jobId from event
const event = receipt.logs.find(log => {
  try {
    return marketplace.interface.parseLog(log)?.name === 'SessionJobCreated';
  } catch { return false; }
});
const parsedEvent = marketplace.interface.parseLog(event);
const jobId = parsedEvent.args.jobId;
console.log('✅ Session created, jobId:', jobId.toString());
```

### Code Example (USDC Session)

```javascript
const USDC_TOKEN = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';

// Step 1: Query host pricing for USDC
const stablePrice = await nodeRegistry.getNodePricing(hostAddress, USDC_TOKEN);

// Step 2: Verify model support (same as ETH)

// Step 3: Approve USDC
const usdc = new ethers.Contract(USDC_TOKEN, [
  'function approve(address spender, uint256 amount) returns (bool)'
], signer);

const depositAmount = 1_000_000n;  // 1 USDC (6 decimals)
await (await usdc.approve(JOB_MARKETPLACE, depositAmount)).wait();

// Step 4: Create session with USDC
const createTx = await marketplace.createSessionJobForModelWithToken(
  hostAddress,
  modelId,           // modelId is 2nd parameter
  USDC_TOKEN,        // token address
  depositAmount,     // deposit amount
  stablePrice,       // price per token
  maxDuration,
  proofInterval
);

const receipt = await createTx.wait();
// Step 5: Get jobId from event (same as ETH)
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Host not active` | Host is not registered or inactive | Choose active host |
| `Host does not support model` | Model not in host's supportedModels | Choose supported model |
| `Price below host minimum (native)` | Offered price too low | Use host's minPricePerTokenNative |
| `Price below host minimum (stable)` | Offered price too low | Use host's minPricePerTokenStable |
| `Deposit below minimum` | Deposit too small | Increase deposit amount |
| `Paused` | Contract is paused | Wait for unpause |

---

## 3. Proof Submission Workflow (Host)

### Prerequisites
- Active session where you are the host
- AI inference service running
- Private key for signing proofs

### Steps

```
┌─────────────────────────────────────────────────────────────┐
│               PROOF SUBMISSION FLOW                          │
├─────────────────────────────────────────────────────────────┤
│  1. Provide AI inference service off-chain                  │
│  2. Track tokens consumed in the session                    │
│  3. Create proof hash and sign with host key                │
│  4. Upload proof data to S5, get proofCID & deltaCID   │
│  5. Call submitProofOfWork() with:                          │
│     - jobId: session identifier                             │
│     - tokensClaimed: tokens since last proof                │
│     - proofHash: keccak256 hash of proof data               │
│     - signature: host's 65-byte signature                   │
│     - proofCID: S5 CID of full proof                   │
│     - deltaCID: S5 CID of delta since last proof       │
│  6. Repeat every proofInterval tokens                       │
└─────────────────────────────────────────────────────────────┘
```

### Code Example

```javascript
// Host submits proof of work
async function submitProof(jobId, tokensClaimed, proofCID, deltaCID) {
  const marketplace = new ethers.Contract(JOB_MARKETPLACE, JobMarketplaceABI, signer);

  // Get session details
  const session = await marketplace.sessionJobs(jobId);

  // Create proof hash from job data
  const proofHash = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint256', 'uint256', 'address'],
    [jobId, tokensClaimed, signer.address]
  ));

  // Sign the proof hash (EIP-191 personal sign)
  const signature = await signer.signMessage(ethers.getBytes(proofHash));

  // Submit proof with all 6 parameters
  const tx = await marketplace.submitProofOfWork(
    jobId,
    tokensClaimed,
    proofHash,        // 32-byte hash
    signature,        // 65-byte signature
    proofCID,         // S5 CID of full proof data
    deltaCID          // S5 CID of delta since last proof
  );

  const receipt = await tx.wait();
  console.log('✅ Proof submitted for', tokensClaimed, 'tokens');

  return receipt;
}

// Example: Submit proofs during inference
async function handleInference(jobId, proofInterval, s5Client) {
  let tokensGenerated = 0;
  let tokensSinceLastProof = 0;
  let conversationLog = [];
  let lastProofContent = null;

  // Simulated inference loop
  while (sessionActive) {
    const { tokens: newTokens, content } = await generateTokens();  // Your AI inference
    tokensGenerated += newTokens;
    tokensSinceLastProof += newTokens;
    conversationLog.push(content);

    // Submit proof when interval reached
    if (tokensSinceLastProof >= proofInterval) {
      // Upload proof data to S5
      const proofData = JSON.stringify({ tokens: tokensSinceLastProof, content: conversationLog });
      const proofCID = await s5Client.upload(proofData);

      // Calculate delta from last proof
      const deltaContent = lastProofContent
        ? conversationLog.slice(lastProofContent.length)
        : conversationLog;
      const deltaCID = await s5Client.upload(JSON.stringify(deltaContent));

      await submitProof(jobId, tokensSinceLastProof, proofCID, deltaCID);

      lastProofContent = [...conversationLog];
      tokensSinceLastProof = 0;
    }
  }

  // Submit final proof for remaining tokens
  if (tokensSinceLastProof >= 100) {  // MIN_PROVEN_TOKENS = 100
    const proofCID = await s5Client.upload(JSON.stringify(conversationLog));
    const deltaCID = await s5Client.upload(JSON.stringify(conversationLog.slice(lastProofContent?.length || 0)));
    await submitProof(jobId, tokensSinceLastProof, proofCID, deltaCID);
  }
}
```

### Signature Format

```
┌─────────────────────────────────────────────────────────────┐
│                  PROOF SIGNATURE FORMAT                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  proofHash = keccak256(abi.encode(jobId, tokens, host))    │
│                                                             │
│  signature = personalSign(proofHash)                        │
│            = sign("\x19Ethereum Signed Message:\n32" + hash)│
│            = 65 bytes (r: 32, s: 32, v: 1)                  │
│                                                             │
│  submitProofOfWork parameters:                              │
│    - proofHash: bytes32 (32 bytes)                          │
│    - signature: bytes (65 bytes)                            │
│    - proofCID: string (S5 content identifier)          │
│    - deltaCID: string (delta changes CID)                   │
│                                                             │
│  Verification: ECDSA.recover(ethHash, sig) == host         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Only host can submit proof` | Caller is not session host | Only host can submit |
| `Session not active` | Session completed/timed out | Cannot submit to inactive session |
| `Invalid signature length` | Signature not 65 bytes | Ensure signature is exactly 65 bytes |
| `Invalid proof signature` | Signature verification failed | Check signing format matches host address |
| `Must claim minimum tokens` | tokensClaimed < 100 | Claim at least MIN_PROVEN_TOKENS (100) |
| `Exceeds deposit` | Claiming more than deposited | Reduce tokens claimed |
| `Excessive tokens claimed` | Rate limit exceeded | Wait longer between proofs |

---

## 4. Session Completion Workflow

### Who Can Complete
- **Host**: After providing service
- **Depositor**: At any time (to end session early)

### Steps

```
┌─────────────────────────────────────────────────────────────┐
│              SESSION COMPLETION FLOW                         │
├─────────────────────────────────────────────────────────────┤
│  1. Upload conversation to S5, get conversationCID     │
│  2. Host or Depositor calls:                                │
│     completeSessionJob(jobId, conversationCID)              │
│  3. Contract calculates:                                    │
│     - hostPayment = tokensProven × pricePerToken × 90%      │
│     - treasuryFee = tokensProven × pricePerToken × 10%      │
│     - refund = deposit - hostPayment - treasuryFee          │
│  4. Payments distributed:                                   │
│     - Host payment → HostEarnings (credited, not sent)      │
│     - Treasury fee → Accumulated in contract                │
│     - Refund → Sent directly to depositor                   │
│  5. Session marked as Completed, conversationCID stored     │
└─────────────────────────────────────────────────────────────┘
```

### Code Example

```javascript
// Complete session (as host or depositor)
async function completeSession(jobId, s5Client, conversationLog) {
  const marketplace = new ethers.Contract(JOB_MARKETPLACE, JobMarketplaceABI, signer);

  // Check session status first
  const session = await marketplace.sessionJobs(jobId);
  if (session.status !== 0n) {  // 0 = Active, 1 = Completed, 2 = TimedOut
    throw new Error('Session is not active');
  }

  // Upload conversation to S5
  const conversationCID = await s5Client.upload(JSON.stringify(conversationLog));

  // Complete the session with conversationCID
  const tx = await marketplace.completeSessionJob(jobId, conversationCID);
  const receipt = await tx.wait();

  // Parse completion event
  const event = receipt.logs.find(log => {
    try {
      return marketplace.interface.parseLog(log)?.name === 'SessionCompleted';
    } catch { return false; }
  });

  if (event) {
    const parsed = marketplace.interface.parseLog(event);
    console.log('✅ Session completed');
    console.log('Host earnings:', ethers.formatEther(parsed.args.hostEarnings));
    console.log('User refund:', ethers.formatEther(parsed.args.userRefund));
  }

  return receipt;
}
```

### Session Timeout

Anyone can trigger timeout for abandoned sessions:

```javascript
// Trigger timeout for abandoned session
async function triggerTimeout(jobId) {
  const marketplace = new ethers.Contract(JOB_MARKETPLACE, JobMarketplaceABI, signer);

  const session = await marketplace.sessionJobs(jobId);
  const now = Math.floor(Date.now() / 1000);
  const timeoutThreshold = session.lastProofTime + (session.proofInterval * 3);

  if (now < timeoutThreshold) {
    throw new Error('Session has not timed out yet');
  }

  const tx = await marketplace.triggerSessionTimeout(jobId);
  await tx.wait();
  console.log('✅ Session timed out');
}
```

---

## 5. Model Governance Workflow

### Steps

```
┌─────────────────────────────────────────────────────────────┐
│              MODEL GOVERNANCE FLOW                           │
├─────────────────────────────────────────────────────────────┤
│  1. Proposer locks 100 FAB, calls proposeModel()            │
│  2. 3-day voting period begins                              │
│  3. FAB holders vote via voteOnProposal()                   │
│  4. After 3 days, anyone calls executeProposal()            │
│  5. If threshold met (100k FAB for):                        │
│     - Model added as tier 2 (community approved)            │
│     - Proposal fee refunded to proposer                     │
│  6. Voters unlock tokens via withdrawVotes()                │
└─────────────────────────────────────────────────────────────┘
```

### Code Example

```javascript
const MODEL_REGISTRY = '0x1a9d91521c85bD252Ac848806Ff5096bBb9ACDb2';
const PROPOSAL_FEE = ethers.parseEther('100');

// Step 1: Propose a new model
async function proposeModel(huggingfaceRepo, fileName, sha256Hash) {
  const modelRegistry = new ethers.Contract(MODEL_REGISTRY, ModelRegistryABI, signer);
  const fabToken = new ethers.Contract(FAB_TOKEN, ERC20ABI, signer);

  // Approve proposal fee
  await (await fabToken.approve(MODEL_REGISTRY, PROPOSAL_FEE)).wait();

  // Propose model
  const tx = await modelRegistry.proposeModel(huggingfaceRepo, fileName, sha256Hash);
  const receipt = await tx.wait();

  // Get modelId from event
  const event = receipt.logs.find(log => {
    try {
      return modelRegistry.interface.parseLog(log)?.name === 'ModelProposed';
    } catch { return false; }
  });
  const modelId = modelRegistry.interface.parseLog(event).args.modelId;

  console.log('✅ Model proposed, ID:', modelId);
  return modelId;
}

// Step 2-3: Vote on proposal
async function voteOnProposal(modelId, amount, support) {
  const modelRegistry = new ethers.Contract(MODEL_REGISTRY, ModelRegistryABI, signer);
  const fabToken = new ethers.Contract(FAB_TOKEN, ERC20ABI, signer);

  // Approve voting tokens
  await (await fabToken.approve(MODEL_REGISTRY, amount)).wait();

  // Cast vote
  const tx = await modelRegistry.voteOnProposal(modelId, amount, support);
  await tx.wait();

  console.log(`✅ Voted ${support ? 'FOR' : 'AGAINST'} with ${ethers.formatEther(amount)} FAB`);
}

// Step 4: Execute proposal (after 3 days)
async function executeProposal(modelId) {
  const modelRegistry = new ethers.Contract(MODEL_REGISTRY, ModelRegistryABI, signer);

  const tx = await modelRegistry.executeProposal(modelId);
  const receipt = await tx.wait();

  const event = receipt.logs.find(log => {
    try {
      return modelRegistry.interface.parseLog(log)?.name === 'ProposalExecuted';
    } catch { return false; }
  });
  const approved = modelRegistry.interface.parseLog(event).args.approved;

  console.log(`✅ Proposal executed, approved: ${approved}`);
  return approved;
}

// Step 5: Withdraw voting tokens
async function withdrawVotes(modelId) {
  const modelRegistry = new ethers.Contract(MODEL_REGISTRY, ModelRegistryABI, signer);

  const tx = await modelRegistry.withdrawVotes(modelId);
  await tx.wait();

  console.log('✅ Voting tokens withdrawn');
}
```

---

## 6. Host Earnings Withdrawal

### Steps

```
┌─────────────────────────────────────────────────────────────┐
│              HOST EARNINGS WITHDRAWAL                        │
├─────────────────────────────────────────────────────────────┤
│  1. Check accumulated earnings via getEarnings()            │
│  2. Call withdraw() for ETH or withdrawToken() for USDC     │
│  3. Entire balance transferred to host                      │
└─────────────────────────────────────────────────────────────┘
```

### Code Example

```javascript
const HOST_EARNINGS = '0xE4F33e9e132E60fc3477509f99b9E1340b91Aee0';

async function withdrawEarnings() {
  const hostEarnings = new ethers.Contract(HOST_EARNINGS, HostEarningsABI, signer);

  // Check ETH earnings
  const ethEarnings = await hostEarnings.getEarnings(signer.address, ethers.ZeroAddress);
  console.log('ETH earnings:', ethers.formatEther(ethEarnings));

  // Check USDC earnings
  const usdcEarnings = await hostEarnings.getEarnings(signer.address, USDC_TOKEN);
  console.log('USDC earnings:', ethers.formatUnits(usdcEarnings, 6));

  // Withdraw ETH
  if (ethEarnings > 0) {
    const tx = await hostEarnings.withdraw();
    await tx.wait();
    console.log('✅ ETH withdrawn');
  }

  // Withdraw USDC
  if (usdcEarnings > 0) {
    const tx = await hostEarnings.withdrawToken(USDC_TOKEN);
    await tx.wait();
    console.log('✅ USDC withdrawn');
  }
}
```

---

## 7. Error Handling Guide

### General Error Categories

| Category | Error Pattern | Recovery |
|----------|---------------|----------|
| **Access Control** | `Only owner`, `Only host`, `Unauthorized` | Check caller permissions |
| **State** | `Not active`, `Already completed`, `Already executed` | Check current state |
| **Validation** | `Below minimum`, `Above maximum`, `Invalid` | Fix input parameters |
| **Funds** | `Insufficient balance`, `Transfer failed` | Ensure sufficient funds |
| **Timing** | `Voting still active`, `Session not timed out` | Wait for required time |

### Recommended Error Handling Pattern

```javascript
async function safeContractCall(contract, method, args, options = {}) {
  try {
    // Estimate gas first
    const gasEstimate = await contract[method].estimateGas(...args, options);

    // Add 20% buffer
    const gasLimit = gasEstimate * 120n / 100n;

    // Execute transaction
    const tx = await contract[method](...args, { ...options, gasLimit });
    const receipt = await tx.wait();

    return { success: true, receipt };
  } catch (error) {
    // Parse revert reason
    let reason = 'Unknown error';
    if (error.reason) {
      reason = error.reason;
    } else if (error.data) {
      try {
        reason = contract.interface.parseError(error.data)?.name || reason;
      } catch {}
    }

    return { success: false, error: reason };
  }
}

// Usage
const result = await safeContractCall(
  marketplace,
  'createSessionJobForModel',
  [host, price, duration, interval, modelId],
  { value: deposit }
);

if (!result.success) {
  console.error('Transaction failed:', result.error);
  // Handle specific errors
  if (result.error.includes('Price below host minimum')) {
    // Query correct price and retry
  }
}
```

### Pre-flight Checks

Before any transaction, validate:

```javascript
async function validateSessionCreation(host, modelId, price, deposit) {
  const errors = [];

  // Check host is active
  const isActive = await nodeRegistry.isActiveNode(host);
  if (!isActive) errors.push('Host is not active');

  // Check model support
  const supportsModel = await nodeRegistry.nodeSupportsModel(host, modelId);
  if (!supportsModel) errors.push('Host does not support this model');

  // Check price meets minimum
  const hostPrice = await nodeRegistry.getNodePricing(host, ethers.ZeroAddress);
  if (price < hostPrice) errors.push(`Price ${price} below host minimum ${hostPrice}`);

  // Check deposit meets minimum
  const minDeposit = await marketplace.tokenMinDeposits(ethers.ZeroAddress);
  if (deposit < minDeposit) errors.push(`Deposit below minimum ${minDeposit}`);

  // Check contract not paused
  const isPaused = await marketplace.paused();
  if (isPaused) errors.push('Contract is paused');

  if (errors.length > 0) {
    throw new Error('Validation failed: ' + errors.join(', '));
  }

  return true;
}
```
