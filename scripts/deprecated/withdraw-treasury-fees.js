const { ethers } = require("ethers");
require("dotenv").config();

// Contract ABIs
const MARKETPLACE_ABI = [
  "function withdrawTreasuryTokens(address token) external",
  "function withdrawTreasuryETH() external",
  "function withdrawAllTreasuryFees(address[] calldata tokens) external",
  "function accumulatedTreasuryTokens(address) external view returns (uint256)",
  "function accumulatedTreasuryETH() external view returns (uint256)",
  "function treasuryAddress() external view returns (address)",
  "event TreasuryFeesWithdrawn(uint256 amount, address token)"
];

const USDC_ABI = [
  "function balanceOf(address) external view returns (uint256)"
];

async function withdrawTreasuryFees() {
  // Setup provider and signer
  const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  
  // Use deployer/treasury private key - hardcoded for now since .env has wrong mapping
  const treasuryPrivateKey = "0xe7231a57c89df087f0291bf20b952199c1d4575206d256397c02ba6383dedc97"; // Treasury/Deployer key
  const treasurySigner = new ethers.Wallet(treasuryPrivateKey, provider);
  
  const marketplaceAddress = "0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0";
  const marketplace = new ethers.Contract(marketplaceAddress, MARKETPLACE_ABI, treasurySigner);
  
  const usdcAddress = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  const usdc = new ethers.Contract(usdcAddress, USDC_ABI, provider);
  
  console.log("=== Treasury Fee Withdrawal ===");
  console.log("Marketplace:", marketplaceAddress);
  console.log("Treasury Address:", treasurySigner.address);
  
  // Verify treasury address matches contract
  const contractTreasury = await marketplace.treasuryAddress();
  console.log("Contract Treasury:", contractTreasury);
  
  if (contractTreasury.toLowerCase() !== treasurySigner.address.toLowerCase()) {
    console.error("❌ ERROR: Signer is not the treasury!");
    console.error("Expected:", contractTreasury);
    console.error("Got:", treasurySigner.address);
    return;
  }
  
  // Check accumulated fees
  const accumulatedUSDC = await marketplace.accumulatedTreasuryTokens(usdcAddress);
  const accumulatedETH = await marketplace.accumulatedTreasuryETH();
  
  console.log("\n📊 Accumulated Treasury Fees:");
  console.log("- USDC:", ethers.utils.formatUnits(accumulatedUSDC, 6), "USDC");
  console.log("- ETH:", ethers.utils.formatEther(accumulatedETH), "ETH");
  
  if (accumulatedUSDC.eq(0) && accumulatedETH.eq(0)) {
    console.log("\n⚠️  No fees to withdraw");
    return;
  }
  
  // Get balances before withdrawal
  const treasuryUSDCBefore = await usdc.balanceOf(treasurySigner.address);
  const treasuryETHBefore = await provider.getBalance(treasurySigner.address);
  
  console.log("\n💰 Treasury Balances Before:");
  console.log("- USDC:", ethers.utils.formatUnits(treasuryUSDCBefore, 6));
  console.log("- ETH:", ethers.utils.formatEther(treasuryETHBefore));
  
  try {
    // Withdraw USDC if accumulated
    if (accumulatedUSDC.gt(0)) {
      console.log("\n🔄 Withdrawing USDC fees...");
      const tx = await marketplace.withdrawTreasuryTokens(usdcAddress);
      console.log("Transaction sent:", tx.hash);
      
      const receipt = await tx.wait();
      console.log("✅ USDC withdrawal confirmed in block:", receipt.blockNumber);
      
      // Check for withdrawal event
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
        console.log("Withdrawn amount:", ethers.utils.formatUnits(parsed.args[0], 6), "USDC");
      }
    }
    
    // Withdraw ETH if accumulated
    if (accumulatedETH.gt(0)) {
      console.log("\n🔄 Withdrawing ETH fees...");
      const tx = await marketplace.withdrawTreasuryETH();
      console.log("Transaction sent:", tx.hash);
      
      const receipt = await tx.wait();
      console.log("✅ ETH withdrawal confirmed in block:", receipt.blockNumber);
    }
    
    // Get balances after withdrawal
    const treasuryUSDCAfter = await usdc.balanceOf(treasurySigner.address);
    const treasuryETHAfter = await provider.getBalance(treasurySigner.address);
    
    console.log("\n💰 Treasury Balances After:");
    console.log("- USDC:", ethers.utils.formatUnits(treasuryUSDCAfter, 6));
    console.log("- ETH:", ethers.utils.formatEther(treasuryETHAfter));
    
    // Calculate actual changes
    const usdcReceived = treasuryUSDCAfter.sub(treasuryUSDCBefore);
    const ethReceived = treasuryETHAfter.sub(treasuryETHBefore);
    
    console.log("\n📈 Actual Changes:");
    if (usdcReceived.gt(0)) {
      console.log("- USDC received:", ethers.utils.formatUnits(usdcReceived, 6));
    }
    if (ethReceived.gt(0)) {
      console.log("- ETH received:", ethers.utils.formatEther(ethReceived), "(minus gas costs)");
    }
    
    // Verify accumulated fees are now zero
    const remainingUSDC = await marketplace.accumulatedTreasuryTokens(usdcAddress);
    const remainingETH = await marketplace.accumulatedTreasuryETH();
    
    console.log("\n✅ Remaining Accumulated Fees:");
    console.log("- USDC:", ethers.utils.formatUnits(remainingUSDC, 6));
    console.log("- ETH:", ethers.utils.formatEther(remainingETH));
    
    if (remainingUSDC.eq(0) && accumulatedUSDC.gt(0)) {
      console.log("\n🎉 SUCCESS: All USDC treasury fees withdrawn!");
    }
    if (remainingETH.eq(0) && accumulatedETH.gt(0)) {
      console.log("🎉 SUCCESS: All ETH treasury fees withdrawn!");
    }
    
  } catch (error) {
    console.error("\n❌ Error withdrawing treasury fees:", error.message);
    if (error.data) {
      console.error("Error data:", error.data);
    }
  }
}

// Alternative: Withdraw all fees at once
async function withdrawAllFees() {
  const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  const treasuryPrivateKey = process.env.PRIVATE_KEY;
  const treasurySigner = new ethers.Wallet(treasuryPrivateKey, provider);
  
  const marketplaceAddress = "0x001A47Bb8C6CaD9995639b8776AB5816Ab9Ac4E0";
  const marketplace = new ethers.Contract(marketplaceAddress, MARKETPLACE_ABI, treasurySigner);
  
  const usdcAddress = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  
  console.log("\n🔄 Alternative: Withdrawing all fees at once...");
  const tx = await marketplace.withdrawAllTreasuryFees([usdcAddress]);
  console.log("Transaction sent:", tx.hash);
  
  const receipt = await tx.wait();
  console.log("✅ All fees withdrawn in block:", receipt.blockNumber);
}

// Run the script
withdrawTreasuryFees()
  .then(() => console.log("\n✅ Script completed"))
  .catch(error => {
    console.error("\n❌ Script failed:", error);
    process.exit(1);
  });