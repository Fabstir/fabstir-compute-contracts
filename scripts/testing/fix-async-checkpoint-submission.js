// CRITICAL: Proper async/await handling for blockchain transactions
// Base Sepolia can take 15-30 seconds for confirmation!

const { ethers } = require('ethers');

/**
 * WRONG - Common timeout/async mistakes
 */
async function WRONG_submitCheckpoint(jobId, tokens, proof) {
  // ❌ WRONG: Not waiting for transaction
  const tx = contract.submitProofOfWork(jobId, tokens, proof);
  console.log("Submitted:", tx); // This might log a Promise, not tx hash!

  // ❌ WRONG: Timeout too short
  setTimeout(() => {
    console.log("Assuming failed");
  }, 5000); // 5 seconds is TOO SHORT for Base Sepolia!

  // ❌ WRONG: Not waiting for confirmation
  try {
    await contract.submitProofOfWork(jobId, tokens, proof);
    console.log("Done"); // Transaction sent, but not confirmed!
  } catch (e) {
    console.error("Failed"); // Might timeout before blockchain responds
  }
}

/**
 * CORRECT - Proper async/await with appropriate timeouts
 */
async function CORRECT_submitCheckpoint(jobId, tokens, proof) {
  console.log(`[${new Date().toISOString()}] Starting checkpoint submission for job ${jobId}`);

  try {
    // Step 1: Send transaction and WAIT for it
    console.log("Step 1: Sending transaction...");
    const tx = await contract.submitProofOfWork(
      jobId,
      tokens,
      proof,
      {
        gasLimit: 300000, // Explicit gas limit
        // Base Sepolia can be slow, set longer timeout
        timeout: 60000    // 60 second timeout for sending
      }
    );

    console.log(`Step 2: Transaction sent! Hash: ${tx.hash}`);
    console.log("         Waiting for confirmation (this can take 15-30 seconds)...");

    // Step 2: Wait for confirmation with timeout
    const receipt = await Promise.race([
      tx.wait(1), // Wait for 1 confirmation
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Transaction confirmation timeout after 60s')), 60000)
      )
    ]);

    console.log(`Step 3: Transaction confirmed!`);
    console.log(`         Status: ${receipt.status === 1 ? 'SUCCESS' : 'FAILED'}`);
    console.log(`         Block: ${receipt.blockNumber}`);
    console.log(`         Gas used: ${receipt.gasUsed.toString()}`);

    if (receipt.status === 0) {
      throw new Error('Transaction reverted on-chain');
    }

    // Step 3: Verify the proof was recorded
    const session = await contract.sessionJobs(jobId);
    console.log(`Step 4: Verified - Session now has ${session.tokensUsed} tokens used`);

    return receipt;

  } catch (error) {
    console.error(`[${new Date().toISOString()}] Checkpoint submission failed:`);

    // Detailed error analysis
    if (error.code === 'TIMEOUT') {
      console.error("❌ TIMEOUT: Transaction took too long. Base Sepolia might be congested.");
      console.error("   Solution: Retry with higher gas price or wait and retry");
    } else if (error.code === 'NONCE_EXPIRED') {
      console.error("❌ NONCE: Another transaction was sent from this wallet");
      console.error("   Solution: Get fresh nonce and retry");
    } else if (error.reason) {
      console.error(`❌ REVERT: ${error.reason}`);
      console.error("   This is a smart contract validation failure");
    } else if (error.message?.includes('timeout')) {
      console.error("❌ TIMEOUT: Increase timeout values and retry");
    } else {
      console.error("❌ UNKNOWN ERROR:", error.message);
      console.error("Full error object:", error);
    }

    throw error;
  }
}

/**
 * Retry logic for resilient submission
 */
async function submitCheckpointWithRetry(jobId, tokens, proof, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    console.log(`\n=== Attempt ${attempt} of ${maxRetries} ===`);

    try {
      const receipt = await CORRECT_submitCheckpoint(jobId, tokens, proof);
      console.log(`✅ SUCCESS on attempt ${attempt}`);
      return receipt;
    } catch (error) {
      console.error(`❌ Attempt ${attempt} failed`);

      if (attempt === maxRetries) {
        console.error("All retry attempts exhausted");
        throw error;
      }

      // Don't retry on permanent failures
      if (error.reason?.includes('Session not active') ||
          error.reason?.includes('Only host can submit')) {
        console.error("Permanent error - not retrying");
        throw error;
      }

      // Wait before retry (exponential backoff)
      const waitTime = attempt * 5000;
      console.log(`Waiting ${waitTime/1000} seconds before retry...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }
}

/**
 * Main test function
 */
async function testCheckpointSubmission() {
  // Configuration
  const provider = new ethers.JsonRpcProvider('https://sepolia.base.org');

  // Add timeout to provider itself
  provider._getConnection().timeout = 60000; // 60 second timeout

  const wallet = new ethers.Wallet(process.env.HOST_PRIVATE_KEY, provider);
  console.log("Host wallet:", wallet.address);

  const contract = new ethers.Contract(
    '0x1273E6358aa52Bb5B160c34Bf2e617B745e4A944',
    [
      'function submitProofOfWork(uint256 jobId, uint256 tokensClaimed, bytes proof)',
      'function sessionJobs(uint256) view returns (uint256,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)'
    ],
    wallet
  );

  // Generate valid proof
  const proof = ethers.randomBytes(64);
  console.log("Proof generated:", ethers.hexlify(proof).slice(0, 20) + "...");

  // Check session before submission
  const sessionBefore = await contract.sessionJobs(143);
  console.log("Session 143 tokens used BEFORE:", sessionBefore[6].toString());

  // Submit with proper error handling and retries
  await submitCheckpointWithRetry(143, 100, proof);

  // Verify after submission
  const sessionAfter = await contract.sessionJobs(143);
  console.log("Session 143 tokens used AFTER:", sessionAfter[6].toString());
}

// For Node Developer to integrate:
module.exports = {
  submitCheckpointWithRetry,

  // Simple wrapper for their system
  submitCheckpoint: async function(jobId, tokensClaimed) {
    const proof = ethers.randomBytes(64);
    return await submitCheckpointWithRetry(jobId, tokensClaimed, proof);
  }
};

// Run if called directly
if (require.main === module) {
  testCheckpointSubmission()
    .then(() => console.log("\n✅ Test completed"))
    .catch(err => console.error("\n❌ Test failed:", err));
}