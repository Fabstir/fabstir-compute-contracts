/**
 * Example: Retrieve Job Details from JobMarketplaceFABWithS5
 * 
 * This example shows how to:
 * 1. Connect to the contract
 * 2. Check if a job exists
 * 3. Retrieve job details
 * 4. Handle the case when no jobs exist
 */

import { ethers } from 'ethers';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

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
  },
  {
    "inputs": [],
    "name": "nextJobId",
    "outputs": [{"name": "", "type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
];

// Job status enum
enum JobStatus {
  Posted = 0,
  Claimed = 1,
  Completed = 2
}

// Job interface
interface JobDetails {
  renter: string;
  payment: bigint;
  status: JobStatus;
  assignedHost: string;
  promptCID: string;
  responseCID: string;
  deadline: bigint;
}

/**
 * Format job details for display
 */
function formatJobDetails(jobId: number, job: JobDetails): string {
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
 * Get the next job ID (to check how many jobs exist)
 */
async function getNextJobId(contract: ethers.Contract): Promise<number> {
  try {
    // Note: nextJobId is private in the contract, so we can't access it directly
    // We'll need to try getting jobs to see which ones exist
    return 1; // Start checking from job ID 1
  } catch (error) {
    console.log('Could not get nextJobId (private variable)');
    return 1;
  }
}

/**
 * Check if a job exists by trying to retrieve it
 */
async function jobExists(contract: ethers.Contract, jobId: number): Promise<boolean> {
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
async function getJobDetails(contract: ethers.Contract, jobId: number): Promise<JobDetails | null> {
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
  } catch (error: any) {
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
      }
    }
    
    // Example: How to watch for new jobs
    console.log('\n📊 Setting up event listener for new jobs...');
    console.log('   (Press Ctrl+C to exit)\n');
    
    // Listen for JobCreated events
    jobMarketplace.on('JobCreated', (jobId, renter, modelId, maxPrice, promptCID) => {
      console.log('🆕 New job created!');
      console.log(`   Job ID: ${jobId}`);
      console.log(`   Renter: ${renter}`);
      console.log(`   Model: ${modelId}`);
      console.log(`   Payment: ${ethers.formatEther(maxPrice)} ETH`);
      console.log(`   Prompt CID: ${promptCID}`);
    });
    
    // Listen for JobCreatedWithToken events (USDC payments)
    jobMarketplace.on('JobCreatedWithToken', (jobId, renter, paymentToken, paymentAmount, promptCID) => {
      console.log('🆕 New job created with token payment!');
      console.log(`   Job ID: ${jobId}`);
      console.log(`   Renter: ${renter}`);
      console.log(`   Token: ${paymentToken}`);
      console.log(`   Amount: ${ethers.formatUnits(paymentAmount, 6)} USDC`); // USDC has 6 decimals
      console.log(`   Prompt CID: ${promptCID}`);
    });
    
  } catch (error) {
    console.error('Error:', error);
  }
}

// Export functions for use in other modules
export {
  getJobDetails,
  jobExists,
  formatJobDetails,
  JobStatus,
  type JobDetails
};

// Run if called directly
if (require.main === module) {
  main().catch(console.error);
}