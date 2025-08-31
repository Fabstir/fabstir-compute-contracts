/**
 * Example: Retrieve Job Details from JobMarketplaceFABWithS5
 * 
 * This example shows how to:
 * 1. Connect to the contract
 * 2. Check if a job exists
 * 3. Retrieve job details
 * 4. Handle the case when no jobs exist
 */

const { ethers } = require('ethers');
require('dotenv').config();

// Contract addresses from fresh deployment
const CONTRACTS = {
  marketplace: '0x58FF6c0E8153bc846612F94a3024Fd7a67711465',
  paymentEscrow: '0x8608cA35DAE816f5CfC4DD76e1f850D92a2bC494',
  hostEarnings: '0x171E6413cC1BA943923F60A187De9753ded1bfd3',
};

// Minimal ABI for getJob function
const JOB_MARKETPLACE_ABI = [
  {
    "inputs": [{"name": "_jobId", "type": "uint256"}],
    "name": "getJob",
    "outputs": [
      {"name": "renter", "type": "address"},
      {"name": "payment", "type": "uint256"},
      {"name": "status", "type": "uint8"},
      {"name": "assignedHost", "type": "address"},
      {"name": "promptCID", "type": "string"},
      {"name": "responseCID", "type": "string"},
      {"name": "deadline", "type": "uint256"}
    ],
    "stateMutability": "view",
    "type": "function"
  }
];

// Job status enum
const JobStatus = {
  Posted: 0,
  Claimed: 1,
  Completed: 2
};

/**
 * Format job details for display
 */
function formatJobDetails(jobId, job) {
  const statusNames = ['Posted', 'Claimed', 'Completed'];
  const deadlineDate = new Date(Number(job.deadline) * 1000);
  
  return `
Job #${jobId} Details:
======================
Renter:        ${job.renter}
Payment:       ${ethers.formatEther(job.payment)} ETH
Status:        ${statusNames[job.status]}
Assigned Host: ${job.assignedHost === ethers.ZeroAddress ? 'None' : job.assignedHost}
Prompt CID:    ${job.promptCID || 'None'}
Response CID:  ${job.responseCID || 'None'}
Deadline:      ${deadlineDate.toISOString()}
`;
}

/**
 * Check if a job exists by trying to retrieve it
 */
async function jobExists(contract, jobId) {
  try {
    const job = await contract.getJob(jobId);
    // If renter is zero address, job doesn't exist
    return job.renter !== ethers.ZeroAddress;
  } catch (error) {
    // If the call reverts, job doesn't exist
    return false;
  }
}

/**
 * Get job details with error handling
 */
async function getJobDetails(contract, jobId) {
  try {
    const job = await contract.getJob(jobId);
    
    // Check if job exists (renter should not be zero address)
    if (job.renter === ethers.ZeroAddress) {
      return null;
    }
    
    return {
      renter: job.renter,
      payment: job.payment,
      status: Number(job.status),
      assignedHost: job.assignedHost,
      promptCID: job.promptCID,
      responseCID: job.responseCID,
      deadline: job.deadline
    };
  } catch (error) {
    if (error.message?.includes('Job does not exist') || 
        error.message?.includes('execution reverted')) {
      return null;
    }
    throw error;
  }
}

/**
 * Main function to demonstrate retrieving job details
 */
async function main() {
  try {
    // Setup provider (Base Sepolia)
    const provider = new ethers.JsonRpcProvider(
      process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org'
    );
    
    // Create contract instance (read-only)
    const jobMarketplace = new ethers.Contract(
      CONTRACTS.marketplace,
      JOB_MARKETPLACE_ABI,
      provider
    );
    
    console.log('Connected to JobMarketplaceFABWithS5 at:', CONTRACTS.marketplace);
    console.log('');
    
    // Try to get job #1
    console.log('Attempting to retrieve Job #1...');
    const job1 = await getJobDetails(jobMarketplace, 1);
    
    if (job1) {
      console.log(formatJobDetails(1, job1));
    } else {
      console.log('❌ Job #1 does not exist yet.');
      console.log('   The contract was just deployed and no jobs have been created.');
      console.log('');
      
      // Check for other jobs (in case they were created out of order)
      console.log('Checking for any existing jobs (IDs 1-10)...');
      let foundAny = false;
      
      for (let jobId = 1; jobId <= 10; jobId++) {
        if (await jobExists(jobMarketplace, jobId)) {
          const job = await getJobDetails(jobMarketplace, jobId);
          if (job) {
            console.log(formatJobDetails(jobId, job));
            foundAny = true;
          }
        }
      }
      
      if (!foundAny) {
        console.log('No jobs found in the contract.');
        console.log('');
        console.log('To create a job, you need to call one of these functions:');
        console.log('  - postJob() for ETH payment');
        console.log('  - postJobWithToken() for USDC payment');
        console.log('');
        console.log('Example code to post a job with USDC:');
        console.log('----------------------------------------');
        console.log(`
const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
const marketplaceWithSigner = jobMarketplace.connect(signer);

// First approve USDC spending
const usdcAddress = '0x036CbD53842c5426634e7929541eC2318f3dCF7e';
const usdcAbi = ['function approve(address spender, uint256 amount) returns (bool)'];
const usdc = new ethers.Contract(usdcAddress, usdcAbi, signer);

const amount = ethers.parseUnits('10', 6); // 10 USDC (6 decimals)
await usdc.approve(CONTRACTS.marketplace, amount);

// Then post the job
const jobDetails = {
  modelId: 'gpt-4',
  promptCID: 'bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi', // Example S5 CID
  responseCID: '', // Empty for new job
  resultFormat: 'json',
  temperature: 700, // 0.7 * 1000
  maxTokens: 500,
  seed: 12345
};

const jobRequirements = {
  minGPUMemory: 16, // 16 GB
  maxTimeToComplete: 3600, // 1 hour
  minReputationScore: 0,
  requiresProof: false
};

const tx = await marketplaceWithSigner.postJobWithToken(
  usdcAddress,
  amount,
  jobDetails,
  jobRequirements,
  ethers.ZeroAddress, // No specific host required
  Math.floor(Date.now() / 1000) + 86400 // 24 hour deadline
);

const receipt = await tx.wait();
console.log('Job posted! Transaction:', receipt.hash);
        `);
      }
    }
    
  } catch (error) {
    console.error('Error:', error);
  }
}

// Export functions for use in other modules
module.exports = {
  getJobDetails,
  jobExists,
  formatJobDetails,
  JobStatus,
  CONTRACTS
};

// Run if called directly
if (require.main === module) {
  main().catch(console.error);
}