# Creating Your First Job

This guide walks you through the complete process of creating, claiming, and completing your first AI inference job on Fabstir.

## Prerequisites

- Completed [Environment Setup](setup.md)
- Deployed contracts (see [Deployment Guide](deployment.md))
- Two accounts with testnet ETH:
  - Job Creator account (0.1 ETH)
  - Node Operator account (100.1 ETH for stake + gas)

## Overview

We'll create a simple GPT-4 text generation job:
1. Register as a node operator
2. Post a job as a renter
3. Claim the job as the node
4. Complete the job with results
5. Release payment

## Step 1: Register as a Node Operator

First, we need a registered node to claim jobs.

### Create Registration Script
Create `scripts/register-node.js`:

```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function registerNode() {
    // Connect to Base Sepolia
    const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.NODE_OPERATOR_KEY, provider);
    
    // Contract ABI (minimal)
    const nodeRegistryABI = [
        "function registerNode(string _peerId, string[] _models, string _region) payable",
        "function getNode(address) view returns (tuple(address operator, string peerId, uint256 stake, bool active, string[] models, string region))",
        "event NodeRegistered(address indexed node, string metadata)"
    ];
    
    // Connect to contract
    const nodeRegistry = new ethers.Contract(
        process.env.NODE_REGISTRY_ADDRESS,
        nodeRegistryABI,
        wallet
    );
    
    // Register node
    console.log("Registering node...");
    const tx = await nodeRegistry.registerNode(
        "QmYourPeerIdHere123",  // IPFS peer ID
        ["gpt-4", "gpt-3.5-turbo", "llama-2-70b"],  // Supported models
        "us-east-1",  // Region
        { value: ethers.parseEther("100") }  // 100 ETH stake
    );
    
    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();
    console.log("Node registered successfully!");
    
    // Verify registration
    const node = await nodeRegistry.getNode(wallet.address);
    console.log("Node details:", {
        operator: node.operator,
        peerId: node.peerId,
        stake: ethers.formatEther(node.stake),
        active: node.active,
        models: node.models,
        region: node.region
    });
}

registerNode().catch(console.error);
```

### Run Registration
```bash
# Make sure you have NODE_OPERATOR_KEY in .env
node scripts/register-node.js
```

Expected output:
```
Registering node...
Transaction sent: 0x123...
Node registered successfully!
Node details: {
  operator: '0xYourAddress...',
  peerId: 'QmYourPeerIdHere123',
  stake: '100.0',
  active: true,
  models: [ 'gpt-4', 'gpt-3.5-turbo', 'llama-2-70b' ],
  region: 'us-east-1'
}
```

## Step 2: Create a Job

Now let's post a job as a renter.

### Create Job Posting Script
Create `scripts/create-job.js`:

```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function createJob() {
    // Connect with job creator wallet
    const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.JOB_CREATOR_KEY, provider);
    
    // JobMarketplace ABI
    const jobMarketplaceABI = [
        "function createJob(string _modelId, string _inputHash, uint256 _maxPrice, uint256 _deadline) payable returns (uint256)",
        "function getJob(uint256) view returns (address renter, uint256 payment, uint8 status, address assignedHost, string resultHash, uint256 deadline)",
        "event JobCreated(uint256 indexed jobId, address indexed renter, string modelId, uint256 maxPrice)"
    ];
    
    const jobMarketplace = new ethers.Contract(
        process.env.JOB_MARKETPLACE_ADDRESS,
        jobMarketplaceABI,
        wallet
    );
    
    // Prepare job data
    const modelId = "gpt-4";
    const prompt = "Write a haiku about blockchain technology";
    const inputHash = ethers.id(prompt);  // Simple hash for demo
    const maxPrice = ethers.parseEther("0.01");  // 0.01 ETH payment
    const deadline = Math.floor(Date.now() / 1000) + 3600;  // 1 hour from now
    
    console.log("Creating job...");
    console.log({
        model: modelId,
        prompt: prompt,
        payment: ethers.formatEther(maxPrice) + " ETH",
        deadline: new Date(deadline * 1000).toLocaleString()
    });
    
    // Create job
    const tx = await jobMarketplace.createJob(
        modelId,
        inputHash,
        maxPrice,
        deadline,
        { value: maxPrice }
    );
    
    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();
    
    // Get job ID from event
    const event = receipt.logs.find(log => {
        try {
            const parsed = jobMarketplace.interface.parseLog(log);
            return parsed.name === "JobCreated";
        } catch { return false; }
    });
    
    const jobId = event.args.jobId.toString();
    console.log("Job created with ID:", jobId);
    
    // Save job details
    const fs = require("fs");
    fs.writeFileSync("job-details.json", JSON.stringify({
        jobId,
        prompt,
        inputHash,
        modelId,
        payment: ethers.formatEther(maxPrice),
        deadline
    }, null, 2));
    
    console.log("Job details saved to job-details.json");
}

createJob().catch(console.error);
```

### Run Job Creation
```bash
node scripts/create-job.js
```

Expected output:
```
Creating job...
{
  model: 'gpt-4',
  prompt: 'Write a haiku about blockchain technology',
  payment: '0.01 ETH',
  deadline: '1/20/2024, 3:30:00 PM'
}
Transaction sent: 0x456...
Job created with ID: 1
Job details saved to job-details.json
```

## Step 3: Claim the Job

As the node operator, claim the job.

### Create Claim Script
Create `scripts/claim-job.js`:

```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function claimJob() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.NODE_OPERATOR_KEY, provider);
    
    // Load job details
    const jobDetails = require("./job-details.json");
    
    const jobMarketplaceABI = [
        "function claimJob(uint256 _jobId)",
        "function getJob(uint256) view returns (address, uint256, uint8, address, string, uint256)",
        "event JobClaimed(uint256 indexed jobId, address indexed host)"
    ];
    
    const jobMarketplace = new ethers.Contract(
        process.env.JOB_MARKETPLACE_ADDRESS,
        jobMarketplaceABI,
        wallet
    );
    
    console.log("Claiming job", jobDetails.jobId, "...");
    
    // Check job status first
    const job = await jobMarketplace.getJob(jobDetails.jobId);
    console.log("Current job status:", job[2]); // 0=Posted, 1=Claimed, 2=Completed
    
    if (job[2] !== 0) {
        console.log("Job already claimed or completed!");
        return;
    }
    
    // Claim the job
    const tx = await jobMarketplace.claimJob(jobDetails.jobId);
    console.log("Transaction sent:", tx.hash);
    
    const receipt = await tx.wait();
    console.log("Job claimed successfully!");
    
    // Verify claim
    const updatedJob = await jobMarketplace.getJob(jobDetails.jobId);
    console.log("Assigned host:", updatedJob[3]);
    console.log("Your address:", wallet.address);
}

claimJob().catch(console.error);
```

### Run Claim
```bash
node scripts/claim-job.js
```

## Step 4: Process the Job (Off-chain)

Simulate AI inference by calling an API or running local inference.

### Create Processing Script
Create `scripts/process-job.js`:

```javascript
const { ethers } = require("ethers");
const fs = require("fs");
require("dotenv").config();

async function processJob() {
    const jobDetails = require("./job-details.json");
    
    console.log("Processing job off-chain...");
    console.log("Prompt:", jobDetails.prompt);
    
    // Simulate AI inference (in production, call actual model)
    const result = `Blocks chain together,
Digital ledger secure,
Trust without center.`;
    
    console.log("\nGenerated result:");
    console.log(result);
    
    // Store result in IPFS (simulated)
    const resultHash = ethers.id(result);
    const resultCID = "QmResult" + resultHash.substring(2, 10);
    
    // Save processing details
    const processingDetails = {
        ...jobDetails,
        result,
        resultHash,
        resultCID,
        processedAt: new Date().toISOString()
    };
    
    fs.writeFileSync("processing-details.json", JSON.stringify(processingDetails, null, 2));
    console.log("\nProcessing details saved to processing-details.json");
    
    // Generate proof (mock for demo)
    const proof = {
        modelCommitment: ethers.id(jobDetails.modelId),
        inputHash: jobDetails.inputHash,
        outputHash: resultHash
    };
    
    fs.writeFileSync("proof.json", JSON.stringify(proof, null, 2));
    console.log("Proof saved to proof.json");
}

processJob().catch(console.error);
```

### Run Processing
```bash
node scripts/process-job.js
```

## Step 5: Complete the Job

Submit the result and proof to complete the job.

### Create Completion Script
Create `scripts/complete-job.js`:

```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function completeJob() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.NODE_OPERATOR_KEY, provider);
    
    // Load processing details
    const details = require("./processing-details.json");
    const proof = require("./proof.json");
    
    const jobMarketplaceABI = [
        "function completeJob(uint256 _jobId, string _resultHash, bytes _proof)",
        "event JobCompleted(uint256 indexed jobId, string resultCID)"
    ];
    
    const jobMarketplace = new ethers.Contract(
        process.env.JOB_MARKETPLACE_ADDRESS,
        jobMarketplaceABI,
        wallet
    );
    
    console.log("Completing job", details.jobId, "...");
    console.log("Result CID:", details.resultCID);
    
    // Encode proof
    const proofBytes = ethers.AbiCoder.defaultAbiCoder().encode(
        ["bytes32", "bytes32", "bytes32"],
        [proof.modelCommitment, proof.inputHash, proof.outputHash]
    );
    
    // Complete the job
    const tx = await jobMarketplace.completeJob(
        details.jobId,
        details.resultCID,
        proofBytes
    );
    
    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();
    
    console.log("Job completed successfully!");
    console.log("Payment transferred to node operator");
    
    // Calculate earnings
    const payment = ethers.parseEther(details.payment);
    const fee = (payment * 250n) / 10000n;  // 2.5% fee
    const earnings = payment - fee;
    
    console.log("\nEarnings breakdown:");
    console.log("Total payment:", details.payment, "ETH");
    console.log("Platform fee (2.5%):", ethers.formatEther(fee), "ETH");
    console.log("Net earnings:", ethers.formatEther(earnings), "ETH");
}

completeJob().catch(console.error);
```

### Run Completion
```bash
node scripts/complete-job.js
```

## Step 6: Verify the Result (Job Creator)

As the job creator, verify and retrieve the result.

### Create Verification Script
Create `scripts/verify-result.js`:

```javascript
const { ethers } = require("ethers");
require("dotenv").config();

async function verifyResult() {
    const provider = new ethers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
    const wallet = new ethers.Wallet(process.env.JOB_CREATOR_KEY, provider);
    
    const details = require("./processing-details.json");
    
    const jobMarketplaceABI = [
        "function getJob(uint256) view returns (address, uint256, uint8, address, string, uint256)"
    ];
    
    const jobMarketplace = new ethers.Contract(
        process.env.JOB_MARKETPLACE_ADDRESS,
        jobMarketplaceABI,
        wallet
    );
    
    console.log("Verifying job", details.jobId, "...");
    
    const job = await jobMarketplace.getJob(details.jobId);
    const [renter, payment, status, assignedHost, resultHash, deadline] = job;
    
    console.log("\nJob Details:");
    console.log("Status:", status === 2 ? "Completed" : status === 1 ? "Claimed" : "Posted");
    console.log("Result CID:", resultHash);
    console.log("Assigned Host:", assignedHost);
    
    // In production, fetch from IPFS
    console.log("\nResult from processing:");
    console.log(details.result);
    
    // Optional: Rate the host
    console.log("\nJob completed successfully! Consider rating the host for quality service.");
}

verifyResult().catch(console.error);
```

### Run Verification
```bash
node scripts/verify-result.js
```

## Complete Example Output

After running all scripts, you should see:

```
1. Node Registration:
   ✓ Node registered with 100 ETH stake
   ✓ Supporting gpt-4, gpt-3.5-turbo, llama-2-70b

2. Job Creation:
   ✓ Job #1 created
   ✓ Payment: 0.01 ETH
   ✓ Model: gpt-4

3. Job Claim:
   ✓ Job claimed by node operator

4. Processing:
   ✓ Generated haiku about blockchain

5. Job Completion:
   ✓ Result submitted
   ✓ Payment released
   ✓ Net earnings: 0.00975 ETH

6. Verification:
   ✓ Result retrieved successfully
```

## Common Issues & Solutions

### Issue: "Not a registered host"
**Solution**: Ensure node registration succeeded:
```bash
cast call $NODE_REGISTRY_ADDRESS "isActiveNode(address)" $NODE_OPERATOR_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Issue: "Job already claimed"
**Solution**: Check job status before claiming:
```bash
cast call $JOB_MARKETPLACE_ADDRESS "getJob(uint256)" 1 --rpc-url $BASE_SEPOLIA_RPC_URL
```

### Issue: "Insufficient payment"
**Solution**: Ensure exact payment amount:
```javascript
const tx = await jobMarketplace.createJob(...args, {
    value: maxPrice,  // Must match exactly
    gasLimit: 300000  // Set explicit gas limit if needed
});
```

## Best Practices

### 1. Error Handling
Always wrap operations in try-catch:
```javascript
try {
    const tx = await contract.method();
    const receipt = await tx.wait();
    // Handle success
} catch (error) {
    console.error("Transaction failed:", error.message);
    // Handle specific errors
}
```

### 2. Gas Management
Monitor gas usage:
```javascript
const gasEstimate = await contract.estimateGas.method(...args);
const tx = await contract.method(...args, {
    gasLimit: gasEstimate.mul(110).div(100)  // 10% buffer
});
```

### 3. Event Monitoring
Listen for events:
```javascript
jobMarketplace.on("JobCreated", (jobId, renter, modelId, maxPrice) => {
    console.log(`New job #${jobId} for ${modelId}`);
});
```

## Next Steps

Now that you've completed your first job:

1. **[Post More Complex Jobs](../job-creators/posting-jobs.md)** - Advanced job configurations
2. **[Optimize Node Operations](../node-operators/claiming-jobs.md)** - Efficient job selection
3. **[Build Applications](../developers/building-on-fabstir.md)** - Create services on Fabstir

## Summary

You've successfully:
- ✅ Registered as a node operator
- ✅ Posted an AI inference job
- ✅ Claimed and processed the job
- ✅ Submitted results with proof
- ✅ Received payment

This is the foundation for all Fabstir operations. Whether you're providing compute or requesting inference, these patterns form the core of the marketplace.

---

Ready to dive deeper? Explore the [Node Operators Guide](../node-operators/running-a-node.md) or [Job Creators Guide](../job-creators/posting-jobs.md) →