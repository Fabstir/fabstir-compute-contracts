// Copyright (c) 2025 Fabstir
// SPDX-License-Identifier: BUSL-1.1
const { ethers } = require("ethers");
require("dotenv").config();

// Contract ABI
const MARKETPLACE_ABI = [
  "function withdrawTreasuryETH() external",
  "function accumulatedTreasuryETH() external view returns (uint256)",
  "function treasuryAddress() external view returns (address)",
  "event TreasuryFeesWithdrawn(uint256 amount, address token)"
];

async function withdrawTreasuryETH() {
  // Setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  
  // Treasury private key (deployer)
  const treasuryPrivateKey = "0xe7231a57c89df087f0291bf20b952199c1d4575206d256397c02ba6383dedc97";
  const treasurySigner = new ethers.Wallet(treasuryPrivateKey, provider);
  
  const marketplaceAddress = "0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0";
  const marketplace = new ethers.Contract(marketplaceAddress, MARKETPLACE_ABI, treasurySigner);
  
  console.log("=== Treasury ETH Withdrawal ===");
  console.log("Marketplace:", marketplaceAddress);
  console.log("Treasury Address:", treasurySigner.address);
  
  // Verify treasury address
  const contractTreasury = await marketplace.treasuryAddress();
  console.log("Contract Treasury:", contractTreasury);
  
  if (contractTreasury.toLowerCase() !== treasurySigner.address.toLowerCase()) {
    console.error("❌ ERROR: Signer is not the treasury!");
    return;
  }
  
  // Check accumulated ETH
  const accumulatedETH = await marketplace.accumulatedTreasuryETH();
  console.log("\n📊 Accumulated Treasury ETH:", ethers.utils.formatEther(accumulatedETH), "ETH");
  
  if (accumulatedETH.eq(0)) {
    console.log("⚠️  No ETH fees to withdraw");
    return;
  }
  
  // Get balance before
  const treasuryETHBefore = await provider.getBalance(treasurySigner.address);
  console.log("\n💰 Treasury ETH Balance Before:", ethers.utils.formatEther(treasuryETHBefore));
  
  try {
    console.log("\n🔄 Withdrawing ETH fees...");
    console.log("Amount to withdraw:", ethers.utils.formatEther(accumulatedETH), "ETH");
    
    // Estimate gas first
    const gasEstimate = await marketplace.estimateGas.withdrawTreasuryETH();
    console.log("Estimated gas:", gasEstimate.toString());
    
    // Send transaction with gas limit
    const tx = await marketplace.withdrawTreasuryETH({
      gasLimit: gasEstimate.mul(120).div(100) // Add 20% buffer
    });
    console.log("Transaction sent:", tx.hash);
    
    const receipt = await tx.wait();
    console.log("✅ Transaction confirmed in block:", receipt.blockNumber);
    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("Status:", receipt.status === 1 ? "SUCCESS" : "FAILED");
    
    // Check for event
    const withdrawEvent = receipt.logs.find(log => {
      try {
        const parsed = marketplace.interface.parseLog(log);
        return parsed.name === "TreasuryFeesWithdrawn";
      } catch {
        return false;
      }
    });
    
    if (withdrawEvent) {
      const parsed = marketplace.interface.parseLog(withdrawEvent);
      console.log("Event - Withdrawn amount:", ethers.utils.formatEther(parsed.args[0]), "ETH");
    }
    
    // Get balance after
    const treasuryETHAfter = await provider.getBalance(treasurySigner.address);
    console.log("\n💰 Treasury ETH Balance After:", ethers.utils.formatEther(treasuryETHAfter));
    
    // Calculate actual change (accounting for gas)
    const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);
    const expectedIncrease = accumulatedETH.sub(gasUsed);
    const actualChange = treasuryETHAfter.sub(treasuryETHBefore);
    
    console.log("\n📈 Analysis:");
    console.log("- Withdrawn amount:", ethers.utils.formatEther(accumulatedETH), "ETH");
    console.log("- Gas cost:", ethers.utils.formatEther(gasUsed), "ETH");
    console.log("- Expected net increase:", ethers.utils.formatEther(expectedIncrease), "ETH");
    console.log("- Actual balance change:", ethers.utils.formatEther(actualChange), "ETH");
    
    // Verify accumulated is now zero
    const remainingETH = await marketplace.accumulatedTreasuryETH();
    console.log("\n✅ Remaining Accumulated ETH:", ethers.utils.formatEther(remainingETH));
    
    if (remainingETH.eq(0)) {
      console.log("🎉 SUCCESS: All ETH treasury fees withdrawn!");
      
      // Calculate if we got the right amount
      const difference = actualChange.sub(expectedIncrease);
      if (difference.abs().lt(ethers.utils.parseEther("0.0001"))) {
        console.log("✅ Amount received matches expected (within gas tolerance)");
      } else {
        console.log("⚠️  Amount difference:", ethers.utils.formatEther(difference), "ETH");
      }
    }
    
  } catch (error) {
    console.error("\n❌ Error withdrawing ETH:", error.message);
    
    // Try to decode the error
    if (error.error && error.error.data) {
      console.error("Error data:", error.error.data);
      
      // Common revert reasons
      if (error.error.data.includes("0x")) {
        if (error.error.data === "0x") {
          console.error("Transaction reverted with no reason");
        } else {
          console.error("Revert data:", error.error.data);
        }
      }
    }
    
    // Check if it's a gas issue
    if (error.code === 'UNPREDICTABLE_GAS_LIMIT') {
      console.error("Gas estimation failed - the transaction would likely revert");
    }
  }
}

// Run the script
withdrawTreasuryETH()
  .then(() => console.log("\n✅ Script completed"))
  .catch(error => {
    console.error("\n❌ Script failed:", error);
    process.exit(1);
  });