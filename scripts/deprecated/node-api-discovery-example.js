const { ethers } = require("ethers");
require("dotenv").config();

// Updated NodeRegistryFAB ABI with API URL support
const REGISTRY_ABI = [
  // Registration functions
  "function registerNode(string memory metadata) external",
  "function registerNodeWithUrl(string memory metadata, string memory apiUrl) external",
  
  // Update functions
  "function updateMetadata(string memory newMetadata) external",
  "function updateApiUrl(string memory newApiUrl) external",
  
  // Query functions
  "function nodes(address) external view returns (address operator, uint256 stakedAmount, bool active, string metadata, string apiUrl)",
  "function getNodeApiUrl(address operator) external view returns (string memory)",
  "function getNodeFullInfo(address operator) external view returns (address, uint256, bool, string memory, string memory)",
  "function getAllActiveNodes() external view returns (address[] memory)",
  
  // Events
  "event NodeRegisteredWithUrl(address indexed operator, uint256 stakedAmount, string metadata, string apiUrl)",
  "event ApiUrlUpdated(address indexed operator, string newApiUrl)"
];

async function demonstrateApiDiscovery() {
  const provider = new ethers.providers.JsonRpcProvider(process.env.BASE_SEPOLIA_RPC_URL);
  
  // Example: NodeRegistry contract address (would need to be deployed)
  const registryAddress = "0x039AB5d5e8D5426f9963140202F506A2Ce6988F9"; // Current deployed address
  const registry = new ethers.Contract(registryAddress, REGISTRY_ABI, provider);
  
  console.log("=== Node API Discovery Example ===\n");
  
  // 1. Example: Register a new node with API URL
  console.log("1. How to register with API URL:");
  console.log(`
  const metadata = "llama-2-7b,gpt-4,inference";
  const apiUrl = "http://my-host.example.com:8080";
  
  const tx = await registry.registerNodeWithUrl(metadata, apiUrl);
  await tx.wait();
  `);
  
  // 2. Example: Update existing node's API URL
  console.log("2. How to update API URL for existing host:");
  console.log(`
  const newApiUrl = "https://my-host.example.com:8443";
  
  const tx = await registry.updateApiUrl(newApiUrl);
  await tx.wait();
  `);
  
  // 3. Discover host API endpoints
  console.log("3. Discovering host API endpoints:\n");
  
  try {
    // Get all active nodes
    const activeNodes = await registry.getAllActiveNodes();
    console.log(`Found ${activeNodes.length} active nodes\n`);
    
    // For each node, get their API URL
    for (const nodeAddress of activeNodes.slice(0, 3)) { // Show first 3
      console.log(`Host: ${nodeAddress}`);
      
      try {
        // Method 1: Get just the API URL
        const apiUrl = await registry.getNodeApiUrl(nodeAddress);
        if (apiUrl) {
          console.log(`  API URL: ${apiUrl}`);
        } else {
          console.log(`  API URL: Not set (host needs to call updateApiUrl)`);
        }
        
        // Method 2: Get full node info including API URL
        const fullInfo = await registry.getNodeFullInfo(nodeAddress);
        console.log(`  Metadata: ${fullInfo[3]}`);
        console.log(`  Staked: ${ethers.utils.formatUnits(fullInfo[1], 18)} FAB`);
        console.log(`  Active: ${fullInfo[2]}`);
        
      } catch (error) {
        console.log(`  Error reading node data: ${error.message}`);
      }
      
      console.log();
    }
    
  } catch (error) {
    console.error("Error discovering nodes:", error.message);
  }
  
  // 4. SDK Integration Example
  console.log("4. SDK Integration Pattern:\n");
  console.log(`
  class HostDiscovery {
    constructor(registryContract) {
      this.registry = registryContract;
    }
    
    async getHostEndpoint(hostAddress) {
      // First try to get from contract
      const apiUrl = await this.registry.getNodeApiUrl(hostAddress);
      
      if (apiUrl && apiUrl !== "") {
        return apiUrl;
      }
      
      // Fallback to environment variable or config
      return process.env[\`HOST_\${hostAddress}_URL\`] || null;
    }
    
    async getAllHostEndpoints() {
      const activeNodes = await this.registry.getAllActiveNodes();
      const endpoints = {};
      
      for (const node of activeNodes) {
        const url = await this.getHostEndpoint(node);
        if (url) {
          endpoints[node] = url;
        }
      }
      
      return endpoints;
    }
  }
  `);
  
  // 5. Migration for existing hosts
  console.log("5. Migration for Existing Hosts:\n");
  console.log("Existing hosts registered without API URLs can add them:");
  console.log(`
  // Existing host just needs to call updateApiUrl
  const hostSigner = new ethers.Wallet(privateKey, provider);
  const registryWithSigner = registry.connect(hostSigner);
  
  const tx = await registryWithSigner.updateApiUrl("http://my-api.example.com:8080");
  await tx.wait();
  console.log("API URL added to existing registration!");
  `);
}

// Run the demonstration
demonstrateApiDiscovery()
  .then(() => console.log("\n✅ API Discovery demonstration complete"))
  .catch(error => {
    console.error("\n❌ Error:", error);
    process.exit(1);
  });