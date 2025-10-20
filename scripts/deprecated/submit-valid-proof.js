// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
const { ethers } = require("ethers");
require("dotenv").config();

// Contract ABI for submitProofOfWork function
const MARKETPLACE_ABI = [
  "function submitProofOfWork(uint256 jobId, bytes calldata ekzlProof, uint256 tokensInBatch) external returns (bool)",
  "function getProvenTokens(uint256 jobId) external view returns (uint256)",
  "function sessions(uint256) external view returns (uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,uint8,uint256,uint256)",
  "event ProofSubmitted(uint256 indexed jobId, address indexed host, uint256 tokens, bytes32 proofHash, bool verified)"
];

async function submitValidProof() {
  // Setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  
  // Use HOST 1 private key
  const hostPrivateKey = process.env.TEST_HOST_1_PRIVATE_KEY;
  const hostSigner = new ethers.Wallet(hostPrivateKey, provider);
  
  const marketplaceAddress = "0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0";
  const marketplace = new ethers.Contract(marketplaceAddress, MARKETPLACE_ABI, hostSigner);
  
  const jobId = 15; // The job we're testing
  const tokensToProve = 100; // Number of tokens to prove
  
  console.log("=== Submitting Valid Proof for Job 15 ===");
  console.log("Job ID:", jobId);
  console.log("Host Address:", hostSigner.address);
  console.log("Tokens to prove:", tokensToProve);
  
  // Check current proven tokens
  const currentTokens = await marketplace.getProvenTokens(jobId);
  console.log("\nCurrent proven tokens:", currentTokens.toString());
  
  // Create a valid 64-byte proof (minimum required by ProofSystem)
  // In production, this would be a real EZKL proof
  // For testing, we create a unique 64-byte value
  const timestamp = Math.floor(Date.now() / 1000);
  const proofData = ethers.utils.defaultAbiCoder.encode(
    ["bytes32", "bytes32"],
    [
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes(`proof_${jobId}_${timestamp}`)),
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes(`data_${tokensToProve}_${timestamp}`))
    ]
  );
  
  console.log("\nProof Details:");
  console.log("- Length:", proofData.length, "characters (", ethers.utils.hexDataLength(proofData), "bytes)");
  console.log("- First 32 bytes:", proofData.slice(0, 66));
  
  try {
    console.log("\nSubmitting proof...");
    const tx = await marketplace.submitProofOfWork(jobId, proofData, tokensToProve);
    console.log("Transaction sent:", tx.hash);
    
    const receipt = await tx.wait();
    console.log("Transaction confirmed in block:", receipt.blockNumber);
    
    // Check for ProofSubmitted event
    const proofEvent = receipt.logs.find(log => {
      try {
        const parsed = marketplace.interface.parseLog(log);
        return parsed.name === "ProofSubmitted";
      } catch {
        return false;
      }
    });
    
    if (proofEvent) {
      const parsed = marketplace.interface.parseLog(proofEvent);
      console.log("\nProof Submitted Event:");
      console.log("- Verified:", parsed.args[4]); // The 'verified' boolean
      console.log("- Proof Hash:", parsed.args[3]); // The proof hash
    }
    
    // Check updated proven tokens
    const newTokens = await marketplace.getProvenTokens(jobId);
    console.log("\nUpdated proven tokens:", newTokens.toString());
    
    if (newTokens > currentTokens) {
      console.log("✅ SUCCESS: Proof was accepted and tokens updated!");
      console.log(`Tokens increased by: ${newTokens - currentTokens}`);
    } else {
      console.log("❌ FAILURE: Proof was not accepted. Tokens unchanged.");
    }
    
    // Get session details to verify
    const session = await marketplace.sessions(jobId);
    console.log("\nSession Status:");
    console.log("- Deposit:", ethers.utils.formatUnits(session[0], 6), "USDC");
    console.log("- Price per token:", session[1].toString());
    console.log("- Proven tokens:", newTokens.toString());
    console.log("- Cost for proven tokens:", ethers.utils.formatUnits(newTokens * session[1], 6), "USDC");
    console.log("- Expected refund:", ethers.utils.formatUnits(session[0] - (newTokens * session[1]), 6), "USDC");
    
  } catch (error) {
    console.error("\n❌ Error submitting proof:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

// Run the script
submitValidProof()
  .then(() => console.log("\n✅ Script completed"))
  .catch(error => {
    console.error("\n❌ Script failed:", error);
    process.exit(1);
  });