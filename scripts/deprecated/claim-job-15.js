const { ethers } = require("ethers");
require("dotenv").config();

// Contract ABI
const MARKETPLACE_ABI = [
  "function claimWithProof(uint256 jobId) external",
  "function sessions(uint256) external view returns (uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,uint8,uint256,uint256)",
  "event HostClaimedWithProof(uint256 indexed jobId, address indexed host, uint256 tokens, uint256 payment)",
  "event SessionCompleted(uint256 indexed jobId, address indexed host, uint256 tokens, uint256 payment, uint256 refund)"
];

const USDC_ABI = [
  "function balanceOf(address) external view returns (uint256)"
];

async function claimJob15() {
  // Setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  
  // Use HOST 1 private key
  const hostPrivateKey = process.env.TEST_HOST_1_PRIVATE_KEY;
  const hostSigner = new ethers.Wallet(hostPrivateKey, provider);
  
  // User (renter) wallet to check refund
  const userPrivateKey = process.env.TEST_USER_1_PRIVATE_KEY;
  const userSigner = new ethers.Wallet(userPrivateKey, provider);
  
  const marketplaceAddress = "0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0";
  const marketplace = new ethers.Contract(marketplaceAddress, MARKETPLACE_ABI, hostSigner);
  
  const usdcAddress = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  const usdc = new ethers.Contract(usdcAddress, USDC_ABI, provider);
  
  const jobId = 15;
  
  console.log("=== Claiming Job 15 with Proof ===");
  console.log("Job ID:", jobId);
  console.log("Host Address:", hostSigner.address);
  console.log("User Address:", userSigner.address);
  
  // Get session details before claim
  const sessionBefore = await marketplace.sessions(jobId);
  console.log("\nSession Before Claim:");
  console.log("- Deposit:", ethers.utils.formatUnits(sessionBefore[0], 6), "USDC");
  console.log("- Price per token:", sessionBefore[1].toString());
  console.log("- Status:", sessionBefore[5].toString(), "(0=Active, 1=Completed)");
  console.log("- Proven tokens:", sessionBefore[6].toString());
  
  // Calculate expected payments
  const provenTokens = ethers.BigNumber.from(sessionBefore[6]);
  const pricePerToken = ethers.BigNumber.from(sessionBefore[1]);
  const deposit = ethers.BigNumber.from(sessionBefore[0]);
  const totalCost = provenTokens.mul(pricePerToken);
  const treasuryFee = totalCost.div(10); // 10% fee
  const hostPayment = totalCost.sub(treasuryFee);
  const refund = deposit.sub(totalCost);
  
  console.log("\nExpected Payments:");
  console.log("- Total cost:", ethers.utils.formatUnits(totalCost, 6), "USDC");
  console.log("- Host payment (90%):", ethers.utils.formatUnits(hostPayment, 6), "USDC");
  console.log("- Treasury fee (10%):", ethers.utils.formatUnits(treasuryFee, 6), "USDC");
  console.log("- User refund:", ethers.utils.formatUnits(refund, 6), "USDC");
  
  // Get balances before
  const userBalanceBefore = await usdc.balanceOf(userSigner.address);
  const marketplaceBalanceBefore = await usdc.balanceOf(marketplaceAddress);
  
  console.log("\nBalances Before:");
  console.log("- User USDC:", ethers.utils.formatUnits(userBalanceBefore, 6));
  console.log("- Marketplace USDC:", ethers.utils.formatUnits(marketplaceBalanceBefore, 6));
  
  try {
    console.log("\nCalling claimWithProof...");
    const tx = await marketplace.claimWithProof(jobId);
    console.log("Transaction sent:", tx.hash);
    
    const receipt = await tx.wait();
    console.log("Transaction confirmed in block:", receipt.blockNumber);
    console.log("Gas used:", receipt.gasUsed.toString());
    
    // Check for events
    const events = receipt.logs.map(log => {
      try {
        return marketplace.interface.parseLog(log);
      } catch {
        return null;
      }
    }).filter(e => e !== null);
    
    console.log("\nEvents emitted:");
    events.forEach(event => {
      console.log("-", event.name);
      if (event.name === "SessionCompleted" && event.args.length >= 5) {
        console.log("  - Tokens:", event.args[2].toString());
        console.log("  - Payment:", ethers.utils.formatUnits(event.args[3], 6), "USDC");
        console.log("  - Refund:", ethers.utils.formatUnits(event.args[4], 6), "USDC");
      }
    });
    
    // Get balances after
    const userBalanceAfter = await usdc.balanceOf(userSigner.address);
    const marketplaceBalanceAfter = await usdc.balanceOf(marketplaceAddress);
    
    console.log("\nBalances After:");
    console.log("- User USDC:", ethers.utils.formatUnits(userBalanceAfter, 6));
    console.log("- Marketplace USDC:", ethers.utils.formatUnits(marketplaceBalanceAfter, 6));
    
    // Calculate actual changes
    const userRefund = userBalanceAfter.sub(userBalanceBefore);
    const marketplaceChange = marketplaceBalanceBefore.sub(marketplaceBalanceAfter);
    
    console.log("\nActual Changes:");
    console.log("- User received:", ethers.utils.formatUnits(userRefund, 6), "USDC");
    console.log("- Marketplace sent:", ethers.utils.formatUnits(marketplaceChange, 6), "USDC");
    
    // Get session after claim
    const sessionAfter = await marketplace.sessions(jobId);
    console.log("\nSession After Claim:");
    console.log("- Status:", sessionAfter[5].toString(), "(0=Active, 1=Completed)");
    
    // Verify refund
    if (userRefund.gt(0)) {
      console.log("\n✅ SUCCESS: User received refund of", ethers.utils.formatUnits(userRefund, 6), "USDC!");
      console.log("Refund bug is FIXED!");
    } else {
      console.log("\n❌ FAILURE: User did not receive refund");
      console.log("Expected:", ethers.utils.formatUnits(refund, 6), "USDC");
    }
    
  } catch (error) {
    console.error("\n❌ Error claiming with proof:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

// Run the script
claimJob15()
  .then(() => console.log("\n✅ Script completed"))
  .catch(error => {
    console.error("\n❌ Script failed:", error);
    process.exit(1);
  });